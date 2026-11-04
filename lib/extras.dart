import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data.dart';

// Extra facts for the species page, from Wikipedia (short summary) and
// Wikidata (IUCN conservation status). Saved on the device after the first load.

class SpeciesExtra {
  final String iucn, summary, title;
  const SpeciesExtra(this.iucn, this.summary, this.title);

  Map<String, dynamic> toJson() => {'iucn': iucn, 'summary': summary, 'title': title};

  factory SpeciesExtra.fromJson(Map<String, dynamic> j) => SpeciesExtra(
        (j['iucn'] ?? '').toString(),
        (j['summary'] ?? '').toString(),
        (j['title'] ?? '').toString(),
      );
}

const Map<String, String> _headers = {
  'User-Agent': 'BioNexus/1.1 (Flutter species encyclopedia app)',
  'Accept': 'application/json',
};

final Map<String, SpeciesExtra> _cache = {};
final Map<String, Future<SpeciesExtra?>> _inflight = {};
bool _cacheLoaded = false;

Future<File> _cacheFile() async {
  final d = await getApplicationSupportDirectory();
  return File('${d.path}/bionexus_extras.json');
}

Future<void> _loadCache() async {
  if (_cacheLoaded) return;
  _cacheLoaded = true;
  try {
    final f = await _cacheFile();
    if (!await f.exists()) return;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    m.forEach((k, v) {
      if (v is Map) _cache[k] = SpeciesExtra.fromJson(Map<String, dynamic>.from(v));
    });
  } catch (e) {
    debugPrint('Could not load extras cache: $e');
  }
}

Future<void> _saveCache() async {
  try {
    final f = await _cacheFile();
    await f.writeAsString(jsonEncode(_cache.map((k, v) => MapEntry(k, v.toJson()))), flush: true);
  } catch (e) {
    debugPrint('Could not save extras cache: $e');
  }
}

String _shorten(String text, {int max = 420}) {
  final t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.length <= max) return t;
  final cut = t.substring(0, max);
  final i = cut.lastIndexOf('. ');
  return i > 120 ? cut.substring(0, i + 1) : '$cut...';
}

String _tidyIucn(String s) {
  var t = s.trim();
  if (t.toLowerCase().endsWith(' species')) t = t.substring(0, t.length - 8);
  return t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);
}

Future<SpeciesExtra?> getSpeciesExtra(String sci) {
  return _inflight.putIfAbsent(sci, () => _fetch(sci).whenComplete(() => _inflight.remove(sci)));
}

Future<SpeciesExtra?> _fetch(String sci) async {
  await _loadCache();
  final cached = _cache[sci];
  if (cached != null) return cached;
  try {
    var summary = '';
    var title = '';
    final w = await http
        .get(
          Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(sci.replaceAll(' ', '_'))}'),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));
    if (w.statusCode == 200) {
      final j = jsonDecode(utf8.decode(w.bodyBytes));
      if (j is Map && j['type'] != 'disambiguation') {
        summary = _shorten((j['extract'] ?? '').toString());
        title = (j['title'] ?? '').toString();
      }
    }

    var iucn = '';
    final q = 'SELECT ?l WHERE { ?item wdt:P225 "${sci.replaceAll('"', '')}" . ?item wdt:P141 ?s . '
        '?s rdfs:label ?l FILTER(LANG(?l)="en") } LIMIT 1';
    final r = await http
        .get(Uri.parse('https://query.wikidata.org/sparql?format=json&query=${Uri.encodeComponent(q)}'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (r.statusCode == 200) {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final b = (d is Map ? d['results']?['bindings'] : null) as List?;
      if (b != null && b.isNotEmpty) {
        iucn = _tidyIucn((b.first['l']?['value'] ?? '').toString());
      }
    }

    if (summary.isEmpty && iucn.isEmpty) return null;
    final e = SpeciesExtra(iucn, summary, title);
    _cache[sci] = e;
    await _saveCache();
    return e;
  } catch (e) {
    return null;
  }
}

Color _iucnColor(String s) {
  final t = s.toLowerCase();
  if (t.contains('extinct')) return const Color(0xFF6D4C41);
  if (t.contains('critically')) return const Color(0xFFD32F2F);
  if (t.contains('endangered')) return const Color(0xFFEF6C00);
  if (t.contains('vulnerable')) return const Color(0xFFF9A825);
  if (t.contains('near')) return const Color(0xFFC0CA33);
  if (t.contains('least')) return const Color(0xFF2E7D32);
  return const Color(0xFF78909C);
}

/// Conservation status and a short summary for one species.
class ExtraCard extends StatefulWidget {
  final Species species;
  final Lang lang;
  const ExtraCard({super.key, required this.species, required this.lang});

  @override
  State<ExtraCard> createState() => _ExtraCardState();
}

class _ExtraCardState extends State<ExtraCard> {
  late final Future<SpeciesExtra?> _f = getSpeciesExtra(widget.species.scientific);

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    return FutureBuilder<SpeciesExtra?>(
      future: _f,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2),
          );
        }
        final e = snap.data;
        if (e == null) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (e.iucn.isNotEmpty)
            Card(
              child: ListTile(
                leading: Icon(Icons.shield_outlined, color: _iucnColor(e.iucn)),
                title: Text(tr(lang, 'Conservation status (IUCN)', 'সংরক্ষণ অবস্থা (IUCN)', '保全状況(IUCN)')),
                subtitle: Text(
                  e.iucn,
                  style: TextStyle(fontWeight: FontWeight.bold, color: _iucnColor(e.iucn)),
                ),
              ),
            ),
          if (e.summary.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    tr(lang, 'About', 'সংক্ষিপ্ত পরিচিতি', '概要'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(e.summary),
                  const SizedBox(height: 8),
                  Text(
                    '${tr(lang, 'Source', 'সূত্র', '出典')}: Wikipedia${e.title.isEmpty ? '' : ' - ${e.title}'} (CC BY-SA), Wikidata',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
