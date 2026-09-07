import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum LeadloopSyncStatus { checking, offline, syncing, synced, error }

class SyncService {
  SyncService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<void> Function()? _syncPending;
  Future<void>? _syncInFlight;
  bool _syncRequested = false;
  final status = ValueNotifier(LeadloopSyncStatus.checking);

  Future<void> start({required Future<void> Function() syncPending}) async {
    _syncPending = syncPending;
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      if (_isOnline(results)) {
        syncNow();
      } else {
        status.value = LeadloopSyncStatus.offline;
      }
    });
    await syncNow();
  }

  Future<void> syncNow() {
    _syncRequested = true;
    final activeSync = _syncInFlight;
    if (activeSync != null) return activeSync;
    final operation = _drainSyncRequests();
    _syncInFlight = operation;
    return operation.whenComplete(() => _syncInFlight = null);
  }

  Future<void> _drainSyncRequests() async {
    while (_syncRequested) {
      _syncRequested = false;
      await _syncOnce();
    }
  }

  Future<void> _syncOnce() async {
    final results = await _connectivity.checkConnectivity();
    if (!_isOnline(results)) {
      status.value = LeadloopSyncStatus.offline;
      return;
    }
    status.value = LeadloopSyncStatus.syncing;
    try {
      await _syncPending?.call();
      status.value = LeadloopSyncStatus.synced;
    } catch (_) {
      status.value = LeadloopSyncStatus.error;
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
