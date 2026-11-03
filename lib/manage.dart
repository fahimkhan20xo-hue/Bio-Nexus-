import 'package:flutter/material.dart';

import 'data.dart';
import 'images.dart';
import 'quiz.dart' show ScienceBackground;

/// One screen to choose which saved photos and online-added species to delete.
class ManageSavedPage extends StatefulWidget {
  final Lang lang;
  const ManageSavedPage({super.key, required this.lang});

  @override
  State<ManageSavedPage> createState() => _ManageSavedPageState();
}

class _ManageSavedPageState extends State<ManageSavedPage> {
  List<SavedPhoto> photos = [];
  List<Species> online = [];
  final Set<String> selPhotos = {};
  final Set<String> selOnline = {};
  bool loading = true;

  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  int get total => photos.length + online.length;
  int get selected => selPhotos.length + selOnline.length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Species? _speciesFor(String key) {
    for (final s in speciesData) {
      if (photoKey(s.scientific) == key) return s;
    }
    return null;
  }

  String _photoTitle(SavedPhoto p) {
    final s = _speciesFor(p.key);
    if (s != null) return s.scientific;
    return p.credit.isNotEmpty ? p.credit : p.key;
  }

  Future<void> _load() async {
    final p = await listSavedPhotos();
    p.sort((a, b) => _photoTitle(a).compareTo(_photoTitle(b)));
    if (!mounted) return;
    setState(() {
      photos = p;
      online = speciesData.where((s) => s.fromOnline).toList();
      selPhotos.removeWhere((k) => !p.any((e) => e.key == k));
      selOnline.removeWhere((k) => !online.any((e) => e.scientific == k));
      loading = false;
    });
  }

  void _toggleAll() {
    setState(() {
      if (selected == total) {
        selPhotos.clear();
        selOnline.clear();
      } else {
        selPhotos
          ..clear()
          ..addAll(photos.map((p) => p.key));
        selOnline
          ..clear()
          ..addAll(online.map((s) => s.scientific));
      }
    });
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Delete selected?', 'বাছাই করাগুলো মুছবে?', '選択したものを削除しますか?')),
        content: Text(
          '${t('Photos', 'ছবি', '写真')}: ${selPhotos.length}\n'
          '${t('Online-added species', 'অনলাইনে যোগ করা প্রজাতি', 'オンライン追加の種')}: ${selOnline.length}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল', 'キャンセル'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Delete', 'মুছো', '削除'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final p = await deleteSavedPhotos(Set<String>.of(selPhotos));
    final s = await removeUserSpecies(Set<String>.of(selOnline));
    selPhotos.clear();
    selOnline.clear();
    photosVersion.value++;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${t('Deleted', 'মুছে ফেলা হয়েছে', '削除しました')}: ${t('photos', 'ছবি', '写真')} $p, ${t('species', 'প্রজাতি', '種')} $s'),
    ));
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  @override
  Widget build(BuildContext context) {
    final allSelected = total > 0 && selected == total;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Manage saved data', 'সেভ করা ডেটা', '保存データの管理')),
        actions: [
          TextButton(
            onPressed: total == 0 ? null : _toggleAll,
            child: Text(allSelected ? t('Clear', 'বাদ দাও', '解除') : t('Select all', 'সব বাছাই', 'すべて選択')),
          ),
        ],
      ),
      body: ScienceBackground(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : total == 0
                ? Center(child: Text(t('Nothing saved yet.', 'কিছু সেভ করা নেই।', '保存されたものはありません。')))
                : ListView(
                    padding: const EdgeInsets.only(bottom: 90),
                    children: [
                      if (photos.isNotEmpty) ...[
                        _heading('${t('Saved photos', 'সেভ করা ছবি', '保存した写真')} (${photos.length})'),
                        for (final p in photos)
                          CheckboxListTile(
                            value: selPhotos.contains(p.key),
                            onChanged: (v) => setState(() => v == true ? selPhotos.add(p.key) : selPhotos.remove(p.key)),
                            secondary: CircleAvatar(backgroundImage: ResizeImage(FileImage(p.file), width: 120)),
                            title: Text(_photoTitle(p), style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              [
                                _speciesFor(p.key)?.name(lang) ?? '',
                                '${(p.bytes / 1024).round()} KB',
                              ].where((e) => e.isNotEmpty).join(' • '),
                            ),
                          ),
                      ],
                      if (online.isNotEmpty) ...[
                        _heading('${t('Online-added species', 'অনলাইনে যোগ করা প্রজাতি', 'オンライン追加の種')} (${online.length})'),
                        for (final s in online)
                          CheckboxListTile(
                            value: selOnline.contains(s.scientific),
                            onChanged: (v) => setState(() => v == true ? selOnline.add(s.scientific) : selOnline.remove(s.scientific)),
                            secondary: const CircleAvatar(child: Icon(Icons.public)),
                            title: Text(s.scientific, style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
                            subtitle: Text(s.name(lang)),
                          ),
                      ],
                    ],
                  ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: selected == 0 ? null : _confirmDelete,
            icon: const Icon(Icons.delete_outline),
            label: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('${t('Delete selected', 'বাছাইগুলো মুছো', '選択を削除')} ($selected)'),
            ),
          ),
        ),
      ),
    );
  }
}
