import 'package:flutter/material.dart';
import 'data.dart';
import 'quiz.dart';
import 'images.dart';
import 'manage.dart';
import 'online.dart';
import 'pronounce.dart';
import 'speech.dart';
import 'updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  speciesData = await loadSpecies();
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
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BioNexus',
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF087F70)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5F8F6),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF42BDA8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: HomePage(
        lang: lang,
        dark: dark,
        onLang: (l) { setState(() => lang = l); saveAppPrefs(lang, dark); },
        onTheme: () { setState(() => dark = !dark); saveAppPrefs(lang, dark); },
      ),
    );
  }
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

  void openQuiz() => Navigator.push(context, MaterialPageRoute(builder: (_) => QuizPage(lang: lang)));

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
      body: ScienceBackground(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() {
          tab = v;
          query = '';
          kingdomFilter = null;
        }),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t('Home', 'হোম', 'ホーム')),
          NavigationDestination(icon: const Icon(Icons.explore_outlined), selectedIcon: const Icon(Icons.explore), label: t('Explore', 'এক্সপ্লোর', '探索')),
          NavigationDestination(icon: const Icon(Icons.bookmark_border), selectedIcon: const Icon(Icons.bookmark), label: t('Saved', 'সংরক্ষিত', '保存')),
          NavigationDestination(icon: const Icon(Icons.school_outlined), selectedIcon: const Icon(Icons.school), label: t('Study', 'পড়াশোনা', '学習')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: t('Settings', 'সেটিংস', '設定')),
        ],
      ),
    );
  }

  // ---------- Home ----------
  Widget _home() {
    final today = speciesData.isEmpty
        ? null
        : speciesData[DateTime.now().difference(DateTime(DateTime.now().year)).inDays % speciesData.length];
    return ListView(
      padding: const EdgeInsets.only(bottom: 18),
      children: [
        _hero(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Card(
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.quiz),
              title: Text(t('Quick quiz', 'কুইক কুইজ', 'クイッククイズ'), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(t('Test your scientific names.', 'বৈজ্ঞানিক নাম যাচাই করো।', '学名の力試し。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: openQuiz,
            ),
          ),
        ),
        if (today != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Text(t('Species of the day', 'আজকের প্রজাতি', '今日の生き物'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _speciesCard(today)),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            child: Text(t('Browse by group', 'দল অনুযায়ী দেখো', 'グループ別'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (final k in kingdoms)
                _groupRow(
                  context,
                  lang,
                  icon: _kingdomIcon(k),
                  title: kingdomLabel(lang, k),
                  count: speciesData.where((s) => s.kingdom == k).length,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupPage(
                        kingdom: k,
                        lang: lang,
                        favorites: favorites,
                        onChanged: () => setState(() {}),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ],
    );
  }

  Widget _hero() => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(colors: [Color(0xFF075E54), Color(0xFF15947D)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('EXPLORE LIFE. DISCOVER SCIENCE.', style: TextStyle(color: Color(0xFFB8F0DD), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
          const SizedBox(height: 9),
          Text(t('Discover the living world.', 'জীবজগৎকে জানো নতুনভাবে।', '生き物の世界を発見しよう。'),
              style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
          const SizedBox(height: 7),
          Text(t('Explore scientific names and classification in one place.', 'বৈজ্ঞানিক নাম ও শ্রেণিবিন্যাস জানো এক জায়গায়।', '学名と分類をひとつの場所で。'),
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 14),
          Wrap(spacing: 8, children: [
            _pill('${speciesData.length} ${t('species', 'টি প্রজাতি', '種')}'),
            _pill(t('Offline ready', 'অফলাইনে ব্যবহারযোগ্য', 'オフライン対応')),
          ]),
        ]),
      );

  Widget _pill(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(30)),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
      );

  // ---------- Explore / Saved ----------
  Widget _library() {
    final list = filtered;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: TextField(
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
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
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
    nav.push(MaterialPageRoute(builder: (_) => SpeciesPage(species: stored, lang: lang)));
  }

  Widget _speciesCard(Species s) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .4)),
        ),
        child: ListTile(
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
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpeciesPage(species: s, lang: lang, list: tab == 0 ? speciesData : filtered))),
        ),
      );

  // ---------- Study ----------
  Widget _study() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(t('Study zone', 'স্টাডি জোন', '学習ゾーン'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(t('Build your biology knowledge step by step.', 'ধাপে ধাপে Biology-র জ্ঞান বাড়াও।', '生物学の知識を少しずつ身につけよう。')),
          const SizedBox(height: 18),
          Card(
            child: ListTile(
              leading: const Icon(Icons.quiz),
              title: Text(t('Quick quiz', 'কুইক কুইজ', 'クイッククイズ')),
              subtitle: Text(t('Scientific names, families and orders.', 'বৈজ্ঞানিক নাম, গোত্র ও বর্গ।', '学名・科・目の問題。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: openQuiz,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.style),
              title: Text(t('Species revision', 'প্রজাতি রিভিশন', '種の復習')),
              subtitle: Text(t('Browse and revise the full species list.', 'পুরো প্রজাতির তালিকা দেখে রিভিশন করো।', '全種のリストを見て復習。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => setState(() => tab = 1),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.headphones),
              title: Text(t('Audio pronunciation', 'অডিও উচ্চারণ', '発音音声')),
              subtitle: Text(t('Listen to species names and practice.', 'প্রজাতির নাম শুনে অনুশীলন করো।', '種名を聞いて練習しよう。')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PronouncePage(lang: lang))),
            ),
          ),
        ],
      );

  // ---------- Settings ----------
  Widget _settings() => ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(t('Settings', 'সেটিংস', '設定'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          Text(t('Language', 'ভাষা', '言語'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SegmentedButton<Lang>(
            segments: const [
              ButtonSegment(value: Lang.en, label: Text('English')),
              ButtonSegment(value: Lang.bn, label: Text('বাংলা')),
              ButtonSegment(value: Lang.ja, label: Text('日本語')),
            ],
            selected: {lang},
            onSelectionChanged: (s) => widget.onLang(s.first),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            value: widget.dark,
            onChanged: (_) => widget.onTheme(),
            title: Text(t('Dark mode', 'ডার্ক মোড', 'ダークモード')),
            secondary: const Icon(Icons.dark_mode),
          ),
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
          ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: Text(t('Manage saved data', 'সেভ করা ডেটা ম্যানেজ করো', '保存データの管理')),
            subtitle: Text(t('Choose which saved photos and online-added species to delete',
                'কোন সেভ করা ছবি ও অনলাইনে যোগ করা প্রজাতি মুছবে বেছে নাও',
                '削除する保存写真とオンライン追加の種を選択')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => ManageSavedPage(lang: lang)));
              if (mounted) setState(() {});
            },
          ),
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
          const Divider(),
          ListTile(
            leading: const Icon(Icons.storage),
            title: Text(t('Local species database', 'লোকাল প্রজাতি ডেটাবেস', 'ローカル種データベース')),
            subtitle: Text('${speciesData.length} ${t('species, works without internet.', 'টি প্রজাতি, ইন্টারনেট ছাড়াই চলে।', '種を収録。オフラインで動作します。')}'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('BioNexus v1.1.0'),
            subtitle: Text(t('Early build', 'প্রাথমিক সংস্করণ', '初期バージョン')),
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
            setState(() => index = i);
          },
          itemBuilder: (context, i) => AnimatedBuilder(
            animation: controller,
            // The page itself is drawn once and only moved/rotated while swiping.
            child: RepaintBoundary(child: _SpeciesBody(species: items[i], lang: lang)),
            builder: (context, child) {
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
            Card(
              child: ListTile(
                leading: const Icon(Icons.record_voice_over),
                title: Text(t('Pronunciation guide', 'উচ্চারণ নির্দেশিকা', '発音ガイド')),
                subtitle: Text(species.pronunciation),
              ),
            ),
          ],
          if (species.fromOnline) ...[
            const SizedBox(height: 12),
            Card(
              child: ListTile(
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
  return Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .4)),
    ),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer),
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.bold, fontStyle: italic ? FontStyle.italic : FontStyle.normal),
      ),
      subtitle: Text('$count ${tr(lang, 'species', 'টি প্রজাতি', '種')}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
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
          MaterialPageRoute(
            builder: (_) => SpeciesListPage(
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
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(17),
                          side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .4)),
                        ),
                        child: ListTile(
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
                            MaterialPageRoute(builder: (_) => SpeciesPage(species: s, lang: lang, list: list)),
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
    ]);
  }
}
