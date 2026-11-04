import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'data.dart';
import 'fx.dart';

// Species photos come from Wikipedia / Wikimedia Commons.
//
// Setting "Save photos on device":
//   ON  - photos are saved on the phone and work offline afterwards.
//   OFF - photos are shown only while online and are not saved (kept in memory
//         for the current session only).
// Photos that were already saved are always shown, even offline.

final ValueNotifier<bool> savePhotos = ValueNotifier<bool>(false);

Future<File> _photoPrefFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/bionexus_photo_pref.json');
}

Future<void> loadPhotoPref() async {
  try {
    final f = await _photoPrefFile();
    if (!await f.exists()) return;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    savePhotos.value = m['save'] == true;
  } catch (e) {
    debugPrint('Could not load photo pref: $e');
  }
}

Future<void> setSavePhotos(bool v) async {
  savePhotos.value = v;
  try {
    final f = await _photoPrefFile();
    await f.writeAsString(jsonEncode({'save': v}), flush: true);
  } catch (e) {
    debugPrint('Could not save photo pref: $e');
  }
}

class SpeciesImageData {
  final File? file;
  final Uint8List? bytes;
  final String credit;
  const SpeciesImageData({this.file, this.bytes, required this.credit});

  ImageProvider get provider => file != null ? FileImage(file!) : MemoryImage(bytes!) as ImageProvider;
}

const Map<String, String> _headers = {
  'User-Agent': 'BioNexus/1.1 (Flutter species encyclopedia app)',
};

final Map<String, Future<SpeciesImageData?>> _inflight = {};
final Map<String, SpeciesImageData> _temp = {};

String _key(String sci) => sci.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');

Future<Directory> _imgDir() async {
  final base = await getApplicationSupportDirectory();
  final d = Directory('${base.path}/species_images');
  if (!await d.exists()) await d.create(recursive: true);
  return d;
}

Future<SpeciesImageData?> _readCached(String sci) async {
  try {
    final d = await _imgDir();
    final k = _key(sci);
    final img = File('${d.path}/$k.img');
    if (!await img.exists()) return null;
    final meta = File('${d.path}/$k.txt');
    final credit = await meta.exists() ? await meta.readAsString() : 'Wikipedia';
    return SpeciesImageData(file: img, credit: credit);
  } catch (e) {
    return null;
  }
}

Future<SpeciesImageData?> _persist(String sci, Uint8List bytes, String credit) async {
  try {
    final d = await _imgDir();
    final k = _key(sci);
    final img = File('${d.path}/$k.img');
    await img.writeAsBytes(bytes, flush: true);
    await File('${d.path}/$k.txt').writeAsString(credit);
    final miss = File('${d.path}/$k.none');
    if (await miss.exists()) await miss.delete();
    _temp.remove(sci);
    return SpeciesImageData(file: img, credit: credit);
  } catch (e) {
    debugPrint('Could not save photo for $sci: $e');
    return SpeciesImageData(bytes: bytes, credit: credit);
  }
}

