import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Read and add calendar events. Narrower than full calendar access.
const String kCalendarScope = 'https://www.googleapis.com/auth/calendar.events';

/// The Android package name the Google Cloud OAuth client must list.
const String kAppPackage = 'com.algoanalytics.vigil';

class GoogleAccount {
  const GoogleAccount({required this.slot, required this.email, required this.label});

  final int slot;
  final String email;
  final String label;

  Map<String, dynamic> toJson() => <String, dynamic>{'slot': slot, 'email': email, 'label': label};

  factory GoogleAccount.fromJson(Map<String, dynamic> j) => GoogleAccount(slot: j['slot'] as int, email: j['email'] as String, label: j['label'] as String);
}

enum AuthStatus { ok, consentNeeded, cancelled, error }

class AuthResult {
  const AuthResult(this.status, {this.token, this.message});

  final AuthStatus status;
  final String? token;
  final String? message;
}

/// The phone side of Google sign-in. The real one talks to Android; tests use a fake.
abstract interface class GoogleAuthPlatform {
  Future<bool> available();

  /// SHA-1 of the key this APK is signed with.
  Future<String?> signingSha1();

  /// Account chooser; the email chosen, or null if the user backed out.
  Future<String?> pickAccount();

  /// Access token for [email] and the calendar scope. Without [interactive] it never opens a screen.
  Future<AuthResult> authorize(String email, {required bool interactive});

  Future<void> revoke(String email);
}

class MethodChannelGoogleAuth implements GoogleAuthPlatform {
  const MethodChannelGoogleAuth();

  static const MethodChannel _ch = MethodChannel('vigil/google_auth');

