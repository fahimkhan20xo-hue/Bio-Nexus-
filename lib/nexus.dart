import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data.dart';
import 'fx.dart';
import 'nexus_context.dart';
import 'nexus_knowledge.dart';

export 'nexus_context.dart';

// ===========================================================================
// Nexus: the BioNexus companion.
//
//  1. models
//  2. the offline engine (works out what you mean and picks an answer)
//  3. the controller (chat history, settings, remembered between sessions)
//  4. the screens (floating bubble, greeting, chat window)
//
// Nothing here can change the species database: Nexus only reads it.
// ===========================================================================

bool get _isTest => Platform.environment.containsKey('FLUTTER_TEST');

// ---------------------------------------------------------------------------
// 1. models
// ---------------------------------------------------------------------------

/// A tappable suggestion under a message.
class NexusChip {
  final String label;
  final String? ask; // sent as a new question
  final String? entry; // answers this knowledge entry directly
  final String? action; // "tab:N", "flashcards" or "species:<scientific name>"
  const NexusChip(this.label, {this.ask, this.entry, this.action});
}

class NexusMessage {
  final bool fromUser;
  final String text;
  final List<NexusChip> chips;
  const NexusMessage(this.fromUser, this.text, [this.chips = const []]);
}

class NexusReply {
  final String text;
  final List<NexusChip> chips;
  const NexusReply(this.text, [this.chips = const []]);
}

// ---------------------------------------------------------------------------
// 2. the offline engine
// ---------------------------------------------------------------------------

final RegExp _bengali = RegExp(r'[\u0980-\u09FF]');
final RegExp _notWord = RegExp(r'[^\p{L}\p{N}\p{M}\s]', unicode: true);

bool _isBn(String s) => _bengali.hasMatch(s);

String _norm(String s) {
  final t = s.toLowerCase().replaceAll("'", '').replaceAll('\u2019', '').replaceAll(_notWord, ' ');
  return t.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).join(' ');
}

const Set<String> _stop = {
  'a', 'an', 'the', 'is', 'are', 'am', 'was', 'were', 'be', 'been', 'to', 'of', 'in', 'on', 'at', 'for', 'with', 'and', 'or',
  'i', 'me', 'my', 'you', 'your', 'it', 'its', 'this', 'that', 'these', 'those', 'what', 'whats', 'which', 'who', 'how', 'do',
  'does', 'did', 'can', 'could', 'should', 'would', 'will', 'please', 'tell', 'about', 'show', 'give', 'want', 'need', 'let',
  'lets', 'there', 'here', 'from', 'by', 'as', 'if', 'so', 'just', 'also', 'any', 'some', 'more', 'really', 'very', 'much',
  'ok', 'okay',
};

const Set<String> _hello = {
  'hi', 'hello', 'hey', 'hola', 'salam', 'assalamualaikum', 'হ্যালো', 'হেলো', 'হাই', 'সালাম', 'আসসালামু', 'নমস্কার',
};
const Set<String> _thanks = {'thanks', 'thank', 'thx', 'ধন্যবাদ', 'থ্যাংকস', 'থ্যাঙ্কস', 'শুকরিয়া'};
const Set<String> _bye = {'bye', 'goodbye', 'টাটা', 'বিদায়'};

const List<String> _screenWords = [
  'this page', 'this screen', 'where am i', 'what can i do here', 'what is here', 'help', 'এই পেজ', 'এই স্ক্রিন', 'এখানে কী', 'সাহায্য',
];
const List<String> _thisSpecies = [
  'this species', 'this one', 'about this', 'explain this', 'about it', 'tell me about it', 'what is it', 'এই প্রজাতি', 'এটি সম্পর্কে', 'এটা কী', 'এটি কী',
];

int _lev(String a, String b) {
  if (a == b) return 0;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = <int>[i];
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur.add(math.min(math.min(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost));
    }
    prev = cur;
  }
  return prev.last;
}

