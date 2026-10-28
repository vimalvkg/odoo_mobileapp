import 'package:local_auth/local_auth.dart';

final _auth = LocalAuthentication();

/// Whether the phone can do fingerprint/face (or device PIN) unlock.
Future<bool> biometricAvailable() async {
  try {
    return await _auth.isDeviceSupported();
  } catch (_) {
    return false;
  }
}

/// Shows the system unlock prompt. The check happens on the phone; Odoo is
/// never involved and nothing biometric leaves the device.
Future<bool> biometricUnlock(String reason) async {
  try {
    return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
  } catch (_) {
    return false;
  }
}
