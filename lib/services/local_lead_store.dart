import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/customer_lead.dart';

class LocalLeadStore {
  static const _boxName = 'leadloop_leads';
  static const _keyName = 'leadloop_hive_key';
  static const _recoveryBoxName = 'leadloop_leads_device_cache';
  static const _recoveryKeyName = 'leadloop_hive_device_key';
  static const purchasedRetention = Duration(days: 10);

  static bool shouldRecyclePurchased(CustomerLead lead, DateTime now) {
    final completedAt = lead.completedAt;
    return lead.deletedAt == null &&
        lead.outcome == EnquiryOutcome.purchased &&
        completedAt != null &&
        !completedAt.isAfter(now.subtract(purchasedRetention));
  }

  static CustomerLead restoredLead(CustomerLead lead, {DateTime? now}) {
    final restoredAt = now ?? DateTime.now();
    return lead.copyWith(
      clearDeletedAt: true,
      isSynced: false,
      completedAt: lead.outcome == EnquiryOutcome.purchased
          ? restoredAt
          : lead.completedAt,
    );
  }

  LocalLeadStore({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(resetOnError: true),
            );

  final FlutterSecureStorage _secureStorage;
  final Map<String, CustomerLead> _cache = {};
  late Box<String> _box;

  Future<void> open() async {
    await Hive.initFlutter();
    try {
      _box = await _openEncryptedBox(_boxName, _keyName);
    } catch (error, stackTrace) {
      // Android may restore the encrypted Hive file onto a new phone without
      // its device-bound Keystore key. Preserve that original cache untouched
      // and use a fresh encrypted cache that Firebase can repopulate.
      debugPrint('Opening a new device-local cache: $error');
      debugPrintStack(stackTrace: stackTrace);
      _box = await _openEncryptedBox(_recoveryBoxName, _recoveryKeyName);
    }
    _cache
      ..clear()
      ..addEntries(
          _box.values.map(_decode).map((lead) => MapEntry(lead.id, lead)));
  }

  Future<Box<String>> _openEncryptedBox(
    String boxName,
    String keyName,
  ) async {
    var encodedKey = await _secureStorage.read(key: keyName);
    if (encodedKey == null) {
      encodedKey = base64UrlEncode(Hive.generateSecureKey());
      await _secureStorage.write(key: keyName, value: encodedKey);
    }
    final key = base64Url.decode(encodedKey);
    if (key.length != 32) {
      throw const FormatException('Invalid local encryption key');
    }
    return Hive.openBox<String>(
      boxName,
      encryptionCipher: HiveAesCipher(key),
    );
  }

  Future<void> save(CustomerLead lead) async {
    await _box.put(lead.id, jsonEncode(_toMap(lead)));
    _cache[lead.id] = lead;
  }

  /// Returns local changes that still need to be sent to Firebase.
  List<CustomerLead> pendingLeads() {
    return _cache.values.where((lead) => !lead.isSynced).toList();
  }

  Future<void> markSynced(String id) async {
    final lead = find(id);
    if (lead == null || lead.isSynced) return;
    await save(lead.copyWith(isSynced: true));
  }

  Future<void> markManySynced(Iterable<String> ids) async {
    final updates = ids
        .map(find)
        .whereType<CustomerLead>()
        .where((lead) => !lead.isSynced)
        .map((lead) => lead.copyWith(isSynced: true));
    await _saveAll(updates);
  }

  /// Stores a record downloaded from the central Firebase database.
  Future<void> saveFromServer(CustomerLead lead) async {
    final local = find(lead.id);
    if (local != null && !local.isSynced) return;
    await save(lead.copyWith(isSynced: true));
  }

  Future<void> removeSyncedLead(String id) async {
    final lead = find(id);
    if (lead == null || !lead.isSynced) return;
    await _deleteAll([id]);
  }

  bool hasSyncedLeads({String? promoterId}) => _cache.values.any(
        (lead) =>
            lead.isSynced &&
            (promoterId == null || lead.promoterId == promoterId),
      );

  int syncedLeadCount({String? promoterId}) => _cache.values
      .where((lead) =>
          lead.isSynced &&
          (promoterId == null || lead.promoterId == promoterId))
      .length;

  /// Removes records that were previously assigned to a promoter but are no
  /// longer returned by the server, such as a lead transferred to somebody
  /// else. Unsynced local records are kept until their upload completes.
  Future<void> reconcilePromoterLeads(
      String promoterId, Iterable<CustomerLead> serverLeads) async {
    final syncedServerLeads = serverLeads
        .map((lead) => lead.copyWith(isSynced: true))
        .toList(growable: false);
    final serverIds = syncedServerLeads.map((lead) => lead.id).toSet();
    final localIdsToDelete = _cache.values
        .where((lead) =>
            lead.promoterId == promoterId &&
            lead.isSynced &&
            !serverIds.contains(lead.id))
        .map((lead) => lead.id)
        .toList();
    await _deleteAll(localIdsToDelete);
    await _saveServerLeads(syncedServerLeads);
  }

  Future<void> reconcileAdminLeads(Iterable<CustomerLead> serverLeads) async {
    final syncedServerLeads = serverLeads
        .map((lead) => lead.copyWith(isSynced: true))
        .toList(growable: false);
    final serverIds = syncedServerLeads.map((lead) => lead.id).toSet();
    final localIdsToDelete = _cache.values
        .where((lead) => lead.isSynced && !serverIds.contains(lead.id))
        .map((lead) => lead.id)
        .toList();
    await _deleteAll(localIdsToDelete);
    await _saveServerLeads(syncedServerLeads);
  }

  CustomerLead? find(String id) => _cache[id];

  Future<void> softDelete(String id) async {
    final lead = find(id);
    if (lead == null) return;
    await save(lead.copyWith(deletedAt: DateTime.now(), isSynced: false));
  }

  Future<void> softDeleteMany(Iterable<String> ids) async {
    final deletedAt = DateTime.now();
    final updates = ids
        .map(find)
        .whereType<CustomerLead>()
        .map((lead) => lead.copyWith(deletedAt: deletedAt, isSynced: false));
    await _saveAll(updates);
  }

  /// Moves purchased enquiries to the recycle bin after their retention
  /// period. They remain recoverable until an owner permanently deletes them.
  Future<List<String>> recycleExpiredPurchases({DateTime? now}) async {
    final recycledAt = now ?? DateTime.now();
    final expired = _cache.values
        .where((lead) => shouldRecyclePurchased(lead, recycledAt))
        .toList(growable: false);
    if (expired.isEmpty) return const [];

    await _saveAll(expired.map((lead) => lead.copyWith(
          deletedAt: recycledAt,
          isSynced: false,
        )));
    return expired.map((lead) => lead.id).toList(growable: false);
  }

  Future<void> restore(String id) async {
    final lead = find(id);
    if (lead == null) return;
    await save(restoredLead(lead));
  }

  Future<void> permanentlyDelete(String id) async {
    await permanentlyDeleteMany([id]);
  }

  Future<void> permanentlyDeleteMany(Iterable<String> ids) async {
    await _deleteAll(ids);
  }

  List<CustomerLead> activeLeads() {
    return _cache.values.where((lead) => lead.deletedAt == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<CustomerLead> recycleBin() {
    return _cache.values.where((lead) => lead.deletedAt != null).toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
  }

  Future<void> _saveAll(Iterable<CustomerLead> leads) async {
    final updates = <String, CustomerLead>{
      for (final lead in leads) lead.id: lead,
    };
    if (updates.isEmpty) return;
    await _box.putAll({
      for (final entry in updates.entries)
        entry.key: jsonEncode(_toMap(entry.value)),
    });
    _cache.addAll(updates);
  }

  Future<void> _saveServerLeads(Iterable<CustomerLead> leads) async {
    await _saveAll(leads.where((lead) {
      final local = find(lead.id);
      return local == null || local.isSynced;
    }));
  }

  Future<void> _deleteAll(Iterable<String> ids) async {
    final idsToDelete = ids.toList(growable: false);
    if (idsToDelete.isEmpty) return;
    await _box.deleteAll(idsToDelete);
    for (final id in idsToDelete) {
      _cache.remove(id);
    }
  }

  CustomerLead _decode(String value) =>
      _fromMap(jsonDecode(value) as Map<String, dynamic>);

  Map<String, dynamic> _toMap(CustomerLead lead) => {
        'id': lead.id,
        'name': lead.name,
        'phone': lead.phone,
        'shopName': lead.shopName,
        'promoterName': lead.promoterName,
        'shopId': lead.shopId,
        'promoterId': lead.promoterId,
        'createdAt': lead.createdAt.toIso8601String(),
        'followUp1': lead.followUp1,
        'followUp1At': lead.followUp1At?.toIso8601String(),
        'followUp2': lead.followUp2,
        'followUp2At': lead.followUp2At?.toIso8601String(),
        'followUp3': lead.followUp3,
        'additionalFollowUps':
            lead.additionalFollowUps.map((entry) => entry.toMap()).toList(),
        'outcome': lead.outcome.name,
        'completedAt': lead.completedAt?.toUtc().toIso8601String(),
        'followUp3At': lead.followUp3At?.toIso8601String(),
        'isSynced': lead.isSynced,
        'deletedAt': lead.deletedAt?.toIso8601String(),
      };

  CustomerLead _fromMap(Map<String, dynamic> map) => CustomerLead(
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String,
        shopName: map['shopName'] as String,
        promoterName: map['promoterName'] as String,
        shopId: map['shopId'] as String? ?? '',
        promoterId: map['promoterId'] as String? ?? '',
        createdAt: DateTime.parse(map['createdAt'] as String),
        followUp1: map['followUp1'] as String?,
        followUp1At: _optionalDateTime(map['followUp1At']),
        followUp2: map['followUp2'] as String?,
        followUp2At: _optionalDateTime(map['followUp2At']),
        followUp3: map['followUp3'] as String?,
        followUp3At: _optionalDateTime(map['followUp3At']),
        additionalFollowUps: (map['additionalFollowUps'] as List? ?? [])
            .map((entry) =>
                FollowUpEntry.fromMap(Map<String, dynamic>.from(entry as Map)))
            .toList(),
        outcome: EnquiryOutcome.values.firstWhere(
            (value) => value.name == map['outcome'],
            orElse: () => EnquiryOutcome.active),
        completedAt: DateTime.tryParse(map['completedAt'] as String? ?? ''),
        isSynced: map['isSynced'] as bool? ?? false,
        deletedAt: map['deletedAt'] == null
            ? null
            : DateTime.parse(map['deletedAt'] as String),
      );

  DateTime? _optionalDateTime(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }
}
