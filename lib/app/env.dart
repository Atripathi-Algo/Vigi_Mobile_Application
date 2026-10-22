import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Typed access to configuration. Two layers, highest first:
///  1. values saved in the app (Loadout > API keys), kept in encrypted storage;
///  2. the bundled `.env` file (see `.env.example`).
/// Every key is optional; a blank value means "feature off".
abstract final class Env {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _prefix = 'vigil_key_';
  static final Map<String, String> _overrides = <String, String>{};

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Missing .env is fine: the app runs fully on-device.
      dotenv.testLoad(fileInput: '');
    }
    await _loadOverrides();
  }

  static Future<void> _loadOverrides() async {
    try {
      final Map<String, String> all = await _storage.readAll();
      _overrides.clear();
      all.forEach((String k, String v) {
        if (k.startsWith(_prefix) && v.trim().isNotEmpty) _overrides[k.substring(_prefix.length)] = v.trim();
      });
    } catch (_) {
      // Secure storage can fail on a locked or restored device; fall back to .env only.
    }
  }

  /// Save app-level values. An empty value removes the override, so the `.env` value (if any) applies again.
  static Future<void> save(Map<String, String> values) async {
    for (final MapEntry<String, String> e in values.entries) {
      final String v = e.value.trim();
      if (v.isEmpty) {
        _overrides.remove(e.key);
        await _storage.delete(key: '$_prefix${e.key}');
      } else {
        _overrides[e.key] = v;
        await _storage.write(key: '$_prefix${e.key}', value: v);
      }
    }
  }

  /// The value in effect for [key] (app value first, then `.env`).
  static String value(String key) => _get(key);

  /// Where the value in effect comes from: `APP`, `.ENV` or `NONE`.
  static String source(String key) {
    if (_overrides.containsKey(key)) return 'APP';
    return (dotenv.maybeGet(key) ?? '').trim().isEmpty ? 'NONE' : '.ENV';
  }

  static String _get(String key, [String fallback = '']) {
    final String v = (_overrides[key] ?? dotenv.maybeGet(key) ?? '').trim();
    return v.isEmpty ? fallback : v;
  }

  static String get vigilApiBaseUrl => _get('VIGIL_API_BASE_URL');
  static String get vigilApiKey => _get('VIGIL_API_KEY');

  static String get googleClientId => _get('GOOGLE_CLIENT_ID');
  static String get googleCalendarApiKey => _get('GOOGLE_CALENDAR_API_KEY');
  static String get googleCalendarId => _get('GOOGLE_CALENDAR_ID');

  static String get weatherBaseUrl => _get('WEATHER_API_BASE_URL', 'https://api.open-meteo.com/v1/forecast');
  static double get weatherLat => double.tryParse(_get('WEATHER_LATITUDE', '28.6139')) ?? 28.6139;
  static double get weatherLon => double.tryParse(_get('WEATHER_LONGITUDE', '77.2090')) ?? 77.2090;

  static String get cloudAiProvider => _get('CLOUD_AI_PROVIDER', 'anthropic').toLowerCase();
  static String get cloudAiKey => _get('CLOUD_AI_API_KEY');
  static String get cloudAiModel => _get('CLOUD_AI_MODEL', cloudAiProvider == 'openai' ? 'gpt-4o-mini' : 'claude-haiku-5-5');
  static String get cloudAiBaseUrl => _get('CLOUD_AI_BASE_URL', cloudAiProvider == 'openai' ? 'https://api.openai.com' : 'https://api.anthropic.com');

  // Firebase Cloud Messaging. Options are passed at runtime, so no google-services.json is needed.
  static String get firebaseApiKey => _get('FIREBASE_API_KEY');
  static String get firebaseAppId => _get('FIREBASE_APP_ID');
  static String get firebaseSenderId => _get('FIREBASE_MESSAGING_SENDER_ID');
  static String get firebaseProjectId => _get('FIREBASE_PROJECT_ID');
  static String get firebaseStorageBucket => _get('FIREBASE_STORAGE_BUCKET');
  static bool get hasFirebase => firebaseApiKey.isNotEmpty && firebaseAppId.isNotEmpty && firebaseSenderId.isNotEmpty && firebaseProjectId.isNotEmpty;

  static bool get hasCloudAi => cloudAiKey.isNotEmpty;
  static bool get hasCalendar => googleCalendarApiKey.isNotEmpty && googleCalendarId.isNotEmpty;
}
