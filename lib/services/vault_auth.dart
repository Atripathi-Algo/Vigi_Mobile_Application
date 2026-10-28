import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

/// How an attempt to open the Vault went.
enum VaultAuthResult {
  /// The user passed the phone's fingerprint, face or PIN check.
  ok,

  /// The user cancelled or did not pass.
  failed,

  /// The phone has no screen lock (or no way to ask for it), so there is nothing to check against.
  unavailable,
}

/// Asks the phone to confirm it is the owner: fingerprint, face, or the screen-lock PIN, pattern or password.
/// A seam so tests do not need a phone.
abstract class VaultAuth {
  Future<VaultAuthResult> unlock();
}

class DeviceVaultAuth implements VaultAuth {
  final LocalAuthentication _auth = LocalAuthentication();

  @override
  Future<VaultAuthResult> unlock() async {
    try {
      if (!await _auth.isDeviceSupported()) return VaultAuthResult.unavailable;
      final bool ok = await _auth.authenticate(localizedReason: 'Unlock the Vault', options: const AuthenticationOptions(stickyAuth: true));
      return ok ? VaultAuthResult.ok : VaultAuthResult.failed;
    } on PlatformException {
      // No screen lock enrolled, or the system could not show its prompt.
      return VaultAuthResult.unavailable;
    }
  }
}