class _Prep {
  final NexusEntry e;
  final List<String> kws;
  final Set<String> qt;
  final Set<String> qn;
  _Prep(this.e)
      : kws = [for (final k in e.keywords) if (_norm(k).isNotEmpty) _norm(k)],
        qt = {
          ..._norm(e.q).split(' ').where((t) => !_stop.contains(t)),
          ..._norm(e.qbn).split(' ').where((t) => !_stop.contains(t)),
        },
        qn = {_norm(e.q), _norm(e.qbn)};
}

final List<_Prep> _preps = [for (final e in kNexusKnowledge) _Prep(e)];
final Map<String, NexusEntry> _byId = {for (final e in kNexusKnowledge) e.id: e};

double _score(_Prep p, String nq, List<String> toks, List<String> ctoks) {
  var s = 0.0;
  final padded = ' $nq ';
  for (final k in p.kws) {
    if (k.contains(' ')) {
      final words = k.split(' ');
      if (padded.contains(' $k ')) {
        s += 3.0 + 0.5 * (words.length - 1);
      } else if (words.every(toks.contains)) {
        s += 2.5;
      }
    } else if (toks.contains(k)) {
      s += 2.0;
    } else if (k.length >= 4 && toks.any((t) => t.startsWith(k))) {
      s += 1.2; // e.g. "flashcards", or a Bengali word with an ending attached
    } else if (k.length >= 5 && toks.any((t) => t.length >= 5 && (t.length - k.length).abs() <= 1 && _lev(t, k) <= 1)) {
      s += 1.2; // one typo
    }
  }
  final overlap = p.qt.where(ctoks.contains).length;
  s += math.min(overlap * 0.6, 1.8);
  if (p.qn.contains(nq)) s += 6.0;
  return s;
}

// ---- species lookup (read-only) ----
int _indexedFor = -1;
final Map<String, Species> _speciesIndex = {};

void _ensureIndex() {
  if (_indexedFor == speciesData.length) return;
  _speciesIndex.clear();
  for (final s in speciesData) {
    final sci = _norm(s.scientific);
    if (sci.isNotEmpty) _speciesIndex.putIfAbsent(sci, () => s);
    final c = _norm(s.common);
    if (c.length >= 4 && c != sci) _speciesIndex.putIfAbsent(c, () => s);
    final b = _norm(s.bangla);
    if (b.length >= 3) _speciesIndex.putIfAbsent(b, () => s);
  }
  _indexedFor = speciesData.length;
}

/// The longest species name found in the question, as whole words.
MapEntry<String, Species>? _findSpecies(String nq) {
  _ensureIndex();
  MapEntry<String, Species>? best;
  final padded = ' $nq ';
  _speciesIndex.forEach((key, s) {
    if ((best == null || key.length > best!.key.length) && nq.contains(key) && padded.contains(' $key ')) {
      best = MapEntry(key, s);
    }
  });
  return best;
}

String _cut(String s, int max) {
  final t = s.trim();
  if (t.length <= max) return t;
  final c = t.substring(0, max);
  final i = c.lastIndexOf(' ');
  return '${i > max ~/ 2 ? c.substring(0, i) : c}…';
}

String _speciesText(Species s, bool bn) {
  final names = <String>[s.scientific];
  if (s.common.isNotEmpty && s.common != s.scientific) names.add(s.common);
  if (s.bangla.isNotEmpty) names.add(s.bangla);
  final ranks = <String>[];
  void add(String en, String b, String v) {
    if (v.isNotEmpty) ranks.add('${bn ? b : en}: $v');
  }

  add('Kingdom', 'জগৎ', s.kingdom);
  add('Phylum', 'পর্ব', s.phylum);
  add('Class', 'শ্রেণি', s.klass);
  add('Order', 'বর্গ', s.order);
  add('Family', 'গোত্র', s.family);
  add('Genus', 'গণ', s.genus);
  final desc = s.description.isEmpty ? '' : '\n\n${_cut(s.description, 320)}';
  return '${names.join(' • ')}\n${ranks.join('\n')}$desc';
}

