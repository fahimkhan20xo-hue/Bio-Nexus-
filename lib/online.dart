import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'data.dart';

// Looks a species up online when it is not in the app database.
//   1. Finds the scientific name (directly, or through Wikidata for common names)
//   2. Gets the classification from GBIF
//   3. Gets common / Bengali / Japanese names from Wikipedia and Wikidata
// The result is built into a normal Species record marked as "from online".

class OnlineResult {
  final Species? species;
  final String? error; // 'offline' | 'notfound' | 'incomplete'
  const OnlineResult.ok(this.species) : error = null;
  const OnlineResult.fail(this.error) : species = null;
}

const Map<String, String> _headers = {
  'User-Agent': 'BioNexus/1.1 (Flutter species encyclopedia app)',
  'Accept': 'application/json',
};

const Map<String, String> _kingdomMap = {
  'Animalia': 'Animalia',
  'Plantae': 'Plantae',
  'Fungi': 'Fungi',
  'Bacteria': 'Bacteria',
  'Viruses': 'Viruses',
  'Archaea': 'Archaea',
  'Protozoa': 'Protista',
  'Chromista': 'Protista',
};

final RegExp _bnRe = RegExp(r'[\u0980-\u09FF]');
final RegExp _jaRe = RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]');

class _Net {
  bool failed = false;
}

Future<dynamic> _getJson(String url, _Net net) async {
  try {
    final r = await http.get(Uri.parse(url), headers: _headers).timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes));
    return null;
  } catch (e) {
    net.failed = true;
    return null;
  }
}

String _cap(String s) {
  s = s.trim();
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

String _normalize(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty || parts.first.isEmpty) return '';
  final out = <String>[_cap(parts.first.toLowerCase())];
  for (final p in parts.skip(1)) {
    out.add(p.toLowerCase());
  }
  return out.join(' ');
}

const Set<String> _speciesRanks = {'SPECIES', 'SUBSPECIES', 'VARIETY', 'FORM'};

Future<Map<String, dynamic>?> _gbif(String name, _Net net) async {
  final d = await _getJson('https://api.gbif.org/v1/species/match?name=${Uri.encodeComponent(name)}', net);
  if (d is Map<String, dynamic> && d['matchType'] == 'EXACT' && _speciesRanks.contains(d['rank'])) {
    return d;
  }
  return null;
}

/// Common-name / other-language search through Wikidata. Returns a scientific name.
Future<String?> _findScientificName(String query, _Net net) async {
  final lang = _bnRe.hasMatch(query) ? 'bn' : (_jaRe.hasMatch(query) ? 'ja' : 'en');
  final search = await _getJson(
    'https://www.wikidata.org/w/api.php?action=wbsearchentities&format=json&type=item&limit=7'
    '&language=$lang&uselang=$lang&search=${Uri.encodeComponent(query)}',
    net,
  );
  if (search is! Map || search['search'] is! List) return null;
  final ids = <String>[];
  for (final e in search['search'] as List) {
    final id = (e is Map ? e['id'] : null)?.toString() ?? '';
    if (RegExp(r'^Q\d+$').hasMatch(id)) ids.add(id);
  }
  if (ids.isEmpty) return null;

  final sparql = 'SELECT ?item ?sci WHERE { VALUES ?item { ${ids.map((i) => 'wd:$i').join(' ')} } ?item wdt:P225 ?sci }';
  final res = await _getJson('https://query.wikidata.org/sparql?format=json&query=${Uri.encodeComponent(sparql)}', net);
  if (res is! Map) return null;
  final bindings = (res['results']?['bindings'] as List?) ?? const [];
  for (final id in ids) {
    for (final b in bindings) {
      final item = (b['item']?['value'] ?? '').toString();
      if (item.endsWith('/$id')) {
        final sci = (b['sci']?['value'] ?? '').toString().trim();
        if (sci.isNotEmpty) return sci;
      }
    }
  }
  return null;
}

