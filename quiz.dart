import 'dart:math';

import 'package:flutter/material.dart';

import 'data.dart';

class QuizPage extends StatefulWidget {
  final Lang lang;
  const QuizPage({super.key, required this.lang});
  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  final _rng = Random();
  late Species _answer;
  late List<Species> _options;
  int _score = 0, _total = 0;
  Species? _picked;

  String t(String en, String bn, String ja) => tr(widget.lang, en, bn, ja);

  @override
  void initState() {
    super.initState();
    _next();
  }

  void _next() {
    final pool = speciesData.where((s) => s.scientific.isNotEmpty).toList();
    if (pool.length < 2) {
      _options = [];
      return;
    }
    pool.shuffle(_rng);
    _options = pool.take(min(4, pool.length)).toList();
    _answer = _options[_rng.nextInt(_options.length)];
    _picked = null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Quick quiz', 'কুইক কুইজ', 'クイッククイズ'))),
      body: _options.isEmpty
          ? Center(child: Text(t('Not enough species', 'যথেষ্ট প্রজাতি নেই', '種が足りません')))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('${t('Score', 'স্কোর', 'スコア')}: $_score / $_total',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(t('What is the scientific name of:', 'এর বৈজ্ঞানিক নাম কী:', '学名はどれ:'),
                    style: Theme.of(context).textTheme.bodyMedium),
                const SizedBox(height: 4),
                Text(_answer.name(widget.lang),
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                for (final o in _options)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: FilledButton.tonal(
                      style: _picked == null
                          ? null
                          : FilledButton.styleFrom(
                              backgroundColor: o == _answer
                                  ? Colors.green.shade400
                                  : (o == _picked ? Colors.red.shade400 : null),
                            ),
                      onPressed: _picked != null
                          ? null
                          : () => setState(() {
                                _picked = o;
                                _total++;
                                if (o == _answer) _score++;
                              }),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(o.scientific,
                            style: const TextStyle(fontStyle: FontStyle.italic)),
                      ),
                    ),
                  ),
                if (_picked != null)
                  FilledButton(
                    onPressed: () => setState(_next),
                    child: Text(t('Next', 'পরবর্তী', '次へ')),
                  ),
              ],
            ),
    );
  }
}
