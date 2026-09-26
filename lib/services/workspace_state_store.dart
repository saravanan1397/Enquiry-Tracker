import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum OwnerWorkspaceView { dashboard, followups, sales, promoters }

class WorkspaceStateStore {
  const WorkspaceStateStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _ownerViewKey = 'enquiry_tracker_owner_view_v1';
  static const _salesMonthKey = 'enquiry_tracker_sales_month_v1';
  static const _salesRecycleBinKey = 'enquiry_tracker_sales_recycle_bin_v1';
  static const _followupRecycleBinKey =
      'enquiry_tracker_followup_recycle_bin_v1';
  static const _promoterRecycleBinKey =
      'enquiry_tracker_promoter_recycle_bin_v1';

  final FlutterSecureStorage _storage;

  Future<OwnerWorkspaceView> readOwnerView() async {
    try {
      final value = await _storage.read(key: _ownerViewKey);
      return OwnerWorkspaceView.values.firstWhere(
        (view) => view.name == value,
        orElse: () => OwnerWorkspaceView.dashboard,
      );
    } catch (_) {
      return OwnerWorkspaceView.dashboard;
    }
  }

  Future<void> writeOwnerView(OwnerWorkspaceView view) async {
    try {
      await _storage.write(key: _ownerViewKey, value: view.name);
    } catch (_) {
      // Navigation remains functional when browser storage is unavailable.
    }
  }

  Future<void> resetAdminWorkspace() async {
    await Future.wait([
      writeOwnerView(OwnerWorkspaceView.dashboard),
      writeSalesRecycleBin(false),
      writeFollowupRecycleBin(false),
      writePromoterRecycleBin(false),
    ]);
  }

  Future<String?> readSalesMonth() async {
    try {
      return await _storage.read(key: _salesMonthKey);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSalesMonth(String monthKey) async {
    try {
      await _storage.write(key: _salesMonthKey, value: monthKey);
    } catch (_) {
      // The current in-memory month remains selected.
    }
  }

  Future<bool> readSalesRecycleBin() async {
    try {
      return await _storage.read(key: _salesRecycleBinKey) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> writeSalesRecycleBin(bool visible) async {
    try {
      await _storage.write(
        key: _salesRecycleBinKey,
        value: visible.toString(),
      );
    } catch (_) {
      // The current in-memory view remains available.
    }
  }

  Future<bool> readFollowupRecycleBin() => _readBoolean(_followupRecycleBinKey);

  Future<void> writeFollowupRecycleBin(bool visible) =>
      _writeBoolean(_followupRecycleBinKey, visible);

  Future<bool> readPromoterRecycleBin() => _readBoolean(_promoterRecycleBinKey);

  Future<void> writePromoterRecycleBin(bool visible) =>
      _writeBoolean(_promoterRecycleBinKey, visible);

  Future<bool> _readBoolean(String key) async {
    try {
      return await _storage.read(key: key) == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _writeBoolean(String key, bool value) async {
    try {
      await _storage.write(key: key, value: value.toString());
    } catch (_) {
      // The current in-memory view remains available.
    }
  }
}
