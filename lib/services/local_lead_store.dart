import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/customer_lead.dart';

class LocalLeadStore {
  static const _boxName = 'leadloop_leads';
  static const _keyName = 'leadloop_hive_key';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Map<String, CustomerLead> _cache = {};
  late Box<String> _box;

  Future<void> open() async {
    await Hive.initFlutter();
    var key = await _secureStorage.read(key: _keyName);
    if (key == null) {
      key = base64UrlEncode(Hive.generateSecureKey());
      await _secureStorage.write(key: _keyName, value: key);
    }
    _box = await Hive.openBox<String>(
      _boxName,
      encryptionCipher: HiveAesCipher(base64Url.decode(key)),
    );
    _cache
      ..clear()
      ..addEntries(
          _box.values.map(_decode).map((lead) => MapEntry(lead.id, lead)));
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
    await save(lead.copyWith(isSynced: true));
  }

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
    await _saveAll(syncedServerLeads);
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
    await _saveAll(syncedServerLeads);
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

  Future<void> restore(String id) async {
    final lead = find(id);
    if (lead == null) return;
    await save(lead.copyWith(clearDeletedAt: true, isSynced: false));
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
