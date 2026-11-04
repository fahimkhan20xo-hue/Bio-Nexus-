import 'package:flutter/material.dart';

import 'data.dart';
import 'quiz.dart' show ScienceBackground;

class _CmpRow {
  final String label, a, b;
  final bool taxon;
  final bool? sameOverride;
  const _CmpRow(this.label, this.a, this.b, this.taxon, [this.sameOverride]);
  bool get same => sameOverride ?? (a.isNotEmpty && a == b);
}

/// Put two species side by side and see which taxonomy levels they share.
class ComparePage extends StatefulWidget {
  final Lang lang;
  final Species? first;
  const ComparePage({super.key, required this.lang, this.first});

  @override
  State<ComparePage> createState() => _ComparePageState();
}

class _ComparePageState extends State<ComparePage> {
  Species? a;
  Species? b;

  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  @override
  void initState() {
    super.initState();
    a = widget.first;
  }

  Future<void> _pick(bool isFirst) async {
    final s = await showModalBottomSheet<Species>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PickerSheet(lang: lang),
    );
    if (s == null || !mounted) return;
    setState(() {
      if (isFirst) {
        a = s;
      } else {
        b = s;
      }
    });
  }

  String _rankName(int i) {
    switch (i) {
      case 0:
        return t('Kingdom', 'জগৎ', '界');
      case 1:
        return t('Phylum', 'পর্ব', '門');
      case 2:
        return t('Class', 'শ্রেণি', '綱');
      case 3:
        return t('Order', 'বর্গ', '目');
      case 4:
        return t('Family', 'গোত্র', '科');
      default:
        return t('Genus', 'গণ', '属');
    }
  }

  Widget _pickCard(Species? s, bool isFirst) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .5)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _pick(isFirst),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: s == null
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.add_circle_outline, size: 30),
                    const SizedBox(height: 6),
                    Text(t('Choose species', 'প্রজাতি বাছো', '種を選ぶ'), textAlign: TextAlign.center),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.scientific, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                    const SizedBox(height: 4),
                    Text(s.name(lang), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Text(t('Tap to change', 'বদলাতে চাপো', 'タップで変更'), style: Theme.of(context).textTheme.bodySmall),
                  ]),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(Species sp) {
    final onP = Theme.of(context).colorScheme.onPrimaryContainer;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(sp.scientific, style: TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic, color: onP)),
        const SizedBox(height: 2),
        Text(sp.name(lang), style: TextStyle(fontSize: 12, color: onP)),
      ]),
    );
  }

  Widget _table(Species x, Species y, List<_CmpRow> rows) {
    final scheme = Theme.of(context).colorScheme;
    final tones = [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh];
    const labelW = 80.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(children: [
        Container(
          color: scheme.primaryContainer,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SizedBox(width: labelW),
            _headerCell(x),
            const SizedBox(width: 8),
            _headerCell(y),
          ]),
        ),
        for (var i = 0; i < rows.length; i++)
          Container(
            color: rows[i].same ? Color.alphaBlend(Colors.green.withValues(alpha: .30), scheme.surface) : tones[i % 2],
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(
                width: labelW,
                child: Row(children: [
                  Flexible(
                    child: Text(
                      rows[i].label,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: scheme.primary),
                    ),
                  ),
                  if (rows[i].same) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.check_circle, color: Colors.green, size: 16),
                  ],
                ]),
              ),
              Expanded(
                child: Text(
                  rows[i].a.isEmpty ? '-' : rows[i].a,
                  style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rows[i].b.isEmpty ? '-' : rows[i].b,
                  style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600),
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final x = a;
    final y = b;
    final children = <Widget>[
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _pickCard(x, true),
        const SizedBox(width: 10),
        _pickCard(y, false),
      ]),
    ];

    if (x != null && y != null) {
      final taxa = <_CmpRow>[
        _CmpRow(_rankName(0), x.kingdom, y.kingdom, true),
        _CmpRow(_rankName(1), x.phylum, y.phylum, true),
        _CmpRow(_rankName(2), x.klass, y.klass, true),
        _CmpRow(_rankName(3), x.order, y.order, true),
        _CmpRow(_rankName(4), x.family, y.family, true),
        _CmpRow(_rankName(5), x.genus, y.genus, true),
      ];
      var shared = 0;
      for (final r in taxa) {
        if (!r.same) break;
        shared++;
      }
      final String summary;
      if (shared == 0) {
        summary = t('They share nothing in this classification.', 'এই শ্রেণিবিন্যাসে এদের কোনো মিল নেই।', 'この分類では共通点がありません。');
      } else if (shared == 6) {
        summary = t('Same genus: very close relatives.', 'একই গণ (Genus): খুব কাছের আত্মীয়।', '同じ属:非常に近い仲間です。');
      } else {
        summary = '${t('Same up to', 'এই পর্যন্ত মিল', 'ここまで同じ')}: ${_rankName(shared - 1)}. '
            '${t('The more levels shared, the closer the relatives.', 'যত বেশি স্তরে মিল, তত কাছের আত্মীয়।', '共通する階級が多いほど近い仲間です。')}';
      }

      children.addAll([
        const SizedBox(height: 14),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.compare_arrows, color: Theme.of(context).colorScheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(child: Text(summary, style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer))),
            ]),
          ),
        ),
        const SizedBox(height: 10),
        _table(x, y, [
          ...taxa,
          _CmpRow(t('Species', 'প্রজাতি', '種'), x.species, y.species, true, x.scientific == y.scientific),
        ]),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            final tmp = a;
            a = b;
            b = tmp;
          }),
          icon: const Icon(Icons.swap_horiz),
          label: Text(t('Swap', 'অদলবদল', '入れ替え')),
        ),
      ]);
    } else {
      children.addAll([
        const SizedBox(height: 24),
        Center(
          child: Text(
            t('Choose two species to compare.', 'তুলনা করতে দুটি প্রজাতি বাছো।', '比べる種を2つ選んでください。'),
            textAlign: TextAlign.center,
          ),
        ),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(t('Compare species', 'প্রজাতির তুলনা', '種の比較'))),
      body: ScienceBackground(
        child: ListView(padding: const EdgeInsets.all(16), children: children),
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  final Lang lang;
  const _PickerSheet({required this.lang});

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  String query = '';

  List<Species> get results {
    final q = query.trim().toLowerCase();
    final raw = query.trim();
    final list = q.isEmpty
        ? speciesData
        : speciesData
            .where((s) =>
                s.scientific.toLowerCase().contains(q) ||
                s.common.toLowerCase().contains(q) ||
                s.bangla.contains(raw) ||
                s.japanese.contains(raw))
            .toList();
    return list.take(80).toList();
  }

  @override
  Widget build(BuildContext context) {
    final list = results;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            autofocus: true,
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              hintText: tr(widget.lang, 'Search species...', 'প্রজাতি খুঁজুন...', '種を検索...'),
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, i) {
              final s = list[i];
              return ListTile(
                title: Text(s.scientific, style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
                subtitle: Text(s.name(widget.lang)),
                onTap: () => Navigator.pop(context, s),
              );
            },
          ),
        ),
      ]),
    );
  }
}
