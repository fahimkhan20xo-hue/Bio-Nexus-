import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'data.dart';
import 'stats.dart';

// ---------------------------------------------------------------------------
// Saved app settings (language + theme). Stored in a small JSON file so they
// survive closing the app. Uses path_provider, which the app already has.
// ---------------------------------------------------------------------------

class AppPrefs {
  final Lang lang;
  final bool dark;
  const AppPrefs(this.lang, this.dark);
}

Future<File> _prefsFile() async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}/bionexus_prefs.json');
}

Future<AppPrefs?> loadAppPrefs() async {
  try {
    final f = await _prefsFile();
    if (!await f.exists()) return null;
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    final i = Lang.values.indexWhere((l) => l.name == m['lang']);
    return AppPrefs(i < 0 ? Lang.bn : Lang.values[i], m['dark'] == true);
  } catch (e) {
    debugPrint('Could not load prefs: $e');
    return null;
  }
}

Future<void> saveAppPrefs(Lang lang, bool dark) async {
  try {
    final f = await _prefsFile();
    await f.writeAsString(jsonEncode({'lang': lang.name, 'dark': dark}), flush: true);
  } catch (e) {
    debugPrint('Could not save prefs: $e');
  }
}

// ---------------------------------------------------------------------------
// Quiz
// ---------------------------------------------------------------------------

enum _Stage { setup, running, result }

enum _QType { sci, family, order }

enum _Mode { sci, family, order, mixed }

enum _Diff { easy, medium, hard }

class _Q {
  final _QType type;
  final Species s;
  final String answer;
  final List<String> options;
  const _Q(this.type, this.s, this.answer, this.options);
}

class _Miss {
  final _Q q;
  final String picked; // '' = no answer (time ran out)
  const _Miss(this.q, this.picked);
}

class QuizPage extends StatefulWidget {
  final Lang lang;
  const QuizPage({super.key, required this.lang});

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  int secs = 20; // seconds per question when the timer is on
  final TextEditingController _secCtl = TextEditingController(text: '20');

  Random _rng = Random();
  _Stage stage = _Stage.setup;
  int count = 10;
  _Mode mode = _Mode.mixed;
  _Diff diff = _Diff.medium;
  bool timed = false;
  bool daily = false;

  List<_Q> questions = [];
  List<_Miss> misses = [];
  List<AnswerRec> recs = [];
  int index = 0;
  int score = 0;
  int streak = 0;
  int bestStreak = 0;
  int left = 20;
  int elapsedSeconds = 0;
  String? picked;
  Timer? _timer;
  final Stopwatch _watch = Stopwatch();

  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  @override
  void dispose() {
    _timer?.cancel();
    _secCtl.dispose();
    super.dispose();
  }

  // ---------- building questions ----------

  String _value(_QType type, Species s) =>
      type == _QType.sci ? s.scientific : (type == _QType.family ? s.family : s.order);

  Species? _bySci(String name) {
    for (final s in speciesData) {
      if (s.scientific == name) return s;
    }
    return null;
  }

  Species? _example(_QType type, String value, Species except) {
    final list = speciesData.where((e) => _value(type, e) == value && e.scientific != except.scientific).toList();
    return list.isEmpty ? null : list[_rng.nextInt(list.length)];
  }

  /// How many taxonomy levels two species share, counted from kingdom downwards.
  int _shared(Species a, Species b) {
    final pairs = [
      [a.kingdom, b.kingdom],
      [a.phylum, b.phylum],
      [a.klass, b.klass],
      [a.order, b.order],
      [a.family, b.family],
      [a.genus, b.genus],
    ];
    var n = 0;
    for (final p in pairs) {
      if (p[0] != p[1]) break;
      n++;
    }
    return n;
  }

