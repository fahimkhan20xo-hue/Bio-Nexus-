#!/usr/bin/env python3
"""BioNexus species sync.

Reads scientific names from database/names.txt and fills in everything else:
  - classification (kingdom -> family) from GBIF
  - common / Bengali / Japanese names from Wikipedia + Wikidata
Optional Bengali pronunciation can be written after a | on the same line
(e.g. "Panthera leo | প্যানথেরা লিও"); it is added to new species and filled
into existing species that have none (or only an English one). Other existing data is never changed. Results go to database/species.json,
database/version.json is bumped, and database/sync_report.md explains what
was added or skipped. Only the Python standard library is used.
"""
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from urllib.parse import quote

ROOT = os.path.dirname(os.path.abspath(__file__))
NAMES = os.path.join(ROOT, 'database', 'names.txt')
DB = os.path.join(ROOT, 'database', 'species.json')
VER = os.path.join(ROOT, 'database', 'version.json')
ASSET = os.path.join(ROOT, 'assets', 'species.json')
REPORT = os.path.join(ROOT, 'database', 'sync_report.md')

UA = 'BioNexusSync/1.0 (https://github.com/fahimkhan20xo-hue/Bio-Nexus-; educational app)'
REQUIRED = ['scientific', 'common', 'kingdom', 'phylum', 'class', 'order', 'family']
KINGDOM = {
    'Animalia': 'Animalia', 'Plantae': 'Plantae', 'Fungi': 'Fungi',
    'Bacteria': 'Bacteria', 'Viruses': 'Viruses', 'Archaea': 'Archaea',
    'Protozoa': 'Protista', 'Chromista': 'Protista',
}
BN_RE = re.compile(r'[\u0980-\u09FF]')
JA_RE = re.compile(r'[\u3040-\u30ff\u4e00-\u9fff]')


def get(url, retries=4):
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA, 'Accept': 'application/json'})
            with urllib.request.urlopen(req, timeout=30) as r:
                return json.loads(r.read().decode('utf-8'))
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            if e.code in (429, 500, 502, 503, 504):
                time.sleep(3 * (i + 1))
                continue
            return None
        except Exception:
            time.sleep(2 * (i + 1))
    return None


def load_list(path):
    try:
        with open(path, encoding='utf-8') as f:
            data = json.load(f)
        return data if isinstance(data, list) else []
    except Exception:
        return []


def normalize(raw):
    parts = ' '.join(raw.split()).split(' ')
    if not parts or not parts[0]:
        return ''
    parts[0] = parts[0].capitalize()
    parts[1:] = [p.lower() for p in parts[1:]]
    return ' '.join(parts)


def read_names():
    out, seen, prons = [], set(), {}
    if not os.path.exists(NAMES):
        return out, prons
    with open(NAMES, encoding='utf-8') as f:
        for line in f:
            line = line.split('#', 1)[0].strip()
            if not line:
                continue
            pron = ''
            if '|' in line:
                line, pron = line.split('|', 1)
                pron = pron.strip()
            n = normalize(line)
            if not n:
                continue
            if pron:
                prons[n.lower()] = pron
            if n.lower() not in seen:
                seen.add(n.lower())
                out.append(n)
    return out, prons


def cap(s):
    s = (s or '').strip()
    return s[:1].upper() + s[1:]


def wikipedia(name):
    d = get('https://en.wikipedia.org/api/rest_v1/page/summary/' + quote(name.replace(' ', '_'), safe=''))
    time.sleep(0.2)
    if not d or d.get('type') == 'disambiguation':
        return {}
    title = re.sub(r'\s*\(.*?\)\s*$', '', d.get('title', '')).strip()
    return {'title': title, 'description': cap(d.get('description', ''))}


def wikidata(name):
    q = ('SELECT ?en ?bn ?ja ?vn WHERE { ?item wdt:P225 "%s" . '
         'OPTIONAL { ?item rdfs:label ?en FILTER(LANG(?en)="en") } '
         'OPTIONAL { ?item rdfs:label ?bn FILTER(LANG(?bn)="bn") } '
         'OPTIONAL { ?item rdfs:label ?ja FILTER(LANG(?ja)="ja") } '
         'OPTIONAL { ?item wdt:P1843 ?vn FILTER(LANG(?vn)="en") } } LIMIT 10') % name.replace('"', '')
    d = get('https://query.wikidata.org/sparql?format=json&query=' + quote(q, safe=''))
    time.sleep(0.4)
    res = {'en': '', 'bn': '', 'ja': '', 'vn': ''}
    if not d:
        return res
    for b in d.get('results', {}).get('bindings', []):
        for k in res:
            if not res[k] and k in b:
                res[k] = b[k].get('value', '').strip()
    return res


