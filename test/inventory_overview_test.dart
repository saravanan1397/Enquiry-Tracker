import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/inventory_widget.dart';
import '../lib/services/inventory_report.dart';
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
  _Store({this.withStock = false, this.withDamage = false});
  final bool withStock, withDamage;
  int? stock;
  bool recycled = false;
  String? addedName, addedLocation;
  String? addedCategory;
  int? addedQuantity;
  (String?, int?, int?)? editedStock;
  InventoryMovement? posted;
  final transfers = <(String, String, String, int)>[];
  int _movementNumber = 0;
  @override
  Future<InventoryRows> products() async => _Rows([
        _Row('p1', {
          'name': 'Cookware Fixture',
          'sku': 'TEST-1',
          'category': 'Cookware',
          'barcode': '00001844',
          'unitCost': 2599,
          'active': !recycled,
          if (recycled) 'deletedAt': 'fixture timestamp',
          'reorder': 2
        }),
        if (addedName != null) _Row('p2', {'name': addedName, 'active': true}),
      ]);
  @override
  Future<List<InventoryRow>> productSuggestions() async =>
      (await products()).docs;
  @override
  Future<void> saveProduct({
    String? id,
    String? storageLocation,
    int? stockQuantity,
    int? expectedStockQuantity,
    required String name,
    required String sku,
    required String category,
    String barcode = '',
    String? supplierId,
    int? unitCost,
    required int? reorder,
    required bool active,
  }) async {
    if (id != null) {
      editedStock = (storageLocation, stockQuantity, expectedStockQuantity);
      if (storageLocation == 'warehouse' && stockQuantity != null) {
        stock = stockQuantity;
      }
      return;
    }
    addedName = name;
    addedCategory = category;
    addedLocation = storageLocation;
    addedQuantity = stockQuantity;
  }

  @override
  Future<Map<String, int>> productStockByLocation(String id) async => {
        if (id == 'p1' && (withStock || stock != null)) 'warehouse': stock ?? 1,
      };

  @override
  Future<InventoryRows> deletedProducts() async =>
      recycled ? products() : _Rows([]);
  @override
  Future<void> setProductRecycled(String id, {required bool recycled}) async {
    expect(id, 'p1');
    this.recycled = recycled;
  }

  @override
  Future<InventoryRows> balances({String? location}) async => _Rows([
        if (withStock || stock != null)
          _Row('balance', {
            'productId': 'p1',
            'location': 'warehouse',
            'quantity': stock ?? 1
          }),
        if (addedLocation != null &&
            (location == null || location == addedLocation))
          _Row('newBalance', {
            'productId': 'p2',
            'location': addedLocation,
            'quantity': addedQuantity ?? 0,
          }),
      ]);
  @override
  Future<InventoryReportSource> reportSource({String? location}) async => (
        products: (await products()).docs,
        balances: (await balances())
            .docs
            .where(
                (row) => location == null || row.data()['location'] == location)
            .toList(),
        movements: (await movements())
            .docs
            .where(
                (row) => location == null || row.data()['location'] == location)
            .toList(),
      );
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
        if (withDamage)
          _Row('damage', {
            'productId': 'p1',
            'location': 'tnhb',
            'type': 'damage',
            'quantity': 3,
            'delta': -3,
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
  Future<InventoryRows> suppliers() async => _Rows([
        _Row('supplier', {
          'name': 'Sample Supplier',
          'phone': '0123456789',
          'email': 'example@example.test',
          'notes': 'Sample notes',
          'active': true,
        }),
      ]);
  @override
  Future<InventoryRows> purchaseOrders() async => _Rows([
        _Row('order', {
          'reference': 'PO-1',
          'supplierId': 'supplier',
          'productId': 'p1',
          'location': 'warehouse',
          'quantity': 3,
          'received': 1,
          'status': 'partial',
        }),
      ]);
  @override
  Future<InventoryRows> branchTransfers() async => _Rows([
        _Row('transfer', {
          'productId': 'p1',
          'from': 'warehouse',
          'to': 'tnhb',
          'quantity': 1,
          'status': 'received',
        }),
      ]);
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
  test('Total Stock reports the final balance once per product and branch', () {
    Map<String, dynamic> entry(String location, int quantity) =>
        {'productId': 'p1', 'location': location, 'quantity': quantity};
    final report = buildInventoryReport((
      products: [
        _Row('p1', {'name': 'Product A'})
      ],
      balances: [_Row('a', entry('a', 7)), _Row('b', entry('b', 9))],
      movements: [
        _Row('opening', {...entry('a', 10), 'type': 'opening', 'delta': 10}),
        _Row('count', {...entry('b', 9), 'type': 'count', 'delta': 9}),
        _Row('damage', {...entry('a', 1), 'type': 'damage', 'delta': -1}),
        _Row('transfer',
            {...entry('a', 2), 'type': 'transfer_out', 'delta': -2}),
      ],
    ), locations: {
      'a': 'Place A',
      'b': 'Place B'
    }, matches: (_) => true);
    expect(report.rows.map((row) => row.take(3).toList()), [
      ['Product A', 'Place A', 7],
      ['Product A', 'Place B', 9],
    ]);
    expect(report.headings[2], 'Total Stock');
    expect(report.headings.skip(6), ['Damaged', 'Transfer out']);
  });

  testWidgets('saved name and category suggestions do not create duplicates',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true);
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, 'Add Product');
    await tester.tap(button);
    await tester.pumpAndSettle();
    final name = find.widgetWithText(TextField, 'Product name');
    await tester.enterText(name, 'cook');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cookware Fixture · SKU TEST-1'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Product'), findsOneWidget);
    expect(store.addedName, isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.enterText(name, '  cookware fixture ');
    await tester.tap(find.text('Save Product'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Product'), findsOneWidget);
    expect(store.addedName, isNull);
  });

  testWidgets('Edit Product shows branch stock and saves a new total',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true);
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    final edit = find.byTooltip('Edit details for Cookware Fixture');
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.text('Where is the product stored?'), findsOneWidget);
    expect(find.text('Current stock here: 1'), findsOneWidget);
    await tester.tap(find.text('Save Product'));
    await tester.pumpAndSettle();
    expect(store.editedStock, ('warehouse', null, 1));
    expect(store.stock, isNull);

    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Total quantity in hand (optional)'),
        '7');
    await tester.tap(find.text('Save Product'));
    await tester.pumpAndSettle();
    expect(store.editedStock, ('warehouse', 7, 1));
    expect(store.stock, 7);
  });

  testWidgets('Add Product requires a location and shows zero stock there',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store();
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Product'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Product name'), 'New Mixer');
    await tester.tap(find.text('Save Product'));
    await tester.pumpAndSettle();
    expect(find.text('Choose where the product is stored.'), findsOneWidget);
    expect(store.addedLocation, isNull);
    await tester.tap(
        find.byKey(const ValueKey('Where is the product stored? (required)')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH TNHB').last);
    await tester.pumpAndSettle();
    final categories = find.byTooltip('Category suggestions');
    await tester.ensureVisible(categories);
    await tester.tap(categories);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cookware').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save Product'));
    await tester.pumpAndSettle();
    expect(store.addedLocation, 'tnhb');
    expect(store.addedCategory, 'Cookware');
    await tester.tap(find.text('Physical Stocks'));
    await tester.pumpAndSettle();
    expect(find.text('New Mixer'), findsOneWidget);
    expect(find.text('SSH TNHB'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
  });

  test('all movement types use per-location totals without a history cap', () {
    _Row movement(
            String id, String type, String location, int units, int delta) =>
        _Row(id, {
          'productId': 'p',
          'location': location,
          'type': type,
          'quantity': units,
          'delta': delta
        });
    final source = (
      products: <InventoryRow>[
        _Row('p', {'name': 'Mixer', 'unitCost': 2599})
      ],
      balances: <InventoryRow>[
        _Row('b', {
          'productId': 'p',
          'location': 'warehouse',
          'quantity': 5,
        })
      ],
      movements: <InventoryRow>[
        for (var i = 0; i < 501; i++)
          movement('sale$i', 'sale', 'warehouse', 2, -2),
        for (final type
            in inventoryMovementLabels.keys.where((type) => type != 'sale'))
          movement(type, type, 'tnhb', 3, type == 'count' ? -3 : 3),
        movement('adjustment2', 'adjustment', 'tnhb', -3, -3),
      ],
    );
    final report = buildInventoryReport(source,
        locations: inventoryLocations, matches: (_) => true);
    final headings = report.headings;
    expect(headings.length, 6 + inventoryMovementLabels.length - 2);
    expect(headings, isNot(contains('Opening stock')));
    expect(headings, isNot(contains('Physical count')));
    final warehouse =
        report.rows.firstWhere((row) => row[1] == 'SSH Warehouse');
    final tnhb = report.rows.firstWhere((row) => row[1] == 'SSH TNHB');
    expect(warehouse[headings.indexOf('Stock out')], 1002);
    expect(warehouse[headings.indexOf('Damaged')], 0);
    expect(tnhb[headings.indexOf('Damaged')], 3);
    expect(tnhb[headings.indexOf('Adjustment')], 0);
    expect(tnhb[headings.indexOf('Total Stock')], '');
    final filtered = buildInventoryReport(source,
        locations: inventoryLocations,
        matches: (fields) => fields.contains('SSH Warehouse'));
    expect(filtered.headings.skip(6), ['Stock out']);
  });

  testWidgets(
      'Reports show a single damage entry and hide empty movement types',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: InventoryWidgetScreen(
            store: _Store(withStock: true, withDamage: true))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Damaged'), findsOneWidget);
    expect(find.text('Total Stock'), findsOneWidget);
    expect(find.text('In hand'), findsNothing);
    expect(find.text('Stock out'), findsNothing);
    final table = tester.widget<DataTable>(find.byType(DataTable));
    expect(table.rows.length, 2);
    final damage = table.columns.indexWhere((column) =>
        column.label is Text && (column.label as Text).data == 'Damaged');
    String? value(DataRow row) =>
        ((row.cells[damage].child as Center).child as Text).data;
    expect(value(table.rows.first), '3'); // Same product, locations A–Z.
    expect(value(table.rows.last), '0');
    await tester.tap(find.text('All locations'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH Warehouse').last);
    await tester.pumpAndSettle();
    expect(find.text('Damaged'), findsNothing);
    expect(find.text('Physical count'), findsNothing);
  });

  testWidgets(
      'product lists, report and movement picker use case-insensitive A–Z',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true)
      ..addedName = 'apple kettle'
      ..addedLocation = 'warehouse';
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    void checkOrder() {
      expect(tester.getCenter(find.text('apple kettle').first).dy,
          lessThan(tester.getCenter(find.text('Cookware Fixture').first).dy));
    }

    checkOrder(); // Physical Stocks.
    await tester.tap(find.text('Record Movement'));
    await tester.pumpAndSettle();
    final picker = tester.widget<DropdownButton<String>>(find.descendant(
        of: find.byKey(const ValueKey('Product')),
        matching: find.byType(DropdownButton<String>)));
    expect(picker.items!.map((item) => (item.child as Text).data),
        ['Not selected', 'apple kettle', 'Cookware Fixture']);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    for (final section in ['Products', 'Overview', 'Reports']) {
      await tester.tap(find.text(section).first);
      await tester.pumpAndSettle();
      checkOrder();
    }
  });

  testWidgets('tables align headers and cells in every inventory section',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true);
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();

    void checkTables() {
      final tables =
          tester.widgetList<DataTable>(find.byType(DataTable)).toList();
      expect(tables, isNotEmpty);
      for (final table in tables) {
        expect(table.headingTextStyle?.fontSize, 13);
        expect(table.dataTextStyle?.fontSize, 14);
        expect(table.rows, isNotEmpty);
        for (final (index, column) in table.columns.indexed) {
          final label = column.label is Flexible
              ? (column.label as Flexible).child
              : column.label;
          expect((label as Text).textAlign, TextAlign.center);
          final position = tester.getCenter(find.byWidget(label)).dx;
          final cell = table.rows.first.cells[index].child as Center;
          expect(
              tester.getCenter(find.byWidget(cell)).dx, closeTo(position, 1));
          if (cell.child case final Text text) {
            expect(text.textAlign, TextAlign.center);
          }
        }
      }
    }

    checkTables(); // Physical Stocks is the starting view.
    for (final section in [
      'Overview',
      'History',
      'Transfers',
      'Reports',
      'Locations',
      'Suppliers',
      'Purchase',
      'Products',
    ]) {
      await tester.tap(find.text(section).first);
      await tester.pumpAndSettle();
      checkTables();
    }
    store.recycled = true;
    await tester.tap(find.text('Recycle Bin'));
    await tester.pumpAndSettle();
    checkTables();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'product tables fill the desktop width and center headers over values',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(2200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: InventoryWidgetScreen(store: _Store(withStock: true))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('inventory-view-search'));
    expect(tester.getSize(find.byType(DataTable).first).width,
        closeTo(tester.getSize(search).width, 1));
    await tester.tap(find.text('Products').first);
    await tester.pumpAndSettle();
    final table = find.byType(DataTable);
    expect(
        tester.getSize(table).width, closeTo(tester.getSize(search).width, 1));
    expect(tester.getCenter(find.text('Tracked stock')).dx,
        closeTo(tester.getCenter(find.text('1')).dx, 1));
    expect(tester.getCenter(find.text('Category')).dx,
        closeTo(tester.getCenter(find.text('Cookware')).dx, 1));
    expect(
        tester.getCenter(find.text('Actions')).dx,
        closeTo(
            (tester
                        .getCenter(
                            find.byTooltip('Edit details for Cookware Fixture'))
                        .dx +
                    tester
                        .getCenter(find.byTooltip('Delete Cookware Fixture'))
                        .dx) /
                2,
            1));
    await tester.binding.setSurfaceSize(const Size(590, 900));
    await tester.pumpAndSettle();
    expect(tester.getSize(table).width, 876);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'movement filters share a desktop row and stock cells stay centered',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1800, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true);
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit stock for Cookware Fixture'), findsNothing);
    await tester.tap(find.byTooltip('Edit details for Cookware Fixture'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Product'), findsOneWidget);
    expect(find.text('Barcode (optional)'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Physical Stocks'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Edit details for Cookware Fixture'), findsNothing);
    final editStock = find.widgetWithText(OutlinedButton, 'Edit stock');
    expect(editStock, findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Add stock in new location'),
        findsOneWidget);
    final physicalSearch = find.byKey(const ValueKey('inventory-view-search'));
    final contentWidth = tester.getSize(physicalSearch).width;
    expect(
        tester.getSize(find.byType(DataTable)).width, closeTo(contentWidth, 1));
    expect(tester.getCenter(find.text('Balance stock')).dx,
        closeTo(tester.getCenter(find.text('1')).dx, 1));
    expect(find.text('1'), findsOneWidget);
    expect(find.text('1.00'), findsNothing);
    await tester.tap(editStock);
    await tester.pumpAndSettle();
    expect(find.text('Location: SSH Warehouse'), findsOneWidget);
    final quantity = find.widgetWithText(TextField, 'New quantity in hand');
    expect(tester.widget<TextField>(quantity).controller!.text, '1');
    await tester.enterText(quantity, '9');
    await tester.tap(find.text('Save Stock'));
    await tester.pumpAndSettle();
    expect(store.posted?.location, 'warehouse');
    expect(store.posted?.quantity, 9);

    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Record Movement'), findsNothing);
    final search = find.byKey(const ValueKey('inventory-view-search'));
    final type = find.text('All types');
    final date = find.text('Any date');
    expect(tester.getCenter(search).dy, closeTo(tester.getCenter(type).dy, 12));
    expect(tester.getCenter(search).dy, closeTo(tester.getCenter(date).dy, 12));
    expect(
        tester.getTopLeft(type).dx, greaterThan(tester.getTopRight(search).dx));
    expect(tester.getTopLeft(date).dx, greaterThan(tester.getTopLeft(type).dx));
    final historyTable = find.byType(DataTable).first;
    expect(tester.getSize(historyTable).width, closeTo(contentWidth, 1));
    expect(tester.getCenter(find.text('Movement')).dx,
        closeTo(tester.getCenter(find.text('Physical count')).dx, 1));
    expect(tester.getCenter(find.text('Balance')).dx,
        closeTo(tester.getCenter(find.text('1')).dx, 1));

    await tester.binding.setSurfaceSize(const Size(590, 900));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(type).dy,
        greaterThan(tester.getBottomLeft(search).dy));
    expect(tester.getSize(historyTable).width, 884);
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
    await tester.tap(find.text('Overview'));
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
    await tester.tap(find.text('Physical Stocks'));
    await tester.pumpAndSettle();
    expect(find.text('Balance stock'), findsOneWidget);
    expect(find.text('Set Total Stock'), findsNothing);
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

    await tester.tap(find.byTooltip('Edit stock for Cookware Fixture'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'New quantity in hand'), '100');
    await tester.tap(find.text('Save Stock'));
    await tester.pumpAndSettle();
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
      ('Physical Stocks', 'warehouse', 'Cookware Fixture'),
      ('History', 'awaiting invoice', 'Resume'),
      ('Reports', 'warehouse', 'Cookware Fixture'),
      ('Locations', 'selvan hotel', 'Selvan Hotel Mart'),
    ]) {
      await tester.tap(find.text(section).first);
      await tester.pumpAndSettle();
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

  testWidgets(
      'transfer asks once and stays on Physical Stock after confirmation',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store();
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Record Movement'), findsOneWidget);
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
      'Physical Stocks opens first and edits stock at a chosen location',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true);
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    expect(find.text('Record Movement'), findsOneWidget);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(find.text('Cookware Fixture'), findsWidgets);
    expect(find.text('Record Movement'), findsNothing);
    expect(find.text('Actions'), findsNothing);
    await tester.tap(find.text('Physical Stocks'));
    await tester.pumpAndSettle();
    await tester
        .tap(find.widgetWithText(FilledButton, 'Add stock in new location'));
    await tester.pumpAndSettle();
    expect(find.text('Edit Stock'), findsOneWidget);
    await tester.tap(find.text('Not selected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SSH Warehouse').last);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'New quantity in hand'), '7');
    await tester.tap(find.text('Save Stock'));
    await tester.pumpAndSettle();
    expect(store.posted?.productId, 'p1');
    expect(store.posted?.location, 'warehouse');
    expect(store.posted?.quantity, 7);
    expect(store.posted?.type, 'count');
    expect(tester.takeException(), isNull);
  });

  testWidgets('products can be recycled and restored without changing stock',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = _Store(withStock: true);
    await tester
        .pumpWidget(MaterialApp(home: InventoryWidgetScreen(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete Cookware Fixture'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to Recycle Bin'));
    await tester.pumpAndSettle();
    expect(store.recycled, isTrue);
    expect(find.text('Cookware Fixture'), findsNothing);
    await tester.tap(find.text('Physical Stocks'));
    await tester.pumpAndSettle();
    expect(find.text('Cookware Fixture'), findsNothing);
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recycle Bin'));
    await tester.pumpAndSettle();
    expect(find.text('Cookware Fixture'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore Product'));
    await tester.pumpAndSettle();
    expect(store.recycled, isFalse);
    expect(find.text('Cookware Fixture'), findsNothing);
    await tester.tap(find.text('Physical Stocks'));
    await tester.pumpAndSettle();
    expect(find.text('Cookware Fixture'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(store.posted, isNull);
  });
}