  List<String> _makeOptions(_QType type, Species s, String answer) {
    final seen = <String>{answer};
    final cands = <MapEntry<String, int>>[];
    for (final e in speciesData) {
      final v = _value(type, e);
      if (v.isEmpty || !seen.add(v)) continue;
      cands.add(MapEntry(v, _shared(s, e)));
    }
    cands.shuffle(_rng);
    if (diff == _Diff.hard) {
      cands.sort((a, b) => b.value.compareTo(a.value)); // closest relatives first
    } else if (diff == _Diff.easy) {
      cands.sort((a, b) => a.value.compareTo(b.value)); // most different first
    } else {
      cands.sort((a, b) => (b.value > 0 ? 1 : 0).compareTo(a.value > 0 ? 1 : 0)); // same kingdom first
    }
    final picks = cands.take(3).map((e) => e.key).toList();
    return [answer, ...picks]..shuffle(_rng);
  }

  List<_Q> _build(int n, _Mode m) {
    final all = speciesData.where((s) => s.scientific.isNotEmpty).toList()..shuffle(_rng);
    final out = <_Q>[];
    for (final s in all) {
      if (out.length >= n) break;
      final types = <_QType>[];
      if (m == _Mode.sci || m == _Mode.mixed) types.add(_QType.sci);
      if ((m == _Mode.family || m == _Mode.mixed) && s.family.isNotEmpty) types.add(_QType.family);
      if ((m == _Mode.order || m == _Mode.mixed) && s.order.isNotEmpty) types.add(_QType.order);
      if (types.isEmpty) continue;
      final type = types[_rng.nextInt(types.length)];
      final answer = _value(type, s);
      final opts = _makeOptions(type, s, answer);
      if (opts.length < 2) continue;
      out.add(_Q(type, s, answer, opts));
    }
    return out;
  }

  // ---------- explanations ----------

  String _info(_Q q) {
    final s = q.s;
    final n = s.name(lang);
    switch (q.type) {
      case _QType.sci:
        return t(
          '${s.scientific} is the scientific name of $n (family ${s.family}).',
          '${s.scientific} হলো $n-এর বৈজ্ঞানিক নাম (গোত্র: ${s.family})।',
          '${s.scientific} は$nの学名です(科: ${s.family})。',
        );
      case _QType.family:
        return t(
          '${s.scientific} ($n) belongs to family ${s.family} (order ${s.order}, class ${s.klass}).',
          '${s.scientific} ($n) গোত্র ${s.family}-এর অন্তর্গত (বর্গ: ${s.order}, শ্রেণি: ${s.klass})।',
          '${s.scientific}($n)は${s.family}科に属します(目: ${s.order}、綱: ${s.klass})。',
        );
      case _QType.order:
        return t(
          '${s.scientific} ($n) belongs to order ${s.order} (class ${s.klass}, family ${s.family}).',
          '${s.scientific} ($n) বর্গ ${s.order}-এর অন্তর্গত (শ্রেণি: ${s.klass}, গোত্র: ${s.family})।',
          '${s.scientific}($n)は${s.order}目に属します(綱: ${s.klass}、科: ${s.family})。',
        );
    }
  }

  String _wrongNote(_Q q, String pickedValue) {
    if (pickedValue.isEmpty) return '';
    if (q.type == _QType.sci) {
      final p = _bySci(pickedValue);
      if (p == null) return '';
      final pn = p.name(lang);
      return t(
        'You chose $pickedValue, which is the scientific name of $pn (family ${p.family}).',
        'তুমি $pickedValue বেছেছ, এটি $pn-এর বৈজ্ঞানিক নাম (গোত্র: ${p.family})।',
        '選んだ $pickedValue は$pnの学名です(科: ${p.family})。',
      );
    }
    final ex = _example(q.type, pickedValue, q.s);
    final label = q.type == _QType.family ? t('family', 'গোত্র', '科') : t('order', 'বর্গ', '目');
    final exText = ex == null ? '' : '${ex.scientific} (${ex.name(lang)})';
    return t(
      'You chose $pickedValue, a different $label${ex == null ? '.' : ' that includes, for example, $exText.'}',
      'তুমি $pickedValue বেছেছ, এটি অন্য একটি $label${ex == null ? '।' : '; যেমন এর মধ্যে আছে $exText।'}',
      '選んだ $pickedValue は別の$labelです${ex == null ? '。' : '(例: $exText)。'}',
    );
  }

