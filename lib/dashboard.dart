import 'package:flutter/material.dart';

import 'data.dart';
import 'quiz.dart' show ScienceBackground;
import 'stats.dart';
import 'tree.dart' show OpenSpecies;

/// Study > My progress: what you have learned and where you are weak.
class DashboardPage extends StatefulWidget {
  final Lang lang;
  final OpenSpecies open;
  const DashboardPage({super.key, required this.lang, required this.open});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  Species? _find(String sci) {
    for (final s in speciesData) {
      if (s.scientific == sci) return s;
    }
    return null;
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _statCard(IconData icon, String value, String label) {
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 8),
            Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }

  Widget _ring() {
    final acc = stats.accuracy;
    return Expanded(
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: acc),
              duration: const Duration(milliseconds: 900),
              builder: (context, v, _) => SizedBox(
                width: 62,
                height: 62,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox(width: 62, height: 62, child: CircularProgressIndicator(value: v, strokeWidth: 7, backgroundColor: Colors.grey.withValues(alpha: .25))),
                  Text('${(v * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(t('Accuracy', 'সঠিক উত্তর', '正答率'), style: Theme.of(context).textTheme.bodyMedium)),
          ]),
        ),
      ),
    );
  }

  Widget _weekBars() {
    final counts = stats.last7Answered();
    var maxV = 1;
    for (final c in counts) {
      if (c > maxV) maxV = c;
    }
    final now = DateTime.now();
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: SizedBox(
          height: 130,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text(counts[i] == 0 ? '' : '${counts[i]}', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 3),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 6 + 80.0 * counts[i] / maxV),
                    duration: const Duration(milliseconds: 700),
                    builder: (context, h, _) => Container(
                      height: h,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: counts[i] == 0 ? Colors.grey.withValues(alpha: .3) : Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(letters[now.subtract(Duration(days: 6 - i)).weekday - 1], style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Reset progress?', 'প্রগ্রেস মুছবে?', '進捗をリセットしますか?')),
        content: Text(t('Quiz history and statistics will be deleted.', 'কুইজ হিস্ট্রি ও পরিসংখ্যান মুছে যাবে।', 'クイズ履歴と統計が削除されます。')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল', 'キャンセル'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Reset', 'মুছো', 'リセット'))),
        ],
      ),
    );
    if (ok != true) return;
    await stats.clearAll();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final weak = stats.weakFamilies();
    final recent = stats.viewed.map(_find).whereType<Species>().take(10).toList();
    final history = stats.quizzes.reversed.take(10).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(t('My progress', 'আমার অগ্রগতি', '学習の進捗')),
        actions: [
          IconButton(tooltip: t('Reset', 'মুছো', 'リセット'), onPressed: _reset, icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ScienceBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(children: [
              _statCard(Icons.school, '${stats.learnedCount}', '${t('species learned', 'টি প্রজাতি শেখা', '種を習得')} / ${speciesData.length}'),
              const SizedBox(width: 10),
              _statCard(Icons.quiz, '${stats.quizzes.length}', t('quizzes taken', 'টি কুইজ দেওয়া', '回のクイズ')),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _ring(),
              const SizedBox(width: 10),
              _statCard(Icons.local_fire_department, '${stats.dayStreak}', t('day streak', 'দিনের ধারা', '日連続')),
            ]),
            _heading(t('Questions this week', 'এই সপ্তাহের প্রশ্ন', '今週の問題数')),
            _weekBars(),
            _heading(t('Weak topics (families)', 'দুর্বল বিষয় (গোত্র)', '苦手な科')),
            if (weak.isEmpty)
              Text(t('Take a few quizzes to find your weak spots.', 'দুর্বল জায়গা জানতে কয়েকটা কুইজ দাও।', 'クイズに挑戦して苦手を見つけましょう。'))
            else
              for (final w in weak)
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(child: Text(w.family, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic))),
                        Text('${w.wrong} ${t('wrong of', 'ভুল,', '誤答')} ${w.total}'),
                      ]),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(value: w.accuracy, minHeight: 6, borderRadius: BorderRadius.circular(6)),
                    ]),
                  ),
                ),
            _heading(t('Recently viewed', 'সম্প্রতি দেখা', '最近見た種')),
            if (recent.isEmpty)
              Text(t('Species you open will show here.', 'যে প্রজাতি খুলবে এখানে দেখা যাবে।', '開いた種がここに表示されます。'))
            else
              for (final s in recent)
                Card(
                  elevation: 0,
                  child: ListTile(
                    title: Text(s.scientific, style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600)),
                    subtitle: Text(s.name(lang)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => widget.open(context, s, recent),
                  ),
                ),
            _heading(t('Quiz history', 'কুইজ হিস্ট্রি', 'クイズ履歴')),
            if (history.isEmpty)
              Text(t('No quizzes yet.', 'এখনো কোনো কুইজ হয়নি।', 'まだクイズがありません。'))
            else
              for (final q in history)
                Card(
                  elevation: 0,
                  child: ListTile(
                    leading: Icon(q.daily ? Icons.today : Icons.quiz_outlined),
                    title: Text('${q.correct}/${q.total} • ${q.total == 0 ? 0 : (q.correct * 100 / q.total).round()}%'),
                    subtitle: Text('${q.day} • ${q.daily ? t('Daily', 'দৈনিক', 'デイリー') : q.difficulty} • ${q.seconds ~/ 60}:${(q.seconds % 60).toString().padLeft(2, '0')}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
