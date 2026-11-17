import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data.dart';
import 'fx.dart';
import 'images.dart';

/// Flashcards for the Study zone.
///
/// Tap a card to flip it. "I know" moves a species up one box (it comes back
/// less often), "Need revision" puts it back in box 0 (it comes back first).
/// Progress is saved on the phone, so it survives closing the app.
class FlashcardsPage extends StatefulWidget {
  final Lang lang;
  final void Function(BuildContext, Species, List<Species>) open;
  const FlashcardsPage({super.key, required this.lang, required this.open});

  @override
  State<FlashcardsPage> createState() => _FlashcardsPageState();
}

class _FlashcardsPageState extends State<FlashcardsPage> {
  static const int _maxBox = 3;

  final Map<String, int> boxes = {}; // scientific name -> box (0 = needs revision)
  bool loaded = false;

  // setup choices
  String? kingdom;
  int count = 10;
  bool onlyMissed = false;

  // session
  int stage = 0; // 0 = setup, 1 = cards, 2 = finished
  List<Species> deck = [];
  int index = 0;
  bool flipped = false;
  final List<Species> knownNow = [];
  final List<Species> missedNow = [];

  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------- saving ----------
  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}/bionexus_flashcards.json');
  }

  Future<void> _load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) {
          m.forEach((k, v) {
            if (v is int) boxes[k.toString()] = v;
          });
        }
      }
    } catch (e) {
      debugPrint('Could not load flashcards: $e');
    }
    if (mounted) setState(() => loaded = true);
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(boxes), flush: true);
    } catch (e) {
      debugPrint('Could not save flashcards: $e');
    }
  }

  // photos of the next cards load while you look at this one
  void _prefetch() {
    prefetchSpeciesImages(deck.skip(index).take(3).map((s) => s.scientific));
  }

  // ---------- choosing cards ----------
  // missed first, then never seen, then the ones you know better and better
  int _priority(Species s) {
    final b = boxes[s.scientific];
    if (b == null) return 1;
    if (b == 0) return 0;
    return b + 1;
  }

  List<Species> _pool() {
    var pool = speciesData.where((s) => kingdom == null || s.kingdom == kingdom).toList();
    if (onlyMissed) pool = pool.where((s) => boxes[s.scientific] == 0).toList();
    return pool;
  }

  void _start() {
    final pool = _pool();
    if (pool.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('No cards here yet.', 'এখানে এখনো কোনো কার্ড নেই।', 'まだカードがありません。'))),
      );
      return;
    }
    pool.shuffle(math.Random());
    pool.sort((a, b) => _priority(a).compareTo(_priority(b)));
    final picked = pool.take(count).toList()..shuffle(math.Random());
    _begin(picked);
  }

  void _begin(List<Species> cards) {
    setState(() {
      deck = cards;
      index = 0;
      flipped = false;
      knownNow.clear();
      missedNow.clear();
      stage = 1;
    });
    _prefetch();
  }

  void _answer(bool know) {
    final s = deck[index];
    final cur = boxes[s.scientific] ?? 0;
    boxes[s.scientific] = know ? math.min(cur + 1, _maxBox) : 0;
    (know ? knownNow : missedNow).add(s);
    _save();
    setState(() {
      if (index + 1 >= deck.length) {
        stage = 2;
      } else {
        index++;
        flipped = false;
      }
    });
    if (stage == 1) _prefetch();
  }

  // ---------- screens ----------
  @override
  Widget build(BuildContext context) {
    Widget body;
    if (!loaded) {
      body = const Center(child: CircularProgressIndicator());
    } else if (stage == 1) {
      body = _cards(context);
    } else if (stage == 2) {
      body = _done(context);
    } else {
      body = _setup(context);
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('Flashcards', 'ফ্ল্যাশকার্ড', 'フラッシュカード'))),
      body: SafeArea(child: body),
    );
  }

  Widget _setup(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final kingdoms = speciesData.map((s) => s.kingdom).toSet().toList()..sort();
    final missed = boxes.values.where((b) => b == 0).length;
    final mastered = boxes.values.where((b) => b >= _maxBox).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 40),
      children: [
        Text(t('Flip, recall, repeat.', 'উল্টাও, মনে করো, আবার করো।', 'めくって、思い出して、繰り返そう。'), style: text.titleMedium),
        const SizedBox(height: 4),
        Text(
          '${t('Seen', 'দেখা', '学習済み')}: ${boxes.length}  •  ${t('Mastered', 'আয়ত্ত', '習得')}: $mastered  •  ${t('To revise', 'রিভিশন বাকি', '要復習')}: $missed',
          style: text.bodySmall,
        ),
        const SizedBox(height: 18),
        Text(t('Which species?', 'কোন প্রজাতি?', 'どの種？'), style: text.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(
            label: Text(t('All', 'সব', 'すべて')),
            selected: kingdom == null,
            onSelected: (_) => setState(() => kingdom = null),
          ),
          for (final k in kingdoms)
            ChoiceChip(
              label: Text(k),
              selected: kingdom == k,
              onSelected: (_) => setState(() => kingdom = k),
            ),
        ]),
        const SizedBox(height: 18),
        Text(t('How many cards?', 'কয়টি কার্ড?', '何枚？'), style: text.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final n in const [10, 20, 30])
            ChoiceChip(
              label: Text('$n'),
              selected: count == n,
              onSelected: (_) => setState(() => count = n),
            ),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: onlyMissed,
          onChanged: missed == 0 ? null : (v) => setState(() => onlyMissed = v),
          title: Text(t('Only cards I missed', 'শুধু যেগুলো ভুল করেছি', '間違えたカードだけ')),
          subtitle: Text('$missed'),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: Text(t('Start', 'শুরু করো', 'スタート')),
        ),
      ],
    );
  }

  Widget _cards(BuildContext context) {
    final s = deck[index];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 8),
          child: Row(children: [
            Expanded(
              child: LinearProgressIndicator(
                value: index / deck.length,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            Text('${index + 1} / ${deck.length}'),
          ]),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
            child: GestureDetector(
              onTap: () => setState(() => flipped = !flipped),
              onHorizontalDragEnd: (d) {
                if (!flipped) return; // swipe only after you have seen the answer
                final v = d.primaryVelocity ?? 0;
                if (v > 350) {
                  _answer(true);
                } else if (v < -350) {
                  _answer(false);
                }
              },
              child: _flip(s),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
          child: Column(children: [
            Text(
              flipped
                  ? t('Swipe right = know, left = revise', 'ডানে সোয়াইপ = জানি, বামে = আবার দেখব', '右＝知っている、左＝要復習')
                  : t('Tap the card to flip', 'কার্ডে ট্যাপ করে উল্টাও', 'カードをタップしてめくる'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.orangeAccent),
                  onPressed: () => _answer(false),
                  icon: const Icon(Icons.replay),
                  label: Text(t('Need revision', 'আবার দেখব', '要復習')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _answer(true),
                  icon: const Icon(Icons.check),
                  label: Text(t('I know', 'জানি', '知っている')),
                ),
              ),
            ]),
          ]),
        ),
      ],
    );
  }

  Widget _flip(Species s) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('card-$index-${s.scientific}'),
      tween: Tween<double>(end: flipped ? 1.0 : 0.0),
      duration: Duration(milliseconds: fxEnabled.value ? 380 : 0),
      curve: Curves.easeInOutCubic,
      builder: (context, v, _) {
        final showBack = v > 0.5;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(v * math.pi),
          child: showBack
              ? Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()..rotateY(math.pi),
                  child: _backFace(context, s),
                )
              : _frontFace(context, s),
        );
      },
    );
  }

  Widget _frontFace(BuildContext context, Species s) {
    final text = Theme.of(context).textTheme;
    return SizedBox.expand(
      child: GlassCard(
        blur: false,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // the same photo widget as the species page, so it loads the same way
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: SpeciesHero(scientific: s.scientific, lang: lang),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              s.scientific,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: text.headlineSmall?.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.touch_app, size: 18),
              const SizedBox(width: 6),
              Text(t('Tap to flip', 'উল্টাতে ট্যাপ করো', 'タップしてめくる'), style: text.bodySmall),
            ]),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _backFace(BuildContext context, Species s) {
    final text = Theme.of(context).textTheme;
    final names = [s.common, s.bangla, s.japanese].where((e) => e.isNotEmpty && e != s.scientific).toList();
    final rows = <MapEntry<String, String>>[
      MapEntry(t('Kingdom', 'জগৎ', '界'), s.kingdom),
      MapEntry(t('Phylum', 'পর্ব', '門'), s.phylum),
      MapEntry(t('Class', 'শ্রেণি', '綱'), s.klass),
      MapEntry(t('Order', 'বর্গ', '目'), s.order),
      MapEntry(t('Family', 'গোত্র', '科'), s.family),
      MapEntry(t('Genus', 'গণ', '属'), s.genus),
    ].where((e) => e.value.isNotEmpty).toList();
    return SizedBox.expand(
      child: GlassCard(
        blur: false,
        padding: const EdgeInsets.all(18),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.scientific, style: text.titleLarge?.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              for (final n in names) Text(n, style: text.titleMedium),
              if (s.pronunciation.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.record_voice_over, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.pronunciation)),
                ]),
              ],
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 8),
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 84, child: Text(r.key, style: text.bodySmall)),
                    Expanded(child: Text(r.value, style: const TextStyle(fontStyle: FontStyle.italic))),
                  ]),
                ),
              if (s.description.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(s.description),
              ],
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () => widget.open(context, s, deck),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(t('Open details', 'বিস্তারিত দেখো', '詳細を見る')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _done(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
      children: [
        const Icon(Icons.emoji_events, size: 56),
        const SizedBox(height: 10),
        Text(t('Round finished!', 'রাউন্ড শেষ!', 'ラウンド終了！'), textAlign: TextAlign.center, style: text.headlineSmall),
        const SizedBox(height: 6),
        Text(
          '${t('Known', 'জানি', '知っている')}: ${knownNow.length}   •   ${t('To revise', 'আবার দেখব', '要復習')}: ${missedNow.length}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (missedNow.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _begin(List<Species>.of(missedNow)..shuffle(math.Random())),
            icon: const Icon(Icons.replay),
            label: Text('${t('Review missed', 'ভুলগুলো আবার', '間違いを復習')} (${missedNow.length})'),
          ),
        if (missedNow.isNotEmpty) const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => setState(() => stage = 0),
          icon: const Icon(Icons.tune),
          label: Text(t('New round', 'নতুন রাউন্ড', '新しいラウンド')),
        ),
        if (missedNow.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text(t('Missed this round', 'এই রাউন্ডে ভুল', 'このラウンドの間違い'), style: text.titleSmall),
          const SizedBox(height: 6),
          for (final s in missedNow)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.scientific, style: const TextStyle(fontStyle: FontStyle.italic)),
              subtitle: Text(s.common),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => widget.open(context, s, missedNow),
            ),
        ],
      ],
    );
  }
}
