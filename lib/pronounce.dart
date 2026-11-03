import 'dart:math';

import 'package:flutter/material.dart';

import 'data.dart';
import 'quiz.dart' show ScienceBackground;
import 'speech.dart';

/// Study > Audio pronunciation: go through species one by one and listen.
class PronouncePage extends StatefulWidget {
  final Lang lang;
  const PronouncePage({super.key, required this.lang});

  @override
  State<PronouncePage> createState() => _PronouncePageState();
}

class _PronouncePageState extends State<PronouncePage> {
  final _rng = Random();
  late List<Species> items;
  int index = 0;
  bool slow = false;
  bool autoplay = false;

  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  @override
  void initState() {
    super.initState();
    items = speciesData.where((s) => s.scientific.isNotEmpty).toList()..shuffle(_rng);
  }

  @override
  void dispose() {
    stopSpeaking();
    super.dispose();
  }

  Future<void> _say(String text, String speechLang) async {
    final r = await speakText(text, lang: speechLang, slow: slow);
    final msg = speakFailMessage(lang, speechLang, r);
    if (msg != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  void _move(int delta) {
    setState(() => index = (index + delta + items.length) % items.length);
    if (autoplay) _say(items[index].scientific, 'en');
  }

  void _reshuffle() {
    stopSpeaking();
    setState(() {
      items.shuffle(_rng);
      index = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      title: Text(t('Audio pronunciation', 'অডিও উচ্চারণ', '発音音声')),
      actions: [
        IconButton(
          tooltip: t('Shuffle', 'এলোমেলো', 'シャッフル'),
          onPressed: items.isEmpty ? null : _reshuffle,
          icon: const Icon(Icons.shuffle),
        ),
      ],
    );
    if (items.isEmpty) {
      return Scaffold(appBar: appBar, body: Center(child: Text(t('No species available.', 'কোনো প্রজাতি নেই।', '種がありません。'))));
    }
    final s = items[index];
    return Scaffold(
      appBar: appBar,
      body: ScienceBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            LinearProgressIndicator(value: (index + 1) / items.length),
            const SizedBox(height: 8),
            Text('${index + 1} / ${items.length}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    s.scientific,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(s.names(lang), style: Theme.of(context).textTheme.titleMedium),
                  if (s.pronunciation.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(t('Pronunciation guide', 'উচ্চারণ নির্দেশিকা', '発音ガイド'), style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(s.pronunciation, style: Theme.of(context).textTheme.titleLarge),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _say(s.scientific, 'en'),
                  icon: const Icon(Icons.volume_up),
                  label: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(t('Listen (Latin)', 'শুনো (ল্যাটিন)', '聞く(ラテン語)')),
                  ),
                ),
              ),
              if (s.pronunciation.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _say(s.pronunciation, 'bn'),
                    icon: const Icon(Icons.record_voice_over),
                    label: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(t('Listen (Bangla)', 'শুনো (বাংলা)', '聞く(ベンガル語)')),
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(t('Normal', 'স্বাভাবিক', '通常'))),
                ButtonSegment(value: true, label: Text(t('Slow', 'ধীরে', 'ゆっくり'))),
              ],
              selected: {slow},
              onSelectionChanged: (v) => setState(() => slow = v.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: autoplay,
              onChanged: (v) => setState(() => autoplay = v),
              title: Text(t('Play automatically on next', 'পরেরটায় গেলে নিজে থেকে চলুক', '次へ進むと自動再生')),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _move(-1),
                  icon: const Icon(Icons.chevron_left),
                  label: Padding(padding: const EdgeInsets.all(8), child: Text(t('Previous', 'আগেরটা', '前へ'))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => _move(1),
                  icon: const Icon(Icons.chevron_right),
                  label: Padding(padding: const EdgeInsets.all(8), child: Text(t('Next', 'পরেরটা', '次へ'))),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