  String _explain(_Q q, String chosen) {
    if (chosen == q.answer) return _info(q);
    final note = _wrongNote(q, chosen);
    return note.isEmpty ? _info(q) : '${_info(q)}\n$note';
  }

  // ---------- actions ----------

  void _begin(List<_Q> qs) {
    if (qs.isEmpty) return;
    _timer?.cancel();
    _watch
      ..reset()
      ..start();
    setState(() {
      questions = qs;
      misses = [];
      recs = [];
      index = 0;
      score = 0;
      streak = 0;
      bestStreak = 0;
      left = secs;
      picked = null;
      stage = _Stage.running;
    });
    _startTimer();
  }

  void _startPractice() {
    daily = false;
    _begin(_build(count, mode));
  }

  void _startDaily() {
    final now = DateTime.now();
    daily = true;
    diff = _Diff.medium;
    mode = _Mode.mixed;
    timed = false;
    _rng = Random(now.year * 10000 + now.month * 100 + now.day); // same questions all day
    final qs = _build(10, _Mode.mixed);
    _rng = Random();
    _begin(qs);
  }

  void _practiceMistakes() {
    daily = false;
    final qs = misses.map((m) => _Q(m.q.type, m.q.s, m.q.answer, [...m.q.options]..shuffle(_rng))).toList();
    _begin(qs);
  }

