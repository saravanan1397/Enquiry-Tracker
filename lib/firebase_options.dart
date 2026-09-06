// This placeholder keeps the app runnable in offline-only mode until the
// Firebase project is connected.
//
// Run `flutterfire configure` from the project root after creating your
// Firebase project. FlutterFire will replace this file with your real,
// platform-specific configuration.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for Fuchsia.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBsF1ITKp8Ikm6Vjs5iB2Ml0YolEAil4x0',
    appId: '1:874882828086:android:c778eb3a1af5216b69d597',
    messagingSenderId: '874882828086',
    projectId: 'sshtrackingapp',
    storageBucket: 'sshtrackingapp.firebasestorage.app',
  );
  static const FirebaseOptions ios = android;
  static const FirebaseOptions macos = android;
  static const FirebaseOptions windows = android;
  static const FirebaseOptions linux = android;
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB5VaIzwx5-H9DhcPHcDYDVXywgXVhiWmo',
    appId: '1:874882828086:web:c5e8fd4fda6ebc9d69d597',
    messagingSenderId: '874882828086',
    projectId: 'sshtrackingapp',
    authDomain: 'sshtrackingapp.firebaseapp.com',
    storageBucket: 'sshtrackingapp.firebasestorage.app',
  );
}
