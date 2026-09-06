import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/customer_lead.dart';

class LocalLeadStore {
  static const _boxName = 'leadloop_leads';
  static const _keyName = 'leadloop_hive_key';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
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
  }

  Future<void> save(CustomerLead lead) async {
    await _box.put(lead.id, jsonEncode(_toMap(lead)));
  }

  /// Returns local changes that still need to be sent to Firebase.
  List<CustomerLead> pendingLeads() {
    return _box.values
        .map((value) => _fromMap(jsonDecode(value) as Map<String, dynamic>))
        .where((lead) => !lead.isSynced)
        .toList();
  }

  Future<void> markSynced(String id) async {
    final lead = find(id);
    if (lead == null || lead.isSynced) return;
    await save(lead.copyWith(isSynced: true));
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
    final serverIds = serverLeads.map((lead) => lead.id).toSet();
    final localLeads = _box.values
        .map((value) => _fromMap(jsonDecode(value) as Map<String, dynamic>))
        .where((lead) =>
            lead.promoterId == promoterId &&
            lead.isSynced &&
            !serverIds.contains(lead.id))
        .toList();
    for (final lead in localLeads) {
      await _box.delete(lead.id);
    }
    for (final lead in serverLeads) {
      await saveFromServer(lead);
    }
  }

  Future<void> reconcileAdminLeads(Iterable<CustomerLead> serverLeads) async {
    final serverIds = serverLeads.map((lead) => lead.id).toSet();
    final localLeads = _box.values
        .map((value) => _fromMap(jsonDecode(value) as Map<String, dynamic>))
        .where((lead) => lead.isSynced && !serverIds.contains(lead.id))
        .toList();
    for (final lead in localLeads) {
      await _box.delete(lead.id);
    }
    for (final lead in serverLeads) {
      await saveFromServer(lead);
    }
  }

  CustomerLead? find(String id) {
    final value = _box.get(id);
    if (value == null) return null;
    return _fromMap(jsonDecode(value) as Map<String, dynamic>);
  }

  Future<void> softDelete(String id) async {
    final lead = find(id);
    if (lead == null) return;
    await save(lead.copyWith(deletedAt: DateTime.now(), isSynced: false));
  }

  Future<void> restore(String id) async {
    final lead = find(id);
    if (lead == null) return;
    await save(lead.copyWith(clearDeletedAt: true, isSynced: false));
  }

  Future<void> permanentlyDelete(String id) async {
    await _box.delete(id);
  }

  List<CustomerLead> activeLeads() {
    return _box.values
        .map((value) => _fromMap(jsonDecode(value) as Map<String, dynamic>))
        .where((lead) => lead.deletedAt == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<CustomerLead> recycleBin() {
    return _box.values
        .map((value) => _fromMap(jsonDecode(value) as Map<String, dynamic>))
        .where((lead) => lead.deletedAt != null)
        .toList()
      ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
  }

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
        'followUp2': lead.followUp2,
        'followUp3': lead.followUp3,
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
        followUp2: map['followUp2'] as String?,
        followUp3: map['followUp3'] as String?,
        isSynced: map['isSynced'] as bool? ?? false,
        deletedAt: map['deletedAt'] == null
            ? null
            : DateTime.parse(map['deletedAt'] as String),
      );
}
