part of 'inventory_widget.dart';

const _orderStatus = {
  'ordered': 'Ordered',
  'partial': 'Partly received',
  'received': 'Received',
  'cancelled': 'Cancelled'
};
const _transferStatus = {'in_transit': 'In transit', 'received': 'Received'};

class _PurchaseInputs {
  _PurchaseInputs(this.id);
  final String id;
  final quantity = TextEditingController(), cost = TextEditingController();
  String? product;
  void dispose() {
    quantity.dispose();
    cost.dispose();
  }
}

extension _InventorySupplyViews on _InventoryWidgetScreenState {
  Widget _productBinContent(BuildContext context, InventoryRows data) =>
      _supplyPage(
        context,
        'Product Recycle Bin',
        'Back to Products',
        () => _showProductBin(false),
        'Restore a product to make its existing stock available again. Products are not permanently deleted here.',
        ['Product', 'SKU', 'Barcode', 'Category', 'Deleted', 'Actions'],
        [
          for (final row in data.docs.take(100))
            if (row.data()['deletedAt'] != null &&
                _matchesSearch([
                  _supplyName(row),
                  row.data()['sku'],
                  row.data()['barcode'],
                  row.data()['category'],
                ]))
              [
                _supplyName(row),
                row.data()['sku'] ?? '',
                row.data()['barcode'] ?? '',
                row.data()['category'] ?? '',
                _time(row.data()['deletedAt']),
                TextButton(
                  onPressed: () => _setProductRecycled(row, recycled: false),
                  child: const Text('Restore'),
                ),
              ],
        ],
        truncated: data.size > 100,
      );

  Widget _supplyPage(
          BuildContext context,
          String title,
          String action,
          VoidCallback onAction,
          String note,
          List<String> columns,
          List<List<Object>> rows,
          {bool truncated = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _pageHeading(
              title, FilledButton(onPressed: onAction, child: Text(action))),
          const SizedBox(height: 14),
          _viewSearch(),
          Text(note),
          const SizedBox(height: 12),
          _table(columns, _sortSupplyProductRows(columns, rows)),
          if (truncated) const Text('Showing the first 100 records.'),
        ],
      );

  List<List<Object>> _sortSupplyProductRows(
      List<String> columns, List<List<Object>> rows) {
    final productColumn = columns.indexOf('Product');
    if (productColumn < 0) return rows;
    final sorted = rows.indexed.toList()
      ..sort((a, b) {
        final nameOrder = compareInventoryLabels(
            a.$2[productColumn].toString(), b.$2[productColumn].toString());
        return nameOrder != 0 ? nameOrder : a.$1.compareTo(b.$1);
      });
    return [for (final (_, row) in sorted) row];
  }

  String _supplyLocation(Object? id) {
    for (final location in _locations) {
      if (location.id == id) return location.name;
    }
    return id?.toString() ?? '—';
  }

  String _supplyName(InventoryRow row) {
    return inventoryProductName(row.data()['name']);
  }

  Map<String, String> _supplyChoices(InventoryRows rows,
          {bool products = false, String? include}) =>
      {
        for (final row
            in products ? inventoryProductsByName(rows.docs) : rows.docs)
          if (row.data()['active'] == true || row.id == include)
            row.id: products ? _supplyName(row) : row.data()['name'] as String,
      };

  Widget _suppliersContent(BuildContext context, InventoryRows suppliers) =>
      _supplyPage(
        context,
        'Suppliers',
        'Add Supplier',
        () => _editSupplier(),
        'Archive suppliers to hide them from new orders without losing their history.',
        ['Supplier', 'Phone', 'Email', 'Notes', 'Status', 'Actions'],
        [
          for (final row in suppliers.docs.take(100))
            if (_matchesSearch(row.data().values))
              [
                row.data()['name'] as String,
                row.data()['phone'] as String,
                row.data()['email'] as String,
                row.data()['notes'] as String,
                row.data()['active'] == true ? 'Active' : 'Archived',
                TextButton(
                    onPressed: () => _editSupplier(row),
                    child: const Text('Edit')),
              ],
        ],
        truncated: suppliers.size > 100,
      );