String _actionLabel(String a, bool bn) {
  switch (a) {
    case 'tab:0':
      return bn ? 'হোম খোলো' : 'Open Home';
    case 'tab:1':
      return bn ? 'এক্সপ্লোর খোলো' : 'Open Explore';
    case 'tab:2':
      return bn ? 'সংরক্ষিত খোলো' : 'Open Saved';
    case 'tab:3':
      return bn ? 'স্টাডি জোন খোলো' : 'Open Study zone';
    case 'tab:4':
      return bn ? 'সেটিংস খোলো' : 'Open Settings';
    case 'flashcards':
      return bn ? 'ফ্ল্যাশকার্ড খোলো' : 'Open Flashcards';
  }
  return bn ? 'খোলো' : 'Open';
}

NexusReply _entryReply(NexusEntry e, bool bn) {
  final chips = <NexusChip>[];
  if (e.action != null) chips.add(NexusChip(_actionLabel(e.action!, bn), action: e.action));
  for (final id in e.related.take(3)) {
    final r = _byId[id];
    if (r != null) chips.add(NexusChip(bn ? r.qbn : r.q, entry: id));
  }
  return NexusReply(bn ? e.bn : e.en, chips);
}

List<NexusChip> _starterChips(bool bn) => [
      for (final id in const ['what_is_bionexus', 'explore_help', 'bio_cell', 'flashcards_guide'])
        NexusChip(bn ? _byId[id]!.qbn : _byId[id]!.q, entry: id),
    ];

String? _screenEntryId(String screen) {
  switch (screen) {
    case 'home':
      return 'nav_home';
    case 'explore':
      return 'nav_explore';
    case 'saved':
      return 'nav_saved';
    case 'study':
      return 'nav_study';
    case 'settings':
      return 'nav_settings';
  }
  final s = screen.toLowerCase();
  if (s.contains('flash')) return 'flashcards_guide';
  if (s.contains('quiz')) return 'quiz_guide';
  if (s.contains('compare')) return 'compare_species';
  if (s.contains('tree')) return 'taxonomy_tree';
  if (s.contains('dashboard') || s.contains('progress')) return 'progress_guide';
  if (s.contains('manage')) return 'manage_saved';
  if (s.contains('pronounc') || s.contains('audio')) return 'pronunciation';
  if (s.contains('revision')) return 'species_revision';
  if (s.contains('group')) return 'filter_kingdom';
  if (s.contains('specieslist')) return 'nav_explore';
  if (s.contains('species')) return 'species_page';
  return null;
}

