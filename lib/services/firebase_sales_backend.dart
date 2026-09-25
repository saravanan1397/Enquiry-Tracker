import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/sales_record.dart';

class SalesBackupStatus {
  const SalesBackupStatus({
    required this.status,
    this.requestedAt,
    this.startedAt,
    this.completedAt,
    this.assetNames = const [],
    this.error,
  });

  final String status;
  final DateTime? requestedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<String> assetNames;
  final String? error;

  bool get isActive => status == 'pending' || status == 'processing';
}

class FirebaseSalesBackend {
  FirebaseSalesBackend({FirebaseFirestore? firestore}) : _firestore = firestore;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _database => _firestore ?? FirebaseFirestore.instance;
  bool get isConfigured => Firebase.apps.isNotEmpty || _firestore != null;

  CollectionReference<Map<String, dynamic>> get _people =>
      _database.collection('salesPersons');
  CollectionReference<Map<String, dynamic>> get _nameReservations =>
      _database.collection('salesPersonNames');
  CollectionReference<Map<String, dynamic>> get _entries =>
      _database.collection('salesEntries');
  CollectionReference<Map<String, dynamic>> get _totalSnapshots =>
      _database.collection('salesPersonTotalSnapshots');
  CollectionReference<Map<String, dynamic>> get _audit =>
      _database.collection('salesEntryAudit');
  CollectionReference<Map<String, dynamic>> get _months =>
      _database.collection('salesMonths');
  DocumentReference<Map<String, dynamic>> get _backupRequest =>
      _database.collection('salesBackupRequests').doc('current');

  Stream<List<SalesPerson>> watchPeople() {
    if (!isConfigured) return Stream.value(const []);
    return _people.snapshots().map((snapshot) {
      final result = snapshot.docs
          .map(_personFromDocument)
          .where((person) => person.active && person.deletedAt == null)
          .toList();
      result.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return result;
    });
  }

  Stream<List<SalesPerson>> watchDeletedPeople() {
    if (!isConfigured) return Stream.value(const []);
    return _people.snapshots().map((snapshot) {
      final result = snapshot.docs
          .map(_personFromDocument)
          .where((person) => !person.active || person.deletedAt != null)
          .toList();
      result
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return result;
    });
  }

  Stream<List<SalesRecord>> watchMonth(String monthKey) {
    if (!isConfigured) return Stream.value(const []);
    return _entries.where('monthKey', isEqualTo: monthKey).snapshots().map((
      snapshot,
    ) {
      final result = snapshot.docs
          .map(_recordFromDocument)
          .where((record) => record.deletedAt == null)
          .toList();
      result.sort((a, b) {
        final date = a.salesDateKey.compareTo(b.salesDateKey);
        return date != 0
            ? date
            : a.personName.toLowerCase().compareTo(b.personName.toLowerCase());
      });
      return result;
    });
  }

  Stream<List<SalesPersonTotalSnapshot>> watchPreservedTotals(
    String monthKey,
  ) {
    if (!isConfigured) return Stream.value(const []);
    return _totalSnapshots
        .where('monthKey', isEqualTo: monthKey)
        .snapshots()
        .map((snapshot) {
      final result = snapshot.docs.map(_totalSnapshotFromDocument).toList();
      result.sort(
        (a, b) => a.personName.toLowerCase().compareTo(
              b.personName.toLowerCase(),
            ),
      );
      return result;
    });
  }

  Stream<SalesMonthState> watchMonthState(String monthKey) {
    if (!isConfigured) return Stream.value(SalesMonthState(monthKey: monthKey));
    return _months.doc(monthKey).snapshots().map((document) {
      final data = document.data();
      return SalesMonthState(
        monthKey: monthKey,
        finalized: data?['finalized'] as bool? ?? false,
        finalizedAt: _dateTime(data?['finalizedAt']),
        finalizedByUid: data?['finalizedByUid'] as String?,
        deletedAt: _dateTime(data?['deletedAt']),
      );
    });
  }

