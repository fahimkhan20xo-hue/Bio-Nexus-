import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Set by the build workflow (--dart-define=BUILD_NUMBER=...). 0 = unknown.
const int kBuildNumber = int.fromEnvironment('BUILD_NUMBER', defaultValue: 0);

const String _latestReleaseApi = 'https://api.github.com/repos/fahimkhan20xo-hue/Bio-Nexus-/releases/latest';

class UpdateInfo {
  final int build;
  final String url;
  const UpdateInfo(this.build, this.url);
  bool get isNewer => build > kBuildNumber;
}

/// Looks at the newest GitHub release. Returns null when it cannot be checked.
Future<UpdateInfo?> checkAppUpdate() async {
  try {
    final r = await http.get(
      Uri.parse(_latestReleaseApi),
      headers: {'Accept': 'application/vnd.github+json', 'User-Agent': 'BioNexus-App'},
    ).timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final m = RegExp(r'(\d+)$').firstMatch((j['tag_name'] ?? '').toString());
    if (m == null) return null;
    var url = (j['html_url'] ?? '').toString();
    final assets = j['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map && (a['name'] ?? '').toString().endsWith('.apk')) {
          url = (a['browser_download_url'] ?? url).toString();
          break;
        }
      }
    }
    return UpdateInfo(int.parse(m.group(1)!), url);
  } catch (e) {
    return null;
  }
}

/// Opens the APK download in the phone's browser.
Future<bool> openDownload(String url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    return false;
  }
}
