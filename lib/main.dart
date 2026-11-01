import 'package:flutter/material.dart';

void main() => runApp(const BioNexusApp());

class BioNexusApp extends StatefulWidget {
  const BioNexusApp({super.key});
  @override
  State<BioNexusApp> createState() => _BioNexusAppState();
}

class _BioNexusAppState extends State<BioNexusApp> {
  bool bengali = true;
  bool dark = false;

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
        bengali: bengali,
        dark: dark,
        onLanguage: () => setState(() => bengali = !bengali),
        onTheme: () => setState(() => dark = !dark),
      ),
    );
  }
}

class Species {
  final String scientific, common, bangla, kingdom, phylum, klass, order, family, genus, species, pronunciation, description;
  const Species({
    required this.scientific, required this.common, required this.bangla,
    required this.kingdom, required this.phylum, required this.klass,
    required this.order, required this.family, required this.genus,
    required this.species, required this.pronunciation, required this.description,
  });
}

const speciesData = <Species>[
  Species(
    scientific: 'Columba livia', common: 'Rock pigeon', bangla: 'কবুতর',
    kingdom: 'Animalia', phylum: 'Chordata', klass: 'Aves',
    order: 'Columbiformes', family: 'Columbidae', genus: 'Columba',
    species: 'livia', pronunciation: 'kuh-LUM-buh LIV-ee-uh',
    description: 'A familiar bird found in cities and many natural habitats.',
  ),
  Species(
    scientific: 'Fasciola hepatica', common: 'Liver fluke', bangla: 'যকৃত কৃমি',
    kingdom: 'Animalia', phylum: 'Platyhelminthes', klass: 'Trematoda',
    order: 'Plagiorchiida', family: 'Fasciolidae', genus: 'Fasciola',
    species: 'hepatica', pronunciation: 'fah-see-OH-luh heh-PAT-ih-kuh',
    description: 'A parasitic flatworm that can infect the liver and bile ducts of mammals.',
  ),
  Species(
    scientific: 'Hydra vulgaris', common: 'Freshwater hydra', bangla: 'হাইড্রা',
    kingdom: 'Animalia', phylum: 'Cnidaria', klass: 'Hydrozoa',
    order: 'Anthoathecata', family: 'Hydridae', genus: 'Hydra',
    species: 'vulgaris', pronunciation: 'HY-druh vul-GAIR-iss',
    description: 'A small freshwater cnidarian with tentacles surrounding its mouth.',
  ),
  Species(
    scientific: 'Anabas testudineus', common: 'Climbing perch', bangla: 'কই মাছ',
    kingdom: 'Animalia', phylum: 'Chordata', klass: 'Actinopterygii',
    order: 'Anabantiformes', family: 'Anabantidae', genus: 'Anabas',
    species: 'testudineus', pronunciation: 'AN-uh-bas tes-too-DIN-ee-us',
    description: 'A freshwater fish native to South and Southeast Asia.',
  ),
];

class HomePage extends StatefulWidget {
  final bool bengali, dark;
  final VoidCallback onLanguage, onTheme;
  const HomePage({super.key, required this.bengali, required this.dark, required this.onLanguage, required this.onTheme});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String query = '';
  int tab = 0;
  final Set<String> favorites = {};

  String t(String en, String bn) => widget.bengali ? bn : en;