  Stream<List<SalesRecord>> watchDeletedEntries() {
    if (!isConfigured) return Stream.value(const []);
    return _entries.snapshots().map((snapshot) {
      final result = snapshot.docs
          .map(_recordFromDocument)
          .where((record) =>
              record.deletedAt != null && !record.deletedAsPartOfMonth)
          .toList();
      result.sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
      return result;
    });
  }

  Stream<List<SalesMonthState>> watchDeletedMonths() {
    if (!isConfigured) return Stream.value(const []);
    return _months.snapshots().map((snapshot) {
      final result = snapshot.docs
          .map((document) {
            final data = document.data();
            return SalesMonthState(
              monthKey: document.id,
              finalized: data['finalized'] as bool? ?? false,
              finalizedAt: _dateTime(data['finalizedAt']),
              finalizedByUid: data['finalizedByUid'] as String?,
              deletedAt: _dateTime(data['deletedAt']),
            );
          })
          .where((month) => month.deletedAt != null)
          .toList();
      result.sort((a, b) => b.monthKey.compareTo(a.monthKey));
      return result;
    });
  }

  Stream<SalesBackupStatus?> watchBackupStatus() {
    if (!isConfigured) return Stream.value(null);
    return _backupRequest.snapshots().map((document) {
      final data = document.data();
      if (!document.exists || data == null) return null;
      return SalesBackupStatus(
        status: data['status'] as String? ?? 'unknown',
        requestedAt: _dateTime(data['requestedAt']),
        startedAt: _dateTime(data['startedAt']),
        completedAt: _dateTime(data['completedAt']),
        assetNames: (data['assetNames'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(growable: false),
        error: data['error'] as String?,
      );
    });
  }

  Future<SalesPerson> ensurePerson(String requestedName) async {
    final cleanName = requestedName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.isEmpty) {
      throw const FormatException('Enter the salesperson name.');
    }
    final normalized = cleanName.toLowerCase();
    final reservationId = sha256.convert(utf8.encode(normalized)).toString();
    final reservation = _nameReservations.doc(reservationId);

    return _database.runTransaction((transaction) async {
      final existingReservation = await transaction.get(reservation);
      if (existingReservation.exists) {
        final personId = existingReservation.data()?['personId'] as String?;
        if (personId != null) {
          final existingPerson = await transaction.get(_people.doc(personId));
          if (existingPerson.exists) {
            if (existingPerson.data()?['active'] == false ||
                existingPerson.data()?['deletedAt'] != null) {
              throw StateError(
                'This salesperson is in the recycle bin. Restore the profile there.',
              );
            }
            final restored = _personFromSnapshot(existingPerson);
            return SalesPerson(
              id: restored.id,
              name: restored.name,
              normalizedName: restored.normalizedName,
              active: true,
              createdAt: restored.createdAt,
            );
          }
        }
      }

      final person = _people.doc();
      transaction.set(person, {
        'name': cleanName,
        'normalizedName': normalized,
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(reservation, {
        'personId': person.id,
        'normalizedName': normalized,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return SalesPerson(
        id: person.id,
        name: cleanName,
        normalizedName: normalized,
      );
    });
  }

  Future<void> renamePerson({
    required SalesPerson person,
    required String requestedName,
  }) async {
    final cleanName = requestedName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleanName.isEmpty) {
      throw const FormatException('Enter the salesperson name.');
    }
    final normalized = cleanName.toLowerCase();
    final newReservationId = sha256.convert(utf8.encode(normalized)).toString();

    await _database.runTransaction((transaction) async {
      final personReference = _people.doc(person.id);
      final current = await transaction.get(personReference);
      if (!current.exists || current.data()?['active'] == false) {
        throw StateError('This salesperson is no longer active.');
      }
      final oldNormalized =
          current.data()?['normalizedName'] as String? ?? person.normalizedName;
      final oldReservationId =
          sha256.convert(utf8.encode(oldNormalized)).toString();
      final newReservation = _nameReservations.doc(newReservationId);
      final reserved = await transaction.get(newReservation);
      final reservedPersonId = reserved.data()?['personId'] as String?;
      if (reserved.exists && reservedPersonId != person.id) {
        throw StateError('A salesperson with this name already exists.');
      }

      transaction.update(personReference, {
        'name': cleanName,
        'normalizedName': normalized,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(newReservation, {
        'personId': person.id,
        'normalizedName': normalized,
        'createdAt':
            reserved.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (oldReservationId != newReservationId) {
        transaction.delete(_nameReservations.doc(oldReservationId));
      }
    });

    final entries =
        await _entries.where('personId', isEqualTo: person.id).get();
    for (var offset = 0; offset < entries.docs.length; offset += 400) {
      final end = offset + 400 < entries.docs.length
          ? offset + 400
          : entries.docs.length;
      final batch = _database.batch();
      for (final document in entries.docs.sublist(offset, end)) {
        batch.update(document.reference, {
          'personName': cleanName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    final totals =
        await _totalSnapshots.where('personId', isEqualTo: person.id).get();
    for (var offset = 0; offset < totals.docs.length; offset += 400) {
      final end =
          offset + 400 < totals.docs.length ? offset + 400 : totals.docs.length;
      final batch = _database.batch();
      for (final document in totals.docs.sublist(offset, end)) {
        batch.update(document.reference, {
          'personName': cleanName,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }
    await _database.waitForPendingWrites();
  }

  Future<void> recyclePerson({
    required SalesPerson person,
    required String ownerUid,
    bool recycleIndividualSales = false,
  }) async {
    if (recycleIndividualSales) {
      await _preserveTotalsAndRecyclePersonEntries(
        person: person,
        ownerUid: ownerUid,
      );
    }
    await _people.doc(person.id).update({
      'active': false,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedByUid': ownerUid,
      'individualSalesRecycled': recycleIndividualSales,
    });
    await _database.waitForPendingWrites();
  }

  Future<void> _preserveTotalsAndRecyclePersonEntries({
    required SalesPerson person,
    required String ownerUid,
  }) async {
    final entries =
        await _entries.where('personId', isEqualTo: person.id).get();
    final activeEntries = entries.docs
        .where((document) => document.data()['deletedAt'] == null)
        .toList(growable: false);
    final entriesByMonth =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final document in activeEntries) {
      final monthKey = document.data()['monthKey'] as String?;
      if (monthKey == null || monthKey.isEmpty) continue;
      entriesByMonth.putIfAbsent(monthKey, () => []).add(document);
    }

    for (final month in entriesByMonth.entries) {
      final snapshotReference =
          _totalSnapshots.doc('${person.id}_${month.key}');
      final existing = await snapshotReference.get();
      final existingData = existing.data();
      final existingIds =
          (existingData?['recordIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet();
      final newEntries = month.value
          .where((document) => !existingIds.contains(document.id))
          .toList(growable: false);
      final totalMilli = (existingData?['totalMilli'] as num?)?.toInt() ?? 0;
      final entryCount = (existingData?['entryCount'] as num?)?.toInt() ?? 0;
      await snapshotReference.set({
        'personId': person.id,
        'personName': person.name,
        'monthKey': month.key,
        'totalMilli': totalMilli +
            newEntries.fold<int>(
              0,
              (total, document) =>
                  total + (document.data()['amountMilli'] as num).toInt(),
            ),
        'entryCount': entryCount + newEntries.length,
        'recordIds': <String>{
          ...existingIds,
          ...newEntries.map((document) => document.id),
        }.toList(growable: false),
        'preservedAt': FieldValue.serverTimestamp(),
        'preservedByUid': ownerUid,
        'reason': 'salesperson-deletion',
      }, SetOptions(merge: true));
    }

    for (var offset = 0; offset < activeEntries.length; offset += 400) {
      final end = offset + 400 < activeEntries.length
          ? offset + 400
          : activeEntries.length;
      final batch = _database.batch();
      for (final document in activeEntries.sublist(offset, end)) {
        batch.update(document.reference, {
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedByUid': ownerUid,
          'deletedAsPartOfMonth': false,
          'deletedWithPerson': true,
        });
      }
      await batch.commit();
    }
    await _database.waitForPendingWrites();
  }

  Future<void> restorePerson(String personId) async {
    await _people.doc(personId).update({
      'active': true,
      'deletedAt': null,
      'deletedByUid': null,
      'restoredAt': FieldValue.serverTimestamp(),
    });
    await _database.waitForPendingWrites();
  }

  Future<void> permanentlyDeletePerson(SalesPerson person) async {
    final reservationId =
        sha256.convert(utf8.encode(person.normalizedName)).toString();
    final reservation = _nameReservations.doc(reservationId);
    await _database.runTransaction((transaction) async {
      final current = await transaction.get(_people.doc(person.id));
      if (current.exists &&
          current.data()?['active'] != false &&
          current.data()?['deletedAt'] == null) {
        throw StateError('Move the salesperson to the recycle bin first.');
      }
      final reserved = await transaction.get(reservation);
      if (reserved.data()?['personId'] == person.id) {
        transaction.delete(reservation);
      }
      transaction.delete(_people.doc(person.id));
    });
    await _database.waitForPendingWrites();
  }

  Future<SalesRecord?> findDailyRecord(
    String personId,
    DateTime salesDate,
  ) async {
    final id = '${personId}_${salesDateKey(salesDate)}';
    final document = await _entries.doc(id).get();
    if (!document.exists || document.data()?['deletedAt'] != null) return null;
    return _recordFromSnapshot(document);
  }

  Future<void> saveDailyRecord({
    required SalesPerson person,
    required DateTime salesDate,
    required int amountMilli,
    required String reference,
    required String ownerUid,
    required String ownerName,
    required bool updateExisting,
  }) async {
    final dateKey = salesDateKey(salesDate);
    final monthKey = salesMonthKey(salesDate);
    final entry = _entries.doc('${person.id}_$dateKey');
    final totalSnapshot = _totalSnapshots.doc('${person.id}_$monthKey');
    final audit = _audit.doc();
    await _database.runTransaction((transaction) async {
      final month = await transaction.get(_months.doc(monthKey));
      if (month.data()?['finalized'] == true) {
        throw StateError(
          'This month is locked. Reopen it before making changes.',
        );
      }
      final existing = await transaction.get(entry);
      final preservedTotal = await transaction.get(totalSnapshot);
      final preservedRecordIds =
          (preservedTotal.data()?['recordIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toSet();
      final existingIsDeleted = existing.data()?['deletedAt'] != null;
      if (existing.exists && !existingIsDeleted && !updateExisting) {
        throw StateError('A daily record already exists for this salesperson.');
      }
      if (existing.exists) {
        final previous = existing.data()!;
        transaction.set(audit, {
          'entryId': entry.id,
          'monthKey': monthKey,
          'personId': person.id,
          'previousAmountMilli': previous['amountMilli'],
          'newAmountMilli': amountMilli,
          'previousReference': previous['reference'] ?? '',
          'newReference': reference.trim(),
          'changedAt': FieldValue.serverTimestamp(),
          'changedByUid': ownerUid,
          'changedByName': ownerName,
        });
        transaction.update(entry, {
          'amountMilli': amountMilli,
          'reference': reference.trim(),
          'previousAmountMilli': previous['amountMilli'],
          'updatedAt': FieldValue.serverTimestamp(),
          'lastEditedByUid': ownerUid,
          'lastEditedByName': ownerName,
          'deletedAt': null,
          'deletedByUid': null,
          'deletedAsPartOfMonth': false,
        });
        if (preservedTotal.exists) {
          final previousAmount = (previous['amountMilli'] as num).toInt();
          if (preservedRecordIds.contains(entry.id)) {
            transaction.update(totalSnapshot, {
              'personName': person.name,
              'totalMilli': FieldValue.increment(
                amountMilli - previousAmount,
              ),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          } else {
            transaction.update(totalSnapshot, {
              'personName': person.name,
              'totalMilli': FieldValue.increment(amountMilli),
              'entryCount': FieldValue.increment(1),
              'recordIds': FieldValue.arrayUnion([entry.id]),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
      } else {
        transaction.set(entry, {
          'personId': person.id,
          'personName': person.name,
          'salesDateKey': dateKey,
          'monthKey': monthKey,
          'amountMilli': amountMilli,
          'reference': reference.trim(),
          'enteredByUid': ownerUid,
          'enteredByName': ownerName,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        if (preservedTotal.exists) {
          transaction.update(totalSnapshot, {
            'personName': person.name,
            'totalMilli': FieldValue.increment(amountMilli),
            'entryCount': FieldValue.increment(1),
            'recordIds': FieldValue.arrayUnion([entry.id]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    });
    await _database.waitForPendingWrites();
  }

  Future<void> recycleRecord({
    required String entryId,
    required String monthKey,
    required String ownerUid,
  }) async {
    final month = await _months.doc(monthKey).get();
    if (month.data()?['finalized'] == true) {
      throw StateError(
        'This month is locked. Reopen it before deleting records.',
      );
    }
    await _entries.doc(entryId).update({
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedByUid': ownerUid,
      'deletedAsPartOfMonth': false,
    });
    await _database.waitForPendingWrites();
  }

  Future<void> recycleRecords({
    required Iterable<SalesRecord> records,
    required String ownerUid,
  }) async {
    final selected = records.toList(growable: false);
    if (selected.isEmpty) return;
    final monthKeys = selected.map((record) => record.monthKey).toSet();
    for (final monthKey in monthKeys) {
      final month = await _months.doc(monthKey).get();
      if (month.data()?['finalized'] == true) {
        throw StateError(
          'Month $monthKey is locked. Reopen it before deleting records.',
        );
      }
    }
    for (var offset = 0; offset < selected.length; offset += 400) {
      final end =
          offset + 400 < selected.length ? offset + 400 : selected.length;
      final batch = _database.batch();
      for (final record in selected.sublist(offset, end)) {
        batch.update(_entries.doc(record.id), {
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedByUid': ownerUid,
          'deletedAsPartOfMonth': false,
        });
      }
      await batch.commit();
    }
    await _database.waitForPendingWrites();
  }

  Future<void> restoreRecord(String entryId) async {
    await _entries.doc(entryId).update({
      'deletedAt': null,
      'deletedByUid': null,
      'deletedAsPartOfMonth': false,
      'restoredAt': FieldValue.serverTimestamp(),
    });
    await _database.waitForPendingWrites();
  }

  Future<void> permanentlyDeleteRecord(String entryId) async {
    final entry = await _entries.doc(entryId).get();
    final audits = await _audit.where('entryId', isEqualTo: entryId).get();
    final batch = _database.batch()..delete(_entries.doc(entryId));
    for (final document in audits.docs) {
      batch.delete(document.reference);
    }
    final entryData = entry.data();
    final personId = entryData?['personId'] as String?;
    final monthKey = entryData?['monthKey'] as String?;
    if (personId != null && monthKey != null) {
      final snapshotReference = _totalSnapshots.doc('${personId}_$monthKey');
      final snapshot = await snapshotReference.get();
      final snapshotData = snapshot.data();
      final recordIds =
          (snapshotData?['recordIds'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(growable: true);
      if (snapshot.exists && recordIds.remove(entryId)) {
        final nextCount =
            ((snapshotData?['entryCount'] as num?)?.toInt() ?? 1) - 1;
        if (nextCount <= 0 || recordIds.isEmpty) {
          batch.delete(snapshotReference);
        } else {
          final amountMilli = (entryData?['amountMilli'] as num?)?.toInt() ?? 0;
          final currentTotal =
              (snapshotData?['totalMilli'] as num?)?.toInt() ?? 0;
          batch.update(snapshotReference, {
            'totalMilli': currentTotal - amountMilli,
            'entryCount': nextCount,
            'recordIds': recordIds,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }
    await batch.commit();
    await _database.waitForPendingWrites();
  }

  Future<void> setFinalized({
    required String monthKey,
    required bool finalized,
    required String ownerUid,
  }) async {
    await _months.doc(monthKey).set({
      'monthKey': monthKey,
      'finalized': finalized,
      'finalizedAt': finalized ? FieldValue.serverTimestamp() : null,
      'finalizedByUid': finalized ? ownerUid : null,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> requestBackup({
    required String monthKey,
    required String ownerUid,
    required String ownerName,
  }) async {
    if (!RegExp(r'^\d{4}-\d{2}$').hasMatch(monthKey)) {
      throw const FormatException('Select a valid sales month.');
    }
    await _backupRequest.set({
      'scope': 'all-sales-tracker-data',
      'monthKey': monthKey,
      'requestedAt': FieldValue.serverTimestamp(),
      'requestedByUid': ownerUid,
      'requestedByName': ownerName,
      'status': 'pending',
      'startedAt': null,
      'completedAt': null,
      'assetNames': const <String>[],
      'error': null,
    });
    await _database.waitForPendingWrites();
  }

  Future<void> recycleMonth(String monthKey, String ownerUid) async {
    final entries = await _entries.where('monthKey', isEqualTo: monthKey).get();
    for (var offset = 0; offset < entries.docs.length; offset += 400) {
      final end = offset + 400 < entries.docs.length
          ? offset + 400
          : entries.docs.length;
      final batch = _database.batch();
      var writes = 0;
      for (final document in entries.docs.sublist(offset, end)) {
        if (document.data()['deletedAt'] == null) {
          batch.update(document.reference, {
            'deletedAt': FieldValue.serverTimestamp(),
            'deletedByUid': ownerUid,
            'deletedAsPartOfMonth': true,
          });
          writes++;
        }
      }
      if (writes > 0) await batch.commit();
    }
    await _months.doc(monthKey).set({
      'monthKey': monthKey,
      'deletedAt': FieldValue.serverTimestamp(),
      'deletedByUid': ownerUid,
    }, SetOptions(merge: true));
    await _database.waitForPendingWrites();
  }

  Future<void> restoreMonth(String monthKey) async {
    final entries = await _entries.where('monthKey', isEqualTo: monthKey).get();
    for (var offset = 0; offset < entries.docs.length; offset += 400) {
      final end = offset + 400 < entries.docs.length
          ? offset + 400
          : entries.docs.length;
      final batch = _database.batch();
      var writes = 0;
      for (final document in entries.docs.sublist(offset, end)) {
        if (document.data()['deletedAsPartOfMonth'] == true) {
          batch.update(document.reference, {
            'deletedAt': null,
            'deletedByUid': null,
            'deletedAsPartOfMonth': false,
            'restoredAt': FieldValue.serverTimestamp(),
          });
          writes++;
        }
      }
      if (writes > 0) await batch.commit();
    }
    await _months.doc(monthKey).update({
      'deletedAt': null,
      'deletedByUid': null,
      'restoredAt': FieldValue.serverTimestamp(),
    });
    await _database.waitForPendingWrites();
  }

  Future<void> permanentlyDeleteMonth(String monthKey) async {
    final entries = await _entries.where('monthKey', isEqualTo: monthKey).get();
    final audits = await _audit.where('monthKey', isEqualTo: monthKey).get();
    final totals =
        await _totalSnapshots.where('monthKey', isEqualTo: monthKey).get();
    final references = <DocumentReference<Map<String, dynamic>>>[
      ...entries.docs.map((document) => document.reference),
      ...audits.docs.map((document) => document.reference),
      ...totals.docs.map((document) => document.reference),
      _months.doc(monthKey),
    ];
    for (var offset = 0; offset < references.length; offset += 400) {
      final end =
          offset + 400 < references.length ? offset + 400 : references.length;
      final batch = _database.batch();
      for (final reference in references.sublist(offset, end)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
    await _database.waitForPendingWrites();
  }

  Future<int> permanentlyDeleteAllRecycledData() async {
    final monthsSnapshot = await _months.get();
    final deletedMonths = monthsSnapshot.docs
        .where((document) => document.data()['deletedAt'] != null)
        .map((document) => document.id)
        .toList(growable: false);
    for (final monthKey in deletedMonths) {
      await permanentlyDeleteMonth(monthKey);
    }

    final entriesSnapshot = await _entries.get();
    final deletedEntries = entriesSnapshot.docs
        .where((document) => document.data()['deletedAt'] != null)
        .toList(growable: false);
    for (final entry in deletedEntries) {
      await permanentlyDeleteRecord(entry.id);
    }

    final peopleSnapshot = await _people.get();
    final deletedPeople = peopleSnapshot.docs
        .where((document) =>
            document.data()['active'] == false ||
            document.data()['deletedAt'] != null)
        .toList(growable: false);
    final deletedPersonIds =
        deletedPeople.map((document) => document.id).toSet();
    final reservationsSnapshot = await _nameReservations.get();
    final relatedReservations = reservationsSnapshot.docs
        .where((document) =>
            deletedPersonIds.contains(document.data()['personId']))
        .toList(growable: false);

    final references = <DocumentReference<Map<String, dynamic>>>[
      ...deletedPeople.map((document) => document.reference),
      ...relatedReservations.map((document) => document.reference),
    ];
    for (var offset = 0; offset < references.length; offset += 400) {
      final end =
          offset + 400 < references.length ? offset + 400 : references.length;
      final batch = _database.batch();
      for (final reference in references.sublist(offset, end)) {
        batch.delete(reference);
      }
      await batch.commit();
    }
    await _database.waitForPendingWrites();
    return deletedMonths.length + deletedEntries.length + deletedPeople.length;
  }

  SalesPerson _personFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) =>
      SalesPerson(
        id: document.id,
        name: document.data()['name'] as String? ?? '',
        normalizedName: document.data()['normalizedName'] as String? ?? '',
        active: document.data()['active'] as bool? ?? true,
        createdAt: _dateTime(document.data()['createdAt']),
        deletedAt: _dateTime(document.data()['deletedAt']),
      );

  SalesPerson _personFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) =>
      SalesPerson(
        id: document.id,
        name: document.data()?['name'] as String? ?? '',
        normalizedName: document.data()?['normalizedName'] as String? ?? '',
        active: document.data()?['active'] as bool? ?? true,
        createdAt: _dateTime(document.data()?['createdAt']),
        deletedAt: _dateTime(document.data()?['deletedAt']),
      );

  SalesRecord _recordFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) =>
      _recordFromSnapshot(document);

  SalesRecord _recordFromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    return SalesRecord(
      id: document.id,
      personId: data['personId'] as String,
      personName: data['personName'] as String,
      salesDateKey: data['salesDateKey'] as String,
      monthKey: data['monthKey'] as String,
      amountMilli: (data['amountMilli'] as num).toInt(),
      reference: data['reference'] as String? ?? '',
      enteredByUid: data['enteredByUid'] as String? ?? '',
      enteredByName: data['enteredByName'] as String? ?? 'Owner',
      createdAt: _dateTime(data['createdAt']),
      updatedAt: _dateTime(data['updatedAt']),
      previousAmountMilli: (data['previousAmountMilli'] as num?)?.toInt(),
      lastEditedByUid: data['lastEditedByUid'] as String?,
      lastEditedByName: data['lastEditedByName'] as String?,
      deletedAt: _dateTime(data['deletedAt']),
      deletedAsPartOfMonth: data['deletedAsPartOfMonth'] as bool? ?? false,
    );
  }

  SalesPersonTotalSnapshot _totalSnapshotFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return SalesPersonTotalSnapshot(
      id: document.id,
      personId: data['personId'] as String? ?? '',
      personName: data['personName'] as String? ?? '',
      monthKey: data['monthKey'] as String? ?? '',
      totalMilli: (data['totalMilli'] as num?)?.toInt() ?? 0,
      entryCount: (data['entryCount'] as num?)?.toInt() ?? 0,
      recordIds: (data['recordIds'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }

  DateTime? _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
