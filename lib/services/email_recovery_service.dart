import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class RecoveryValidation {
  static bool email(String value) =>
      value.length <= 254 &&
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim()) &&
      !value.trim().toLowerCase().endsWith('@auth.leadloop.app');
  static bool pin(String value) => RegExp(r'^\d{6,128}$').hasMatch(value);
  static bool legacy(String? email) =>
      email == null || email.toLowerCase().endsWith('@auth.leadloop.app');
}

/// Email only, never the PIN. Scoped to this device/browser and Firebase project.
class DeviceLoginEmails {
  DeviceLoginEmails({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  String _key(String project, String mobile) =>
      'login_email_v1_${project}_$mobile';
  Future<String?> read(String project, String mobile) =>
      _storage.read(key: _key(project, mobile));
  Future<void> remember(String project, String mobile, String email) => _storage
      .write(key: _key(project, mobile), value: email.trim().toLowerCase());
}

class EmailRecoveryService {
  EmailRecoveryService({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;
  final FirebaseAuth _auth;
  static const site = 'https://saravanan1397.github.io/Enquiry-Tracker/';
  static ActionCodeSettings get settings => ActionCodeSettings(
      url: '$site?recovery=promoter', handleCodeInApp: false);

  Future<void> sendReset(String email) async {
    if (!RecoveryValidation.email(email)) {
      throw const FormatException('Enter your real registered email address.');
    }
    try {
      await _auth.sendPasswordResetEmail(
          email: email.trim().toLowerCase(), actionCodeSettings: settings);
    } on FirebaseAuthException catch (error) {
      // Same UI for unknown and registered addresses; do not disclose accounts.
      if (error.code != 'user-not-found') rethrow;
    }
  }

  Future<void> sendVerification(String email, String pin) async {
    if (!RecoveryValidation.email(email)) {
      throw const FormatException('Enter a real email address you can access.');
    }
    if (!RecoveryValidation.pin(pin)) {
      throw const FormatException('Enter your current PIN (6–128 digits).');
    }
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const FormatException(
          'Sign in again before setting up email recovery.');
    }
    await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: pin));
    if (user.email!.toLowerCase() == email.trim().toLowerCase()) {
      await user.sendEmailVerification(settings);
    } else {
      // Firebase changes the email only AFTER the recipient verifies it; UID stays the same.
      await user.verifyBeforeUpdateEmail(email.trim().toLowerCase(), settings);
    }
  }

  Future<User> confirmVerification(String email, String pin) async {
    if (!RecoveryValidation.email(email) || !RecoveryValidation.pin(pin)) {
      throw const FormatException(
          'Enter your verified email and current numeric PIN.');
    }
    final user = _auth.currentUser;
    if (user == null) {
      throw const FormatException(
          'Use “New device / email changed?” on sign-in to enter your verified email once.');
    }
    // Reauthentication cannot switch to a different Firebase UID.
    await user.reauthenticateWithCredential(EmailAuthProvider.credential(
        email: email.trim().toLowerCase(), password: pin));
    await user.reload();
    final refreshed = _auth.currentUser!;
    if (!refreshed.emailVerified ||
        RecoveryValidation.legacy(refreshed.email)) {
      throw const FormatException(
          'Open the verification email and click its link first.');
    }
    await refreshed.getIdToken(true);
    return refreshed;
  }
}
