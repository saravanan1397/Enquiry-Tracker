import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';

import '../models/sales_record.dart';

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
  CollectionReference<Map<String, dynamic>> get _audit =>
      _database.collection('salesEntryAudit');
  CollectionReference<Map<String, dynamic>> get _months =>
      _database.collection('salesMonths');

  Stream<List<SalesPerson>> watchPeople() {
    if (!isConfigured) return Stream.value(const []);
    return _people.snapshots().map((snapshot) {
      final result = snapshot.docs.map(_personFromDocument).toList();
      result
          .sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return result;
    });
  }

  Stream<List<SalesRecord>> watchMonth(String monthKey) {
    if (!isConfigured) return Stream.value(const []);
    return _entries.where('monthKey', isEqualTo: monthKey).snapshots().map(
      (snapshot) {
        final result = snapshot.docs.map(_recordFromDocument).toList();
        result.sort((a, b) {
          final date = a.salesDateKey.compareTo(b.salesDateKey);
          return date != 0
              ? date
              : a.personName
                  .toLowerCase()
                  .compareTo(b.personName.toLowerCase());
        });
        return result;
      },
    );
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
          if (existingPerson.exists) return _personFromSnapshot(existingPerson);
        }
      }

      final person = _people.doc();
      transaction.set(person, {
        'name': cleanName,
        'normalizedName': normalized,
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

  Future<SalesRecord?> findDailyRecord(
      String personId, DateTime salesDate) async {
    final id = '${personId}_${salesDateKey(salesDate)}';
    final document = await _entries.doc(id).get();
    return document.exists ? _recordFromSnapshot(document) : null;
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
    final audit = _audit.doc();
    await _database.runTransaction((transaction) async {
      final month = await transaction.get(_months.doc(monthKey));
      if (month.data()?['finalized'] == true) {
        throw StateError(
            'This month is locked. Reopen it before making changes.');
      }
      final existing = await transaction.get(entry);
      if (existing.exists && !updateExisting) {
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
        });
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
      }
    });
    await _database.waitForPendingWrites();
  }

  Future<void> deleteRecord(String entryId, String monthKey) async {
    final month = await _months.doc(monthKey).get();
    if (month.data()?['finalized'] == true) {
      throw StateError(
          'This month is locked. Reopen it before deleting records.');
    }
    final audits = await _audit.where('entryId', isEqualTo: entryId).get();
    final batch = _database.batch()..delete(_entries.doc(entryId));
    for (final document in audits.docs) {
      batch.delete(document.reference);
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

  Future<void> deleteMonth(String monthKey) async {
    final entries = await _entries.where('monthKey', isEqualTo: monthKey).get();
    final audits = await _audit.where('monthKey', isEqualTo: monthKey).get();
    final references = <DocumentReference<Map<String, dynamic>>>[
      ...entries.docs.map((document) => document.reference),
      ...audits.docs.map((document) => document.reference),
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

  SalesPerson _personFromDocument(
          QueryDocumentSnapshot<Map<String, dynamic>> document) =>
      SalesPerson(
        id: document.id,
        name: document.data()['name'] as String? ?? '',
        normalizedName: document.data()['normalizedName'] as String? ?? '',
        createdAt: _dateTime(document.data()['createdAt']),
      );

  SalesPerson _personFromSnapshot(
          DocumentSnapshot<Map<String, dynamic>> document) =>
      SalesPerson(
        id: document.id,
        name: document.data()?['name'] as String? ?? '',
        normalizedName: document.data()?['normalizedName'] as String? ?? '',
        createdAt: _dateTime(document.data()?['createdAt']),
      );

  SalesRecord _recordFromDocument(
          QueryDocumentSnapshot<Map<String, dynamic>> document) =>
      _recordFromSnapshot(document);

  SalesRecord _recordFromSnapshot(
      DocumentSnapshot<Map<String, dynamic>> document) {
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
    );
  }

  DateTime? _dateTime(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
