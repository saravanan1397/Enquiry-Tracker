import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/customer_lead.dart';
import 'follow_up_deadline_service.dart';
import 'local_lead_store.dart';
import 'recycle_retention_policy.dart';

class LeadloopPromoterProfile {
  const LeadloopPromoterProfile({
    required this.uid,
    required this.name,
    required this.mobile,
    required this.shopId,
    required this.shopName,
    required this.active,
    required this.status,
    this.deletedAt,
  });

  final String uid;
  final String name;
  final String mobile;
  final String shopId;
  final String shopName;
  final bool active;
  final String status;
  final DateTime? deletedAt;
}

/// Firebase transport for the offline-first local lead store.
///
/// Hive remains the source used by the screens. This service only uploads
/// pending local changes and, for an admin device, downloads the central list.
class FirebaseLeadBackend {
  FirebaseLeadBackend({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  })  : _firestore = firestore,
        _functions = functions;

  final FirebaseFirestore? _firestore;
  final FirebaseFunctions? _functions;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  static const _writeBatchSize = 240;
  Future<void> _snapshotQueue = Future.value();
  bool _retentionSweepComplete = false;

  bool get isConfigured => Firebase.apps.isNotEmpty;

  CollectionReference<Map<String, dynamic>> get _leads =>
      _database.collection('leads');
  CollectionReference<Map<String, dynamic>> get _assignmentEvents =>
      _database.collection('leadAssignmentEvents');
  CollectionReference<Map<String, dynamic>> get _deletionEvents =>
      _database.collection('leadDeletionEvents');

  FirebaseFirestore get _database => _firestore ?? FirebaseFirestore.instance;
  FirebaseFunctions get _cloudFunctions =>
      _functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  Future<void> syncPromoter(
      LocalLeadStore localStore, String promoterId) async {
    if (!isConfigured) return;

    final pending = localStore
        .pendingLeads()
        .where((lead) => lead.promoterId == promoterId)
        .toList();
    await _uploadLeads(pending);
    await localStore.markManySynced(pending.map((lead) => lead.id));
  }

  Future<void> syncAdmin(LocalLeadStore localStore) async {
    if (!isConfigured) return;

    // Upload owner-side changes first, including recycle-bin tombstones.
    final pending = localStore.pendingLeads();
    await _uploadLeads(pending);
    await localStore.markManySynced(pending.map((lead) => lead.id));

    if (!_retentionSweepComplete) {
      await _purgeExpiredRecycleBin(localStore);
      _retentionSweepComplete = true;
    }
  }

  Future<void> _recycleExpiredPurchases(LocalLeadStore localStore) async {
    final recycledIds = await localStore.recycleExpiredPurchases();
    if (recycledIds.isEmpty) return;

    final recycledIdSet = recycledIds.toSet();
    final recycled = localStore
        .pendingLeads()
        .where((lead) => recycledIdSet.contains(lead.id))
        .toList(growable: false);
    await _uploadLeads(recycled);
    await localStore.markManySynced(recycledIds);
  }

  Future<void> _purgeExpiredRecycleBin(LocalLeadStore localStore) async {
    final cutoff = Timestamp.fromDate(recycleBinCutoff(DateTime.now()).toUtc());
    final expiredLeads =
        await _leads.where('deletedAt', isLessThanOrEqualTo: cutoff).get();
    final leadIds = expiredLeads.docs
        .map((document) => document.id)
        .toList(growable: false);
    await deleteLeads(leadIds);
    await localStore.permanentlyDeleteMany(leadIds);

    final expiredPromoters = await _database
        .collection('promoters')
        .where('deletedAt', isLessThanOrEqualTo: cutoff)
        .get();
    for (final promoter in expiredPromoters.docs) {
      await _cloudFunctions
          .httpsCallable(
        'deletePromoterPermanently',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      )
          .call({'uid': promoter.id, 'confirmation': 'DELETE'});
    }
  }

  Future<List<LeadloopPromoterProfile>> listPromoters() async {
    if (!isConfigured) return const [];
    final snapshot = await (_firestore ?? FirebaseFirestore.instance)
        .collection('promoters')
        .get();
    final profiles = snapshot.docs
        .map((document) {
          final data = document.data();
          return LeadloopPromoterProfile(
            uid: document.id,
            name: data['name'] as String? ?? 'Unnamed promoter',
            mobile: data['mobile'] as String? ?? '',
            shopId: data['shopId'] as String? ?? '',
            shopName: data['shopName'] as String? ?? '',
            active: data['active'] as bool? ?? false,
            status: data['status'] as String? ?? 'pending',
            deletedAt: _dateTime(data['deletedAt']),
          );
        })
        .where((profile) =>
            profile.deletedAt == null &&
            profile.status != 'recycled' &&
            profile.status != 'deleting')
        .toList();
    profiles
        .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return profiles;
  }

