import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Set if saving a file on this phone failed at start-up.
String? launchError;

/// Counts how many times the app has been started on this phone.
/// If the count never goes above 1, the app's saved data is being lost between starts.
Future<void> recordLaunch() async {
  try {
    final d = await getApplicationSupportDirectory();
    final f = File('${d.path}/bionexus_launch.json');
    var count = 0;
    var first = DateTime.now().toIso8601String();
    if (await f.exists()) {
      final m = jsonDecode(await f.readAsString());
      if (m is Map) {
        count = (m['count'] as num?)?.toInt() ?? 0;
        first = m['first']?.toString() ?? first;
      }
    }
    await f.writeAsString(
      jsonEncode({'count': count + 1, 'first': first, 'last': DateTime.now().toIso8601String()}),
      flush: true,
    );
  } catch (e) {
    launchError = e.toString();
    debugPrint('recordLaunch failed: $e');
  }
}

/// A plain-text report for Settings → Storage check.
Future<String> storageReport() async {
  final b = StringBuffer();
  try {
    final d = await getApplicationSupportDirectory();
    b.writeln('Folder:\n${d.path}\n');

    // can we write a file and read it back?
    final probe = File('${d.path}/bionexus_selftest.txt');
    final stamp = DateTime.now().toIso8601String();
    await probe.writeAsString(stamp, flush: true);
    final back = await probe.readAsString();
    b.writeln('Write and read back: ${back == stamp ? 'OK' : 'FAILED (different text)'}');

    // how many times has the app started?
    final l = File('${d.path}/bionexus_launch.json');
    if (await l.exists()) {
      final m = jsonDecode(await l.readAsString());
      if (m is Map) {
        b.writeln('App starts counted: ${m['count']}');
        b.writeln('First start: ${m['first']}');
        b.writeln('Last start: ${m['last']}');
      }
    } else {
      b.writeln('Start counter: no file (the data of an earlier start is gone)');
    }
    if (launchError != null) b.writeln('Start-up save error: $launchError');

    // what is saved right now?
    final files = <String>[];
    var photos = 0;
    await for (final e in d.list()) {
      final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is File) {
        files.add('$name  (${await e.length()} B)');
      } else if (name == 'species_images') {
        await for (final p in Directory(e.path).list()) {
          if (p is File) photos++;
        }
      }
    }
    files.sort();
    b.writeln('\nSaved files (${files.length}):');
    for (final f in files) {
      b.writeln('• $f');
    }
    b.writeln('\nSaved photo files: $photos');
  } catch (e) {
    b.writeln('ERROR: $e');
  }
  return b.toString();
}
