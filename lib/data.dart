import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Interface languages.
enum Lang { en, bn, ja }

/// Picks the text for the current language.
String tr(Lang l, String en, String bn, String ja) =>
    l == Lang.bn ? bn : (l == Lang.ja ? ja : en);

String kingdomLabel(Lang l, String k) {
  switch (k) {
    case 'Animalia':
      return tr(l, 'Animals', 'প্রাণী', '動物');
    case 'Plantae':
      return tr(l, 'Plants', 'উদ্ভিদ', '植物');
    case 'Fungi':
      return tr(l, 'Fungi', 'ছত্রাক', '菌類');
    case 'Bacteria':
      return tr(l, 'Bacteria', 'ব্যাকটেরিয়া', '細菌');
    case 'Viruses':
      return tr(l, 'Viruses', 'ভাইরাস', 'ウイルス');
    case 'Protista':
      return tr(l, 'Protists', 'প্রোটিস্ট', '原生生物');
    default:
      return k;
  }
}

class Species {
  final String scientific, common, bangla, japanese;
  final String kingdom, phylum, klass, order, family, genus, species;
  final String pronunciation, description;

  const Species({
    required this.scientific,
    required this.common,
    required this.bangla,
    required this.japanese,
    required this.kingdom,
    required this.phylum,
    required this.klass,
    required this.order,
    required this.family,
    required this.genus,
    required this.species,
    required this.pronunciation,
    required this.description,
  });

  /// Required keys: scientific, common, bangla, kingdom, phylum, class, order, family.
  /// Optional: japanese, genus, species, pronunciation, description.
  /// genus and species are derived from the scientific name when missing.
  factory Species.fromJson(Map<String, dynamic> j) {
    String g(String k, [String d = '']) => (j[k] ?? d).toString().trim();
    final sci = g('scientific');
    final parts = sci.split(RegExp(r'\s+'));
    return Species(
      scientific: sci,
      common: g('common'),
      bangla: g('bangla'),
      japanese: g('japanese'),
      kingdom: g('kingdom'),
      phylum: g('phylum'),
      klass: g('class'),
      order: g('order'),
      family: g('family'),
      genus: g('genus', parts.isNotEmpty ? parts.first : ''),
      species: g('species', parts.length > 1 ? parts[1] : ''),
      pronunciation: g('pronunciation'),
      description: g('description'),
    );
  }

  /// Main display name in the chosen language (falls back to English).
  String name(Lang l) {
    if (l == Lang.bn && bangla.isNotEmpty) return bangla;
    if (l == Lang.ja && japanese.isNotEmpty) return japanese;
    return common;
  }

  /// "Name • other name" line used on list cards.
  String names(Lang l) {
    final list = <String>[];
    void add(String s) {
      if (s.isNotEmpty && !list.contains(s)) list.add(s);
    }

    add(name(l));
    add(common);
    if (l != Lang.ja) add(bangla);
    return list.take(2).join(' • ');
  }
}

List<Species> speciesData = [];

/// Loads every species from assets/species.json (sorted A-Z, duplicates skipped).
Future<List<Species>> loadSpecies() async {
  try {
    final raw = await rootBundle.loadString('assets/species.json');
    final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final seen = <String>{};
    final out = <Species>[];
    for (final j in list) {
      final s = Species.fromJson(j);
      if (s.scientific.isEmpty || !seen.add(s.scientific.toLowerCase())) continue;
      out.add(s);
    }
    out.sort((a, b) => a.scientific.compareTo(b.scientific));
    return out;
  } catch (e) {
    debugPrint('Could not load species.json: $e');
    return [];
  }
}
