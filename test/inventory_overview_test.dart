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
  _Store({this.withStock = false});
  final bool withStock;
  int? stock;
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
  Future<InventoryRows> balances({String? location}) async => _Rows([
        if (withStock || stock != null)
          _Row('balance', {
            'productId': 'p1',
            'location': 'warehouse',
            'quantity': stock ?? 1
          }),
      ]);
  @override
  Future<InventoryRows> counts({String? location}) =>
      movements(location: location);
  @override
  Future<InventoryRows> movements({String? location}) async => _Rows([
        _Row('movement', {
          'productId': 'p1',
          'location': 'warehouse',
          'type': 'count',
          'before': 2,
          'quantityAfter': 1,
          'delta': -1,
          'note': 'Shelf check',
        }),
      ]);
  @override
  Future<InventoryRows> drafts({String? location}) async => _Rows([
        _Row('draft', {
          'productId': 'p1',
          'location': 'warehouse',
          'quantity': 3,
          'note': 'Awaiting invoice',
        }),
      ]);
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
    final before = stock ?? (withStock ? 1 : 0);
    stock = before + entry.deltaFor(before);
    posted = entry;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Physical Stock sets totals and subtracts outgoing units',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true);
    await tester.pumpWidget(MaterialApp(
        home: InventoryWidgetScreen(store: store, adminDark: false)));
    await tester.pumpAndSettle();
    expect(find.text('Back up now'), findsOneWidget);
    expect(find.text('Restore from backup'), findsOneWidget);
    await tester.tap(find.text('Physical Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Balance stock'), findsOneWidget);
    expect(find.text('Expected'), findsNothing);
    expect(find.text('Variance'), findsNothing);

    Future<void> enterStock(
        String button, String field, String value, String save) async {
      await tester.tap(find.text(button));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not selected').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('SSH Warehouse').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not selected').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cookware Fixture').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, field), value);
      await tester.tap(find.text(save));
      await tester.pumpAndSettle();
    }

    await enterStock('Set Total Stock', 'Total stock', '100', 'Save Total');
    expect(find.text('100'), findsOneWidget);
    await enterStock(
        'Subtract Outgoing Stock', 'Outgoing stock', '25', 'Subtract Stock');
    expect(find.text('75'), findsOneWidget);
    expect(store.posted?.type, 'sale');
    expect(tester.takeException(), isNull);
  });

  testWidgets('each inventory view searches its records independently of menus',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: InventoryWidgetScreen(store: _Store(withStock: true))));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('inventory-view-search'));
    for (final (section, query, shown) in [
      ('Overview', 'test-1', 'Cookware Fixture'),
      ('Products', 'cookware', 'Cookware Fixture'),
      ('Physical Stock', 'warehouse', 'Cookware Fixture'),
      ('Stock Movements', 'awaiting invoice', 'Resume'),
      ('Reports', 'warehouse', 'Cookware Fixture'),
      ('Locations', 'selvan hotel', 'Selvan Hotel Mart'),
    ]) {
      if (section != 'Overview') {
        await tester.tap(find.text(section).first);
        await tester.pumpAndSettle();
      }
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, query);
      await tester.pumpAndSettle();
      expect(find.text(shown), findsWidgets);
      expect(find.text('Stock Movements'), findsWidgets);
      await tester.enterText(field, 'no match');
      await tester.pumpAndSettle();
      expect(find.text(shown), findsNothing);
      expect(find.text('No matching records.'), findsWidgets);
      if (section == 'Reports') {
        expect(
            tester
                .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'Export Excel'))
                .onPressed,
            isNull);
      }
      await tester.tap(find.byTooltip('Clear view search'));
      await tester.pumpAndSettle();
      expect(find.text(shown), findsWidgets);
    }
    expect(tester.takeException(), isNull);
  });

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
