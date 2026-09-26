import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/sales_record.dart';
import 'package:leadloop/sales_tracker_screen.dart';
import 'package:leadloop/services/firebase_sales_backend.dart';

class _BackupStatusBackend extends FirebaseSalesBackend {
  _BackupStatusBackend(
    this.statuses, {
    this.records = const [],
  });

  final Stream<SalesBackupStatus?> statuses;
  final List<SalesRecord> records;

  @override
  Stream<List<SalesPerson>> watchPeople() => Stream.value(const []);

  @override
  Stream<SalesMonthState> watchMonthState(String monthKey) =>
      Stream.value(SalesMonthState(monthKey: monthKey));

  @override
  Stream<List<SalesRecord>> watchMonth(String monthKey) =>
      Stream.value(records);

  @override
  Stream<List<SalesPersonTotalSnapshot>> watchPreservedTotals(
          String monthKey) =>
      Stream.value(const []);

  @override
  Stream<SalesBackupStatus?> watchBackupStatus() => statuses;
}

SalesBackupStatus _status(String status) => SalesBackupStatus(
      status: status,
      completedAt: status == 'completed' ? DateTime(2026, 9, 25, 12) : null,
      assetNames:
          status == 'completed' ? const ['sales-backup.etbackup'] : const [],
    );

SalesRecord _record(String id, String personId, String personName) =>
    SalesRecord(
      id: id,
      personId: personId,
      personName: personName,
      salesDateKey: '2026-09-25',
      monthKey: '2026-09',
      amountMilli: 10000000,
      enteredByUid: 'owner-1',
      enteredByName: 'Admin',
    );

Future<void> _pumpTracker(
  WidgetTester tester,
  Stream<SalesBackupStatus?> statuses,
) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SalesTrackerScreen(
          backend: _BackupStatusBackend(statuses),
          ownerUid: 'owner-1',
          ownerName: 'Owner',
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('an old successful backup is not shown when tracker reopens',
      (tester) async {
    await _pumpTracker(tester, Stream.value(_status('completed')));

    expect(find.text('Manual backup successful'), findsNothing);
  });

  testWidgets('a backup completed during this visit is shown for ten seconds',
      (tester) async {
    final controller = StreamController<SalesBackupStatus?>();
    addTearDown(controller.close);
    await _pumpTracker(tester, controller.stream);

    controller.add(_status('pending'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Manual backup queued'), findsOneWidget);
    controller.add(_status('completed'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Manual backup successful'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Manual backup successful'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Manual backup successful'), findsNothing);
  });

  testWidgets('salesperson totals search filters only the totals panel',
      (tester) async {
    final backend = _BackupStatusBackend(
      Stream.value(null),
      records: [
        _record('record-a', 'person-a', 'Alice'),
        _record('record-b', 'person-b', 'Bob'),
      ],
    );
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesTrackerScreen(
            backend: backend,
            ownerUid: 'owner-1',
            ownerName: 'Admin',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Bob'), findsNWidgets(2));
    await tester.enterText(
      find.widgetWithText(TextField, 'Search salespersons'),
      'Alice',
    );
    await tester.pump();

    expect(find.text('Alice'), findsNWidgets(3));
    expect(find.text('Bob'), findsOneWidget);
  });
}