  Future<void> _editSupplier([InventoryRow? row]) async {
    final data = row?.data() ?? {};
    final name = TextEditingController(text: data['name'] as String?);
    final phone = TextEditingController(text: data['phone'] as String?);
    final email = TextEditingController(text: data['email'] as String?);
    final notes = TextEditingController(text: data['notes'] as String?);
    var active = data['active'] != false;
    final saved = await _editor(
        title: row == null ? 'Add Supplier' : 'Edit Supplier',
        fields: (update) => [
              _input(name, 'Supplier name'),
              _input(phone, 'Phone'),
              _input(email, 'Email'),
              _input(notes, 'Notes'),
              SwitchListTile(
                  title: const Text('Active'),
                  value: active,
                  onChanged: (value) => update(() => active = value)),
            ],
        action: 'Save Supplier',
        save: () => _store.saveSupplier(
            id: row?.id,
            name: name.text,
            phone: phone.text,
            email: email.text,
            notes: notes.text,
            active: active));
    for (final controller in [name, phone, email, notes]) {
      controller.dispose();
    }
    if (saved) _refresh();
  }

  Widget _purchasingContent(BuildContext context, List<InventoryRows> data) {
    final products = {for (final row in data[0].docs) row.id: _supplyName(row)};
    final suppliers = {
      for (final row in data[2].docs) row.id: row.data()['name'] as String
    };
    return _supplyPage(
      context,
      inventoryPurchaseSection,
      'New Purchase Order',
      () => _newOrder(data[0], data[2]),
      'Group products under one order reference. Receive or cancel each line separately; only received units enter stock.',
      [
        'Reference',
        'Supplier',
        'Product',
        'Branch',
        'Ordered',
        'Received',
        'Unit cost INR',
        'Status',
        'Actions'
      ],
      [
        for (final row in data[1].docs.take(100))
          if ((_location == null || row.data()['location'] == _location) &&
              _matchesSearch([
                row.data()['reference'],
                suppliers[row.data()['supplierId']],
                products[row.data()['productId']],
                _supplyLocation(row.data()['location']),
                _orderStatus[row.data()['status']],
              ]))
            [
              row.data()['reference'] as String,
              suppliers[row.data()['supplierId']] ?? '—',
              products[row.data()['productId']] ?? '—',
              _supplyLocation(row.data()['location']),
              row.data()['quantity'] as int,
              row.data()['received'] as int,
              inventoryRupees(row.data()['unitCost'] as int?),
              _orderStatus[row.data()['status']] ?? '—',
              if (['ordered', 'partial'].contains(row.data()['status']))
                Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(
                      onPressed: () => _receiveOrder(row),
                      child: const Text('Receive')),
                  TextButton(
                      onPressed: () => _cancelOrder(row),
                      child: const Text('Cancel remainder')),
                ])
              else
                const SizedBox.shrink(),
            ],
      ],
      truncated: data[1].size > 100,
    );
  }

  Future<void> _newOrder(
      InventoryRows products, InventoryRows suppliers) async {
    final reference = TextEditingController();
    final lines = [_PurchaseInputs(_store.newPurchaseOrderId())];
    final controllers = [...lines];
    final byProduct = {for (final row in products.docs) row.id: row.data()};
    final supplierOptions = _supplyChoices(suppliers);
    final productOptions = _supplyChoices(products, products: true);
    String? supplier, location = _location;
    final saved = await _editor(
        title: 'New Purchase Order',
        fields: (update) => [
              if (supplierOptions.isEmpty)
                const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                        'Add an active supplier from the Suppliers menu first.')),
              _select('Supplier', supplier, supplierOptions,
                  (value) => update(() => supplier = value),
                  resetKey: supplier),
              _select('Receiving branch', location, _activeLocations,
                  (value) => update(() => location = value)),
              _input(
                  reference, 'Purchase order or invoice reference (optional)'),
              for (final (index, line) in lines.indexed)
                Column(
                  key: ValueKey(line.id),
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(),
                    if (lines.length > 1)
                      TextButton(
                          onPressed: () => update(() => lines.remove(line)),
                          child: Text('Remove item ${index + 1}')),
                    _select(
                        'Product ${index + 1}',
                        line.product,
                        productOptions,
                        (value) => update(() {
                              line.product = value;
                              final preferred =
                                  byProduct[value]?['supplierId'] as String?;
                              if (supplier == null &&
                                  supplierOptions.containsKey(preferred))
                                supplier = preferred;
                              line.cost.text = inventoryRupees(
                                  byProduct[value]?['unitCost'] as int?);
                            })),
                    _input(line.quantity, 'Quantity ordered', number: true),
                    _input(line.cost, 'Unit cost in rupees (optional)'),
                  ],
                ),
              if (lines.length < 5)
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add another product'),
                  onPressed: () => update(() {
                    final line = _PurchaseInputs(_store.newPurchaseOrderId());
                    lines.add(line);
                    controllers.add(line);
                  }),
                ),
            ],
        action: 'Place Order',
        save: () => _store.createPurchaseOrder(
            supplier: supplier,
            location: location,
            lines: [
              for (final line in lines)
                InventoryPurchaseLine(
                    line.id,
                    line.product,
                    _optionalInt(line.quantity.text),
                    inventoryCostPaise(line.cost.text))
            ],
            reference: reference.text));
    reference.dispose();
    for (final line in controllers) {
      line.dispose();
    }
    if (saved) _refresh();
  }

  Future<void> _receiveOrder(InventoryRow row) async {
    final remaining =
        (row.data()['quantity'] as int) - (row.data()['received'] as int);
    final units = TextEditingController(text: remaining.toString());
    final movement = _store.newMovementId();
    final saved = await _editor(
        title: 'Receive Purchase Order',
        fields: (_) => [
              Text(
                  '$remaining units remain. Received units will be added to ${_supplyLocation(row.data()['location'])}.'),
              const SizedBox(height: 10),
              _input(units, 'Quantity received', number: true),
            ],
        action: 'Confirm Receipt',
        save: () => _store.receivePurchase(
            id: row.id,
            receiptId: movement,
            quantity: _optionalInt(units.text)));
    units.dispose();
    if (saved) _refresh();
  }

  Future<void> _cancelOrder(InventoryRow row) async {
    final saved = await _editor(
        title: 'Cancel Unreceived Quantity',
        fields: (_) => [
              const Text(
                  'Units already received will stay in stock. The remaining order will be closed.'),
            ],
        action: 'Cancel Remainder',
        save: () => _store.cancelPurchaseOrder(row.id));
    if (saved) _refresh();
  }

  Widget _transfersContent(BuildContext context, List<InventoryRows> data) {
    final products = {for (final row in data[0].docs) row.id: _supplyName(row)};
    return _supplyPage(
      context,
      'Transfers',
      'New Transfer',
      () => _movement(data[0].docs, stockType: 'transfer'),
      'New transfers update both branches after one confirmation. Older pending transfers can be reviewed in History.',
      [
        'Product',
        'From',
        'To',
        'Quantity',
        'Status',
        'Dispatched',
        'Received',
      ],
      [
        for (final row in data[1].docs.take(100))
          if ((_location == null ||
                  row.data()['from'] == _location ||
                  row.data()['to'] == _location) &&
              _matchesSearch([
                products[row.data()['productId']],
                _supplyLocation(row.data()['from']),
                _supplyLocation(row.data()['to']),
                _transferStatus[row.data()['status']],
              ]))
            [
              products[row.data()['productId']] ?? '—',
              _supplyLocation(row.data()['from']),
              _supplyLocation(row.data()['to']),
              row.data()['quantity'] as int,
              _transferStatus[row.data()['status']] ?? '—',
              _time(row.data()['at']),
              _time(row.data()['receivedAt']),
            ],
      ],
      truncated: data[1].size > 100,
    );
  }

  Widget _olderTransferActions(BuildContext context, InventoryRows transfers,
      Map<String, InventoryRow> products) {
    final rows = <List<Object>>[];
    for (final row in transfers.docs.take(100)) {
      final data = row.data();
      final product = products[data['productId']];
      final name = product == null ? 'Unknown product' : _supplyName(product);
      final from = _supplyLocation(data['from']);
      final to = _supplyLocation(data['to']);
      if ((_location == null ||
              data['from'] == _location ||
              data['to'] == _location) &&
          _matchesSearch([name, from, to, 'In transit'])) {
        rows.add([
          name,
          from,
          to,
          data['quantity'] as int,
          TextButton(
              onPressed: () => _finishOlderTransfer(row),
              child: const Text('Finish older transfer'))
        ]);
      }
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Older transfers still in transit',
          style: Theme.of(context).textTheme.titleMedium),
      const Text(
          'The source was already debited. Complete an older transfer only once its stock has arrived.'),
      _table(['Product', 'From', 'To', 'Quantity', 'Actions'], rows,
          centeredWidths: const [190, 174, 174, 112, 184]),
    ]);
  }

  Future<void> _finishOlderTransfer(InventoryRow row) async {
    final movement = _store.newMovementId();
    final saved = await _editor(
        title: 'Finish older transfer',
        fields: (_) => [
              Text(
                  'Add ${row.data()['quantity']} units to ${_supplyLocation(row.data()['to'])}? The source will not be debited again.'),
            ],
        action: 'Confirm Arrival',
        save: () => _store.receiveTransfer(row.id, movement));
    if (saved) _refresh();
  }
}
