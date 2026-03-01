import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static const _key = 'biometric_enabled';

  final LocalAuthentication _auth = LocalAuthentication();

  /// Whether the current platform supports biometric via local_auth.
  bool get _platformSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  /// Check if the device supports biometric authentication.
  Future<bool> isDeviceSupported() async {
    if (!_platformSupported) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Get the list of available biometric types on the device.
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (!_platformSupported) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Trigger biometric authentication with the given [reason] prompt.
  /// Returns true if authentication succeeded.
  Future<bool> authenticate({required String reason}) async {
    if (!_platformSupported) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// Read the biometric enabled preference.
  Future<bool> isBiometricEnabled() async {
    if (!_platformSupported) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  /// Save the biometric enabled preference.
  Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