/// Works out the best answer. Pure and offline: it never changes anything.
NexusReply nexusAnswer(String raw, {required String screen, Species? species}) {
  final bn = _isBn(raw);
  String l(String en, String b) => bn ? b : en;
  final nq = _norm(raw);
  final toks = nq.isEmpty ? <String>[] : nq.split(' ');
  final ctoks = toks.where((t) => !_stop.contains(t)).toList();

  // greetings and thanks
  if (toks.isNotEmpty && toks.length <= 4) {
    if (toks.any(_hello.contains)) {
      return NexusReply(l('Hello, Explorer! 👋 What would you like to do?', 'হ্যালো, এক্সপ্লোরার! 👋 কী করতে চাও?'), _starterChips(bn));
    }
    if (toks.any(_thanks.contains)) {
      return NexusReply(l("You're welcome! Ask me anything else.", 'স্বাগতম! আর কিছু জানতে চাইলে বলো।'));
    }
    if (toks.any(_bye.contains)) {
      return NexusReply(l('See you soon, Explorer! 🧬', 'আবার দেখা হবে, এক্সপ্লোরার! 🧬'));
    }
  }

  // score every answer
  var best = 0.0;
  NexusEntry? bestEntry;
  var second = 0.0;
  NexusEntry? secondEntry;
  final ranked = <MapEntry<double, NexusEntry>>[];
  for (final p in _preps) {
    final sc = _score(p, nq, toks, ctoks);
    ranked.add(MapEntry(sc, p.e));
    if (sc > best) {
      second = best;
      secondEntry = bestEntry;
      best = sc;
      bestEntry = p.e;
    } else if (sc > second) {
      second = sc;
      secondEntry = p.e;
    }
  }

  // the species on screen ("tell me about this species")
  if (species != null && best < 3.0 && _thisSpecies.any((p) => nq.contains(_norm(p)))) {
    return _speciesReply(species, bn);
  }

  // a species named in the question
  final hit = nq.isEmpty ? null : _findSpecies(nq);
  if (hit != null && (hit.key.contains(' ') ? best < 6.0 : best < 2.0)) {
    return _speciesReply(hit.value, bn);
  }

  // "what is this page?"
  if (best < 2.0 && _screenWords.any((p) => nq.contains(_norm(p)))) {
    final id = _screenEntryId(screen);
    if (id != null && _byId[id] != null) return _entryReply(_byId[id]!, bn);
    return NexusReply(
      l('I can help with whatever you are doing here. Ask me how something works, or tap a suggestion.',
          'তুমি যা করছ তাতে আমি সাহায্য করতে পারি। কিছু কীভাবে কাজ করে জিজ্ঞেস করো, বা একটি পরামর্শে চাপো।'),
      _starterChips(bn),
    );
  }

  if (bestEntry != null && best >= 2.0) {
    final r = _entryReply(bestEntry, bn);
    // two close answers from different areas: offer the second one too
    if (secondEntry != null && second >= 2.0 && second >= best * 0.8 && secondEntry.category != bestEntry.category) {
      final chips = [...r.chips, NexusChip(bn ? secondEntry.qbn : secondEntry.q, entry: secondEntry.id)];
      return NexusReply(r.text, chips);
    }
    return r;
  }

  // not sure: say so, and offer the closest topics
  ranked.sort((a, b) => b.key.compareTo(a.key));
  final near = ranked.where((m) => m.key >= 0.6).take(3).map((m) => NexusChip(bn ? m.value.qbn : m.value.q, entry: m.value.id)).toList();
  return NexusReply(
    l(
      "I'm not sure about that one, and I'd rather not guess. I can help with BioNexus (search, Study zone, flashcards, settings, updates), tell you about species in the database and explain basic biology.\n\nDeeper biology answers will come when the online AI mode is added. Try one of these:",
      'এটা নিয়ে আমি নিশ্চিত নই, আর আন্দাজে বলতে চাই না। আমি BioNexus (সার্চ, স্টাডি জোন, ফ্ল্যাশকার্ড, সেটিংস, আপডেট), ডেটাবেসের প্রজাতি এবং বেসিক বায়োলজি নিয়ে সাহায্য করতে পারি।\n\nঅনলাইন AI মোড যোগ হলে আরও গভীর বায়োলজির উত্তর দিতে পারব। এগুলো চেষ্টা করো:',
    ),
    near.isNotEmpty ? near : _starterChips(bn),
  );
}

NexusReply _speciesReply(Species s, bool bn) {
  return NexusReply(_speciesText(s, bn), [
    NexusChip(bn ? 'প্রজাতির পেজ খোলো' : 'Open species page', action: 'species:${s.scientific}'),
    NexusChip(bn ? _byId['pronunciation']!.qbn : _byId['pronunciation']!.q, entry: 'pronunciation'),
  ]);
}

// ---------------------------------------------------------------------------
// 3. the controller: chat history and settings, kept between sessions
// ---------------------------------------------------------------------------