  Stream<List<LeadloopPromoterProfile>> watchDeletedPromoters() {
    if (!isConfigured) return Stream.value(const []);
    return _database.collection('promoters').snapshots().map((snapshot) {
      final result = snapshot.docs
          .map((document) {
            final data = document.data();
            return LeadloopPromoterProfile(
              uid: document.id,
              name: data['name'] as String? ?? 'Unnamed promoter',
              mobile: data['mobile'] as String? ?? '',
              shopId: data['shopId'] as String? ?? '',
              shopName: data['shopName'] as String? ?? '',
              active: data['active'] as bool? ?? false,
              status: data['status'] as String? ?? 'pending',
              deletedAt: _dateTime(data['deletedAt']),
            );
          })
          .where((profile) =>
              profile.deletedAt != null ||
              profile.status == 'recycled' ||
              profile.status == 'deleting')
          .toList();
      result
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return result;
    });
  }

  Future<void> recyclePromoter(LeadloopPromoterProfile promoter) async {
    await _database.collection('promoters').doc(promoter.uid).update({
      'previousActive': promoter.active,
      'previousStatus': promoter.status,
      'active': false,
      'status': 'recycled',
      'deletedAt': FieldValue.serverTimestamp(),
    });
    await _database.waitForPendingWrites();
  }

