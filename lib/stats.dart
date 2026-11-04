import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

String dayKey(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// One answered quiz question.
class AnswerRec {
  final String day, sci, type, family, kingdom;
  final bool ok;
  const AnswerRec({
    required this.day,
    required this.sci,
    required this.type,
    required this.family,
    required this.kingdom,
    required this.ok,
  });

  Map<String, dynamic> toJson() => {'d': day, 's': sci, 't': type, 'f': family, 'k': kingdom, 'ok': ok};

  factory AnswerRec.fromJson(Map<String, dynamic> j) => AnswerRec(
        day: (j['d'] ?? '').toString(),
        sci: (j['s'] ?? '').toString(),
        type: (j['t'] ?? '').toString(),
        family: (j['f'] ?? '').toString(),
        kingdom: (j['k'] ?? '').toString(),
        ok: j['ok'] == true,
      );
}

/// One finished quiz.
class QuizRec {
  final String ts; // local ISO time
  final int total, correct, seconds, bestStreak;
  final String mode, difficulty;
  final bool daily, timed;
  const QuizRec({
    required this.ts,
    required this.total,
    required this.correct,
    required this.seconds,
    required this.bestStreak,
    required this.mode,
    required this.difficulty,
    required this.daily,
    required this.timed,
  });

  String get day => ts.length >= 10 ? ts.substring(0, 10) : ts;

  Map<String, dynamic> toJson() => {
        'ts': ts,
        'n': total,
        'c': correct,
        'sec': seconds,
        'best': bestStreak,
        'mode': mode,
        'diff': difficulty,
        'daily': daily,
        'timed': timed,
      };

  factory QuizRec.fromJson(Map<String, dynamic> j) => QuizRec(
        ts: (j['ts'] ?? '').toString(),
        total: (j['n'] as num?)?.toInt() ?? 0,
        correct: (j['c'] as num?)?.toInt() ?? 0,
        seconds: (j['sec'] as num?)?.toInt() ?? 0,
        bestStreak: (j['best'] as num?)?.toInt() ?? 0,
        mode: (j['mode'] ?? '').toString(),
        difficulty: (j['diff'] ?? '').toString(),
        daily: j['daily'] == true,
        timed: j['timed'] == true,
      );
}

class WeakTopic {
  final String family;
  final int wrong, total;
  const WeakTopic(this.family, this.wrong, this.total);
  double get accuracy => total == 0 ? 0 : (total - wrong) / total;
}

/// Learning statistics kept on the device (quiz results and recently viewed species).
class StatsStore {
  List<AnswerRec> answers = [];
  List<QuizRec> quizzes = [];
  List<String> viewed = [];

  Future<File> _file(String name) async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}/$name');
  }

  Future<void> load() async {
    try {
      final f = await _file('bionexus_stats.json');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        answers = ((m['answers'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AnswerRec.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        quizzes = ((m['quizzes'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => QuizRec.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    } catch (e) {
      debugPrint('Could not load stats: $e');
    }
    try {
      final f = await _file('bionexus_viewed.json');
      if (await f.exists()) {
        final l = jsonDecode(await f.readAsString());
        if (l is List) viewed = l.map((e) => e.toString()).toList();
      }
    } catch (e) {
      debugPrint('Could not load viewed list: $e');
    }
  }

  Future<void> _saveMain() async {
    try {
      final f = await _file('bionexus_stats.json');
      await f.writeAsString(
        jsonEncode({
          'answers': answers.map((a) => a.toJson()).toList(),
          'quizzes': quizzes.map((q) => q.toJson()).toList(),
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('Could not save stats: $e');
    }
  }

  Future<void> _saveViewed() async {
    try {
      final f = await _file('bionexus_viewed.json');
      await f.writeAsString(jsonEncode(viewed), flush: true);
    } catch (e) {
      debugPrint('Could not save viewed list: $e');
    }
  }

  void addViewed(String sci) {
    viewed.remove(sci);
    viewed.insert(0, sci);
    if (viewed.length > 20) viewed = viewed.sublist(0, 20);
    _saveViewed();
  }

  Future<void> addQuiz(QuizRec q, List<AnswerRec> a) async {
    quizzes.add(q);
    if (quizzes.length > 300) quizzes = quizzes.sublist(quizzes.length - 300);
    answers.addAll(a);
    if (answers.length > 3000) answers = answers.sublist(answers.length - 3000);
    await _saveMain();
  }

  Future<void> clearAll() async {
    answers = [];
    quizzes = [];
    viewed = [];
    await _saveMain();
    await _saveViewed();
  }

  // ---- numbers shown on the dashboard ----
  int get totalAnswered => answers.length;
  int get totalCorrect => answers.where((a) => a.ok).length;
  double get accuracy => answers.isEmpty ? 0 : totalCorrect / answers.length;
  int get learnedCount => answers.where((a) => a.ok).map((a) => a.sci).toSet().length;

  bool get dailyDoneToday => quizzes.any((q) => q.daily && q.day == dayKey(DateTime.now()));

  /// Days in a row (up to today) with at least one finished quiz.
  int get dayStreak {
    final days = quizzes.map((q) => q.day).toSet();
    var d = DateTime.now();
    if (!days.contains(dayKey(d))) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while (days.contains(dayKey(d))) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Questions answered per day for the last 7 days (oldest first).
  List<int> last7Answered() {
    final now = DateTime.now();
    final out = <int>[];
    for (var i = 6; i >= 0; i--) {
      final key = dayKey(now.subtract(Duration(days: i)));
      out.add(answers.where((a) => a.day == key).length);
    }
    return out;
  }

  /// Families with the most wrong answers.
  List<WeakTopic> weakFamilies() {
    final wrong = <String, int>{};
    final total = <String, int>{};
    for (final a in answers) {
      if (a.family.isEmpty) continue;
      total[a.family] = (total[a.family] ?? 0) + 1;
      if (!a.ok) wrong[a.family] = (wrong[a.family] ?? 0) + 1;
    }
    final out = <WeakTopic>[];
    wrong.forEach((f, w) {
      final t = total[f] ?? 0;
      if (t >= 2) out.add(WeakTopic(f, w, t));
    });
    out.sort((a, b) {
      final c = a.accuracy.compareTo(b.accuracy);
      return c != 0 ? c : b.wrong.compareTo(a.wrong);
    });
    return out.take(6).toList();
  }
}

final StatsStore stats = StatsStore();