Future<Map<String, String>> _wikidataNames(String sci, _Net net) async {
  final q = 'SELECT ?en ?bn ?ja ?vn WHERE { ?item wdt:P225 "${sci.replaceAll('"', '')}" . '
      'OPTIONAL { ?item rdfs:label ?en FILTER(LANG(?en)="en") } '
      'OPTIONAL { ?item rdfs:label ?bn FILTER(LANG(?bn)="bn") } '
      'OPTIONAL { ?item rdfs:label ?ja FILTER(LANG(?ja)="ja") } '
      'OPTIONAL { ?item wdt:P1843 ?vn FILTER(LANG(?vn)="en") } } LIMIT 10';
  final out = <String, String>{'en': '', 'bn': '', 'ja': '', 'vn': ''};
  final d = await _getJson('https://query.wikidata.org/sparql?format=json&query=${Uri.encodeComponent(q)}', net);
  if (d is! Map) return out;
  final bindings = (d['results']?['bindings'] as List?) ?? const [];
  for (final b in bindings) {
    for (final k in out.keys.toList()) {
      if (out[k]!.isEmpty && b is Map && b[k] is Map) {
        out[k] = (b[k]['value'] ?? '').toString().trim();
      }
    }
  }
  return out;
}

Future<Map<String, String>> _wikipedia(String sci, _Net net) async {
  final d = await _getJson(
    'https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(sci.replaceAll(' ', '_'))}',
    net,
  );
  if (d is! Map || d['type'] == 'disambiguation') return const {};
  final title = (d['title'] ?? '').toString().replaceAll(RegExp(r'\s*\(.*?\)\s*$'), '').trim();
  return {'title': title, 'description': _cap((d['description'] ?? '').toString())};
}

Future<OnlineResult> lookupOnline(String query) async {
  final q = query.trim();
  if (q.isEmpty) return const OnlineResult.fail('notfound');
  final net = _Net();
  try {
    // 1) Maybe the user typed a scientific name.
    Map<String, dynamic>? g;
    final asSci = _normalize(q);
    if (asSci.contains(' ') && !_bnRe.hasMatch(q) && !_jaRe.hasMatch(q)) {
      g = await _gbif(asSci, net);
    }
    // 2) Otherwise find the scientific name through Wikidata (common names, Bengali, Japanese).
    if (g == null) {
      final sci = await _findScientificName(q, net);
      if (sci != null) g = await _gbif(sci, net);
    }
    if (g == null) return OnlineResult.fail(net.failed ? 'offline' : 'notfound');

    var sci = (g['canonicalName'] ?? '').toString();
    if (g['status'] == 'SYNONYM' && g['rank'] == 'SPECIES' && (g['species'] ?? '').toString().isNotEmpty) {
      sci = g['species'].toString();
    }
    if (sci.isEmpty) return const OnlineResult.fail('notfound');

    final kingdom = _kingdomMap[g['kingdom']] ?? (g['kingdom'] ?? '').toString();
    final phylum = (g['phylum'] ?? '').toString();
    final klass = (g['class'] ?? '').toString();
    final order = (g['order'] ?? '').toString();
    final family = (g['family'] ?? '').toString();
    if ([kingdom, phylum, klass, order, family].any((e) => e.isEmpty)) {
      return const OnlineResult.fail('incomplete');
    }

    final wp = await _wikipedia(sci, net);
    final wd = await _wikidataNames(sci, net);
    final low = sci.toLowerCase();
    var common = '';
    for (final c in [wp['title'] ?? '', wd['en'] ?? '', wd['vn'] ?? '']) {
      if (c.isNotEmpty && c.toLowerCase() != low) {
        common = _cap(c);
        break;
      }
    }
    if (common.isEmpty) common = sci;
    final bn = _bnRe.hasMatch(wd['bn'] ?? '') ? wd['bn']! : '';
    final ja = _jaRe.hasMatch(wd['ja'] ?? '') ? wd['ja']! : '';

    final species = Species.fromJson({
      'scientific': sci,
      'common': common,
      'bangla': bn,
      'japanese': ja,
      'kingdom': kingdom,
      'phylum': phylum,
      'class': klass,
      'order': order,
      'family': family,
      'description': wp['description'] ?? '',
      'online': true,
    });
    return OnlineResult.ok(species);
  } catch (e) {
    return OnlineResult.fail(net.failed ? 'offline' : 'notfound');
  }
}
