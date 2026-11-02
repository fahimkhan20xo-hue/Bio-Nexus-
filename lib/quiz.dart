import 'dart:math';

import 'package:flutter/material.dart';

import 'data.dart';

enum QType { sciFromName, nameFromSci, familyOf, orderOf }

class QuizQuestion {
  final QType type;
  final Species species;
  final List<String> options;
  final int answer;
  const QuizQuestion(this.type, this.species, this.options, this.answer);
  String get correct => options[answer];
}

bool _valid(String v) => v.isNotEmpty && v != '-';

List<String> _pick(String correct, Iterable<String> candidates, Random rnd, int n) {
  final list = candidates.where((c) => _valid(c) && c != correct).toSet().toList();
  list.shuffle(rnd);
  return list.take(n).toList();
}

/// Builds up to [count] multiple-choice questions from [pool].
List<QuizQuestion> buildQuiz(Lang lang, List<Species> pool, int count, Random rnd) {
  final picks = List<Species>.from(pool)..shuffle(rnd);
  final out = <QuizQuestion>[];
  for (final s in picks) {
    if (out.length >= count) break;
    final types = <QType>[QType.sciFromName, QType.nameFromSci];
    if (_valid(s.family)) types.add(QType.familyOf);
    if (_valid(s.order)) types.add(QType.orderOf);
    final type = types[rnd.nextInt(types.length)];
    final src = pool.length >= 8 ? pool : speciesData;
    final sameKingdom = speciesData.where((o) => o.kingdom == s.kingdom).toList();

    String correct = '';
    List<String> wrong = [];
    switch (type) {
      case QType.sciFromName:
        correct = s.scientific;
        wrong = _pick(correct, src.map((o) => o.scientific), rnd, 3);
        break;
      case QType.nameFromSci:
        correct = s.name(lang);
        wrong = _pick(correct, src.map((o) => o.name(lang)), rnd, 3);
        break;
      case QType.familyOf:
        correct = s.family;
        wrong = _pick(correct, sameKingdom.map((o) => o.family), rnd, 3);
        if (wrong.length < 3) {
          wrong = _pick(correct, speciesData.map((o) => o.family), rnd, 3);
        }
        break;
      case QType.orderOf:
        correct = s.order;
        wrong = _pick(correct, sameKingdom.map((o) => o.order), rnd, 3);
        if (wrong.length < 3) {
          wrong = _pick(correct, speciesData.map((o) => o.order), rnd, 3);
        }
        break;
    }
    if (wrong.length < 2 || !_valid(correct)) continue;
    final options = <String>[correct, ...wrong]..shuffle(rnd);
    out.add(QuizQuestion(type, s, options, options.indexOf(correct)));
  }
  return out;
}

class QuizPage extends StatefulWidget {
  final Lang lang;
  const QuizPage({super.key, required this.lang});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final Random rnd = Random();
  int stage = 0; // 0 = setup, 1 = playing, 2 = result
  String category = 'all';
  int count = 10;
  List<QuizQuestion> questions = [];
  int index = 0;
  int score = 0;
  int? picked;
  final List<QuizQuestion> missed = [];

  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  List<Species> get pool => speciesData.where((s) {
        if (category == 'plants') return s.kingdom == 'Plantae';
        if (category == 'animals') return s.kingdom == 'Animalia';
        if (category == 'micro') return s.kingdom != 'Plantae' && s.kingdom != 'Animalia';
        return true;
      }).toList();

  void start() {
    final qs = buildQuiz(lang, pool, count, rnd);
    if (qs.isEmpty) return;
    setState(() {
      questions = qs;
      index = 0;
      score = 0;
      picked = null;
      missed.clear();
      stage = 1;
    });
  }

  void choose(int i) {
    if (picked != null) return;
    final q = questions[index];
    setState(() {
      picked = i;
      if (i == q.answer) {
        score++;
      } else {
        missed.add(q);
      }
    });
  }

  void next() {
    if (index + 1 >= questions.length) {
      setState(() => stage = 2);
    } else {
      setState(() {
        index++;
        picked = null;
      });
    }
  }

