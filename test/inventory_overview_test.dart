import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/inventory_widget.dart';
import '../lib/services/inventory_store.dart';

class _Row implements InventoryRow {
  _Row(this.id, this.values);
  @override
  final String id;
  final Map<String, dynamic> values;
  @override
  Map<String, dynamic> data() => values;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Rows implements InventoryRows {
  _Rows(this.docs);
  @override
  final List<InventoryRow> docs;
  @override
  int get size => docs.length;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements InventoryStore {
  InventoryMovement? posted;
  @override
  Future<InventoryRows> products() async => _Rows([
        _Row('p1', {
          'name': 'Cookware Fixture',
          'sku': 'TEST-1',
          'active': true,
          'reorder': 2
        }),
      ]);
  @override
  Future<InventoryRows> balances({String? location}) async => _Rows([]);
  @override
  Future<List<InventoryLocation>> locations() async =>
      mergeInventoryLocations(const []);
  @override
  String newMovementId() => 'movement-test';
  @override
  String newDraftId() => 'draft-test';
  @override
  Future<void> post(InventoryMovement entry,
      {required String movementId, String? draftId}) async {
    posted = entry;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'Overview shows unstocked products and edits stock at a chosen location',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store();
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Cookware Fixture'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit stock for Cookware Fixture'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Stock'), findsOneWidget);
    await tester.tap(find.text('Not selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH Warehouse').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'New quantity on hand'), '7');
    await tester.tap(find.text('Save Stock'));
    await tester.pumpAndSettle();
    expect(store.posted?.productId, 'p1');
    expect(store.posted?.location, 'warehouse');
    expect(store.posted?.quantity, 7);
    expect(store.posted?.type, 'count');
    expect(tester.takeException(), isNull);
  });
}
