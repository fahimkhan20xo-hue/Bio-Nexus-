import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'data.dart';

// Reads species names aloud with the phone's own text-to-speech voices.
// "en" speaks the Latin name with an English voice, "bn" speaks the Bengali
// pronunciation text with a Bengali voice. No audio files are needed.

final FlutterTts _tts = FlutterTts();

enum SpeakResult { ok, noVoice, error }

bool _yes(dynamic v) => v == true || v == 1;

Future<SpeakResult> speakText(String text, {required String lang, bool slow = false}) async {
  final clean = text.trim();
  if (clean.isEmpty) return SpeakResult.error;
  try {
    final candidates = lang == 'bn' ? ['bn-BD', 'bn-IN', 'bn'] : ['en-US', 'en-GB', 'en'];
    String? code;
    for (final c in candidates) {
      if (_yes(await _tts.isLanguageAvailable(c))) {
        code = c;
        break;
      }
    }
    if (code == null) return SpeakResult.noVoice;
    await _tts.setLanguage(code);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setSpeechRate(slow ? 0.28 : 0.45);
    await _tts.stop();
    await _tts.speak(clean);
    return SpeakResult.ok;
  } catch (e) {
    debugPrint('Text-to-speech error: $e');
    return SpeakResult.error;
  }
}

Future<void> stopSpeaking() async {
  try {
    await _tts.stop();
  } catch (e) {
    debugPrint('Text-to-speech stop error: $e');
  }
}

/// A short message for the user when speaking did not work (null when it did).
String? speakFailMessage(Lang ui, String speechLang, SpeakResult r) {
  if (r == SpeakResult.ok) return null;
  if (r == SpeakResult.noVoice) {
    if (speechLang == 'bn') {
      return tr(
        ui,
        'No Bengali voice found. Install a Bengali voice in Google "Speech Services" (phone Settings).',
        'বাংলা ভয়েস পাওয়া যায়নি। ফোনের Settings-এ Google "Speech Services"-এ বাংলা ভয়েস ইনস্টল করো।',
        'ベンガル語の音声がありません。端末のGoogle「音声サービス」でベンガル語をインストールしてください。',
      );
    }
    return tr(
      ui,
      'No English voice found on this phone.',
      'এই ফোনে ইংরেজি ভয়েস পাওয়া যায়নি।',
      'この端末に英語の音声がありません。',
    );
  }
  return tr(ui, 'Could not play the audio.', 'অডিও চালানো যায়নি।', '音声を再生できませんでした。');
}
