import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Phone notifications are privately registered to the authenticated account.
/// The server derives the recipient UID; clients cannot choose another user.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();
  StreamSubscription<String>? _tokens;
  Timer? _retry;
  String? _uid;
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start(String uid) async {
    if (!supported) return;
    stop();
    _uid = uid;
    _tokens =
        FirebaseMessaging.instance.onTokenRefresh.listen((_) => _register());
    _retry = Timer.periodic(const Duration(minutes: 5), (_) => _register());
    try {
      final permission = await FirebaseMessaging.instance.requestPermission();
      if (permission.authorizationStatus == AuthorizationStatus.authorized) {
        await _register();
      }
    } catch (error) {
      debugPrint('Notification setup failed: $error');
    }
  }

  Future<void> _register() async {
    final uid = _uid;
    if (uid == null || FirebaseAuth.instance.currentUser?.uid != uid) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null ||
          _uid != uid ||
          FirebaseAuth.instance.currentUser?.uid != uid) {
        return;
      }
      await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('registerReminderDevice')
          .call({'token': token}).timeout(const Duration(seconds: 15));
    } catch (error) {
      debugPrint('Notification registration will retry: $error');
    }
  }

  // Called before sign-out: invalidate this installation's old recipient token.
  Future<void> disable() async {
    if (!supported) return;
    stop();
    await FirebaseMessaging.instance.deleteToken();
  }

  void stop() {
    _uid = null;
    _tokens?.cancel();
    _tokens = null;
    _retry?.cancel();
    _retry = null;
  }
}
