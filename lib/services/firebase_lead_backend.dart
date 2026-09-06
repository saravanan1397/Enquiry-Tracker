import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/customer_lead.dart';
import 'local_lead_store.dart';

class EnquiryTrackerPromoterProfile {
  const EnquiryTrackerPromoterProfile({
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

  bool get isConfigured => Firebase.apps.isNotEmpty;

  CollectionReference<Map<String, dynamic>> get _leads =>
      (_firestore ?? FirebaseFirestore.instance).collection('leads');

  Future<void> syncPromoter(
      LocalLeadStore localStore, String promoterId) async {
    if (!isConfigured) return;

    final pending = localStore
        .pendingLeads()
        .where((lead) => lead.promoterId == promoterId)
        .toList();
    for (final lead in pending) {
      await _leads.doc(lead.id).set(_toMap(lead));
    }
    await (_firestore ?? FirebaseFirestore.instance).waitForPendingWrites();
    for (final lead in pending) {
      await localStore.markSynced(lead.id);
    }

    final snapshot =
        await _leads.where('promoterId', isEqualTo: promoterId).get();
    final serverLeads = snapshot.docs.map(_fromDocument).toList();
    await localStore.reconcilePromoterLeads(promoterId, serverLeads);
  }

  Future<void> syncAdmin(LocalLeadStore localStore) async {
    if (!isConfigured) return;

    // Upload owner-side changes first, including recycle-bin tombstones.
    final pending = localStore.pendingLeads();
    for (final lead in pending) {
      await _leads.doc(lead.id).set(_toMap(lead));
    }
    await (_firestore ?? FirebaseFirestore.instance).waitForPendingWrites();
    for (final lead in pending) {
      await localStore.markSynced(lead.id);
    }

    final snapshot = await _leads.get();
    await localStore.reconcileAdminLeads(snapshot.docs.map(_fromDocument));
  }

  Future<List<EnquiryTrackerPromoterProfile>> listPromoters() async {
    if (!isConfigured) return const [];
    final snapshot = await (_firestore ?? FirebaseFirestore.instance)
        .collection('promoters')
        .get();
    final profiles = snapshot.docs.map((document) {
      final data = document.data();
      return EnquiryTrackerPromoterProfile(
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
    required EnquiryTrackerPromoterProfile promoter,
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

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> watchLeads({
    required LocalLeadStore localStore,
    required void Function() onChanged,
    String? promoterId,
  }) {
    final query = promoterId == null
        ? _leads
        : _leads.where('promoterId', isEqualTo: promoterId);
    return query.snapshots(includeMetadataChanges: true).listen((snapshot) {
      unawaited(
          _applyLeadSnapshot(snapshot, localStore, onChanged, promoterId));
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
        'createdAt': lead.createdAt.toIso8601String(),
        'followUp1': lead.followUp1,
        'followUp2': lead.followUp2,
        'followUp3': lead.followUp3,
        'isSynced': true,
        'deletedAt': lead.deletedAt?.toIso8601String(),
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
        createdAt: DateTime.parse(map['createdAt'] as String),
        followUp1: map['followUp1'] as String?,
        followUp2: map['followUp2'] as String?,
        followUp3: map['followUp3'] as String?,
        isSynced: true,
        deletedAt: map['deletedAt'] == null
            ? null
            : DateTime.parse(map['deletedAt'] as String),
      );

  CustomerLead _fromDocument(
          QueryDocumentSnapshot<Map<String, dynamic>> document) =>
      _fromMap(document.data());
}