Future<SpeciesImageData?> _download(String sci) async {
  try {
    final d = await _imgDir();
    final k = _key(sci);
    final miss = File('${d.path}/$k.none');
    if (await miss.exists()) {
      final age = DateTime.now().difference(await miss.lastModified());
      if (age < const Duration(days: 7)) return null;
    }

    final title = Uri.encodeComponent(sci.trim().replaceAll(' ', '_'));
    final res = await http
        .get(Uri.parse('https://en.wikipedia.org/api/rest_v1/page/summary/$title?redirect=true'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode == 404) {
      await miss.writeAsString('x');
      return null;
    }
    if (res.statusCode != 200) return null;

    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final thumb = (j['thumbnail'] as Map?)?['source']?.toString();
    if (thumb == null || thumb.isEmpty) {
      await miss.writeAsString('x');
      return null;
    }

    final big = thumb.replaceFirstMapped(RegExp(r'/\d+px-'), (m) => '/500px-');
    http.Response? imgRes;
    for (final u in [big, thumb]) {
      try {
        final r = await http.get(Uri.parse(u), headers: _headers).timeout(const Duration(seconds: 20));
        if (r.statusCode == 200 && r.bodyBytes.isNotEmpty) {
          imgRes = r;
          break;
        }
      } catch (e) {
        debugPrint('Image download failed for $u: $e');
      }
    }
    if (imgRes == null) return null;

    final credit = 'Wikipedia – ${(j['title'] ?? sci).toString()}';
    if (savePhotos.value) return _persist(sci, imgRes.bodyBytes, credit);

    // Saving is off: keep it in memory for this session only.
    final data = SpeciesImageData(bytes: imgRes.bodyBytes, credit: credit);
    if (_temp.length >= 24) _temp.remove(_temp.keys.first);
    _temp[sci] = data;
    return data;
  } catch (e) {
    debugPrint('Species image lookup skipped for $sci: $e');
    return null;
  }
}

/// online = false only looks at photos already available on the device.
Future<SpeciesImageData?> getSpeciesImage(String sci, {bool online = true}) async {
  final cached = await _readCached(sci);
  if (cached != null) return cached;
  final tmp = _temp[sci];
  if (tmp != null) {
    if (online && savePhotos.value && tmp.bytes != null) {
      return _persist(sci, tmp.bytes!, tmp.credit);
    }
    return tmp;
  }
  if (!online) return null;
  return _inflight.putIfAbsent(sci, () => _download(sci).whenComplete(() => _inflight.remove(sci)));
}

/// Bumped whenever saved photos are deleted, so list thumbnails refresh.
final ValueNotifier<int> photosVersion = ValueNotifier<int>(0);

String photoKey(String sci) => _key(sci);

class SavedPhoto {
  final String key;
  final File file;
  final String credit;
  final int bytes;
  const SavedPhoto(this.key, this.file, this.credit, this.bytes);
}

/// Every photo saved on the device.
Future<List<SavedPhoto>> listSavedPhotos() async {
  final out = <SavedPhoto>[];
  try {
    final d = await _imgDir();
    await for (final e in d.list()) {
      if (e is File && e.path.endsWith('.img')) {
        final name = e.uri.pathSegments.last;
        final key = name.substring(0, name.length - 4);
        final meta = File('${d.path}/$key.txt');
        final credit = await meta.exists() ? await meta.readAsString() : '';
        out.add(SavedPhoto(key, e, credit, await e.length()));
      }
    }
  } catch (e) {
    debugPrint('Could not list photos: $e');
  }
  return out;
}

/// Deletes only the chosen photos. Returns how many were removed.
Future<int> deleteSavedPhotos(Set<String> keys) async {
  var n = 0;
  try {
    final d = await _imgDir();
    for (final k in keys) {
      final img = File('${d.path}/$k.img');
      if (await img.exists()) {
        await img.delete();
        n++;
      }
      final meta = File('${d.path}/$k.txt');
      if (await meta.exists()) await meta.delete();
    }
  } catch (e) {
    debugPrint('Could not delete photos: $e');
  }
  _temp.clear();
  return n;
}

/// Deletes all saved photos. Returns how many photos were removed.
Future<int> clearSavedPhotos() async {
  var n = 0;
  _temp.clear();
  try {
    final d = await _imgDir();
    await for (final e in d.list()) {
      if (e is File) {
        if (e.path.endsWith('.img')) n++;
        await e.delete();
      }
    }
  } catch (e) {
    debugPrint('Could not clear photos: $e');
  }
  return n;
}

/// Small round photo for list cards. Shows the fallback until the species
/// photo is available on the device (saved, or loaded earlier this session).
class SpeciesThumb extends StatefulWidget {
  final String scientific;
  final Widget fallback;
  const SpeciesThumb({super.key, required this.scientific, required this.fallback});

  @override
  State<SpeciesThumb> createState() => _SpeciesThumbState();
}

class _SpeciesThumbState extends State<SpeciesThumb> {
  late Future<SpeciesImageData?> _f = getSpeciesImage(widget.scientific, online: false);

  @override
  void initState() {
    super.initState();
    photosVersion.addListener(_reload);
  }

  @override
  void dispose() {
    photosVersion.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _f = getSpeciesImage(widget.scientific, online: false));
  }

  @override
  void didUpdateWidget(covariant SpeciesThumb old) {
    super.didUpdateWidget(old);
    if (old.scientific != widget.scientific) {
      _f = getSpeciesImage(widget.scientific, online: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpeciesImageData?>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null) return widget.fallback;
        return CircleAvatar(backgroundImage: ResizeImage(d.provider, width: 120));
      },
    );
  }
}

/// Large photo at the top of the species detail page.
class SpeciesHero extends StatefulWidget {
  final String scientific;
  final Lang lang;
  const SpeciesHero({super.key, required this.scientific, required this.lang});

  @override
  State<SpeciesHero> createState() => _SpeciesHeroState();
}

class _SpeciesHeroState extends State<SpeciesHero> {
  late final Future<SpeciesImageData?> _f = getSpeciesImage(widget.scientific);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SpeciesImageData?>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        final waiting = snap.connectionState != ConnectionState.done;
        const icon = Center(child: Icon(Icons.biotech, color: Colors.white, size: 72));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 210,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: Emerald.hero,
            ),
            child: d == null
                ? (waiting
                    ? const Stack(alignment: Alignment.center, children: [
                        Positioned.fill(child: ShimmerBox(radius: 0)),
                        icon,
                      ])
                    : icon)
                : GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => _ZoomPage(provider: d.provider, title: widget.scientific)),
                    ),
                    child: Image(
                      image: ResizeImage(d.provider, width: 900),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => icon,
                    ),
                  ),
          ),
          if (d != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text('Photo: ${d.credit} (Wikimedia Commons)', style: Theme.of(context).textTheme.bodySmall),
            )
          else if (!waiting)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                tr(widget.lang, 'No photo available (you may be offline).', 'ছবি পাওয়া যায়নি (হয়তো অফলাইনে আছো)।', '写真がありません(オフラインの可能性があります)。'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ]);
      },
    );
  }
}

/// Full-screen photo you can pinch to zoom.
class _ZoomPage extends StatelessWidget {
  final ImageProvider provider;
  final String title;
  const _ZoomPage({required this.provider, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title, style: const TextStyle(fontStyle: FontStyle.italic)),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1,
          maxScale: 6,
          child: Image(image: provider, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
