import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'data.dart';
import 'updater.dart';

// ---------------------------------------------------------------------------
// "What's new" window.
//
// After an update the app shows what was added, once. To announce a new
// release: add a new WhatsNewEntry at the TOP of [kWhatsNew] with a new `id`.
// Users who skipped a few releases see all the entries they missed.
// ---------------------------------------------------------------------------

class WhatsNewItem {
  final IconData icon;
  final String en, bn, ja;
  const WhatsNewItem(this.icon, this.en, this.bn, this.ja);
}

class WhatsNewEntry {
  /// Change this for every release you want to announce. It is only compared,
  /// never shown.
  final String id;
  final String title; // short label shown under the heading, e.g. "Flashcards update"
  final List<WhatsNewItem> items;
  const WhatsNewEntry(this.id, this.title, this.items);
}

/// Newest first.
const List<WhatsNewEntry> kWhatsNew = [
  WhatsNewEntry('nexus-2', 'Smoother Nexus & full database', [
    WhatsNewItem(
      Icons.open_with,
      'The Nexus bubble now follows your finger smoothly and starts on the left, so it no longer covers switches and buttons.',
      'Nexus বাবল এখন আঙুলের সঙ্গে মসৃণভাবে চলে এবং বাঁ দিকে শুরু হয়, তাই সুইচ বা বোতাম ঢাকে না।',
      'Nexusバブルが指にスムーズに追従し、左側から始まるので、スイッチやボタンを隠しません。',
    ),
    WhatsNewItem(
      Icons.storage,
      'The full species database is now built into the app, so a fresh install has every species right away.',
      'পুরো প্রজাতির ডেটাবেস এখন অ্যাপের ভেতরেই আছে, তাই নতুন ইনস্টলেই সব প্রজাতি পাবে।',
      '全種のデータベースをアプリに内蔵しました。インストール直後からすべての種が使えます。',
    ),
  ]),
  WhatsNewEntry('nexus-1', 'Meet Nexus', [
    WhatsNewItem(
      Icons.auto_awesome,
      'Meet Nexus, your biology companion. Tap the glowing bubble to ask how the app works, look up a species or learn basic biology. It works offline.',
      'পরিচয় করো Nexus-এর সঙ্গে, তোমার বায়োলজি সঙ্গী। জ্বলজ্বলে বাবলে চেপে অ্যাপ কীভাবে চলে, কোনো প্রজাতির তথ্য বা বেসিক বায়োলজি জিজ্ঞেস করো। এটি অফলাইনেও চলে।',
      'あなたの生物学パートナー「Nexus」です。光るバブルをタップして、アプリの使い方や種の情報、基本の生物学を聞けます。オフラインでも使えます。',
    ),
    WhatsNewItem(
      Icons.open_with,
      'Drag the bubble anywhere you like, or turn it off in Settings → Nexus assistant.',
      'বাবলটি টেনে যেখানে খুশি সরাও, বা সেটিংস → Nexus সহকারী থেকে বন্ধ করো।',
      'バブルは好きな場所にドラッグできます。設定 → Nexusアシスタントでオフにもできます。',
    ),
  ]),
  WhatsNewEntry('splash-1', 'Speed & opening screen', [
    WhatsNewItem(
      Icons.bolt,
      'Photos load faster: the next species photos are prepared while you read.',
      'ছবি আরও দ্রুত লোড হয়: তুমি পড়ার সময়েই পরের প্রজাতির ছবি তৈরি হয়ে যায়।',
      '写真の読み込みが速くなりました。読んでいる間に次の写真を準備します。',
    ),
    WhatsNewItem(
      Icons.auto_awesome,
      'A new opening screen with a loading animation.',
      'নতুন ওপেনিং স্ক্রিন ও লোডিং অ্যানিমেশন।',
      '読み込みアニメーション付きの新しいオープニング画面。',
    ),
  ]),
  WhatsNewEntry('streak-1', 'Daily streak', [
    WhatsNewItem(
      Icons.local_fire_department,
      'Your streak now counts every day you open the app, not only quiz days.',
      'এখন অ্যাপ খুললেই দিনের ধারা গোনা হবে, শুধু কুইজের দিন নয়।',
      'クイズをしなくても、アプリを開いた日が連続日数に数えられます。',
    ),
    WhatsNewItem(
      Icons.whatshot,
      'The flame grows with your streak: Spark, Flame, Blaze, Inferno, Legend, Mythic. Miss a day and it goes out.',
      'ধারা বাড়লে শিখাও বড় হয়: স্পার্ক, শিখা, ব্লেজ, ইনফার্নো, লিজেন্ড, মিথিক। একদিন বাদ গেলে নিভে যায়।',
      '連続日数に合わせて炎が成長します。1日休むと消えてしまいます。',
    ),
  ]),
  WhatsNewEntry('flashcards-1', 'Flashcards & more', [
    WhatsNewItem(
      Icons.view_carousel,
      'Flashcards in the Study zone: flip a card, then swipe right if you know it or left to see it again.',
      'স্টাডি জোনে ফ্ল্যাশকার্ড: কার্ড উল্টাও, জানা হলে ডানে, আবার দেখতে চাইলে বামে সোয়াইপ করো।',
      '学習ゾーンにフラッシュカード：カードをめくって、知っていれば右、もう一度見たいなら左にスワイプ。',
    ),
    WhatsNewItem(
      Icons.pets,
      'Over 10,000 species: many more animals were added to the database.',
      '১০,০০০-এরও বেশি প্রজাতি: ডেটাবেসে অনেক নতুন প্রাণী যোগ হয়েছে।',
      '10,000種以上：データベースに多くの動物が追加されました。',
    ),
    WhatsNewItem(
      Icons.animation,
      'Smoother page transitions: a card now grows into its page and shrinks back.',
      'আরও মসৃণ পেজ ট্রানজিশন: কার্ড বড় হয়ে পেজ খোলে, আবার ছোট হয়ে ফিরে আসে।',
      'なめらかな画面遷移：カードが広がってページが開き、戻ると小さくなります。',
    ),
    WhatsNewItem(
      Icons.new_releases,
      'After every update this window tells you what is new.',
      'প্রতিটি আপডেটের পর এখানে জানা যাবে নতুন কী এসেছে।',
      'アップデートの後は、ここで新機能をお知らせします。',
    ),
  ]),
];

