import 'package:flutter/material.dart';
import 'data.dart';
import 'quiz.dart';
import 'compare.dart';
import 'dashboard.dart';
import 'extras.dart';
import 'fx.dart';
import 'images.dart';
import 'manage.dart';
import 'online.dart';
import 'pronounce.dart';
import 'speech.dart';
import 'stats.dart';
import 'tree.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  speciesData = await loadSpecies();
  await stats.load();
  await loadFx();
  runApp(const BioNexusApp());
}

class BioNexusApp extends StatefulWidget {
  const BioNexusApp({super.key});
  @override
  State<BioNexusApp> createState() => _BioNexusAppState();
}

class _BioNexusAppState extends State<BioNexusApp> {
  Lang lang = Lang.bn;
  bool dark = false;

  @override
  void initState() {
    super.initState();
    // Restore the saved language and theme.
    loadAppPrefs().then((p) {
      if (p != null && mounted) setState(() { lang = p.lang; dark = p.dark; });
    });
    loadPhotoPref();
    // The bundled/cached database is already available; this refresh runs in
    // the background and rebuilds the UI only if a newer database is installed.
    syncRemoteSpecies(onUpdated: () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: fxEnabled,
      builder: (context, fx, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'BioNexus',
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        theme: _buildTheme(Brightness.light),
        darkTheme: _buildTheme(Brightness.dark),
        home: HomePage(
          lang: lang,
          dark: dark,
          onLang: (l) { setState(() => lang = l); saveAppPrefs(lang, dark); },
          onTheme: () { setState(() => dark = !dark); saveAppPrefs(lang, dark); },
        ),
      ),
    );
  }
}

/// Emerald green theme with tighter, bolder headings.
ThemeData _buildTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: dark ? Emerald.c500 : Emerald.c600, brightness: b);
  final bg = dark ? const Color(0xFF08120F) : const Color(0xFFF0FAF5);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: b);
  final tt = base.textTheme;
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: tt.copyWith(
      headlineMedium: tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15),
      headlineSmall: tt.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.2),
      titleLarge: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.2),
      titleMedium: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: tt.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: tt.bodyMedium?.copyWith(height: 1.45),
      bodySmall: tt.bodySmall?.copyWith(height: 1.35, letterSpacing: 0.2),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: dark ? const Color(0xFF0D1B17) : Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Emerald.c500.withValues(alpha: .22),
    ),
  );
}

class HomePage extends StatefulWidget {
  final Lang lang;
  final bool dark;
  final ValueChanged<Lang> onLang;
  final VoidCallback onTheme;
  const HomePage({
    super.key,
    required this.lang,
    required this.dark,
    required this.onLang,
    required this.onTheme,
  });
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  int tab = 0;
  String? kingdomFilter;
  final Set<String> favorites = {};

