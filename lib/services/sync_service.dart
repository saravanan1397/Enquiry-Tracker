import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum EnquiryTrackerSyncStatus { checking, offline, syncing, synced, error }

class SyncService {
  SyncService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<void> Function()? _syncPending;
  final status = ValueNotifier(EnquiryTrackerSyncStatus.checking);

  Future<void> start({required Future<void> Function() syncPending}) async {
    _syncPending = syncPending;
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      if (_isOnline(results)) {
        syncNow();
      } else {
        status.value = EnquiryTrackerSyncStatus.offline;
      }
    });
    await syncNow();
  }

  Future<void> syncNow() async {
    final results = await _connectivity.checkConnectivity();
    if (!_isOnline(results)) {
      status.value = EnquiryTrackerSyncStatus.offline;
      return;
    }
    status.value = EnquiryTrackerSyncStatus.syncing;
    try {
      await _syncPending?.call();
      status.value = EnquiryTrackerSyncStatus.synced;
    } catch (_) {
      status.value = EnquiryTrackerSyncStatus.error;
    }
  }

  bool _isOnline(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    status.dispose();
  }
}
