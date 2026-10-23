import 'package:vigil/services/google_accounts.dart';

class FakeGoogle implements GoogleAuthPlatform {
  FakeGoogle({List<String?>? picks, Map<String, AuthResult>? auth})
      : picks = picks ?? <String?>[],
        auth = auth ?? <String, AuthResult>{};

  final List<String?> picks;
  final Map<String, AuthResult> auth;
  final Map<String, AuthResult> driveAuth = <String, AuthResult>{};
  final List<String> revoked = <String>[];
  final List<bool> interactiveCalls = <bool>[];
  bool playServices = true;

  @override
  Future<bool> available() async => playServices;

  @override
  Future<String?> signingSha1() async => 'AA:BB';

  @override
  Future<String?> pickAccount() async => picks.isEmpty ? null : picks.removeAt(0);

  final List<List<String>> scopesAsked = <List<String>>[];

  @override
  Future<AuthResult> authorize(String email, {required bool interactive, List<String> scopes = const <String>[kCalendarScope]}) async {
    interactiveCalls.add(interactive);
    scopesAsked.add(scopes);
    return (scopes.contains(kDriveScope) ? driveAuth[email] : null) ?? auth[email] ?? const AuthResult(AuthStatus.error, message: 'no such account');
  }

  @override
  Future<void> revoke(String email) async => revoked.add(email);
}

AuthResult tokenFor(String t) => AuthResult(AuthStatus.ok, token: t);
