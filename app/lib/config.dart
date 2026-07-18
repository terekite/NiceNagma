// App-wide configuration and defaults.
//
// The render service base URL is the one thing that changes between machines.
// Override it at launch without editing code:
//
//   flutter run --dart-define=RENDER_URL=http://192.168.1.23:8000
//
// The iOS Simulator can reach the Mac at 127.0.0.1. A physical device must use
// the Mac's LAN IP (System Settings -> Wi-Fi -> Details), and the Mac and phone
// must be on the same network. Cleartext HTTP to the LAN is allowed via the ATS
// exception `bootstrap.sh` writes into Info.plist.

class Config {
  // Which renderer produces loops:
  //   'local' (default) — on-device: renders on the phone, free and offline.
  //   'http'            — the Python render service at renderBaseUrl (LAN/cloud).
  // Override at launch: flutter run --dart-define=RENDERER=http
  static const String renderer =
      String.fromEnvironment('RENDERER', defaultValue: 'local');

  // Only used when renderer == 'http'. The one thing that changes between
  // machines; point it at a LAN Mac or a cloud-hosted render service.
  static const String renderBaseUrl =
      String.fromEnvironment('RENDER_URL', defaultValue: 'http://127.0.0.1:8000');

  // MVP defaults (spec): Bhairavi-flavoured proposed lehra, D Sa, madhya ~80 BPM.
  static const String defaultSa = 'D';
  static const double defaultBpm = 80;
  static const int defaultAvartans = 4;
  static const String defaultTaal = 'teentaal';

  // Tempo control range. Laya (vilambit/madhya/drut) is auto-selected server-side.
  static const double minBpm = 30;
  static const double maxBpm = 300;

  // The 12 keys the tabla can be tuned to. Sargam transposes to match.
  static const List<String> keys = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  // The canonical proposed Teentaal lehra, embedded so the app plays on first
  // launch with no bundled asset. Mirrors assets/nagmas/proposed-teentaal.nagma
  // (comments stripped; the parser accepts either).
  static const String defaultNagma = '''
S S S N.,S
g R N. S
M. P. g. R.,S.
g. M. P. N.''';
}
