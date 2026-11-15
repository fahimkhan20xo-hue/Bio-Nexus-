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
import difflib
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
FIXES = os.path.join(ROOT, 'database', 'name_fixes.json')  # remembers auto-corrected names

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


GBIF = 'https://api.gbif.org/v1'
UNPLACED = 'Incertae sedis'  # the proper taxonomic term for "placement not settled"


def similar(a, b):
    return difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio()


def gbif_match(name):
    d = get(GBIF + '/species/match?verbose=true&name=' + quote(name))
    time.sleep(0.2)
    return d


def is_species_hit(g):
    return bool(g) and g.get('matchType') in ('EXACT', 'FUZZY') and g.get('rank') in (
        'SPECIES', 'SUBSPECIES', 'VARIETY', 'FORM') and g.get('canonicalName')


def find_correction(name, g):
    """The name did not match exactly. Look for the species it most likely means:
    first among GBIF's own alternatives, then with a GBIF search. Only close
    spellings are accepted, so a wrong species is never added by accident."""
    best, best_score = None, 0.0
    cands = [g] + list(g.get('alternatives') or [])
    for c in cands:
        if not is_species_hit(c):
            continue
        sim = similar(name, c['canonicalName'])
        score = sim + (0.05 if c.get('status') == 'ACCEPTED' else 0) + (c.get('confidence', 0) / 1000.0)
        if sim >= 0.86 and score > best_score:
            best, best_score = c['canonicalName'], score
    if best:
        return best
    d = get(GBIF + '/species/search?rank=SPECIES&status=ACCEPTED&limit=8&q=' + quote(name))
    time.sleep(0.2)
    for r in (d or {}).get('results', []):
        cn = r.get('canonicalName') or ''
        if cn and similar(name, cn) >= 0.9 and score_ok(name, cn):
            return cn
    return None


def score_ok(name, cn):
    # same genus word or same species word, so "Rosa chinensis" cannot become "Pinus sylvestris"
    a, b = name.lower().split(), cn.lower().split()
    return len(a) == 2 and len(b) == 2 and (a[0] == b[0] or a[1] == b[1])


def complete_classification(rec, g, notes):
    """GBIF sometimes lacks a rank. Try the taxon record, then the genus."""
    ranks = ('kingdom', 'phylum', 'class', 'order', 'family')

    def missing():
        return [k for k in ranks if not rec.get(k)]

    key = g.get('acceptedUsageKey') or g.get('usageKey')
    if missing() and key:
        d = get('%s/species/%s' % (GBIF, key))
        time.sleep(0.2)
        for k in ranks:
            if d and not rec.get(k) and d.get(k):
                rec[k] = KINGDOM.get(d[k], d[k]) if k == 'kingdom' else d[k]
    if missing() and g.get('genus'):
        d = get(GBIF + '/species/match?rank=GENUS&name=' + quote(g['genus']))
        time.sleep(0.2)
        for k in ranks:
            if d and d.get('matchType') == 'EXACT' and not rec.get(k) and d.get(k):
                rec[k] = KINGDOM.get(d[k], d[k]) if k == 'kingdom' else d[k]
    for k in ('class', 'order', 'family'):
        if not rec.get(k) and rec.get('phylum'):
            rec[k] = UNPLACED
            notes.append('GBIF has no %s for this species, marked "%s"' % (k, UNPLACED))
    return [k for k in ('kingdom', 'phylum') if not rec.get(k)]


def resolve(name):
    """Returns (record, notes, error). Names that do not match exactly are
    corrected automatically when a close species exists."""
    g = gbif_match(name)
    if not g:
        return None, [], 'GBIF did not respond'
    notes = []
    if g.get('matchType') != 'EXACT' or g.get('rank') not in ('SPECIES', 'SUBSPECIES', 'VARIETY', 'FORM'):
        fixed = find_correction(name, g)
        if not fixed:
            hint = g.get('scientificName') or 'no suggestion'
            return None, [], 'GBIF found no close match (closest: %s). Check the spelling.' % hint
        g2 = gbif_match(fixed)
        if not g2 or g2.get('matchType') != 'EXACT':
            return None, [], 'GBIF could not confirm the corrected name "%s"' % fixed
        notes.append('"%s" was corrected to "%s"' % (name, fixed))
        g = g2

    sci = g.get('canonicalName') or name
    if g.get('species') and (g.get('status') == 'SYNONYM' or g.get('rank') != 'SPECIES'):
        notes.append('"%s" is a synonym or sub-rank, saved as accepted species "%s"' % (name, g['species']))
        sci = g['species']

    rec = {
        'scientific': sci,
        'kingdom': KINGDOM.get(g.get('kingdom', ''), g.get('kingdom', '')),
        'phylum': g.get('phylum', ''),
        'class': g.get('class', ''),
        'order': g.get('order', ''),
        'family': g.get('family', ''),
    }
    lacking = complete_classification(rec, g, notes)
    if lacking:
        return None, notes, 'GBIF has no %s for this name' % ', '.join(lacking)

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

    fixes = {}
    try:
        with open(FIXES, encoding='utf-8') as f:
            fixes = json.load(f)
    except Exception:
        pass
    fixes_before = dict(fixes)

    added, skipped, noted, corrected = [], [], [], []

    def attempt(i, total, name):
        print('[%d/%d] %s' % (i, total, name), flush=True)
        rec, notes, err = resolve(name)
        if err or rec is None:
            return err or 'unknown error'
        key = rec['scientific'].lower()
        if key != name.lower():
            fixes[name.lower()] = rec['scientific']
            corrected.append((name, rec['scientific']))
        if key in existing:
            noted.append((name, 'is the same species as "%s", already in the database' % rec['scientific']))
            return None
        if not valid(rec):
            return 'incomplete record'
        p = prons.get(key) or prons.get(name.lower())
        if p:
            rec['pronunciation'] = p
        existing[key] = rec
        added.append(rec['scientific'])
        for n in notes:
            noted.append((rec['scientific'], n))
        return None

    retry = []
    for i, name in enumerate(names, 1):
        if name.lower() in existing:
            continue
        fx = fixes.get(name.lower())
        if fx and fx.lower() in existing:
            continue  # corrected earlier and already added
        err = attempt(i, len(names), name)
        if err and 'did not respond' in err:
            retry.append((i, name))  # temporary problem, try again below
        elif err:
            skipped.append((name, err))

    if retry:
        print('Retrying %d names after a short pause...' % len(retry), flush=True)
        time.sleep(30)
        for i, name in retry:
            err = attempt(i, len(names), name)
            if err:
                skipped.append((name, err))

    filled = []
    for key, p in prons.items():
        rec = existing.get(key)
        cur = str(rec.get('pronunciation', '')).strip() if rec else ''
        if rec and (not cur or not BN_RE.search(cur)):  # fill empty or English-only
            rec['pronunciation'] = p
            filled.append(rec['scientific'])

    merged = sorted(existing.values(), key=lambda r: r['scientific'])
    changed = merged != db_before
    if fixes != fixes_before:
        with open(FIXES, 'w', encoding='utf-8') as f:
            json.dump(fixes, f, ensure_ascii=False, indent=1, sort_keys=True)
            f.write('\n')

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
    if corrected:
        lines += ['## Names corrected automatically'] + ['- %s -> %s' % c for c in corrected] + ['']
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
