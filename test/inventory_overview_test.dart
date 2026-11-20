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
  final transfers = <(String, String, String, int)>[];
  int _movementNumber = 0;
  @override
  Future<InventoryRows> products() async => _Rows([
        _Row('p1', {
          'name': 'Cookware Fixture',
          'sku': 'TEST-1',
          'barcode': '00001844',
          'unitCost': 2599,
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
  String newMovementId() => 'movement-test-${_movementNumber++}';
  @override
  String newDraftId() => 'draft-test';
  @override
  String newTransferId() => 'transfer-test';
  @override
  Future<InventoryRows> legacyTransfers() async => _Rows([]);
  @override
  Future<void> transferStock(
      {required String id,
      required String outgoingId,
      required String incomingId,
      required String from,
      required String to,
      required String product,
      required int quantity,
      String? draftId}) async {
    if (outgoingId == incomingId) throw StateError('Transfer IDs match.');
    transfers.add((from, to, product, quantity));
  }

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
  testWidgets(
      'product columns have the same fixed width on wide and narrow displays',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: InventoryWidgetScreen(store: _Store(withStock: true))));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(DataTable).first).width, 872);
    await tester.tap(find.text('Products').first);
    await tester.pumpAndSettle();
    final table = find.byType(DataTable);
    expect(tester.getSize(table).width, 872);
    expect(
        tester.getTopLeft(find.text('Tracked stock')).dx -
            tester.getTopLeft(find.text('Category')).dx,
        lessThan(160));
    await tester.binding.setSurfaceSize(const Size(590, 900));
    await tester.pumpAndSettle();
    expect(tester.getSize(table).width, 872);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'movement filters share a desktop row and stock tables stay compact',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: InventoryWidgetScreen(store: _Store(withStock: true))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit details for Cookware Fixture'), findsNothing);
    expect(find.byTooltip('Edit stock for Cookware Fixture'), findsOneWidget);
    final category = tester.getTopLeft(find.text('Category'));
    final tracked = tester.getTopLeft(find.text('Tracked stock'));
    expect(tracked.dx - category.dx, lessThan(225));
    final stock = tester.getTopRight(find.text('1'));
    final status = tester.getTopLeft(find.text('Active'));
    expect(status.dx - stock.dx, greaterThanOrEqualTo(20));
    await tester.tap(find.text('Physical Stock'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit details for Cookware Fixture'), findsOneWidget);
    final location = tester.getTopLeft(find.text('Location'));
    final balance = tester.getTopLeft(find.text('Balance stock'));
    expect(balance.dx - location.dx, lessThan(300));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('1.00'), findsNothing);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('inventory-view-search'));
    final type = find.text('All types');
    final date = find.text('Any date');
    expect(tester.getCenter(search).dy, closeTo(tester.getCenter(type).dy, 12));
    expect(tester.getCenter(search).dy, closeTo(tester.getCenter(date).dy, 12));
    expect(
        tester.getTopLeft(type).dx, greaterThan(tester.getTopRight(search).dx));
    expect(tester.getTopLeft(date).dx, greaterThan(tester.getTopLeft(type).dx));
    expect(
        tester.getTopLeft(find.text('Balance')).dx -
            tester.getTopLeft(find.text('Movement')).dx,
        lessThan(390));

    await tester.binding.setSurfaceSize(const Size(590, 900));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(type).dy,
        greaterThan(tester.getBottomLeft(search).dy));
    expect(tester.takeException(), isNull);
  });

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
    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();
    expect(find.text('Back up inventory'), findsOneWidget);
    expect(find.text('Trust this device'), findsOneWidget);
    expect(find.text('Use saved folder'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Back up inventory'), findsNothing);
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
      ('Products', '00001844', 'Cookware Fixture'),
      ('Physical Stock', 'warehouse', 'Cookware Fixture'),
      ('History', 'awaiting invoice', 'Resume'),
      ('Reports', 'warehouse', 'Cookware Fixture'),
      ('Locations', 'selvan hotel', 'Selvan Hotel Mart'),
    ]) {
      if (section != 'Overview') {
        await tester.tap(find.text(section).first);
        await tester.pumpAndSettle();
      }
      if (section == 'Reports') {
        expect(find.text('Stock value INR'), findsOneWidget);
        expect(find.text('25.99'), findsNWidgets(2));
      }
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      await tester.enterText(field, query);
      await tester.pumpAndSettle();
      expect(find.text(shown), findsWidgets);
      expect(find.text('History'), findsWidgets);
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

  testWidgets('transfer asks once and stays on History after confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store();
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record Movement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not selected').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Transfer to another branch').last);
    await tester.pumpAndSettle();
    expect(find.text('Source branch'), findsOneWidget);
    expect(find.text('Destination branch'), findsOneWidget);
    expect(find.text('Transfer Stock'), findsOneWidget);
    expect(find.text('Save Draft'), findsNothing);
    await tester.tap(find.text('Not selected').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH Warehouse').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not selected').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH TNHB').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not selected').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cookware Fixture').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '4');
    await tester.tap(find.text('Transfer Stock'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm transfer'), findsOneWidget);
    expect(store.transfers, isEmpty);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(store.transfers, isEmpty);
    await tester.tap(find.text('Transfer Stock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, transfer'));
    await tester.pumpAndSettle();
    expect(store.transfers, [('warehouse', 'tnhb', 'p1', 4)]);
    expect(find.text('Record Movement'), findsOneWidget);
    expect(find.text('Confirm transfer'), findsNothing);
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
