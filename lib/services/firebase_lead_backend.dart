import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../models/customer_lead.dart';
import 'local_lead_store.dart';

class LeadloopPromoterProfile {
  const LeadloopPromoterProfile({
    required this.uid,
    required this.name,
    required this.mobile,
    required this.shopId,
    required this.shopName,
    required this.active,
    required this.status,
  });

  final String uid;
  final String name;
  final String mobile;
  final String shopId;
  final String shopName;
  final bool active;
  final String status;
}

/// Firebase transport for the offline-first local lead store.
///
/// Hive remains the source used by the screens. This service only uploads
/// pending local changes and, for an admin device, downloads the central list.
class FirebaseLeadBackend {
  FirebaseLeadBackend({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  static const _writeBatchSize = 400;
  Future<void> _snapshotQueue = Future.value();

  bool get isConfigured => Firebase.apps.isNotEmpty;

  CollectionReference<Map<String, dynamic>> get _leads =>
      _database.collection('leads');

  FirebaseFirestore get _database => _firestore ?? FirebaseFirestore.instance;

  Future<void> syncPromoter(
      LocalLeadStore localStore, String promoterId) async {
    if (!isConfigured) return;

    final pending = localStore
        .pendingLeads()
        .where((lead) => lead.promoterId == promoterId)
        .toList();
    await _uploadLeads(pending);
    await localStore.markManySynced(pending.map((lead) => lead.id));

    final snapshot =
        await _leads.where('promoterId', isEqualTo: promoterId).get();
    final serverLeads = snapshot.docs.map(_fromDocument).toList();
    await localStore.reconcilePromoterLeads(promoterId, serverLeads);
  }

  Future<void> syncAdmin(LocalLeadStore localStore) async {
    if (!isConfigured) return;

    // Upload owner-side changes first, including recycle-bin tombstones.
    final pending = localStore.pendingLeads();
    await _uploadLeads(pending);
    await localStore.markManySynced(pending.map((lead) => lead.id));

    final snapshot = await _leads.get();
    await localStore.reconcileAdminLeads(snapshot.docs.map(_fromDocument));
  }

  Future<List<LeadloopPromoterProfile>> listPromoters() async {
    if (!isConfigured) return const [];
    final snapshot = await (_firestore ?? FirebaseFirestore.instance)
        .collection('promoters')
        .get();
    final profiles = snapshot.docs.map((document) {
      final data = document.data();
      return LeadloopPromoterProfile(
        uid: document.id,
        name: data['name'] as String? ?? 'Unnamed promoter',
        mobile: data['mobile'] as String? ?? '',
        shopId: data['shopId'] as String? ?? '',
        shopName: data['shopName'] as String? ?? '',
        active: data['active'] as bool? ?? false,
        status: data['status'] as String? ?? 'pending',
      );
    }).toList();
    profiles
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return profiles;
  }

  Future<void> updatePromoter({
    required String uid,
    required String shopId,
    required String shopName,
    required bool active,
    required String status,
  }) async {
    if (!isConfigured) return;
    await (_firestore ?? FirebaseFirestore.instance)
        .collection('promoters')
        .doc(uid)
        .update({
      'shopId': shopId,
      'shopName': shopName,
      'active': active,
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> transferLead({
    required CustomerLead lead,
    required LeadloopPromoterProfile promoter,
  }) async {
    if (!isConfigured) return;
    await _leads.doc(lead.id).update({
      'promoterId': promoter.uid,
      'promoterName': promoter.name,
      'shopId': promoter.shopId,
      'shopName': promoter.shopName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await (_firestore ?? FirebaseFirestore.instance).waitForPendingWrites();
  }

  Future<void> deleteLead(String leadId) async {
    if (!isConfigured) return;
    await _leads.doc(leadId).delete();
    await (_firestore ?? FirebaseFirestore.instance).waitForPendingWrites();
  }

  Future<void> _uploadLeads(List<CustomerLead> leads) async {
    if (leads.isEmpty) return;
    for (var offset = 0; offset < leads.length; offset += _writeBatchSize) {
      final candidateEnd = offset + _writeBatchSize;
      final end = candidateEnd < leads.length ? candidateEnd : leads.length;
      final batch = _database.batch();
      for (final lead in leads.sublist(offset, end)) {
        batch.set(_leads.doc(lead.id), _toMap(lead));
      }
      await batch.commit();
    }
    await _database.waitForPendingWrites();
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchLeads({
    required LocalLeadStore localStore,
    required void Function() onChanged,
    String? promoterId,
  }) {
    final query = promoterId == null
        ? _leads
        : _leads.where('promoterId', isEqualTo: promoterId);
    return query.snapshots(includeMetadataChanges: true).listen((snapshot) {
      _snapshotQueue = _snapshotQueue
          .then((_) =>
              _applyLeadSnapshot(snapshot, localStore, onChanged, promoterId))
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('Lead snapshot processing failed: $error');
      });
    });
  }

  Future<void> _applyLeadSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
    LocalLeadStore localStore,
    void Function() onChanged,
    String? promoterId,
  ) async {
    final serverLeads = snapshot.docs
        .where((document) => !document.metadata.hasPendingWrites)
        .map(_fromDocument)
        .toList();
    if (promoterId == null) {
      await localStore.reconcileAdminLeads(serverLeads);
    } else {
      await localStore.reconcilePromoterLeads(promoterId, serverLeads);
    }
    onChanged();
  }

  Map<String, dynamic> _toMap(CustomerLead lead) => {
        'id': lead.id,
        'name': lead.name,
        'phone': lead.phone,
        'shopName': lead.shopName,
        'promoterName': lead.promoterName,
        'shopId': lead.shopId,
        'promoterId': lead.promoterId,
        'createdAt': Timestamp.fromDate(lead.createdAt.toUtc()),
        'followUp1': lead.followUp1,
        'followUp1At': _toTimestamp(lead.followUp1At),
        'followUp2': lead.followUp2,
        'followUp2At': _toTimestamp(lead.followUp2At),
        'followUp3': lead.followUp3,
        'followUp3At': _toTimestamp(lead.followUp3At),
        'isSynced': true,
        'deletedAt': _toTimestamp(lead.deletedAt),
        'updatedAt': FieldValue.serverTimestamp(),
      };

  CustomerLead _fromMap(Map<String, dynamic> map) => CustomerLead(
        id: map['id'] as String,
        name: map['name'] as String,
        phone: map['phone'] as String,
        shopName: map['shopName'] as String,
        promoterName: map['promoterName'] as String,
        shopId: map['shopId'] as String? ?? '',
        promoterId: map['promoterId'] as String? ?? '',
        createdAt: _dateTime(map['createdAt']) ?? DateTime.now(),
        followUp1: map['followUp1'] as String?,
        followUp1At: _dateTime(map['followUp1At']),
        followUp2: map['followUp2'] as String?,
        followUp2At: _dateTime(map['followUp2At']),
        followUp3: map['followUp3'] as String?,
        followUp3At: _dateTime(map['followUp3At']),
        isSynced: true,
        deletedAt: _dateTime(map['deletedAt']),
      );

  Timestamp? _toTimestamp(DateTime? value) =>
      value == null ? null : Timestamp.fromDate(value.toUtc());

  DateTime? _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  CustomerLead _fromDocument(
          QueryDocumentSnapshot<Map<String, dynamic>> document) =>
      _fromMap(document.data());
}