  String _prompt(QType type) {
    switch (type) {
      case QType.sciFromName:
        return t('Which scientific name belongs to this organism?', 'এই জীবটির বৈজ্ঞানিক নাম কোনটি?', 'この生物の学名はどれですか?');
      case QType.nameFromSci:
        return t('What is the common name of this species?', 'এই প্রজাতির সাধারণ নাম কোনটি?', 'この種の一般名はどれですか?');
      case QType.familyOf:
        return t('Which family does this species belong to?', 'এই প্রজাতিটি কোন গোত্রের (Family)?', 'この種はどの科に属しますか?');
      case QType.orderOf:
        return t('Which order does this species belong to?', 'এই প্রজাতিটি কোন বর্গের (Order)?', 'この種はどの目に属しますか?');
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (stage == 0) {
      body = _setup();
    } else if (stage == 1) {
      body = _play();
    } else {
      body = _result();
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('Quick quiz', 'কুইক কুইজ', 'クイッククイズ'))),
      body: SafeArea(child: body),
    );
  }

  Widget _setup() {
    final n = pool.length;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Text(t('Test your knowledge', 'নিজেকে যাচাই করো', '実力を試そう'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 18),
        Text(t('Category', 'বিভাগ', 'カテゴリー'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(t('All', 'সব', 'すべて'), category == 'all', () => setState(() => category = 'all')),
          _chip(t('Plants', 'উদ্ভিদ', '植物'), category == 'plants', () => setState(() => category = 'plants')),
          _chip(t('Animals', 'প্রাণী', '動物'), category == 'animals', () => setState(() => category = 'animals')),
          _chip(t('Microbes', 'অণুজীব', '微生物'), category == 'micro', () => setState(() => category = 'micro')),
        ]),
        const SizedBox(height: 18),
        Text(t('Number of questions', 'প্রশ্নের সংখ্যা', '問題数'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final c in [5, 10, 20]) _chip('$c', count == c, () => setState(() => count = c)),
        ]),
        const SizedBox(height: 14),
        Text('$n ${t('species available', 'টি প্রজাতি পাওয়া যাবে', '種から出題')}', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: n >= 4 ? start : null,
          icon: const Icon(Icons.play_arrow),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(t('Start quiz', 'কুইজ শুরু করো', 'クイズを始める')),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());

  Widget _play() {
    final q = questions[index];
    final answered = picked != null;
    final isLast = index + 1 >= questions.length;
    final sciSubject = q.type != QType.sciFromName;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        LinearProgressIndicator(value: index / questions.length, minHeight: 6, borderRadius: BorderRadius.circular(6)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: Text('${t('Question', 'প্রশ্ন', '問題')} ${index + 1}/${questions.length}')),
          Text('${t('Score', 'স্কোর', 'スコア')}: $score', style: const TextStyle(fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_prompt(q.type), style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 10),
              Text(
                sciSubject ? q.species.scientific : q.species.name(lang),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontStyle: sciSubject ? FontStyle.italic : FontStyle.normal,
                    ),
              ),
              if (!sciSubject && q.species.common != q.species.name(lang))
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.species.common)),
              if (sciSubject && q.type != QType.nameFromSci)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.species.names(lang))),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < q.options.length; i++) _option(q, i),
        const SizedBox(height: 10),
        if (answered)
          FilledButton(
            onPressed: next,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(isLast ? t('See result', 'ফলাফল দেখো', '結果を見る') : t('Next', 'পরের প্রশ্ন', '次へ')),
            ),
          ),
      ],
    );
  }

  Widget _option(QuizQuestion q, int i) {
    final answered = picked != null;
    final isCorrect = i == q.answer;
    final isPicked = picked == i;
    Color? bg;
    Color border = Theme.of(context).dividerColor;
    if (answered && isCorrect) {
      bg = Colors.green.withValues(alpha: .18);
      border = Colors.green;
    } else if (answered && isPicked) {
      bg = Colors.red.withValues(alpha: .18);
      border = Colors.red;
    }
    final italic = q.type == QType.sciFromName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: answered ? null : () => choose(i),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 1.4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Expanded(
              child: Text(q.options[i],
                  style: TextStyle(fontSize: 16, fontStyle: italic ? FontStyle.italic : FontStyle.normal)),
            ),
            if (answered && isCorrect)
              const Icon(Icons.check_circle, color: Colors.green)
            else if (answered && isPicked)
              const Icon(Icons.cancel, color: Colors.red),
          ]),
        ),
      ),
    );
  }

  Widget _result() {
    final total = questions.length;
    final pct = total == 0 ? 0 : (score * 100 / total).round();
    final msg = pct >= 80
        ? t('Excellent work!', 'চমৎকার!', '素晴らしい!')
        : pct >= 50
            ? t('Good job, keep practicing.', 'ভালো হয়েছে, আরও অনুশীলন করো।', 'よくできました。もう少し練習しましょう。')
            : t('Keep going, you will improve!', 'চালিয়ে যাও, উন্নতি হবে!', '続ければ必ず上達します!');
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 10),
        Center(child: Text('$score / $total', style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.bold))),
        Center(child: Text('$pct%', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 8),
        Center(child: Text(msg)),
        const SizedBox(height: 18),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: start,
              child: Text(t('Play again', 'আবার খেলো', 'もう一度')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => stage = 0),
              child: Text(t('Change settings', 'সেটিংস বদলাও', '設定を変更')),
            ),
          ),
        ]),
        if (missed.isNotEmpty) ...[
          const SizedBox(height: 22),
          Text(t('Review your mistakes', 'ভুলগুলো দেখো', '間違えた問題'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (final q in missed)
            Card(
              elevation: 0,
              child: ListTile(
                title: Text(q.species.scientific, style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
                subtitle: Text('${q.species.names(lang)}\n${t('Answer', 'উত্তর', '正解')}: ${q.correct}'),
                isThreeLine: true,
              ),
            ),
        ],
      ],
    );
  }
}