  void _startTimer() {
    _timer?.cancel();
    if (!timed || stage != _Stage.running) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (tm) {
      if (!mounted || picked != null) {
        tm.cancel();
        return;
      }
      setState(() => left--);
      if (left <= 0) {
        tm.cancel();
        _answer(null);
      }
    });
  }

  void _answer(String? o) {
    if (picked != null) return;
    _timer?.cancel();
    final q = questions[index];
    final ok = o == q.answer;
    if (ok) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.heavyImpact();
    }
    recs.add(AnswerRec(
      day: dayKey(DateTime.now()),
      sci: q.s.scientific,
      type: q.type.name,
      family: q.s.family,
      kingdom: q.s.kingdom,
      ok: ok,
    ));
    setState(() {
      picked = o ?? '';
      if (ok) {
        score++;
        streak++;
        if (streak > bestStreak) bestStreak = streak;
      } else {
        streak = 0;
        misses.add(_Miss(q, o ?? ''));
      }
    });
  }

  void _next() {
    if (index + 1 >= questions.length) {
      _finish();
      return;
    }
    setState(() {
      picked = null;
      index++;
      left = secs;
    });
    _startTimer();
  }

  Future<void> _finish() async {
    _timer?.cancel();
    _watch.stop();
    elapsedSeconds = _watch.elapsed.inSeconds;
    final rec = QuizRec(
      ts: DateTime.now().toIso8601String(),
      total: questions.length,
      correct: score,
      seconds: elapsedSeconds,
      bestStreak: bestStreak,
      mode: mode.name,
      difficulty: diff.name,
      daily: daily,
      timed: timed,
    );
    setState(() {
      picked = null;
      stage = _Stage.result;
    });
    await stats.addQuiz(rec, recs);
    if (mounted) setState(() {});
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (stage) {
      case _Stage.setup:
        body = _setup();
        break;
      case _Stage.running:
        body = _question(questions[index]);
        break;
      case _Stage.result:
        body = _result();
        break;
    }
    return Scaffold(
      appBar: AppBar(title: Text(t('Quick quiz', 'কুইক কুইজ', 'クイッククイズ'))),
      body: ScienceBackground(child: body),
    );
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
      );

  Widget _setup() {
    final modes = <_Mode, String>{
      _Mode.mixed: t('Mixed', 'মিশ্র', 'ミックス'),
      _Mode.sci: t('Scientific names', 'বৈজ্ঞানিক নাম', '学名'),
      _Mode.family: t('Family', 'গোত্র', '科'),
      _Mode.order: t('Order', 'বর্গ', '目'),
    };
    final diffs = <_Diff, String>{
      _Diff.easy: t('Easy', 'সহজ', 'かんたん'),
      _Diff.medium: t('Medium', 'মাঝারি', 'ふつう'),
      _Diff.hard: t('Hard', 'কঠিন', 'むずかしい'),
    };
    final doneToday = stats.dailyDoneToday;
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: ListTile(
            leading: Icon(Icons.today, color: Theme.of(context).colorScheme.onPrimaryContainer),
            title: Text(t('Daily challenge', 'দৈনিক চ্যালেঞ্জ', 'デイリーチャレンジ'),
                style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onPrimaryContainer)),
            subtitle: Text(
              doneToday
                  ? t('Done today. Streak: ${stats.dayStreak} days', 'আজ শেষ। ধারা: ${stats.dayStreak} দিন', '今日は完了。連続: ${stats.dayStreak}日')
                  : t('10 mixed questions, new every day', '১০টি মিশ্র প্রশ্ন, প্রতিদিন নতুন', '毎日新しい10問'),
              style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            trailing: FilledButton(
              onPressed: _startDaily,
              child: Text(doneToday ? t('Again', 'আবার', 'もう一度') : t('Start', 'শুরু', '開始')),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(t('Practice setup', 'প্র্যাকটিস সেটআপ', '練習の設定'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        _heading(t('Number of questions', 'কয়টি প্রশ্ন', '問題数')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in [10, 20, 30, 50])
            ChoiceChip(label: Text('$c'), selected: count == c, onSelected: (_) => setState(() => count = c)),
        ]),
        _heading(t('Question type', 'প্রশ্নের ধরন', '問題の種類')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in modes.entries)
            ChoiceChip(label: Text(e.value), selected: mode == e.key, onSelected: (_) => setState(() => mode = e.key)),
        ]),
        _heading(t('Difficulty', 'কঠিনতা', '難易度')),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in diffs.entries)
            ChoiceChip(label: Text(e.value), selected: diff == e.key, onSelected: (_) => setState(() => diff = e.key)),
        ]),
        const SizedBox(height: 4),
        Text(
          diff == _Diff.hard
              ? t('Wrong options are close relatives.', 'ভুল অপশনগুলো কাছের আত্মীয়।', '誤答は近縁種になります。')
              : diff == _Diff.easy
                  ? t('Wrong options are very different species.', 'ভুল অপশনগুলো একদম আলাদা প্রজাতির।', '誤答はまったく違う種になります。')
                  : t('Wrong options are mostly from the same group.', 'ভুল অপশন বেশিরভাগ একই দলের।', '誤答は主に同じグループです。'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: timed,
          onChanged: (v) => setState(() => timed = v),
          title: Text(t('Timed quiz', 'সময় সীমা সহ কুইজ', '時間制限つき')),
          subtitle: Text(timed
              ? t('Set the seconds for each question', 'প্রতি প্রশ্নের সেকেন্ড ঠিক করো', '1問あたりの秒数を設定')
              : t('Off', 'বন্ধ', 'オフ')),
        ),
        if (timed) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final v in [5, 10, 20, 30, 60])
              ChoiceChip(
                label: Text('${v}s'),
                selected: secs == v,
                onSelected: (_) => setState(() {
                  secs = v;
                  _secCtl.text = '$v';
                }),
              ),
          ]),
          const SizedBox(height: 10),
          SizedBox(
            width: 190,
            child: TextField(
              controller: _secCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t('Custom seconds (1 - 600)', 'নিজের সেকেন্ড (১ - ৬০০)', '秒数を入力 (1〜600)'),
                suffixText: 's',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) {
                final n = int.tryParse(v.trim());
                if (n != null) setState(() => secs = n.clamp(1, 600));
              },
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: speciesData.length < 4 ? null : _startPractice,
          child: Padding(padding: const EdgeInsets.all(10), child: Text(t('Start', 'শুরু করো', 'スタート'))),
        ),
      ],
    );
  }

  Widget _optionTile(_Q q, String o) {
    final answered = picked != null;
    final isCorrect = o == q.answer;
    final isPicked = o == picked;
    Color? bg;
    Color? border;
    IconData? icon;
    Color? iconColor;
    if (answered && isCorrect) {
      bg = Colors.green.withValues(alpha: .25);
      border = Colors.green;
      icon = Icons.check_circle;
      iconColor = Colors.green;
    } else if (answered && isPicked) {
      bg = Colors.red.withValues(alpha: .22);
      border = Colors.red;
      icon = Icons.cancel;
      iconColor = Colors.red;
    }
    return Card(
      elevation: 0,
      color: bg,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border ?? Theme.of(context).dividerColor.withValues(alpha: .6), width: border == null ? 1 : 2),
      ),
      child: ListTile(
        title: Text(o, style: TextStyle(fontStyle: q.type == _QType.sci ? FontStyle.italic : FontStyle.normal)),
        trailing: icon == null ? null : Icon(icon, color: iconColor),
        onTap: answered ? null : () => _answer(o),
      ),
    );
  }

  Widget _question(_Q q) {
    final s = q.s;
    String prompt;
    switch (q.type) {
      case _QType.sci:
        prompt = t('What is the scientific name of:', 'এর বৈজ্ঞানিক নাম কী:', '学名はどれ:');
        break;
      case _QType.family:
        prompt = t('Which family does this species belong to?', 'এই প্রজাতিটি কোন গোত্রের?', 'この種は何科?');
        break;
      case _QType.order:
        prompt = t('Which order does this species belong to?', 'এই প্রজাতিটি কোন বর্গের?', 'この種は何目?');
        break;
    }
    final title = q.type == _QType.sci ? s.name(lang) : s.scientific;
    final answered = picked != null;
    final correct = picked == q.answer;
    final timeUp = answered && picked!.isEmpty;
    final last = index + 1 >= questions.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LinearProgressIndicator(value: (index + (answered ? 1 : 0)) / questions.length),
        const SizedBox(height: 10),
        Row(children: [
          Text('${index + 1} / ${questions.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Icon(Icons.local_fire_department, size: 20, color: streak > 0 ? Colors.deepOrange : Colors.grey),
          const SizedBox(width: 2),
          Text('$streak'),
          const SizedBox(width: 14),
          Text('${t('Score', 'স্কোর', 'スコア')}: $score'),
        ]),
        if (timed && !answered) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.timer_outlined, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: LinearProgressIndicator(
                value: left / secs,
                minHeight: 6,
                borderRadius: BorderRadius.circular(6),
                color: left <= 5 ? Colors.red : null,
              ),
            ),
            const SizedBox(width: 8),
            Text('$left'),
          ]),
        ],
        const SizedBox(height: 16),
        Text(prompt, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Text(title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontStyle: q.type == _QType.sci ? FontStyle.normal : FontStyle.italic,
                )),
        const SizedBox(height: 16),
        for (final o in q.options) _optionTile(q, o),
        if (answered) ...[
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (correct ? Colors.green : (timeUp ? Colors.orange : Colors.red)).withValues(alpha: .1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                correct
                    ? t('Correct!', 'সঠিক!', '正解!')
                    : (timeUp ? t("Time's up", 'সময় শেষ', '時間切れ') : t('Wrong', 'ভুল', '不正解')),
                style: TextStyle(fontWeight: FontWeight.bold, color: correct ? Colors.green : (timeUp ? Colors.orange : Colors.red)),
              ),
              const SizedBox(height: 6),
              Text(_explain(q, picked!)),
            ]),
          ),
          FilledButton(
            onPressed: _next,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(last ? t('See result', 'ফলাফল দেখো', '結果を見る') : t('Next', 'পরবর্তী', '次へ')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _typeRow(_QType type, String label) {
    final list = recs.where((r) => r.type == type.name).toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final ok = list.where((r) => r.ok).length;
    final pct = (ok * 100 / list.length).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label)),
          Text('$ok/${list.length} ($pct%)'),
        ]),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: ok / list.length, minHeight: 6, borderRadius: BorderRadius.circular(6)),
      ]),
    );
  }

  Widget _result() {
    final total = questions.length;
    final percent = total == 0 ? 0 : (score * 100 / total).round();
    final mm = elapsedSeconds ~/ 60;
    final ss = (elapsedSeconds % 60).toString().padLeft(2, '0');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 4),
        Icon(percent >= 80 ? Icons.emoji_events : Icons.insights, size: 60),
        const SizedBox(height: 6),
        Center(child: Text('$score / $total', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold))),
        Center(child: Text('$percent%', style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 14),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(t('Performance report', 'পারফরম্যান্স রিপোর্ট', '成績レポート'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.timer_outlined, size: 18),
                const SizedBox(width: 6),
                Text('${t('Time', 'সময়', '時間')}: $mm:$ss'),
                const Spacer(),
                const Icon(Icons.local_fire_department, size: 18, color: Colors.deepOrange),
                const SizedBox(width: 4),
                Text('${t('Best streak', 'সেরা ধারা', '最高連続')}: $bestStreak'),
              ]),
              const SizedBox(height: 12),
              _typeRow(_QType.sci, t('Scientific names', 'বৈজ্ঞানিক নাম', '学名')),
              _typeRow(_QType.family, t('Family', 'গোত্র', '科')),
              _typeRow(_QType.order, t('Order', 'বর্গ', '目')),
              if (daily)
                Text(
                  t('Daily challenge done. Streak: ${stats.dayStreak} days', 'দৈনিক চ্যালেঞ্জ শেষ। ধারা: ${stats.dayStreak} দিন', 'デイリー完了。連続: ${stats.dayStreak}日'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: () => setState(() => stage = _Stage.setup),
          child: Padding(padding: const EdgeInsets.all(8), child: Text(t('New quiz', 'নতুন কুইজ', '新しいクイズ'))),
        ),
        if (misses.isNotEmpty) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _practiceMistakes,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text(t('Practice my mistakes again', 'ভুলগুলো আবার প্র্যাকটিস করো', '間違いをもう一度')),
            ),
          ),
          _heading('${t('Your mistakes', 'তোমার ভুলগুলো', '間違えた問題')} (${misses.length})'),
          for (final m in misses) _missCard(m),
        ] else
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Center(child: Text(t('No mistakes. Great job!', 'কোনো ভুল নেই। দারুণ!', '間違いなし。すばらしい!'))),
          ),
      ],
    );
  }

  Widget _missCard(_Miss m) {
    final q = m.q;
    final isSci = q.type == _QType.sci;
    final title = isSci ? q.s.name(lang) : q.s.scientific;
    TextStyle italicIf(bool on) => TextStyle(fontStyle: on ? FontStyle.italic : FontStyle.normal, fontWeight: FontWeight.w600);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, fontStyle: isSci ? FontStyle.normal : FontStyle.italic)),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.cancel, color: Colors.red, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: m.picked.isEmpty
                  ? Text(t('No answer (time ran out)', 'উত্তর দেওয়া হয়নি (সময় শেষ)', '未回答(時間切れ)'))
                  : Text(m.picked, style: italicIf(isSci)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 18),
            const SizedBox(width: 6),
            Expanded(child: Text(q.answer, style: italicIf(isSci))),
          ]),
          const SizedBox(height: 8),
          Text(_explain(q, m.picked), style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated science background: rotating DNA helices + drifting cells/molecules
// Pure Flutter drawing, no extra packages or image files.
// ---------------------------------------------------------------------------

final Stopwatch _bgClock = Stopwatch()..start();

/// Set to true while the screen is being swiped/scrolled so the background stops drawing.
final ValueNotifier<bool> bgPaused = ValueNotifier<bool>(false);

double _fr(double v) => v - v.floorToDouble();

class ScienceBackground extends StatefulWidget {
  final Widget child;
  const ScienceBackground({super.key, required this.child});

  @override
  State<ScienceBackground> createState() => _ScienceBackgroundState();
}

class _ScienceBackgroundState extends State<ScienceBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 1))..repeat();

  @override
  void initState() {
    super.initState();
    bgPaused.addListener(_onPause);
  }

  void _onPause() {
    if (bgPaused.value) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    bgPaused.removeListener(_onPause);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: RepaintBoundary(child: CustomPaint(painter: _BgPainter(_c, color))),
        ),
      ),
      widget.child,
    ]);
  }
}