// ---------- remembering what the user has already seen ----------
Future<File> _file() async {
  final d = await getApplicationSupportDirectory();
  return File('${d.path}/bionexus_whatsnew.json');
}

/// null = nothing saved yet. Throws if the phone storage cannot be used, so the
/// caller can stay quiet instead of showing the window on every start.
Future<String?> _loadSeen() async {
  final f = await _file();
  if (!await f.exists()) return null;
  try {
    final m = jsonDecode(await f.readAsString());
    return m is Map ? m['seen']?.toString() : null;
  } on FormatException {
    return null; // damaged file: treat as "nothing seen yet"
  }
}

Future<void> _saveSeen(String id) async {
  try {
    final f = await _file();
    await f.writeAsString(jsonEncode({'seen': id}), flush: true);
  } catch (e) {
    debugPrint('Could not save what\'s new: $e');
  }
}

List<WhatsNewEntry> _unseen(String? seen) {
  if (kWhatsNew.isEmpty) return const [];
  if (seen == null) return [kWhatsNew.first];
  final i = kWhatsNew.indexWhere((e) => e.id == seen);
  if (i == 0) return const []; // already seen the newest
  if (i < 0) return [kWhatsNew.first]; // unknown (older) id: just show the newest
  return kWhatsNew.sublist(0, i);
}

bool _shownThisStart = false;

/// Called once when the app starts. Shows the window only if there is
/// something the user has not seen yet.
Future<void> showWhatsNewIfNeeded(BuildContext context, Lang Function() currentLang) async {
  // Widget tests have no phone storage and must not be left with a pending timer.
  if (Platform.environment.containsKey('FLUTTER_TEST')) return;
  // give the saved language a moment to load, so the window opens in it
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  if (!context.mounted) return;
  String? seen;
  var storageOk = true;
  try {
    seen = await _loadSeen();
  } catch (e) {
    // The phone storage cannot be read. Do not hide the news because of that:
    // show it once per start instead (and Settings → Storage check shows the reason).
    storageOk = false;
    debugPrint('What\'s new: storage problem: $e');
  }
  final unseen = _unseen(seen);
  if (unseen.isEmpty || !context.mounted) return;
  if (storageOk) {
    await _saveSeen(kWhatsNew.first.id); // saved first, so it never repeats
  } else {
    if (_shownThisStart) return;
  }
  _shownThisStart = true;
  if (!context.mounted) return;
  await showWhatsNewDialog(context, currentLang(), unseen);
}

/// Also used by Settings -> "What's new" (shows the newest entry).
Future<void> showWhatsNewDialog(BuildContext context, Lang lang, [List<WhatsNewEntry>? entries]) {
  final list = entries ?? (kWhatsNew.isEmpty ? <WhatsNewEntry>[] : [kWhatsNew.first]);
  String t(String en, String bn, String ja) => tr(lang, en, bn, ja);
  return showDialog<void>(
    context: context,
    builder: (context) {
      final text = Theme.of(context).textTheme;
      return AlertDialog(
        icon: const Icon(Icons.auto_awesome),
        title: Text(t("What's new", 'নতুন কী এসেছে', '新機能')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in list) ...[
                  if (list.length > 1) ...[
                    Text(e.title, style: text.titleSmall),
                    const SizedBox(height: 6),
                  ],
                  for (final it in e.items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(it.icon, size: 20, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(child: Text(t(it.en, it.bn, it.ja))),
                      ]),
                    ),
                ],
                Text(
                  '${t('Installed build', 'ইনস্টল করা বিল্ড', 'インストール済みビルド')}: ${kBuildNumber == 0 ? '-' : kBuildNumber}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('Got it', 'বুঝেছি', 'OK')),
          ),
        ],
      );
    },
  );
}
