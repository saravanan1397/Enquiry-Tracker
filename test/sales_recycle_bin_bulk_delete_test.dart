import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/sales_record.dart';
import 'package:leadloop/sales_tracker_screen.dart';
import 'package:leadloop/services/firebase_sales_backend.dart';

class _FakeSalesBackend extends FirebaseSalesBackend {
  int deleteAllCalls = 0;

  @override
  Stream<List<SalesPerson>> watchDeletedPeople() => Stream.value(const []);

  @override
  Stream<List<SalesRecord>> watchDeletedEntries() => Stream.value(const []);

  @override
  Stream<List<SalesMonthState>> watchDeletedMonths() => Stream.value(const []);

  @override
  Future<int> permanentlyDeleteAllRecycledData() async {
    deleteAllCalls++;
    return 4;
  }
}

void main() {
  testWidgets('sales recycle bin can permanently delete every recycled item',
      (tester) async {
    final backend = _FakeSalesBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesTrackerRecycleBinScreen(
            backend: backend,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Delete all Sales Tracker data permanently'),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Every salesperson profile'),
      findsOneWidget,
    );

    await tester.tap(find.text('Delete forever'));
    await tester.pumpAndSettle();

    expect(backend.deleteAllCalls, 1);
    expect(
      find.text('4 Sales Tracker items permanently deleted from Firebase.'),
      findsOneWidget,
    );
  });

  testWidgets('cancelling sales bulk deletion keeps recycle-bin data',
      (tester) async {
    final backend = _FakeSalesBackend();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalesTrackerRecycleBinScreen(
            backend: backend,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Delete all Sales Tracker data permanently'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(backend.deleteAllCalls, 0);
  });
}