class _BgPainter extends CustomPainter {
  final Color color;
  _BgPainter(Listenable repaint, this.color) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final t = _bgClock.elapsedMilliseconds / 1000.0;
    _molecules(canvas, size, t);
    _helix(canvas, size, t, cx: size.width * 0.10, amp: 34, speed: 0.9, alpha: .30);
    _helix(canvas, size, t, cx: size.width * 0.92, amp: 26, speed: -0.7, alpha: .22);
  }

  void _helix(Canvas canvas, Size size, double t,
      {required double cx, required double amp, required double speed, required double alpha}) {
    final strand = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..color = color.withValues(alpha: alpha * .6);
    final rung = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: alpha * .7);
    final fill = Paint()..style = PaintingStyle.fill;
    final pa = Path();
    final pb = Path();
    final n = (size.height / 14).ceil() + 3;
    final rows = <List<double>>[];
    for (var i = 0; i < n; i++) {
      final y = -14.0 + i * 14.0;
      final th = y * 0.02 + t * speed;
      final s = sin(th);
      final c = cos(th);
      final ax = cx + amp * s;
      final bx = cx - amp * s;
      if (i == 0) {
        pa.moveTo(ax, y);
        pb.moveTo(bx, y);
      } else {
        pa.lineTo(ax, y);
        pb.lineTo(bx, y);
      }
      rows.add([y, ax, bx, c]);
    }
    canvas.drawPath(pa, strand);
    canvas.drawPath(pb, strand);
    void dot(double x, double y, double z) {
      fill.color = color.withValues(alpha: (alpha * (0.55 + 0.45 * z)).clamp(0.0, 1.0));
      canvas.drawCircle(Offset(x, y), 3.6 + 2.2 * z, fill);
    }

    for (var i = 0; i < rows.length; i++) {
      final y = rows[i][0], ax = rows[i][1], bx = rows[i][2], c = rows[i][3];
      if (i.isEven) canvas.drawLine(Offset(ax, y), Offset(bx, y), rung);
      if (c >= 0) {
        dot(bx, y, -c);
        dot(ax, y, c);
      } else {
        dot(ax, y, c);
        dot(bx, y, -c);
      }
    }
  }

  void _molecules(Canvas canvas, Size size, double t) {
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (var k = 1; k <= 10; k++) {
      final fx = _fr(sin(k * 12.9898) * 43758.5453);
      final fy = _fr(sin(k * 78.233) * 12345.6789);
      final fz = _fr(sin(k * 39.425) * 9876.5432);
      final r = 9 + fz * 15;
      final x = fx * size.width + 16 * sin(t * .35 + k);
      final y = (fy * size.height - t * (6 + fz * 8)) % size.height;
      final a = .10 + .08 * fz;
      line.color = color.withValues(alpha: a * 1.5);
      fill.color = color.withValues(alpha: a);
      final p = Offset(x, y);
      switch (k % 3) {
        case 0: // cell with nucleus
          canvas.drawCircle(p, r, line);
          canvas.drawCircle(Offset(x + r * .25, y - r * .2), r * .35, fill);
          break;
        case 1: // ring molecule
          final path = Path();
          final rot = t * .25 * (k.isEven ? 1 : -1);
          for (var i = 0; i < 6; i++) {
            final ang = rot + i * pi / 3;
            final v = Offset(x + r * cos(ang), y + r * sin(ang));
            if (i == 0) {
              path.moveTo(v.dx, v.dy);
            } else {
              path.lineTo(v.dx, v.dy);
            }
            canvas.drawCircle(v, 2.6, fill);
          }
          path.close();
          canvas.drawPath(path, line);
          break;
        default: // two-atom molecule
          final ang = t * .4 + k;
          final p1 = Offset(x + cos(ang) * r * .8, y + sin(ang) * r * .8);
          final p2 = Offset(x - cos(ang) * r * .8, y - sin(ang) * r * .8);
          canvas.drawLine(p1, p2, line);
          canvas.drawCircle(p1, r * .35, fill);
          canvas.drawCircle(p2, r * .25, fill);
      }
    }
  }

  @override
  bool shouldRepaint(_BgPainter old) => old.color != color;
}