  List<Species> get filtered {
    final q = query.trim().toLowerCase();
    final list = speciesData.where((s) =>
      q.isEmpty ||
      s.scientific.toLowerCase().contains(q) ||
      s.common.toLowerCase().contains(q) ||
      s.bangla.contains(query) ||
      s.phylum.toLowerCase().contains(q) ||
      s.genus.toLowerCase().contains(q)
    ).toList();
    if (tab == 2) return list.where((s) => favorites.contains(s.scientific)).toList();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isStudy = tab == 3;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.biotech, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Text('BioNexus', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .2)),
        ]),
        actions: [
          IconButton(tooltip: 'Language', onPressed: widget.onLanguage, icon: const Icon(Icons.translate)),
          IconButton(tooltip: 'Theme', onPressed: widget.onTheme, icon: Icon(widget.dark ? Icons.light_mode : Icons.dark_mode)),
        ],
      ),
      body: tab == 4
        ? _settings()
        : isStudy
          ? _study()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (tab == 0) _hero(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    onChanged: (v) => setState(() => query = v),
                    decoration: InputDecoration(
                      hintText: t('Search scientific name, common name, phylum...', 'বৈজ্ঞানিক নাম, সাধারণ নাম বা পর্ব খুঁজুন...'),
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Row(children: [
                    Expanded(child: Text(tab == 2 ? t('Favorites', 'পছন্দের তালিকা') : t('Species library', 'প্রজাতির তালিকা'), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
                    Text('${filtered.length} ${t('records', 'টি')}', style: Theme.of(context).textTheme.bodySmall),
                  ]),
                ),
                Expanded(
                  child: filtered.isEmpty
                    ? Center(child: Text(t('No species found.', 'কোনো প্রজাতি পাওয়া যায়নি।')))
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) => _speciesCard(filtered[i]),
                      ),
                ),
              ],
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() { tab = v; query = ''; }),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t('Home', 'হোম')),
          NavigationDestination(icon: const Icon(Icons.explore_outlined), selectedIcon: const Icon(Icons.explore), label: t('Explore', 'এক্সপ্লোর')),
          NavigationDestination(icon: const Icon(Icons.bookmark_border), selectedIcon: const Icon(Icons.bookmark), label: t('Saved', 'সংরক্ষিত')),
          NavigationDestination(icon: const Icon(Icons.school_outlined), selectedIcon: const Icon(Icons.school), label: t('Study', 'পড়াশোনা')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), selectedIcon: const Icon(Icons.settings), label: t('Settings', 'সেটিংস')),
        ],
      ),
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
      Text(t('Discover the living world.', 'জীবজগৎকে জানো নতুনভাবে।'), style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 7),
      Text(t('Explore scientific names and classification in one place.', 'বৈজ্ঞানিক নাম ও শ্রেণিবিন্যাস জানো এক জায়গায়।'), style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 14),
      Wrap(spacing: 8, children: [
        _pill('${speciesData.length} ${t('sample species', 'টি নমুনা')}'),
        _pill(t('Offline ready', 'অফলাইনে ব্যবহারযোগ্য')),
      ]),
    ]),
  );

  Widget _pill(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .16), borderRadius: BorderRadius.circular(30)),
    child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
  );

  Widget _speciesCard(Species s) => Card(
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17), side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: .4))),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Icon(Icons.biotech, color: Theme.of(context).colorScheme.onPrimaryContainer),
      ),
      title: Text(s.scientific, style: const TextStyle(fontWeight: FontWeight.bold, fontStyle: FontStyle.italic)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text('${s.common} • ${s.bangla}\n${s.phylum}', maxLines: 2),
      ),
      isThreeLine: true,
      trailing: IconButton(
        icon: Icon(favorites.contains(s.scientific) ? Icons.bookmark : Icons.bookmark_border),
        onPressed: () => setState(() {
          favorites.contains(s.scientific) ? favorites.remove(s.scientific) : favorites.add(s.scientific);
        }),
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SpeciesPage(species: s, bengali: widget.bengali))),
    ),
  );

  Widget _study() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(t('Study zone', 'স্টাডি জোন'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Text(t('Build your biology knowledge step by step.', 'ধাপে ধাপে Biology-র জ্ঞান বাড়াও।')),
      const SizedBox(height: 18),
      Card(child: ListTile(leading: const Icon(Icons.style), title: Text(t('Species revision', 'প্রজাতি রিভিশন')), subtitle: Text(t('Review the sample species list.', 'নমুনা প্রজাতিগুলো রিভিশন করো।')), onTap: () => setState(() => tab = 1))),
      Card(child: ListTile(leading: const Icon(Icons.quiz), title: Text(t('Quick quiz', 'কুইক কুইজ')), subtitle: Text(t('Coming in the next development phase.', 'পরবর্তী ধাপে যুক্ত হবে।')))),
      Card(child: ListTile(leading: const Icon(Icons.headphones), title: Text(t('Audio pronunciation', 'অডিও উচ্চারণ')), subtitle: Text(t('Pronunciation audio will be added next.', 'পরবর্তী ধাপে অডিও যুক্ত হবে।')))),
    ],
  );

  Widget _settings() => ListView(
    padding: const EdgeInsets.all(18),
    children: [
      Text(t('Settings', 'সেটিংস'), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      SwitchListTile(value: widget.bengali, onChanged: (_) => widget.onLanguage(), title: Text(t('Bengali interface', 'বাংলা ইন্টারফেস')), secondary: const Icon(Icons.translate)),
      SwitchListTile(value: widget.dark, onChanged: (_) => widget.onTheme(), title: Text(t('Dark mode', 'ডার্ক মোড')), secondary: const Icon(Icons.dark_mode)),
      const Divider(),
      ListTile(leading: const Icon(Icons.storage), title: Text(t('Local sample database', 'লোকাল নমুনা ডেটাবেস')), subtitle: Text(t('Works without internet. Cloud sync is planned.', 'ইন্টারনেট ছাড়াই চলে। Cloud sync পরে যুক্ত হবে।'))),
      ListTile(leading: const Icon(Icons.info_outline), title: const Text('BioNexus v1.0.0'), subtitle: Text(t('Early MVP build', 'প্রাথমিক MVP সংস্করণ'))),
    ],
  );
}

class SpeciesPage extends StatelessWidget {
  final Species species;
  final bool bengali;
  const SpeciesPage({super.key, required this.species, required this.bengali});

  @override
  Widget build(BuildContext context) {
    final rows = <String, String>{
      'Kingdom': species.kingdom, 'Phylum': species.phylum, 'Class': species.klass,
      'Order': species.order, 'Family': species.family, 'Genus': species.genus,
      'Species': species.species,
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Species details')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            height: 145,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [Color(0xFF075E54), Color(0xFF15947D)]),
            ),
            child: const Center(child: Icon(Icons.biotech, color: Colors.white, size: 72)),
          ),
          const SizedBox(height: 18),
          Text(species.scientific, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontStyle: FontStyle.italic, fontWeight: FontWeight.bold)),
          const SizedBox(height: 5),
          Text('${species.common} • ${species.bangla}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          Card(child: ListTile(leading: const Icon(Icons.record_voice_over), title: const Text('Pronunciation guide'), subtitle: Text(species.pronunciation), trailing: const Icon(Icons.volume_up))),
          const SizedBox(height: 12),
          Text(bengali ? 'শ্রেণিবিন্যাস' : 'Taxonomic classification', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...rows.entries.map((e) => Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
              child: Row(children: [
                Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                Flexible(child: Text(e.value, textAlign: TextAlign.end, style: const TextStyle(fontStyle: FontStyle.italic))),
              ]),
            ),
          )),
          const SizedBox(height: 12),
          Text(bengali ? 'সংক্ষিপ্ত পরিচিতি' : 'Overview', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(species.description),
          const SizedBox(height: 20),
          Text(bengali ? 'তথ্য যাচাই: প্রাথমিক নমুনা ডেটা। প্রকাশের আগে নির্ভরযোগ্য উৎস দিয়ে যাচাই করতে হবে।' : 'Data status: Starter sample record. Verify against authoritative sources before publication.', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
