import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/leadloop_app.dart';
import 'package:leadloop/models/customer_lead.dart';
import 'package:leadloop/services/firebase_lead_backend.dart';
import 'package:leadloop/services/local_lead_store.dart';

class _FakeBackend extends FirebaseLeadBackend {
  final List<String> deletedIds = [];

  @override
  bool get isConfigured => true;

  @override
  Future<void> deleteLeads(Iterable<String> leadIds) async {
    deletedIds.addAll(leadIds);
  }
}

class _FakeStore extends LocalLeadStore {
  _FakeStore(this.deleted);

  final List<CustomerLead> deleted;

  @override
  List<CustomerLead> recycleBin() => List.unmodifiable(deleted);

  @override
  Future<void> permanentlyDeleteMany(Iterable<String> ids) async {
    final removed = ids.toSet();
    deleted.removeWhere((lead) => removed.contains(lead.id));
  }
}

CustomerLead _lead(String id, String name) => CustomerLead(
      id: id,
      name: name,
      phone: '9000000001',
      shopId: 'branch-1',
      shopName: 'Branch 1',
      promoterId: 'promoter-1',
      promoterName: 'Promoter 1',
      createdAt: DateTime(2026, 9, 11, 10),
      deletedAt: DateTime(2026, 9, 11, 11),
      isSynced: true,
    );

void main() {
  testWidgets('owner can confirm permanent deletion of every recycled record',
      (tester) async {
    final store = _FakeStore([_lead('one', 'First'), _lead('two', 'Second')]);
    final backend = _FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeadloopRecycleBinScreen(store: store, backend: backend),
      ),
    ));

    expect(find.text('Delete all permanently'), findsOneWidget);
    await tester.tap(find.text('Delete all permanently'));
    await tester.pumpAndSettle();
    expect(find.textContaining('All 2 records'), findsOneWidget);

    await tester.tap(find.text('Delete all forever'));
    await tester.pumpAndSettle();

    expect(backend.deletedIds, unorderedEquals(['one', 'two']));
    expect(store.recycleBin(), isEmpty);
    expect(find.text('Recycle bin is empty'), findsOneWidget);
  });

  testWidgets('cancelling bulk deletion keeps every record', (tester) async {
    final store = _FakeStore([_lead('one', 'First')]);
    final backend = _FakeBackend();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeadloopRecycleBinScreen(store: store, backend: backend),
      ),
    ));

    await tester.tap(find.text('Delete all permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(backend.deletedIds, isEmpty);
    expect(store.recycleBin(), hasLength(1));
  });
}