  Lang get lang => widget.lang;
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUpdateQuietly());
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    _homeSearch.dispose();
    super.dispose();
  }

  Future<void> _checkUpdateQuietly() async {
    final info = await checkAppUpdate();
    if (!mounted || info == null || !info.isNewer) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 12),
      content: Text(t('A new version of BioNexus is available.', 'BioNexus-এর নতুন সংস্করণ এসেছে।', 'BioNexusの新しいバージョンがあります。')),
      action: SnackBarAction(
        label: t('Download', 'ডাউনলোড', 'ダウンロード'),
        onPressed: () => openDownload(info.url),
      ),
    ));
  }

  List<String> get kingdoms => speciesData.map((s) => s.kingdom).toSet().toList()..sort();

  List<Species> get filtered {
    final q = query.trim().toLowerCase();
    final raw = query.trim();
    return speciesData.where((s) {
      if (tab == 2 && !favorites.contains(s.scientific)) return false;
      if (kingdomFilter != null && s.kingdom != kingdomFilter) return false;
      if (q.isEmpty) return true;
      return s.scientific.toLowerCase().contains(q) ||
          s.common.toLowerCase().contains(q) ||
          s.bangla.contains(raw) ||
          s.japanese.contains(raw) ||
          s.phylum.toLowerCase().contains(q) ||
          s.klass.toLowerCase().contains(q) ||
          s.order.toLowerCase().contains(q) ||
          s.family.toLowerCase().contains(q) ||
          s.genus.toLowerCase().contains(q);
    }).toList();
  }

  void openQuiz() => Navigator.push(context, fxRoute((_) => QuizPage(lang: lang)));

  @override
  Widget build(BuildContext context) {
    Widget body;
    switch (tab) {
      case 0:
        body = _home();
        break;
      case 3:
        body = _study();
        break;
      case 4:
        body = _settings();
        break;
      default:
        body = _library();
    }
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.biotech, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('BioNexus', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
        ]),
        actions: [
          PopupMenuButton<Lang>(
            tooltip: 'Language',
            icon: const Icon(Icons.translate),
            onSelected: widget.onLang,
            itemBuilder: (_) => const [
              PopupMenuItem(value: Lang.en, child: Text('English')),
              PopupMenuItem(value: Lang.bn, child: Text('বাংলা')),
              PopupMenuItem(value: Lang.ja, child: Text('日本語')),
            ],
          ),
          IconButton(tooltip: 'Theme', onPressed: widget.onTheme, icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode)),
        ],
      ),
      body: ScienceBackground(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) => _dragDx = 0,
          onHorizontalDragUpdate: (d) => _dragDx += d.delta.dx,
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            // swipe right = next tab, swipe left = previous tab
            if (_dragDx > 70 && v > 250) {
              _goTab(tab + 1);
            } else if (_dragDx < -70 && v < -250) {
              _goTab(tab - 1);
            }
          },
          child: AnimatedSwitcher(
            duration: Duration(milliseconds: fxEnabled.value ? 280 : 0),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) {
              final incoming = child.key == ValueKey<int>(tab);
              final sign = incoming ? -_dir : _dir;
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: Offset(sign * 0.18, 0), end: Offset.zero).animate(anim),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(key: ValueKey<int>(tab), child: body),
          ),
        ),
      ),
      bottomNavigationBar: _GlassNavBar(
        index: tab,
        onTap: _goTab,
        items: [
          _NavItem(Icons.home_outlined, Icons.home, t('Home', 'হোম', 'ホーム')),
          _NavItem(Icons.explore_outlined, Icons.explore, t('Explore', 'এক্সপ্লোর', '探索')),
          _NavItem(Icons.bookmark_border, Icons.bookmark, t('Saved', 'সংরক্ষিত', '保存')),
          _NavItem(Icons.school_outlined, Icons.school, t('Study', 'পড়াশোনা', '学習')),
          _NavItem(Icons.settings_outlined, Icons.settings, t('Settings', 'সেটিংস', '設定')),
        ],
      ),
    );
  }

  // ---------- Home ----------
  int _dir = 1; // 1 = moving to a later tab, -1 = to an earlier tab
  double _dragDx = 0;

  void _goTab(int i) {
    if (i < 0 || i > 4 || i == tab) return;
    setState(() {
      _dir = i > tab ? 1 : -1;
      tab = i;
      query = '';
      _searchCtl.clear();
      kingdomFilter = null;
    });
  }

  final TextEditingController _searchCtl = TextEditingController(); // Explore search box
  final TextEditingController _homeSearch = TextEditingController(); // Home search box

  void _goSearch(String text) {
    final q = text.trim();
    setState(() {
      tab = 1;
      kingdomFilter = null;
      query = q;
      _searchCtl.text = q;
    });
    _homeSearch.clear();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 10),
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      );

  Widget _home() {
    final all = speciesData;
    final day = DateTime.now().difference(DateTime(DateTime.now().year)).inDays;
    final spotlight = all.isEmpty ? null : all[day % all.length];
    final ks = kingdoms;
    final families = all.map((s) => s.family).where((f) => f.isNotEmpty).toSet().length;

    final discoveries = <Species>[];
    for (var i = 0; i < ks.length; i++) {
      final list = all.where((s) => s.kingdom == ks[i] && !identical(s, spotlight)).toList();
      if (list.isNotEmpty) discoveries.add(list[(day * 7 + i * 13) % list.length]);
    }

    final speciesWord = t('species', 'টি প্রজাতি', '種');
    return ListView(
      padding: const EdgeInsets.only(bottom: 110),
      children: [
        // ---- Welcome ----
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: Emerald.hero,
            boxShadow: fxEnabled.value
                ? [BoxShadow(color: Emerald.c600.withValues(alpha: .35), blurRadius: 24, offset: const Offset(0, 12))]
                : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              t('EXPLORE LIFE. DISCOVER SCIENCE.', 'জীবনকে জানো। বিজ্ঞানকে আবিষ্কার করো।', '生命を探る。科学を発見する。'),
              style: const TextStyle(color: Emerald.c200, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),
            Text(
              t('Welcome to BioNexus', 'BioNexus-এ স্বাগতম', 'BioNexusへようこそ'),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              t('Scientific names and classification, all in one place.', 'বৈজ্ঞানিক নাম ও শ্রেণিবিন্যাস, এক জায়গায়।', '学名と分類をひとつの場所で。'),
              style: const TextStyle(color: Colors.white70, height: 1.4),
            ),
            const SizedBox(height: 20),
            Row(children: [
              _counter(all.length, speciesWord),
              _counter(families, t('families', 'গোত্র', '科')),
              _counter(ks.length, t('kingdoms', 'জগৎ', '界')),
            ]),
          ]),
        ),

        // ---- Search species ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: GlassCard(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(children: [
              const Icon(Icons.search),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _homeSearch,
                  textInputAction: TextInputAction.search,
                  onSubmitted: _goSearch,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: t('Search species...', 'প্রজাতি খুঁজুন...', '種を検索...'),
                  ),
                ),
              ),
              IconButton(onPressed: () => _goSearch(_homeSearch.text), icon: const Icon(Icons.arrow_forward)),
            ]),
          ),
        ),

        // ---- Quick actions ----
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            _quick(Icons.quiz_outlined, t('Quiz', 'কুইজ', 'クイズ'), openQuiz),
            const SizedBox(width: 10),
            _quick(Icons.compare_arrows, t('Compare', 'তুলনা', '比較'), () => Navigator.push(context, fxRoute((_) => ComparePage(lang: lang)))),
            const SizedBox(width: 10),
            _quick(Icons.account_tree_outlined, t('Tree', 'গাছ', 'ツリー'),
                () => Navigator.push(context, fxRoute((_) => TaxonomyTreePage(lang: lang, open: _openSpecies)))),
            const SizedBox(width: 10),
            _quick(Icons.insights, t('Progress', 'অগ্রগতি', '進捗'),
                () => Navigator.push(context, fxRoute((_) => DashboardPage(lang: lang, open: _openSpecies)))),
          ]),
        ),

        // ---- Daily Species Spotlight ----
        if (spotlight != null) ...[
          _sectionTitle(t('Daily Species Spotlight', 'আজকের স্পটলাইট প্রজাতি', '今日の注目種')),
          _SpotlightCard(
            species: spotlight,
            lang: lang,
            onTap: () => Navigator.push(context, fxRoute((_) => SpeciesPage(species: spotlight, lang: lang, list: speciesData))),
          ),
        ],

        // ---- Featured Discovery ----
        if (discoveries.isNotEmpty) ...[
          _sectionTitle(t('Featured Discovery', 'বিশেষ আবিষ্কার', '注目の発見')),
          SizedBox(
            height: 170,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: discoveries.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) => _discoveryCard(discoveries[i], discoveries),
            ),
          ),
        ],

        // ---- Explore Biological Kingdoms ----
        _sectionTitle(t('Explore Biological Kingdoms', 'জীবজগতের দলগুলো ঘুরে দেখো', '生物界を探検')),
        LayoutBuilder(builder: (context, cons) {
          final w = (cons.maxWidth - 32 - 12) / 2;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 12, runSpacing: 12, children: [
              for (final k in ks) SizedBox(width: w, child: _kingdomTile(k, speciesWord)),
            ]),
          );
        }),
      ],
    );
  }

  Widget _counter(int value, String label) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AnimatedCount(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800, height: 1.1)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ]),
      );

  Widget _quick(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: GlassCard(
          radius: 18,
          padding: const EdgeInsets.symmetric(vertical: 14),
          blur: false,
          onTap: onTap,
          child: Column(children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );

  Widget _discoveryCard(Species s, List<Species> list) => SizedBox(
        width: 156,
        child: GlassCard(
          radius: 20,
          padding: const EdgeInsets.all(12),
          onTap: () => Navigator.push(context, fxRoute((_) => SpeciesPage(species: s, lang: lang, list: list))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SpeciesThumb(
              scientific: s.scientific,
              fallback: CircleAvatar(
                backgroundColor: Emerald.c500.withValues(alpha: .2),
                child: Icon(_kingdomIcon(s.kingdom), color: Emerald.c600),
              ),
            ),
            const Spacer(),
            Text(s.scientific, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text(s.name(lang), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 2),
            Text(s.family, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.primary)),
          ]),
        ),
      );

  Widget _kingdomTile(String k, String speciesWord) {
    final count = speciesData.where((s) => s.kingdom == k).length;
    return GlassCard(
      radius: 22,
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.push(
        context,
        fxRoute((_) => GroupPage(kingdom: k, lang: lang, favorites: favorites, onChanged: () => setState(() {}))),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: Emerald.c500.withValues(alpha: .2),
          child: Icon(_kingdomIcon(k), color: Emerald.c600),
        ),
        const SizedBox(height: 14),
        Text(kingdomLabel(lang, k), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 2),
        Row(children: [
          AnimatedCount(count, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary)),
          const SizedBox(width: 4),
          Text(speciesWord, style: const TextStyle(fontSize: 12)),
        ]),
      ]),
    );
  }

  // ---------- Explore / Saved ----------
  Widget _library() {
    final list = filtered;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: TextField(
          controller: _searchCtl,
          onChanged: (v) => setState(() => query = v),
          decoration: InputDecoration(
            hintText: t('Search name, family, order...', 'নাম, গোত্র বা বর্গ খুঁজুন...', '名前・科・目で検索...'),
            prefixIcon: const Icon(Icons.search),
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ),
      SizedBox(
        height: 46,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(t('All', 'সব', 'すべて')),
                selected: kingdomFilter == null,
                onSelected: (_) => setState(() => kingdomFilter = null),
              ),
            ),
            for (final k in kingdoms)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(kingdomLabel(lang, k)),
                  selected: kingdomFilter == k,
                  onSelected: (_) => setState(() => kingdomFilter = kingdomFilter == k ? null : k),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
        child: Row(children: [
          Expanded(
            child: Text(
              tab == 2 ? t('Favorites', 'পছন্দের তালিকা', 'お気に入り') : t('Species library', 'প্রজাতির তালিকা', '種のライブラリ'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Text('${list.length} ${t('records', 'টি', '件')}', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(t('No species found.', 'কোনো প্রজাতি পাওয়া যায়নি।', '見つかりませんでした。')),
                    if (_canSearchOnline) ...[
                      const SizedBox(height: 14),
                      _onlineButton(),
                    ],
                  ]),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                itemCount: list.length + (_canSearchOnline ? 1 : 0),
                itemBuilder: (context, i) => i < list.length
                    ? _speciesCard(list[i])
                    : Padding(padding: const EdgeInsets.only(top: 4), child: _onlineButton()),
              ),
      ),
    ]);
  }

  bool get _canSearchOnline => tab != 2 && query.trim().length >= 3;

  Widget _onlineButton() => OutlinedButton.icon(
        icon: const Icon(Icons.public),
        label: Text(t('Not found? Search online', 'পাচ্ছো না? অনলাইনে খোঁজো', '見つからない?オンラインで検索')),
        onPressed: _searchOnline,
      );

  Future<void> _searchOnline() async {
    final q = query.trim();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text(t('Searching online...', 'অনলাইনে খোঁজা হচ্ছে...', 'オンラインで検索中...'))),
        ]),
      ),
    );
    final r = await lookupOnline(q);
    if (!mounted) return;
    nav.pop();
    final found = r.species;
    if (found == null) {
      final String msg;
      switch (r.error) {
        case 'offline':
          msg = t('No internet connection.', 'ইন্টারনেট সংযোগ পাওয়া যায়নি।', 'インターネットに接続できません。');
          break;
        case 'incomplete':
          msg = t('Found, but its classification is incomplete, so it cannot be added.',
              'পাওয়া গেছে, কিন্তু শ্রেণিবিন্যাস অসম্পূর্ণ, তাই যোগ করা যায়নি।',
              '見つかりましたが、分類が不完全なため追加できません。');
          break;
        default:
          msg = t('Not found online either. Try the English or scientific name.',
              'অনলাইনেও পাওয়া যায়নি। ইংরেজি বা বৈজ্ঞানিক নাম দিয়ে চেষ্টা করো।',
              'オンラインでも見つかりません。英語名か学名でお試しください。');
      }
      messenger.showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    final stored = await addUserSpecies(found);
    if (!mounted) return;
    setState(() {});
    nav.push(fxRoute((_) => SpeciesPage(species: stored, lang: lang)));
  }

  Widget _speciesCard(Species s) => GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, radius: 18, blur: false, child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          leading: SpeciesThumb(
            scientific: s.scientific,
            fallback: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: Icon(Icons.biotech, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
          ),
          title: Text(s.scientific, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text('${s.names(lang)}\n${s.family}', maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          isThreeLine: true,
          trailing: IconButton(
            icon: Icon(favorites.contains(s.scientific) ? Icons.bookmark : Icons.bookmark_border),
            onPressed: () => setState(() {
              favorites.contains(s.scientific) ? favorites.remove(s.scientific) : favorites.add(s.scientific);
            }),
          ),
          onTap: () => Navigator.push(context, fxRoute((_) => SpeciesPage(species: s, lang: lang, list: tab == 0 ? speciesData : filtered))),
        ),
      );

  void _openSpecies(BuildContext c, Species s, List<Species> list) {
    Navigator.push(c, fxRoute((_) => SpeciesPage(species: s, lang: lang, list: list)));
  }

  // ---------- Study ----------
  Widget _study() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
        children: [
          Text(t('Study zone', 'স্টাডি জোন', '学習ゾーン'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t('Build your biology knowledge step by step.', 'ধাপে ধাপে Biology-র জ্ঞান বাড়াও।', '生物学の知識を少しずつ身につけよう。')),
          const SizedBox(height: 18),
          GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
              leading: const Icon(Icons.quiz),
              title: Text(t('Quick quiz', 'কুইক কুইজ', 'クイッククイズ')),
              subtitle: Text(t('Scientific names, families and orders.', 'বৈজ্ঞানিক নাম, গোত্র ও বর্গ।', '学名・科・目の問題。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: openQuiz,
            ),
          ),
          GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
              leading: const Icon(Icons.compare_arrows),
              title: Text(t('Compare species', 'প্রজাতির তুলনা', '種の比較')),
              subtitle: Text(t('Put two species side by side.', 'দুটি প্রজাতি পাশাপাশি দেখো।', '2つの種を並べて比べます。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, fxRoute((_) => ComparePage(lang: lang))),
            ),
          ),
          GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
              leading: const Icon(Icons.account_tree),
              title: Text(t('Taxonomy tree', 'শ্রেণিবিন্যাস গাছ', '分類ツリー')),
              subtitle: Text(t('Kingdom down to species, level by level.', 'জগৎ থেকে প্রজাতি, ধাপে ধাপে।', '界から種まで、階級ごとに。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                fxRoute((_) => TaxonomyTreePage(lang: lang, open: _openSpecies)),
              ),
            ),
          ),
          GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
              leading: const Icon(Icons.insights),
              title: Text(t('My progress', 'আমার অগ্রগতি', '学習の進捗')),
              subtitle: Text(t('Quiz results, weak topics, weekly activity.', 'কুইজের ফল, দুর্বল বিষয়, সাপ্তাহিক কাজ।', 'クイズ結果・苦手・今週の学習。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                fxRoute((_) => DashboardPage(lang: lang, open: _openSpecies)),
              ),
            ),
          ),
          GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
              leading: const Icon(Icons.style),
              title: Text(t('Species revision', 'প্রজাতি রিভিশন', '種の復習')),
              subtitle: Text(t('Browse and revise the full species list.', 'পুরো প্রজাতির তালিকা দেখে রিভিশন করো।', '全種のリストを見て復習。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => tab = 1),
            ),
          ),
          GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
              leading: const Icon(Icons.headphones),
              title: Text(t('Audio pronunciation', 'অডিও উচ্চারণ', '発音音声')),
              subtitle: Text(t('Listen to species names and practice.', 'প্রজাতির নাম শুনে অনুশীলন করো।', '種名を聞いて練習しよう。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, fxRoute((_) => PronouncePage(lang: lang))),
            ),
          ),
        ],
      );

  // ---------- Settings ----------
  Widget _box(Widget child) => GlassCard(
        margin: const EdgeInsets.only(bottom: 10),
        padding: EdgeInsets.zero,
        blur: false,
        child: child,
      );

  Widget _settings() => ListView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 110),
        children: [
          Text(t('Settings', 'সেটিংস', '設定'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          _box(
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Language', 'ভাষা', '言語'), style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                SegmentedButton<Lang>(
            segments: const [
              ButtonSegment(value: Lang.en, label: Text('English')),
              ButtonSegment(value: Lang.bn, label: Text('বাংলা')),
              ButtonSegment(value: Lang.ja, label: Text('日本語')),
            ],
            selected: {lang},
            onSelectionChanged: (s) => widget.onLang(s.first),
          ),
              ]),
            ),
          ),
          _box(
            SwitchListTile(
            value: widget.dark,
            onChanged: (_) => widget.onTheme(),
            title: Text(t('Dark mode', 'ডার্ক মোড', 'ダークモード')),
            secondary: const Icon(Icons.dark_mode),
          ),
          ),
          _box(
            ValueListenableBuilder<bool>(
            valueListenable: fxEnabled,
            builder: (context, on, _) => SwitchListTile(
              value: on,
              onChanged: (v) => setFx(v),
              title: Text(t('3D effects & animations', '৩ডি ইফেক্ট ও অ্যানিমেশন', '3D効果とアニメーション')),
              subtitle: Text(on
                  ? t('DNA background, page rotation, blur and motion', 'DNA ব্যাকগ্রাউন্ড, পেজ ঘোরা, ব্লার ও মুভমেন্ট', 'DNA背景・ページ回転・ぼかし・動き')
                  : t('Simple mode: faster on low-end phones', 'সিম্পল মোড: কম শক্তির ফোনে দ্রুত চলবে', 'シンプルモード:低スペック端末で軽く動作')),
              secondary: const Icon(Icons.auto_awesome),
            ),
          ),
          ),
          _box(
            ValueListenableBuilder<bool>(
            valueListenable: savePhotos,
            builder: (context, on, _) => SwitchListTile(
              value: on,
              onChanged: (v) => setSavePhotos(v),
              title: Text(t('Save photos on device', 'ছবি ডিভাইসে সেভ করো', '写真を端末に保存')),
              subtitle: Text(on
                  ? t('Saved photos also work offline.', 'সেভ করা ছবি অফলাইনেও দেখা যাবে।', '保存した写真はオフラインでも見られます。')
                  : t('Photos show only when online and are not saved.', 'ছবি শুধু অনলাইনে দেখা যাবে, সেভ হবে না।', '写真はオンライン時のみ表示され、保存されません。')),
              secondary: const Icon(Icons.photo_library),
            ),
          ),
          ),
          _box(
            ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: Text(t('Manage saved data', 'সেভ করা ডেটা ম্যানেজ করো', '保存データの管理')),
            subtitle: Text(t('Choose which saved photos and online-added species to delete',
                'কোন সেভ করা ছবি ও অনলাইনে যোগ করা প্রজাতি মুছবে বেছে নাও',
                '削除する保存写真とオンライン追加の種を選択')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, fxRoute((_) => ManageSavedPage(lang: lang)));
              if (mounted) setState(() {});
            },
          ),
          ),
          _box(
            ListTile(
            leading: const Icon(Icons.system_update),
            title: Text(t('Check for app update', 'অ্যাপ আপডেট দেখো', 'アプリの更新を確認')),
            subtitle: Text('${t('Current build', 'বর্তমান বিল্ড', '現在のビルド')}: ${kBuildNumber == 0 ? '-' : kBuildNumber}'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(SnackBar(content: Text(t('Checking...', 'দেখা হচ্ছে...', '確認中...'))));
              final info = await checkAppUpdate();
              if (!mounted) return;
              messenger.hideCurrentSnackBar();
              if (info == null) {
                messenger.showSnackBar(SnackBar(
                  content: Text(t('Could not check. Please check your internet.', 'চেক করা যায়নি, ইন্টারনেট দেখো।', '確認できませんでした。インターネットを確認してください。')),
                ));
                return;
              }
              if (!info.isNewer) {
                messenger.showSnackBar(SnackBar(
                  content: Text(t('You have the latest version.', 'তোমার অ্যাপ সর্বশেষ সংস্করণে আছে।', '最新バージョンです。')),
                ));
                return;
              }
              messenger.showSnackBar(SnackBar(
                duration: const Duration(seconds: 12),
                content: Text(t('New version available (build ${info.build}).', 'নতুন সংস্করণ এসেছে (বিল্ড ${info.build})।', '新しいバージョンがあります(ビルド${info.build})。')),
                action: SnackBarAction(
                  label: t('Download', 'ডাউনলোড', 'ダウンロード'),
                  onPressed: () => openDownload(info.url),
                ),
              ));
            },
          ),
          ),
          _box(
            ListTile(
            leading: const Icon(Icons.sync),
            title: Text(t('Check for database update', 'ডেটাবেস আপডেট দেখো', 'データベースの更新を確認')),
            subtitle: Text(
              '${t('Version', 'সংস্করণ', 'バージョン')}: ${speciesDbVersion == 0 ? t('built-in', 'বিল্ট-ইন', '内蔵') : speciesDbVersion} • ${speciesData.length} ${t('species', 'টি প্রজাতি', '種')}',
            ),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              messenger.showSnackBar(SnackBar(content: Text(t('Checking...', 'দেখা হচ্ছে...', '確認中...'))));
              final updated = await syncRemoteSpecies(force: true, onUpdated: () {
                if (mounted) setState(() {});
              });
              if (!mounted) return;
              final String msg;
              if (updated) {
                msg = t('Updated to version $speciesDbVersion (${speciesData.length} species).',
                    'আপডেট হয়েছে: সংস্করণ $speciesDbVersion (${speciesData.length} টি প্রজাতি)।',
                    'バージョン$speciesDbVersionに更新しました(${speciesData.length}種)。');
              } else if (lastSyncStatus == 'error') {
                msg = t('Could not check. Please check your internet.', 'চেক করা যায়নি, ইন্টারনেট দেখো।', '確認できませんでした。インターネットを確認してください。');
              } else {
                msg = t('Already up to date (version $speciesDbVersion).', 'ডেটাবেস এখনই সর্বশেষ (সংস্করণ $speciesDbVersion)।', 'すでに最新です(バージョン$speciesDbVersion)。');
              }
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(SnackBar(content: Text(msg)));
              setState(() {});
            },
          ),
          ),
          _box(
            ListTile(
            leading: const Icon(Icons.storage),
            title: Text(t('Local species database', 'লোকাল প্রজাতি ডেটাবেস', 'ローカル種データベース')),
            subtitle: Text('${speciesData.length} ${t('species, works without internet.', 'টি প্রজাতি, ইন্টারনেট ছাড়াই চলে।', '種を収録。オフラインで動作します。')}'),
          ),
          ),
          _box(
            ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('BioNexus v1.1.0'),
            subtitle: Text(t('Early build', 'প্রাথমিক সংস্করণ', '初期バージョン')),
          ),
          ),
        ],
      );
}