  Future<void> restorePromoter(String uid) async {
    final reference = _database.collection('promoters').doc(uid);
    await _database.runTransaction((transaction) async {
      final document = await transaction.get(reference);
      if (!document.exists) return;
      final data = document.data()!;
      transaction.update(reference, {
        'active': data['previousActive'] as bool? ?? true,
        'status': data['previousStatus'] as String? ?? 'approved',
        'deletedAt': null,
        'previousActive': FieldValue.delete(),
        'previousStatus': FieldValue.delete(),
        'restoredAt': FieldValue.serverTimestamp(),
      });
    });
    await _database.waitForPendingWrites();
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
    final batch = _database.batch();
    batch.update(_leads.doc(lead.id), {
      'promoterId': promoter.uid,
      'promoterName': promoter.name,
      'shopId': promoter.shopId,
      'shopName': promoter.shopName,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.delete(_assignmentEvents.doc('${promoter.uid}_${lead.id}'));
    batch.set(_assignmentEvents.doc('${lead.promoterId}_${lead.id}'), {
      'leadId': lead.id,
      'previousPromoterId': lead.promoterId,
      'nextPromoterId': promoter.uid,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await (_firestore ?? FirebaseFirestore.instance).waitForPendingWrites();
  }

  Future<void> deleteLead(String leadId) async {
    await deleteLeads([leadId]);
  }

  /// Permanently deletes records in bounded batches. Firestore permits up to
  /// 500 writes per batch; keeping this below that limit leaves headroom for
  /// future server-side bookkeeping.
  Future<void> deleteLeads(Iterable<String> leadIds) async {
    if (!isConfigured) return;
    final ids = leadIds.toSet().toList(growable: false);
    for (var offset = 0; offset < ids.length; offset += _writeBatchSize) {
      final candidateEnd = offset + _writeBatchSize;
      final end = candidateEnd < ids.length ? candidateEnd : ids.length;
      final batch = _database.batch();
      for (final id in ids.sublist(offset, end)) {
        batch.delete(_leads.doc(id));
        batch.set(_deletionEvents.doc(id), {
          'leadId': id,
          'deletedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await _database.waitForPendingWrites();
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

  Future<List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>>
      watchLeads({
    required LocalLeadStore localStore,
    required void Function() onChanged,
    required String userId,
    String? promoterId,
  }) async {
    final scope = promoterId ?? 'admin-$userId';
    final cursorKey = 'leadloop_lead_cursor_$scope';
    final storedCursor = await _readCursor(cursorKey);
    Query<Map<String, dynamic>> query = promoterId == null
        ? _leads
        : _leads.where('promoterId', isEqualTo: promoterId);
    var canResume = storedCursor != null &&
        localStore.hasSyncedLeads(promoterId: promoterId);
    if (canResume) {
      try {
        final serverCount = (await query.count().get()).count;
        canResume =
            serverCount == localStore.syncedLeadCount(promoterId: promoterId);
      } catch (_) {
        canResume = false;
      }
    }
    final incremental = canResume;
    if (canResume) {
      query = query.where(
        'updatedAt',
        isGreaterThanOrEqualTo: Timestamp.fromDate(storedCursor!.toUtc()),
      );
    }

    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    subscriptions.add(query.snapshots().listen((snapshot) {
      _snapshotQueue = _snapshotQueue
          .then((_) => _applyLeadSnapshot(
                snapshot,
                localStore,
                onChanged,
                promoterId,
                reconcile: !incremental,
              ))
          .then((_) => _storeLatestCursor(
                cursorKey,
                snapshot,
                allowEmptyWatermark: !incremental,
              ))
          .catchError((Object error, StackTrace stackTrace) {
        debugPrint('Lead snapshot processing failed: $error');
      });
    }));

    if (promoterId != null) {
      final eventCursorKey = 'leadloop_assignment_cursor_$promoterId';
      final eventCursor = await _readCursor(eventCursorKey);
      Query<Map<String, dynamic>> events = _assignmentEvents.where(
        'previousPromoterId',
        isEqualTo: promoterId,
      );
      if (eventCursor != null) {
        events = events.where(
          'updatedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(eventCursor.toUtc()),
        );
      }
      subscriptions.add(events.snapshots().listen((snapshot) {
        _snapshotQueue = _snapshotQueue.then((_) async {
          for (final event in snapshot.docs) {
            final leadId = event.data()['leadId'] as String?;
            if (leadId != null) {
              await localStore.removeSyncedLead(leadId);
            }
          }
          await _storeLatestCursor(
            eventCursorKey,
            snapshot,
            allowEmptyWatermark: true,
          );
          onChanged();
        }).catchError((Object error, StackTrace stackTrace) {
          debugPrint('Lead assignment processing failed: $error');
        });
      }));
    }

    final deletionCursorKey = 'leadloop_deletion_cursor_$scope';
    final deletionCursor = await _readCursor(deletionCursorKey);
    final deletionStart = deletionCursor ??
        DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    final deletions = _deletionEvents.where(
      'deletedAt',
      isGreaterThanOrEqualTo: Timestamp.fromDate(deletionStart),
    );
    subscriptions.add(deletions.snapshots().listen((snapshot) {
      _snapshotQueue = _snapshotQueue.then((_) async {
        for (final event in snapshot.docs) {
          final leadId = event.data()['leadId'] as String?;
          if (leadId != null) await localStore.removeSyncedLead(leadId);
        }
        await _storeLatestCursor(
          deletionCursorKey,
          snapshot,
          allowEmptyWatermark: true,
          timestampField: 'deletedAt',
        );
        onChanged();
      }).catchError((Object error, StackTrace stackTrace) {
        debugPrint('Lead deletion processing failed: $error');
      });
    }));
    return subscriptions;
  }

  Future<void> _applyLeadSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot,
      LocalLeadStore localStore, void Function() onChanged, String? promoterId,
      {required bool reconcile}) async {
    final serverLeads = snapshot.docs
        .where((document) => !document.metadata.hasPendingWrites)
        .map(_fromDocument)
        .toList();
    if (reconcile && !snapshot.metadata.isFromCache) {
      if (promoterId == null) {
        await localStore.reconcileAdminLeads(serverLeads);
      } else {
        await localStore.reconcilePromoterLeads(promoterId, serverLeads);
      }
    } else {
      for (final lead in serverLeads) {
        await localStore.saveFromServer(lead);
      }
    }
    await _recycleExpiredPurchases(localStore);
    onChanged();
  }

  Future<DateTime?> _readCursor(String key) async {
    try {
      final value = await _storage.read(key: key);
      return value == null ? null : DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }

  Future<void> _storeLatestCursor(
    String key,
    QuerySnapshot<Map<String, dynamic>> snapshot, {
    bool allowEmptyWatermark = false,
    String timestampField = 'updatedAt',
  }) async {
    if (snapshot.metadata.isFromCache) return;
    DateTime? latest;
    for (final document in snapshot.docs) {
      final updatedAt = _dateTime(document.data()[timestampField]);
      if (updatedAt != null && (latest == null || updatedAt.isAfter(latest))) {
        latest = updatedAt;
      }
    }
    if (latest == null && allowEmptyWatermark) {
      latest = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
    }
    if (latest == null) return;
    try {
      await _storage.write(key: key, value: latest.toUtc().toIso8601String());
    } catch (_) {
      // A missing cursor only causes a safe full refresh next time.
    }
  }

  Map<String, dynamic> _toMap(CustomerLead lead) {
    final nextFollowUpAt = FollowUpDeadlineService.nextDueAt(lead);
    return {
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
      'additionalFollowUps':
          lead.additionalFollowUps.map((entry) => entry.toMap()).toList(),
      'outcome': lead.outcome.name,
      'completedAt': lead.completedAt?.toUtc().toIso8601String(),
      'followUp3At': _toTimestamp(lead.followUp3At),
      'isSynced': true,
      'deletedAt': _toTimestamp(lead.deletedAt),
      'updatedAt': FieldValue.serverTimestamp(),
      'nextFollowUpAt': _toTimestamp(nextFollowUpAt),
    };
  }

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
        additionalFollowUps: (map['additionalFollowUps'] as List? ?? [])
            .map((entry) =>
                FollowUpEntry.fromMap(Map<String, dynamic>.from(entry as Map)))
            .toList(),
        outcome: EnquiryOutcome.values.firstWhere(
            (value) => value.name == map['outcome'],
            orElse: () => EnquiryOutcome.active),
        completedAt: _dateTime(map['completedAt']),
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