  Future<T?> _call<T>(String method, [Map<String, Object?>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> available() async {
    try {
      return (await _call<bool>('available')) ?? false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String?> signingSha1() async {
    try {
      return await _call<String>('sha1');
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<String?> pickAccount() async {
    try {
      return await _call<String>('pickAccount');
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<AuthResult> authorize(String email, {required bool interactive}) async {
    try {
      final Map<Object?, Object?>? r = await _call<Map<Object?, Object?>>('authorize', <String, Object?>{
        'email': email,
        'scopes': <String>[kCalendarScope],
        'interactive': interactive,
      });
      return switch (r?['status']) {
        'ok' => AuthResult(AuthStatus.ok, token: r!['token'] as String?),
        'consent_needed' => const AuthResult(AuthStatus.consentNeeded),
        'cancelled' => const AuthResult(AuthStatus.cancelled),
        _ => AuthResult(AuthStatus.error, message: (r?['message'] as String?) ?? 'Google sign-in is not available in this build.'),
      };
    } on PlatformException catch (e) {
      return AuthResult(AuthStatus.error, message: e.message ?? e.code);
    }
  }

  @override
  Future<void> revoke(String email) async {
    try {
      await _call<bool>('revoke', <String, Object?>{'email': email, 'scopes': <String>[kCalendarScope]});
    } on PlatformException {
      // The link is removed here either way; the user can also remove access in their Google account.
    }
  }
}

/// A plain-language reason for a failed sign-in, from Google's error text.
String explainAuthError(AuthResult r) {
  switch (r.status) {
    case AuthStatus.ok:
      return 'Linked.';
    case AuthStatus.cancelled:
      return 'Cancelled. Nothing was linked.';
    case AuthStatus.consentNeeded:
      return 'Google needs your approval again.';
    case AuthStatus.error:
      final String m = r.message ?? '';
      if (RegExp(r'^\s*10\b').hasMatch(m) || m.toUpperCase().contains('DEVELOPER_ERROR')) {
        return 'Google rejected this app. The Android OAuth client must list package $kAppPackage and this app\'s SHA-1 (shown on this screen).';
      }
      if (RegExp(r'^\s*(7|8)\b').hasMatch(m) || m.toLowerCase().contains('network')) return 'No connection to Google. Try again online.';
      if (m.toLowerCase().contains('access_denied') || m.toLowerCase().contains('not authorized')) {
        return 'Google refused. Add this account as a Test user on the OAuth consent screen.';
      }
      return m.isEmpty ? 'Google sign-in failed.' : 'Google said: $m';
  }
}

/// Up to two linked Google accounts. Nothing secret is stored: the phone keeps the grant, and an access
/// token is requested whenever one is needed.
class GoogleAccounts extends ChangeNotifier {
  GoogleAccounts({GoogleAuthPlatform? platform}) : _platform = platform ?? const MethodChannelGoogleAuth();

  static final GoogleAccounts instance = GoogleAccounts();

  static const int slots = 2;
  static const List<String> defaultLabels = <String>['PERSONAL', 'WORK'];
  static const String _prefKey = 'google_accounts';

  final GoogleAuthPlatform _platform;
  List<GoogleAccount> _accounts = const <GoogleAccount>[];
  final Map<String, String> _notes = <String, String>{}; // email -> why it needs attention
  bool? _available;
  String? _sha1;

  List<GoogleAccount> get accounts => _accounts;
  bool get hasAny => _accounts.isNotEmpty;

  GoogleAccount? bySlot(int slot) {
    for (final GoogleAccount a in _accounts) {
      if (a.slot == slot) return a;
    }
    return null;
  }

  /// Why [a] needs attention, or null when it is fine.
  String? noteOf(GoogleAccount a) => _notes[a.email];

  Future<void> load([SharedPreferences? prefs]) async {
    final SharedPreferences p = prefs ?? await SharedPreferences.getInstance();
    final String? raw = p.getString(_prefKey);
    if (raw == null) return;
    try {
      _accounts = <GoogleAccount>[
        for (final dynamic j in jsonDecode(raw) as List<dynamic>) GoogleAccount.fromJson(j as Map<String, dynamic>),
      ]..sort((GoogleAccount a, GoogleAccount b) => a.slot.compareTo(b.slot));
    } catch (_) {
      _accounts = const <GoogleAccount>[]; // unreadable: start clean rather than crash at launch
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final SharedPreferences p = await SharedPreferences.getInstance();
    await p.setString(_prefKey, jsonEncode(<Map<String, dynamic>>[for (final GoogleAccount a in _accounts) a.toJson()]));
  }

  Future<bool> isAvailable() async => _available ??= await _platform.available();

  Future<String?> signingSha1() async => _sha1 ??= await _platform.signingSha1();

  /// Pick an account on the phone and approve calendar access for it. Null on success, else what to tell the user.
  Future<String?> link(int slot) async {
    if (slot < 0 || slot >= slots) return 'Only two accounts can be linked.';
    if (!await isAvailable()) return 'Google Play services is not available on this phone.';
    final String? email = (await _platform.pickAccount())?.trim();
    if (email == null || email.isEmpty) return 'No account chosen.';
    for (final GoogleAccount a in _accounts) {
      if (a.slot != slot && a.email.toLowerCase() == email.toLowerCase()) return '$email is already linked as ${a.label}.';
    }
    final AuthResult r = await _platform.authorize(email, interactive: true);
    if (r.status != AuthStatus.ok) return explainAuthError(r);
    _accounts = <GoogleAccount>[
      ..._accounts.where((GoogleAccount a) => a.slot != slot),
      GoogleAccount(slot: slot, email: email, label: defaultLabels[slot]),
    ]..sort((GoogleAccount a, GoogleAccount b) => a.slot.compareTo(b.slot));
    _notes.remove(email);
    await _save();
    notifyListeners();
    return null;
  }

  Future<void> unlink(int slot) async {
    final GoogleAccount? a = bySlot(slot);
    if (a == null) return;
    await _platform.revoke(a.email);
    _accounts = _accounts.where((GoogleAccount x) => x.slot != slot).toList();
    _notes.remove(a.email);
    await _save();
    notifyListeners();
  }

  /// An access token for [a] without opening any screen; null when the approval has lapsed or Google failed.
  Future<String?> token(GoogleAccount a) async {
    final AuthResult r = await _platform.authorize(a.email, interactive: false);
    if (r.status == AuthStatus.ok && r.token != null) {
      markOk(a);
      return r.token;
    }
    markProblem(a, r.status == AuthStatus.consentNeeded ? 'Approve again: open Google accounts and link it once more.' : explainAuthError(r));
    return null;
  }

  void markOk(GoogleAccount a) {
    if (_notes.remove(a.email) != null) notifyListeners();
  }

  void markProblem(GoogleAccount a, String note) {
    if (_notes[a.email] == note) return;
    _notes[a.email] = note;
    notifyListeners();
  }
}