/// Species detail screen. Swipe right to go to the next species in the list
/// you came from (swipe left to go back).
class SpeciesPage extends StatefulWidget {
  final Species species;
  final Lang lang;
  final List<Species> list;
  const SpeciesPage({super.key, required this.species, required this.lang, this.list = const []});

  @override
  State<SpeciesPage> createState() => _SpeciesPageState();
}

class _SpeciesPageState extends State<SpeciesPage> {
  late final List<Species> items;
  late final PageController controller;
  late int index;

  @override
  void initState() {
    super.initState();
    items = widget.list.isEmpty ? [widget.species] : widget.list;
    final i = items.indexWhere((s) => s.scientific == widget.species.scientific);
    index = i < 0 ? 0 : i;
    controller = PageController(initialPage: index);
    stats.addViewed(items[index].scientific);
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(lang, 'Species details', 'প্রজাতির বিবরণ', '種の詳細')),
        actions: [
          if (items.length > 1)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text('${index + 1} / ${items.length}'),
              ),
            ),
        ],
      ),
      body: ScienceBackground(
        child: PageView.builder(
          controller: controller,
          reverse: true, // swipe right = next species
          allowImplicitScrolling: true, // prepare the neighbouring pages in advance
          itemCount: items.length,
          onPageChanged: (i) {
            stopSpeaking();
            stats.addViewed(items[i].scientific);
            setState(() => index = i);
          },
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: controller,
            // The page itself is drawn once and only moved/rotated while swiping.
            child: RepaintBoundary(child: _SpeciesBody(species: items[i], lang: lang)),
            builder: (context, child) {
              if (!fxEnabled.value) return child!;
              var page = index.toDouble();
              if (controller.hasClients && controller.position.haveDimensions) {
                page = controller.page ?? page;
              }
              final v = (page - i).clamp(-1.0, 1.0).toDouble();
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012) // perspective
                  ..rotateY(-v * 0.9), // rotation while swiping
                child: child,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpeciesBody extends StatelessWidget {
  final Species species;
  final Lang lang;
  const _SpeciesBody({required this.species, required this.lang});

  @override
  Widget build(BuildContext context) {
    String t(String en, String bn, String ja) => tr(lang, en, bn, ja);
    final rows = <MapEntry<String, String>>[
      MapEntry(t('Kingdom', 'জগৎ (Kingdom)', '界'), species.kingdom),
      MapEntry(t('Phylum', 'পর্ব (Phylum)', '門'), species.phylum),
      MapEntry(t('Class', 'শ্রেণি (Class)', '綱'), species.klass),
      MapEntry(t('Order', 'বর্গ (Order)', '目'), species.order),
      MapEntry(t('Family', 'গোত্র (Family)', '科'), species.family),
      MapEntry(t('Genus', 'গণ (Genus)', '属'), species.genus),
      MapEntry(t('Species', 'প্রজাতি (Species)', '種'), species.species),
    ];
    return ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SpeciesHero(scientific: species.scientific, lang: lang),
          const SizedBox(height: 18),
          Text(species.scientific, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text(
            [species.common, species.bangla, species.japanese].where((e) => e.isNotEmpty).join(' • '),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          _ListenRow(species: species, lang: lang),
          if (species.pronunciation.isNotEmpty) ...[
            const SizedBox(height: 14),
            GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
                leading: const Icon(Icons.record_voice_over),
                title: Text(t('Pronunciation guide', 'উচ্চারণ নির্দেশিকা', '発音ガイド')),
                subtitle: Text(species.pronunciation),
              ),
            ),
          ],
          if (species.fromOnline) ...[
            const SizedBox(height: 12),
            GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, blur: false, child: ListTile(
                leading: const Icon(Icons.public),
                title: Text(t('Added from online sources', 'অনলাইন থেকে যোগ করা', 'オンラインから追加')),
                subtitle: Text(t('Data from GBIF, Wikipedia and Wikidata. Not verified yet, please double check.',
                    'GBIF, Wikipedia ও Wikidata থেকে নেওয়া তথ্য। এখনো যাচাই করা হয়নি, নিজে মিলিয়ে নিও।',
                    'GBIF・Wikipedia・Wikidataのデータです。未確認のため、ご自身でご確認ください。')),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(t('Taxonomic classification', 'শ্রেণিবিন্যাস', '分類'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...rows.map((e) => Card(
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                  child: Row(children: [
                    Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Flexible(child: Text(e.value, textAlign: TextAlign.end, style: const TextStyle(fontStyle: FontStyle.italic))),
                  ]),
                ),
              )),
          ExtraCard(species: species, lang: lang),
          if (species.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(t('Overview', 'সংক্ষিপ্ত পরিচিতি', '概要'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(species.description),
          ],
          const SizedBox(height: 20),
          Text(
            t(
              'Data note: please verify against GBIF, ITIS or Catalogue of Life before publishing. Classification of microbes and viruses follows recent naming and may differ from textbooks.',
              'তথ্য নোট: প্রকাশের আগে GBIF, ITIS বা Catalogue of Life দিয়ে যাচাই করো। অণুজীব ও ভাইরাসের শ্রেণিবিন্যাস সাম্প্রতিক নামকরণ অনুসারে, তাই পাঠ্যবইয়ের সাথে কিছু পার্থক্য থাকতে পারে।',
              'データ注記: 公開前にGBIF・ITIS・Catalogue of Lifeで確認してください。微生物とウイルスの分類は最新の命名に従っており、教科書と異なる場合があります。',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
    );
  }
}


// ---------------------------------------------------------------------------
// Browse by group: kingdom -> phylum -> species list
// ---------------------------------------------------------------------------

IconData _kingdomIcon(String k) {
  switch (k) {
    case 'Animalia':
      return Icons.pets;
    case 'Plantae':
      return Icons.eco;
    case 'Fungi':
      return Icons.spa;
    case 'Bacteria':
      return Icons.bubble_chart;
    case 'Protista':
      return Icons.blur_circular;
    case 'Viruses':
      return Icons.coronavirus;
    default:
      return Icons.biotech;
  }
}

Widget _groupRow(
  BuildContext context,
  Lang lang, {
  required IconData icon,
  required String title,
  required int count,
  required VoidCallback onTap,
  bool italic = false,
}) {
  return GlassCard(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    radius: 18,
    blur: false,
    onTap: onTap,
    child: Row(children: [
      CircleAvatar(
        backgroundColor: Emerald.c500.withValues(alpha: .2),
        child: Icon(icon, color: Emerald.c600),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w800, fontStyle: italic ? FontStyle.italic : FontStyle.normal),
          ),
          Text('$count ${tr(lang, 'species', 'টি প্রজাতি', '種')}', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      const Icon(Icons.chevron_right),
    ]),
  );
}

/// Inside one group (kingdom): "All" plus one row per phylum.
class GroupPage extends StatelessWidget {
  final String kingdom;
  final Lang lang;
  final Set<String> favorites;
  final VoidCallback onChanged;
  const GroupPage({
    super.key,
    required this.kingdom,
    required this.lang,
    required this.favorites,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final all = speciesData.where((s) => s.kingdom == kingdom).toList();
    final byPhylum = <String, List<Species>>{};
    for (final s in all) {
      byPhylum.putIfAbsent(s.phylum.isEmpty ? '-' : s.phylum, () => []).add(s);
    }
    final phyla = byPhylum.entries.toList()..sort((a, b) => b.value.length.compareTo(a.value.length));
    void open(String title, List<Species> list) => Navigator.push(
          context,
          fxRoute((_) => SpeciesListPage(
              title: title,
              species: list,
              lang: lang,
              favorites: favorites,
              onChanged: onChanged,
            ),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(kingdomLabel(lang, kingdom))),
      body: ScienceBackground(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _groupRow(
              context,
              lang,
              icon: Icons.apps,
              title: tr(lang, 'All', 'সব', 'すべて'),
              count: all.length,
              onTap: () => open(kingdomLabel(lang, kingdom), all),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
              child: Text(
                tr(lang, 'Phylum', 'পর্ব (Phylum)', '門'),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            for (final e in phyla)
              _groupRow(
                context,
                lang,
                icon: _kingdomIcon(kingdom),
                title: e.key,
                count: e.value.length,
                italic: true,
                onTap: () => open(e.key, e.value),
              ),
          ],
        ),
      ),
    );
  }
}

/// The species inside one group, with a search box.
class SpeciesListPage extends StatefulWidget {
  final String title;
  final List<Species> species;
  final Lang lang;
  final Set<String> favorites;
  final VoidCallback onChanged;
  const SpeciesListPage({
    super.key,
    required this.title,
    required this.species,
    required this.lang,
    required this.favorites,
    required this.onChanged,
  });

  @override
  State<SpeciesListPage> createState() => _SpeciesListPageState();
}

class _SpeciesListPageState extends State<SpeciesListPage> {
  String query = '';

  List<Species> get filtered {
    final q = query.trim().toLowerCase();
    final raw = query.trim();
    if (q.isEmpty) return widget.species;
    return widget.species
        .where((s) =>
            s.scientific.toLowerCase().contains(q) ||
            s.common.toLowerCase().contains(q) ||
            s.bangla.contains(raw) ||
            s.japanese.contains(raw) ||
            s.family.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final lang = widget.lang;
    final list = filtered;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text('${list.length}'),
            ),
          ),
        ],
      ),
      body: ScienceBackground(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              onChanged: (v) => setState(() => query = v),
              decoration: InputDecoration(
                hintText: tr(lang, 'Search in this group...', 'এই দলে খুঁজুন...', 'このグループ内を検索...'),
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(tr(lang, 'No species found.', 'কোনো প্রজাতি পাওয়া যায়নি।', '見つかりませんでした。')))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final s = list[i];
                      final saved = widget.favorites.contains(s.scientific);
                      return GlassCard(margin: const EdgeInsets.only(bottom: 10), padding: EdgeInsets.zero, radius: 18, blur: false, child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                          leading: SpeciesThumb(
                            scientific: s.scientific,
                            fallback: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                              child: Icon(Icons.biotech, color: Theme.of(context).colorScheme.onPrimaryContainer),
                            ),
                          ),
                          title: Text(s.scientific, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 5),
                            child: Text('${s.names(lang)}\n${s.family}', maxLines: 2, overflow: TextOverflow.ellipsis),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                            onPressed: () {
                              setState(() {
                                saved ? widget.favorites.remove(s.scientific) : widget.favorites.add(s.scientific);
                              });
                              widget.onChanged();
                            },
                          ),
                          onTap: () => Navigator.push(
                            context,
                            fxRoute((_) => SpeciesPage(species: s, lang: lang, list: list)),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}


/// Listen buttons on the species page (phone text-to-speech).
class _ListenRow extends StatelessWidget {
  final Species species;
  final Lang lang;
  const _ListenRow({required this.species, required this.lang});

  Future<void> _go(BuildContext context, String text, String speechLang) async {
    final r = await speakText(text, lang: speechLang);
    final msg = speakFailMessage(lang, speechLang, r);
    if (msg != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      FilledButton.tonalIcon(
        onPressed: () => _go(context, species.scientific, 'en'),
        icon: const Icon(Icons.volume_up),
        label: Text(tr(lang, 'Listen', 'শুনো', '聞く')),
      ),
      if (species.pronunciation.isNotEmpty)
        FilledButton.tonalIcon(
          onPressed: () => _go(context, species.pronunciation, 'bn'),
          icon: const Icon(Icons.record_voice_over),
          label: Text(tr(lang, 'Bangla', 'বাংলা', 'ベンガル語')),
        ),
      OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          fxRoute((_) => ComparePage(lang: lang, first: species)),
        ),
        icon: const Icon(Icons.compare_arrows),
        label: Text(tr(lang, 'Compare', 'তুলনা', '比較')),
      ),
    ]);
  }
}


/// Big photo card for the species of the day.
class _SpotlightCard extends StatefulWidget {
  final Species species;
  final Lang lang;
  final VoidCallback onTap;
  const _SpotlightCard({required this.species, required this.lang, required this.onTap});

  @override
  State<_SpotlightCard> createState() => _SpotlightCardState();
}

class _SpotlightCardState extends State<_SpotlightCard> {
  late Future<SpeciesImageData?> _f = getSpeciesImage(widget.species.scientific);

  @override
  void didUpdateWidget(covariant _SpotlightCard old) {
    super.didUpdateWidget(old);
    if (old.species.scientific != widget.species.scientific) {
      _f = getSpeciesImage(widget.species.scientific);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.species;
    final lang = widget.lang;
    return FutureBuilder<SpeciesImageData?>(
      future: _f,
      builder: (context, snap) {
        final d = snap.data;
        final waiting = snap.connectionState != ConnectionState.done;
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            height: 230,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: Emerald.hero,
              boxShadow: fxEnabled.value
                  ? [BoxShadow(color: Colors.black.withValues(alpha: .25), blurRadius: 22, offset: const Offset(0, 10))]
                  : null,
            ),
            child: Stack(fit: StackFit.expand, children: [
              if (d != null)
                Image(
                  image: ResizeImage(d.provider, width: 900),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                )
              else if (waiting)
                const ShimmerBox(radius: 0)
              else
                const Center(child: Icon(Icons.biotech, size: 72, color: Colors.white54)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withValues(alpha: .75)],
                    stops: const [0.35, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 14,
                left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: .35), borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome, size: 14, color: Emerald.c200),
                    const SizedBox(width: 5),
                    Text(
                      tr(lang, 'Spotlight', 'আজকের স্পটলাইট', '今日の注目'),
                      style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
              Positioned(
                left: 18,
                right: 18,
                bottom: 16,
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    s.scientific,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${s.names(lang)}  •  ${s.family}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  if (s.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(s.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ]),
              ),
            ]),
          ),
        );
      },
    );
  }
}


class _NavItem {
  final IconData icon, selectedIcon;
  final String label;
  const _NavItem(this.icon, this.selectedIcon, this.label);
}

/// Floating emerald glass bottom bar.
class _GlassNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<_NavItem> items;
  const _GlassNavBar({required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fx = fxEnabled.value;
    final tint = dark
        ? Emerald.c900.withValues(alpha: fx ? .55 : .96)
        : Colors.white.withValues(alpha: fx ? .72 : .97);
    final activeColor = dark ? Emerald.c400 : Emerald.c700;
    final idleColor = Theme.of(context).colorScheme.onSurface.withValues(alpha: .62);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GlassCard(
          radius: 28,
          tint: tint,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(22),
                  onTap: () => onTap(i),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      AnimatedContainer(
                        duration: Duration(milliseconds: fx ? 260 : 0),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                        decoration: BoxDecoration(
                          color: i == index ? Emerald.c500.withValues(alpha: dark ? .28 : .22) : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(i == index ? items[i].selectedIcon : items[i].icon, size: 24, color: i == index ? activeColor : idleColor),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                          color: i == index ? activeColor : idleColor,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
