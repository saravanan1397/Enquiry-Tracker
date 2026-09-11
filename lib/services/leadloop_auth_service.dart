import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'email_recovery_service.dart';
import 'mobile_number_validator.dart';
import 'notification_service.dart';

class LeadloopAuthSession {
  const LeadloopAuthSession({
    required this.uid,
    required this.role,
    required this.displayName,
    this.shopId = '',
    this.shopName = '',
  });

  final String uid;
  final String role;
  final String displayName;
  final String shopId;
  final String shopName;
}

class LeadloopAuthService {
  LeadloopAuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  static const _sessionKey = 'leadloop_auth_session';
  static const _activityKey = 'leadloop_auth_last_activity';
  static const _sessionDuration = Duration(days: 30);
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final DeviceLoginEmails _deviceEmails = DeviceLoginEmails();
  String get _project => _auth.app.options.projectId;

  Future<LeadloopAuthSession> registerPromoter({
    required String name,
    required String mobile,
    required String pin,
    required String shopName,
    required String email,
  }) async {
    final normalizedMobile = _normalizeMobile(mobile);
    if (!RecoveryValidation.email(email) || !RecoveryValidation.pin(pin)) {
      throw const LeadloopAuthException(
          'Enter a real email address and a PIN of 6–128 digits.');
    }
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim().toLowerCase(),
      password: pin,
    );
    final user = credential.user!;
    await user.updateDisplayName(name.trim());
    try {
      final batch = _firestore.batch();
      batch.set(
        _firestore.collection('promoterMobiles').doc(normalizedMobile),
        {'uid': user.uid},
      );
      batch.set(_firestore.collection('promoters').doc(user.uid), {
        'name': name.trim(),
        'mobile': normalizedMobile,
        'shopName': shopName.trim(),
        'shopId': _shopIdFromName(shopName),
        'role': 'promoter',
        'active': false,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();
    } on FirebaseException catch (error) {
      // Roll back only the Auth account just created by this registration attempt.
      await user.delete();
      if (error.code == 'permission-denied') {
        throw const LeadloopAuthException(
            'This mobile number is already registered.');
      }
      rethrow;
    } catch (_) {
      await user.delete();
      rethrow;
    }
    await _deviceEmails.remember(_project, normalizedMobile, user.email!);
    try {
      await user.sendEmailVerification(EmailRecoveryService.settings);
    } catch (_) {
      throw const LeadloopAuthException(
          'Account created, but verification email could not be sent. Use “Set up / verify recovery email” to resend; do not register again.');
    }
    return LeadloopAuthSession(
      uid: user.uid,
      role: 'promoter',
      displayName: name.trim(),
      shopId: _shopIdFromName(shopName),
      shopName: shopName.trim(),
    );
  }

  Future<LeadloopAuthSession> signInPromoter({
    required String mobile,
    required String pin,
    String? email,
    bool emailSetupOnly = false,
  }) async {
    final normalizedMobile = _normalizeMobile(mobile);
    final suppliedEmail = email?.trim() ?? '';
    if (suppliedEmail.isNotEmpty && !RecoveryValidation.email(suppliedEmail)) {
      throw const LeadloopAuthException('Enter a real email address.');
    }
    final loginEmail = suppliedEmail.isNotEmpty
        ? suppliedEmail.toLowerCase()
        : await _deviceEmails.read(_project, normalizedMobile) ??
            _authEmail(normalizedMobile);
    final credential = await _auth.signInWithEmailAndPassword(
      email: loginEmail,
      password: pin,
    );
    final user = credential.user!;
    final snapshot =
        await _firestore.collection('promoters').doc(user.uid).get();
    final data = snapshot.data();
    if (data == null ||
        data['role'] != 'promoter' ||
        data['mobile'] != normalizedMobile) {
      await _auth.signOut();
      throw const LeadloopAuthException(
          'The email and mobile number do not match this promoter account.');
    }
    if (!RecoveryValidation.legacy(user.email)) {
      await _deviceEmails.remember(_project, normalizedMobile, user.email!);
    }
    if (!emailSetupOnly &&
        !RecoveryValidation.legacy(user.email) &&
        !user.emailVerified) {
      await _auth.signOut();
      throw const LeadloopAuthException(
          'Verify your email before signing in. Use “Set up / verify recovery email” to resend the link.');
    }
    final status = data['status'] as String? ?? '';
    if (emailSetupOnly && (status == 'disabled' || status == 'deleting')) {
      await _auth.signOut();
      throw const LeadloopAuthException('This promoter account is disabled.');
    }
    if (!emailSetupOnly && data['active'] != true) {
      await _auth.signOut();
      throw LeadloopAuthException(status == 'pending'
          ? 'Registration is waiting for owner approval.'
          : 'This promoter account is disabled.');
    }
    final session = LeadloopAuthSession(
      uid: user.uid,
      role: 'promoter',
      displayName: data['name'] as String? ?? user.displayName ?? 'Promoter',
      shopId: data['shopId'] as String? ?? '',
      shopName: data['shopName'] as String? ?? '',
    );
    if (!emailSetupOnly) await _rememberSession(session);
    return session;
  }

  Future<void> rememberVerifiedEmail(User user) async {
    final data =
        (await _firestore.collection('promoters').doc(user.uid).get()).data();
    if (data == null ||
        data['role'] != 'promoter' ||
        (data['status'] == 'disabled' || data['status'] == 'deleting') ||
        !user.emailVerified ||
        RecoveryValidation.legacy(user.email)) {
      throw const LeadloopAuthException(
          'A verified promoter email is required.');
    }
    final mobile = data['mobile'] as String;
    await _firestore
        .collection('promoterMobiles')
        .doc(mobile)
        .set({'uid': user.uid});
    await _deviceEmails.remember(_project, mobile, user.email!);
  }

  Future<LeadloopAuthSession> signInAdmin({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    final snapshot = await _firestore.collection('users').doc(user.uid).get();
    final data = snapshot.data();
    if (data == null || data['role'] != 'admin' || data['active'] != true) {
      await _auth.signOut();
      throw const LeadloopAuthException(
          'This account is not an active owner account.');
    }
    final session = LeadloopAuthSession(
      uid: user.uid,
      role: 'admin',
      displayName: data['name'] as String? ?? user.displayName ?? 'Owner',
    );
    await _rememberSession(session);
    return session;
  }

  Future<LeadloopAuthSession?> restoreSession() async {
    if (Firebase.apps.isEmpty || _auth.currentUser == null) return null;

    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null) return null;
    final map = jsonDecode(encoded) as Map<String, dynamic>;
    final user = _auth.currentUser!;
    if (map['uid'] != user.uid) return null;

    final lastActivityValue = await _storage.read(key: _activityKey);
    final lastActivity =
        lastActivityValue == null ? null : DateTime.tryParse(lastActivityValue);
    if (lastActivity != null &&
        DateTime.now().difference(lastActivity) > _sessionDuration) {
      await signOut();
      return null;
    }

    final session = LeadloopAuthSession(
      uid: user.uid,
      role: map['role'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'User',
      shopId: map['shopId'] as String? ?? '',
      shopName: map['shopName'] as String? ?? '',
    );
    await touchActivity();
    return session;
  }

  Future<void> touchActivity() async {
    if (_auth.currentUser != null) {
      await _storage.write(
          key: _activityKey, value: DateTime.now().toIso8601String());
    }
  }

  Future<void> signOut() async {
    await NotificationService.instance.disable();
    await _auth.signOut();
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _activityKey);
  }

  Future<void> clearBlockedSession() async {
    // A remote disable/delete must not leave the UI unlocked just because FCM
    // token removal fails offline. Server permission checks already deny access.
    NotificationService.instance.stop();
    try {
      await _auth.signOut();
    } catch (_) {/* Already revoked/deleted. */}
    try {
      await _storage.delete(key: _sessionKey);
      await _storage.delete(key: _activityKey);
    } catch (_) {/* Profile watcher will block again on the next connection. */}
  }

  Future<void> _rememberSession(LeadloopAuthSession session) async {
    await _storage.write(
        key: _sessionKey,
        value: jsonEncode({
          'uid': session.uid,
          'role': session.role,
          'displayName': session.displayName,
          'shopId': session.shopId,
          'shopName': session.shopName,
        }));
    await touchActivity();
  }

  String _normalizeMobile(String mobile) {
    final normalized = mobile.trim();
    if (!MobileNumberValidator.isValid(normalized)) {
      throw const LeadloopAuthException(MobileNumberValidator.errorMessage);
    }
    return normalized;
  }

  String _authEmail(String mobile) => '$mobile@auth.leadloop.app';

  String _shopIdFromName(String shopName) => shopName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

class LeadloopAuthException implements Exception {
  const LeadloopAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
