import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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

// Public, read-only database hosted in this app's GitHub repository.
const String _remoteManifestUrl =
    'https://raw.githubusercontent.com/fahimkhan20xo-hue/Bio-Nexus-/main/database/version.json';
const String _remoteSpeciesUrl =
    'https://raw.githubusercontent.com/fahimkhan20xo-hue/Bio-Nexus-/main/database/species.json';
const Duration _networkTimeout = Duration(seconds: 15);
const Duration _checkInterval = Duration(hours: 6);

class _SpeciesCache {
  final int version;
  final DateTime? checkedAt;
  final List<Species> species;
  const _SpeciesCache(this.version, this.checkedAt, this.species);
}

Future<File> _cacheFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/bionexus_species_cache.json');
}

List<Species> _decodeSpecies(String raw, {int minimumCount = 1}) {
  final decoded = jsonDecode(raw);
  if (decoded is! List || decoded.length < minimumCount) {
    throw const FormatException('Species database is empty or incomplete.');
  }

  final seen = <String>{};
  final out = <Species>[];
  for (final item in decoded) {
    if (item is! Map) throw const FormatException('Invalid species record.');
    final json = Map<String, dynamic>.from(item);
    for (final key in ['scientific', 'common', 'kingdom', 'phylum', 'class', 'order', 'family']) {
      if ((json[key] ?? '').toString().trim().isEmpty) {
        throw FormatException('A species record is missing "$key".');
      }
    }
    final species = Species.fromJson(json);
    if (seen.add(species.scientific.toLowerCase())) out.add(species);
  }
  if (out.length < minimumCount) {
    throw const FormatException('Species database contains too few unique records.');
  }
  out.sort((a, b) => a.scientific.compareTo(b.scientific));
  return out;
}

Future<_SpeciesCache?> _readCache() async {
  try {
    final file = await _cacheFile();
    if (!await file.exists()) return null;
    final envelope = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final version = (envelope['version'] as num?)?.toInt() ?? 0;
    final checked = DateTime.tryParse((envelope['checkedAt'] ?? '').toString());
    final rawData = jsonEncode(envelope['data']);
    final cachedSpecies = _decodeSpecies(rawData);
    return _SpeciesCache(version, checked, cachedSpecies);
  } catch (e) {
    debugPrint('Ignoring invalid BioNexus cache: $e');
    return null;
  }
}

Future<void> _writeCache(int version, List<Species> species) async {
  final file = await _cacheFile();
  final temp = File('${file.path}.tmp');
  final payload = <String, dynamic>{
    'version': version,
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
    'data': species.map((s) => {
      'scientific': s.scientific,
      'common': s.common,
      'bangla': s.bangla,
      'japanese': s.japanese,
      'kingdom': s.kingdom,
      'phylum': s.phylum,
      'class': s.klass,
      'order': s.order,
      'family': s.family,
      'genus': s.genus,
      'species': s.species,
      'pronunciation': s.pronunciation,
      'description': s.description,
    }).toList(),
  };
  await temp.writeAsString(jsonEncode(payload), flush: true);
  await temp.rename(file.path);
}

/// Loads the bundled database first, then uses a valid newer on-device cache.
/// This keeps the app usable offline and avoids blocking startup on the network.
Future<List<Species>> loadSpecies() async {
  List<Species> bundled;
  try {
    bundled = _decodeSpecies(await rootBundle.loadString('assets/species.json'));
  } catch (e) {
    debugPrint('Could not load bundled species.json: $e');
    bundled = [];
  }

  final cache = await _readCache();
  if (cache != null && cache.version > 0 && cache.species.isNotEmpty) {
    return cache.species;
  }
  return bundled;
}

/// Checks GitHub periodically and safely replaces the local cache only after
/// the manifest, downloaded JSON, and record schema have all been validated.
/// Returns true only when a newer database was installed.
Future<bool> syncRemoteSpecies({VoidCallback? onUpdated}) async {
  try {
    final cache = await _readCache();
    final now = DateTime.now().toUtc();
    if (cache?.checkedAt != null &&
        now.difference(cache!.checkedAt!) < _checkInterval) {
      return false;
    }

    final manifestResponse = await http
        .get(Uri.parse(_remoteManifestUrl))
        .timeout(_networkTimeout);
    if (manifestResponse.statusCode != 200) {
      throw HttpException('Manifest request returned ${manifestResponse.statusCode}.');
    }
    final manifest = jsonDecode(manifestResponse.body) as Map<String, dynamic>;
    final remoteVersion = (manifest['version'] as num?)?.toInt();
    if (remoteVersion == null || remoteVersion < 1) {
      throw const FormatException('Invalid database version manifest.');
    }

    final localVersion = cache?.version ?? 0;
    if (remoteVersion <= localVersion) {
      if (cache != null) await _writeCache(cache.version, cache.species);
      return false;
    }

    final dataResponse = await http
        .get(Uri.parse(_remoteSpeciesUrl))
        .timeout(_networkTimeout);
    if (dataResponse.statusCode != 200) {
      throw HttpException('Database request returned ${dataResponse.statusCode}.');
    }
    // The remote file is the complete master list, not an additions-only patch.
    final minimumCount = speciesData.isEmpty ? 1 : (speciesData.length * 0.8).floor();
    final updated = _decodeSpecies(dataResponse.body, minimumCount: minimumCount);

    await _writeCache(remoteVersion, updated);
    speciesData = updated;
    onUpdated?.call();
    debugPrint('BioNexus database updated to version $remoteVersion (${updated.length} records).');
    return true;
  } catch (e) {
    // Network or validation failures never replace the last known-good data.
    debugPrint('BioNexus online database check skipped: $e');
    return false;
  }
}