def resolve(name):
    """Returns (record, notes, error)."""
    g = get('https://api.gbif.org/v1/species/match?name=' + quote(name))
    time.sleep(0.2)
    if not g:
        return None, [], 'GBIF did not respond'
    if g.get('matchType') != 'EXACT':
        hint = g.get('scientificName') or 'no suggestion'
        return None, [], 'GBIF found no exact match (closest: %s). Check the spelling.' % hint

    notes = []
    sci = g.get('canonicalName') or name
    if g.get('status') == 'SYNONYM' and g.get('rank') == 'SPECIES' and g.get('species'):
        notes.append('"%s" is a synonym, saved as accepted name "%s"' % (name, g['species']))
        sci = g['species']

    rec = {
        'scientific': sci,
        'kingdom': KINGDOM.get(g.get('kingdom', ''), g.get('kingdom', '')),
        'phylum': g.get('phylum', ''),
        'class': g.get('class', ''),
        'order': g.get('order', ''),
        'family': g.get('family', ''),
    }
    missing = [k for k in ('kingdom', 'phylum', 'class', 'order', 'family') if not rec[k]]
    if missing:
        return None, notes, 'GBIF has no %s for this name' % ', '.join(missing)

    wp = wikipedia(sci)
    wd = wikidata(sci)
    low = sci.lower()
    common = ''
    for cand in (wp.get('title', ''), wd['en'], wd['vn']):
        if cand and cand.lower() != low:
            common = cap(cand)
            break
    if not common:
        common = sci
        notes.append('no common name found, scientific name used')
    bn = wd['bn'] if BN_RE.search(wd['bn']) else ''
    ja = wd['ja'] if JA_RE.search(wd['ja']) else ''
    if not bn:
        notes.append('no Bengali name')
    if not ja:
        notes.append('no Japanese name')

    out = {
        'scientific': rec['scientific'],
        'common': common,
        'bangla': bn,
        'japanese': ja,
        'kingdom': rec['kingdom'],
        'phylum': rec['phylum'],
        'class': rec['class'],
        'order': rec['order'],
        'family': rec['family'],
    }
    if wp.get('description'):
        out['description'] = wp['description']
    return out, notes, None


def valid(rec):
    return all(str(rec.get(k, '')).strip() for k in REQUIRED)


def main():
    names, prons = read_names()
    existing = {}
    for rec in load_list(ASSET) + load_list(DB):  # database/ wins over assets/
        if isinstance(rec, dict) and str(rec.get('scientific', '')).strip():
            existing[rec['scientific'].strip().lower()] = rec
    db_before = load_list(DB)

    added, skipped, noted = [], [], []
    for i, name in enumerate(names, 1):
        if name.lower() in existing:
            continue
        print('[%d/%d] %s' % (i, len(names), name), flush=True)
        rec, notes, err = resolve(name)
        if err or rec is None:
            skipped.append((name, err or 'unknown error'))
            continue
        key = rec['scientific'].lower()
        if key in existing:
            skipped.append((name, 'already in the database as "%s"' % rec['scientific']))
            continue
        if not valid(rec):
            skipped.append((name, 'incomplete record'))
            continue
        p = prons.get(key) or prons.get(name.lower())
        if p:
            rec['pronunciation'] = p
        existing[key] = rec
        added.append(rec['scientific'])
        for n in notes:
            noted.append((rec['scientific'], n))

    filled = []
    for key, p in prons.items():
        rec = existing.get(key)
        cur = str(rec.get('pronunciation', '')).strip() if rec else ''
        if rec and (not cur or not BN_RE.search(cur)):  # fill empty or English-only
            rec['pronunciation'] = p
            filled.append(rec['scientific'])

    merged = sorted(existing.values(), key=lambda r: r['scientific'])
    changed = merged != db_before

    if changed:
        with open(DB, 'w', encoding='utf-8') as f:
            json.dump(merged, f, ensure_ascii=False, indent=1)
            f.write('\n')
        manifest = {}
        try:
            with open(VER, encoding='utf-8') as f:
                manifest = json.load(f)
        except Exception:
            pass
        old = manifest.get('version', 0)
        manifest['version'] = (old if isinstance(old, int) else 0) + 1
        with open(VER, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, indent=1)
            f.write('\n')

    lines = ['# Species sync report', '',
             'Total species in database: %d' % len(merged),
             'Added this run: %d' % len(added), '']
    if added:
        lines += ['## Added'] + ['- ' + a for a in added] + ['']
    if filled:
        lines += ['## Pronunciation filled in'] + ['- ' + a for a in filled] + ['']
    if skipped:
        lines += ['## Skipped (fix the name or add by hand)'] + ['- %s: %s' % s for s in skipped] + ['']
    if noted:
        lines += ['## Notes'] + ['- %s: %s' % n for n in noted] + ['']
    lines += ['Data sources: GBIF (classification), Wikipedia and Wikidata (names).', '']
    with open(REPORT, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines))
    print('Done. Added %d, pronunciation filled %d, skipped %d.' % (len(added), len(filled), len(skipped)))


if __name__ == '__main__':
    sys.exit(main())