class NexusController extends ChangeNotifier {
  final ValueNotifier<bool> enabled = ValueNotifier<bool>(true);
  final List<NexusMessage> messages = [];
  bool thinking = false;
  bool introSeen = false;
  int lastGreetingMs = 0;
  double? fx, fy; // where the bubble was left (fractions of the screen)

  static const int _keep = 40;

  Future<File> _file() async {
    final d = await getApplicationSupportDirectory();
    return File('${d.path}/bionexus_nexus.json');
  }

  Future<void> load() async {
    if (_isTest) return;
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map) return;
      enabled.value = m['enabled'] != false;
      introSeen = m['introSeen'] == true;
      lastGreetingMs = (m['lastGreeting'] as num?)?.toInt() ?? 0;
      fx = (m['fx'] as num?)?.toDouble();
      fy = (m['fy'] as num?)?.toDouble();
      final h = m['history'];
      if (h is List) {
        for (final x in h) {
          if (x is Map && x['t'] is String) messages.add(NexusMessage(x['u'] == true, x['t'] as String));
        }
      }
    } catch (e) {
      debugPrint('Could not load Nexus: $e');
    }
  }

  Future<void> _save() async {
    if (_isTest) return;
    try {
      final f = await _file();
      final tail = messages.length > _keep ? messages.sublist(messages.length - _keep) : messages;
      await f.writeAsString(
        jsonEncode({
          'enabled': enabled.value,
          'introSeen': introSeen,
          'lastGreeting': lastGreetingMs,
          'fx': fx,
          'fy': fy,
          'history': [for (final m in tail) {'u': m.fromUser, 't': m.text}],
        }),
        flush: true,
      );
    } catch (e) {
      debugPrint('Could not save Nexus: $e');
    }
  }

  Future<void> setEnabled(bool v) async {
    enabled.value = v;
    await _save();
  }

  void markGreeted() {
    introSeen = true;
    lastGreetingMs = DateTime.now().millisecondsSinceEpoch;
    _save();
  }

  void rememberPosition(double x, double y) {
    fx = x;
    fy = y;
    _save();
  }

  void clear() {
    messages.clear();
    thinking = false;
    notifyListeners();
    _save();
  }

  /// A typed question.
  Future<void> ask(String text) async {
    final t = text.trim();
    if (t.isEmpty || thinking) return;
    messages.add(NexusMessage(true, t));
    await _reply(() => nexusAnswer(t, screen: nexusCtx.screen, species: nexusCtx.species));
  }

  /// A suggestion chip that points at one knowledge entry.
  Future<void> askEntry(String id, String label) async {
    final e = _byId[id];
    if (e == null || thinking) return;
    messages.add(NexusMessage(true, label));
    await _reply(() => _entryReply(e, _isBn(label)));
  }

  Future<void> _reply(NexusReply Function() make) async {
    thinking = true;
    notifyListeners();
    // a short pause, so the answer feels like a conversation
    if (!_isTest) await Future<void>.delayed(const Duration(milliseconds: 420));
    NexusReply r;
    try {
      r = make();
    } catch (e) {
      debugPrint('Nexus could not answer: $e');
      r = const NexusReply('Sorry, something went wrong on my side. Please try asking again.');
    }
    messages.add(NexusMessage(false, r.text, r.chips));
    thinking = false;
    notifyListeners();
    _save();
  }
}

final NexusController nexus = NexusController();

// ---------------------------------------------------------------------------
// 4. the screens
// ---------------------------------------------------------------------------

const Color _mintA = Color(0xFFA7E6C4);
const Color _mintB = Color(0xFF34B27F);
const Color _ink = Color(0xFF0B2B22);

/// Nexus's round emblem. It "breathes" softly while effects are on.
class NexusOrb extends StatefulWidget {
  final double size;
  const NexusOrb({super.key, this.size = 58});

  @override
  State<NexusOrb> createState() => _NexusOrbState();
}

