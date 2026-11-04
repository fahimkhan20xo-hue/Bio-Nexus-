import 'package:flutter/material.dart';

import 'data.dart';
import 'quiz.dart' show ScienceBackground;

typedef OpenSpecies = void Function(BuildContext context, Species species, List<Species> list);

class _N {
  final Map<String, _N> kids = {};
  final List<Species> species = [];
  int count = 0;
}

_N _buildTree() {
  final root = _N();
  for (final s in speciesData) {
    final path = [s.kingdom, s.phylum, s.klass, s.order, s.family, s.genus];
    var n = root;
    for (final p in path) {
      n = n.kids.putIfAbsent(p.isEmpty ? '-' : p, () => _N());
      n.count++;
    }
    n.species.add(s);
  }
  return root;
}

/// Kingdom > Phylum > Class > Order > Family > Genus > Species, one level at a time.
class TaxonomyTreePage extends StatefulWidget {
  final Lang lang;
  final OpenSpecies open;
  const TaxonomyTreePage({super.key, required this.lang, required this.open});

  @override
  State<TaxonomyTreePage> createState() => _TaxonomyTreePageState();
}

class _TaxonomyTreePageState extends State<TaxonomyTreePage> {
  late final _N root = _buildTree();

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final top = root.kids.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));
    return Scaffold(
      appBar: AppBar(title: Text(tr(lang, 'Taxonomy tree', 'শ্রেণিবিন্যাস গাছ', '分類ツリー'))),
      body: ScienceBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                tr(lang, 'Tap a name to open the next level.', 'পরের স্তর দেখতে নামে চাপো।', '名前をタップして次の階級を開きます。'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            for (final e in top) _TreeTile(name: e.key, node: e.value, level: 0, lang: lang, open: widget.open),
          ],
        ),
      ),
    );
  }
}

class _TreeTile extends StatefulWidget {
  final String name;
  final _N node;
  final int level;
  final Lang lang;
  final OpenSpecies open;
  const _TreeTile({required this.name, required this.node, required this.level, required this.lang, required this.open});

  @override
  State<_TreeTile> createState() => _TreeTileState();
}

class _TreeTileState extends State<_TreeTile> {
  bool expanded = false;

  String _rank(Lang l, int level) {
    switch (level) {
      case 0:
        return tr(l, 'Kingdom', 'জগৎ', '界');
      case 1:
        return tr(l, 'Phylum', 'পর্ব', '門');
      case 2:
        return tr(l, 'Class', 'শ্রেণি', '綱');
      case 3:
        return tr(l, 'Order', 'বর্গ', '目');
      case 4:
        return tr(l, 'Family', 'গোত্র', '科');
      default:
        return tr(l, 'Genus', 'গণ', '属');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final isGenus = widget.level >= 5;
    final label = widget.level == 0 ? kingdomLabel(lang, widget.name) : widget.name;
    List<Widget> children = const [];
    if (expanded) {
      if (isGenus) {
        children = [
          for (final s in widget.node.species)
            ListTile(
              contentPadding: EdgeInsets.only(left: 12.0 + 14.0 * (widget.level + 1), right: 12),
              leading: const Icon(Icons.biotech, size: 20),
              title: Text(s.scientific, style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
              subtitle: Text(s.name(lang)),
              onTap: () => widget.open(context, s, widget.node.species),
            ),
        ];
      } else {
        final kids = widget.node.kids.entries.toList()..sort((a, b) => b.value.count.compareTo(a.value.count));
        children = [
          for (final e in kids)
            _TreeTile(name: e.key, node: e.value, level: widget.level + 1, lang: lang, open: widget.open),
        ];
      }
    }
    return ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.only(left: 12.0 + 14.0 * widget.level, right: 12),
      leading: Icon(widget.level == 0 ? Icons.public : Icons.account_tree_outlined, size: 22),
      title: Text(
        label,
        style: TextStyle(fontWeight: FontWeight.bold, fontStyle: widget.level == 0 ? FontStyle.normal : FontStyle.italic),
      ),
      subtitle: Text('${_rank(lang, widget.level)} • ${widget.node.count} ${tr(lang, 'species', 'টি প্রজাতি', '種')}'),
      onExpansionChanged: (v) => setState(() => expanded = v),
      children: children,
    );
  }
}