class _NexusOrbState extends State<NexusOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void initState() {
    super.initState();
    if (!_isTest && fxEnabled.value) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = Curves.easeInOut.transform(_c.value);
        return Transform.scale(
          scale: 1 + .05 * v,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_mintA, _mintB]),
              boxShadow: [BoxShadow(color: _mintB.withValues(alpha: .30 + .20 * v), blurRadius: 16 + 10 * v, spreadRadius: 1)],
            ),
            child: Icon(Icons.auto_awesome, size: widget.size * .5, color: _ink),
          ),
        );
      },
    );
  }
}

/// Mounted once, above every page (see MaterialApp.builder in main.dart).
class NexusHost extends StatefulWidget {
  final Lang lang;
  const NexusHost({super.key, required this.lang});

  @override
  State<NexusHost> createState() => _NexusHostState();
}

class _NexusHostState extends State<NexusHost> {
  static const double _size = 58;
  Offset? _pos;
  bool _dragging = false;
  bool _sheetOpen = false;
  String? _greeting;

  String t(String en, String bn, String ja) => tr(widget.lang, en, bn, ja);

  @override
  void initState() {
    super.initState();
    nexusCtx.version.addListener(_refresh);
    if (!_isTest) _greet();
  }

  @override
  void dispose() {
    nexusCtx.version.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _greet() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted || !nexus.enabled.value) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    String? msg;
    if (!nexus.introSeen) {
      msg = t(
        "Hello, Explorer! 👋 I'm Nexus. Tap me whenever you need help with BioNexus or biology.",
        'হ্যালো, এক্সপ্লোরার! 👋 আমি Nexus। BioNexus বা বায়োলজি নিয়ে সাহায্য লাগলে আমাকে চাপো।',
        'こんにちは、エクスプローラー！👋 Nexusです。BioNexusや生物学で困ったらタップしてね。',
      );
    } else if (now - nexus.lastGreetingMs > 6 * 3600 * 1000) {
      msg = t('Welcome back, Explorer! 👋', 'আবার স্বাগতম, এক্সপ্লোরার! 👋', 'おかえりなさい、エクスプローラー！👋');
    }
    if (msg == null) return;
    setState(() => _greeting = msg);
    nexus.markGreeted();
    await Future<void>.delayed(const Duration(seconds: 9));
    if (mounted && _greeting == msg) setState(() => _greeting = null);
  }

  Offset _start(Size s, EdgeInsets pad) {
    final fx = nexus.fx, fy = nexus.fy;
    if (fx != null && fy != null) return Offset(fx * (s.width - _size), fy * (s.height - _size));
    return Offset(s.width - _size - 14, s.height - _size - 126 - pad.bottom);
  }

  Offset _clamp(Offset o, Size s, EdgeInsets pad) => Offset(
        o.dx.clamp(0.0, s.width - _size),
        o.dy.clamp(pad.top + 8, s.height - _size - pad.bottom - 8),
      );

  Future<void> _open() async {
    final ctx = nexusNavKey.currentContext;
    if (ctx == null) return;
    setState(() {
      _sheetOpen = true;
      _greeting = null;
    });
    await showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => NexusPanel(lang: widget.lang),
    );
    if (mounted) setState(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isTest) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: nexus.enabled,
      builder: (context, on, _) {
        final mq = MediaQuery.of(context);
        final size = mq.size;
        final keyboard = mq.viewInsets.bottom > 0;
        final onQuiz = nexusCtx.screen.toLowerCase().contains('quiz'); // do not distract during a quiz
        if (!on || keyboard || _sheetOpen || onQuiz) return const SizedBox.shrink();

        final pos = _clamp(_pos ?? _start(size, mq.padding), size, mq.padding);
        final right = pos.dx + _size / 2 > size.width / 2;
        final below = pos.dy < size.height / 2;

        return Material(
          type: MaterialType.transparency,
          child: Stack(children: [
            if (_greeting != null)
              Positioned(
                left: right ? null : pos.dx,
                right: right ? size.width - pos.dx - _size : null,
                top: below ? pos.dy + _size + 8 : pos.dy - 96,
                width: 250,
                child: _GreetingCard(text: _greeting!, onTap: _open, onClose: () => setState(() => _greeting = null)),
              ),
            AnimatedPositioned(
              duration: _dragging ? Duration.zero : const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              left: pos.dx,
              top: pos.dy,
              child: GestureDetector(
                onTap: _open,
                onPanStart: (_) => setState(() => _dragging = true),
                onPanUpdate: (d) => setState(() => _pos = _clamp(pos + d.delta, size, mq.padding)),
                onPanEnd: (_) {
                  final p = _clamp(_pos ?? pos, size, mq.padding);
                  final snapRight = p.dx + _size / 2 > size.width / 2;
                  final snapped = Offset(snapRight ? size.width - _size - 6 : 6, p.dy);
                  setState(() {
                    _dragging = false;
                    _pos = snapped;
                  });
                  nexus.rememberPosition(snapRight ? 1.0 : 0.0, snapped.dy / (size.height - _size));
                },
                child: Semantics(
                  button: true,
                  label: 'Nexus assistant',
                  child: const NexusOrb(size: _size),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _GreetingCard extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  final VoidCallback onClose;
  const _GreetingCard({required this.text, required this.onTap, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutBack,
      builder: (context, v, child) => Opacity(opacity: v.clamp(0.0, 1.0), child: Transform.scale(scale: .92 + .08 * v, child: child)),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _mintB.withValues(alpha: .6)),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 14)],
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Text(text, style: TextStyle(color: cs.onSurface, height: 1.3))),
            GestureDetector(
              onTap: onClose,
              child: const Padding(padding: EdgeInsets.all(6), child: Icon(Icons.close, size: 18)),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The chat window (opens as a bottom sheet, so the Android back button closes it).
class NexusPanel extends StatefulWidget {
  final Lang lang;
  const NexusPanel({super.key, required this.lang});

  @override
  State<NexusPanel> createState() => _NexusPanelState();
}

class _NexusPanelState extends State<NexusPanel> {
  final TextEditingController _ctl = TextEditingController();
  final ScrollController _scroll = ScrollController();

  String t(String en, String bn, String ja) => tr(widget.lang, en, bn, ja);

  @override
  void initState() {
    super.initState();
    nexus.addListener(_onChat);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom(jump: true));
  }

  @override
  void dispose() {
    nexus.removeListener(_onChat);
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChat() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _toBottom({bool jump = false}) {
    if (!_scroll.hasClients) return;
    final end = _scroll.position.maxScrollExtent;
    if (jump) {
      _scroll.jumpTo(end);
    } else {
      _scroll.animateTo(end, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    }
  }

  void _send() {
    final text = _ctl.text.trim();
    if (text.isEmpty || nexus.thinking) return;
    _ctl.clear();
    nexus.ask(text);
  }

  void _chip(NexusChip c) {
    if (c.action != null) {
      _run(c.action!);
    } else if (c.entry != null) {
      nexus.askEntry(c.entry!, c.label);
    } else if (c.ask != null) {
      nexus.ask(c.ask!);
    }
  }

  void _run(String a) {
    Navigator.of(context).pop(); // close this window
    nexusNavKey.currentState?.popUntil((r) => r.isFirst);
    if (a.startsWith('tab:')) {
      nexusHooks.openTab?.call(int.tryParse(a.substring(4)) ?? 0);
    } else if (a == 'flashcards') {
      nexusHooks.openFlashcards?.call();
    } else if (a.startsWith('species:')) {
      final sci = a.substring(8);
      for (final s in speciesData) {
        if (s.scientific == sci) {
          nexusHooks.openSpecies?.call(s);
          break;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final cs = Theme.of(context).colorScheme;
    final inset = mq.viewInsets.bottom;
    final height = math.min(mq.size.height * .88, mq.size.height - mq.padding.top - inset - 8).clamp(260.0, mq.size.height).toDouble();
    final msgs = nexus.messages;
    final bn = widget.lang == Lang.bn;

    final items = <Widget>[];
    if (msgs.isEmpty) {
      items.add(_Bubble(
        NexusMessage(
          false,
          t(
            "Hello, Explorer! 👋\nI'm Nexus. Your biology companion is ready. Let's explore the living world together.",
            'হ্যালো, এক্সপ্লোরার! 👋\nআমি Nexus। তোমার বায়োলজি সঙ্গী তৈরি। চলো একসঙ্গে জীবজগৎ ঘুরে দেখি।',
            'こんにちは、エクスプローラー！👋\nNexusです。生物学のパートナー、準備できました。一緒に生き物の世界を探検しましょう。',
          ),
        ),
      ));
      items.add(_Chips(_starterChips(bn), _chip));
    }
    for (var i = 0; i < msgs.length; i++) {
      items.add(_Bubble(msgs[i]));
      final last = i == msgs.length - 1;
      if (last && !msgs[i].fromUser && msgs[i].chips.isNotEmpty && !nexus.thinking) items.add(_Chips(msgs[i].chips, _chip));
    }
    if (nexus.thinking) items.add(const _TypingDots());

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: Material(
              color: cs.surface,
              child: Column(children: [
                // header
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 6, 10),
                  child: Row(children: [
                    const NexusOrb(size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Nexus', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(
                          t('BioNexus companion • works offline', 'BioNexus সঙ্গী • অফলাইনে চলে', 'BioNexusのパートナー・オフライン対応'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ]),
                    ),
                    PopupMenuButton<String>(
                      tooltip: '',
                      onSelected: (v) {
                        if (v == 'clear') nexus.clear();
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'clear', child: Text(t('Clear chat', 'চ্যাট মুছো', 'チャットを消す'))),
                      ],
                    ),
                    IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
                  ]),
                ),
                const Divider(height: 1),
                // messages
                Expanded(
                  child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    children: items,
                  ),
                ),
                // input
                Padding(
                  padding: EdgeInsets.fromLTRB(12, 6, 12, 10 + (inset > 0 ? 0 : mq.padding.bottom)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: TextField(
                        controller: _ctl,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        decoration: InputDecoration(
                          hintText: t('Ask Nexus…', 'Nexus-কে জিজ্ঞেস করো…', 'Nexusに聞く…'),
                          filled: true,
                          fillColor: cs.surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _ctl,
                      builder: (context, v, _) => IconButton.filled(
                        onPressed: (v.text.trim().isEmpty || nexus.thinking) ? null : _send,
                        icon: const Icon(Icons.send),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final NexusMessage m;
  const _Bubble(this.m);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = m.fromUser;
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .82),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: user ? cs.primary : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(user ? 18 : 4),
              topRight: Radius.circular(user ? 4 : 18),
              bottomLeft: const Radius.circular(18),
              bottomRight: const Radius.circular(18),
            ),
          ),
          child: Text(m.text, style: TextStyle(height: 1.35, color: user ? cs.onPrimary : cs.onSurface)),
        ),
      ),
    );
  }
}

class _Chips extends StatelessWidget {
  final List<NexusChip> chips;
  final void Function(NexusChip) onTap;
  const _Chips(this.chips, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Wrap(spacing: 8, runSpacing: 6, children: [
        for (final c in chips)
          ActionChip(
            avatar: c.action != null ? const Icon(Icons.open_in_new, size: 16) : null,
            label: Text(c.label),
            onPressed: () => onTap(c),
          ),
      ]),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.onSurface.withValues(alpha: .25 + .55 * math.max(0.0, math.sin((_c.value - i * .15) * math.pi * 2))),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
