import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'services/inventory_store.dart';

class InventoryWidgetScreen extends StatefulWidget {
  const InventoryWidgetScreen({super.key, this.store});

  final InventoryStore? store;

  @override
  State<InventoryWidgetScreen> createState() => _InventoryWidgetScreenState();
}

class _InventoryWidgetScreenState extends State<InventoryWidgetScreen> {
  late final InventoryStore _store = widget.store ?? InventoryStore();
  late Future<List<InventoryRows>> _data;
  var _section = 'Overview';
  String? _location;
  var _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _data = Future.wait([
      _store.products(),
      if (_section == 'Overview' || _section == 'Products')
        _store.balances(location: _location),
      if (_section == 'Stock Movements') ...[
        _store.movements(location: _location),
        _store.drafts(location: _location),
      ],
    ]);
  }

  void _refresh() {
    if (mounted) setState(_load);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Inventory System'),
          actions: [
            IconButton(
              tooltip: 'Refresh inventory',
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final section in [
                  'Overview',
                  'Products',
                  'Stock Movements'
                ])
                  ChoiceChip(
                    label: Text(section),
                    selected: _section == section,
                    onSelected: (_) {
                      if (_section == section) return;
                      setState(() {
                        _section = section;
                        _query = '';
                        _load();
                      });
                    },
                  ),
                SizedBox(
                  width: 225,
                  child: DropdownButtonFormField<String>(
                    initialValue: _location,
                    decoration:
                        const InputDecoration(labelText: 'Stock location'),
                    items: [
                      const DropdownMenuItem<String>(
                          child: Text('All locations')),
                      for (final location in inventoryLocations.entries)
                        DropdownMenuItem(
                            value: location.key, child: Text(location.value)),
                    ],
                    onChanged: (value) => setState(() {
                      _location = value;
                      _load();
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FutureBuilder<List<InventoryRows>>(
              future: _data,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError || !snapshot.hasData) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                          'Inventory could not be loaded. Check your connection and admin access.'),
                      TextButton(
                          onPressed: _refresh, child: const Text('Try again')),
                    ],
                  );
                }
                return _content(snapshot.requireData);
              },
            ),
          ],
        ),
      );

  Widget _content(List<InventoryRows> data) {
    final products = data.first;
    final rows = data[1];
    final byProduct = {for (final p in products.docs) p.id: p.data()};
    String productName(String? id) =>
        (byProduct[id]?['name'] as String?)?.trim().isNotEmpty == true
            ? byProduct[id]!['name'] as String
            : id == null || id.isEmpty
                ? '—'
                : 'Unnamed product';
    String locationName(Object? id) => inventoryLocations[id] ?? '—';
    final title = _section == 'Overview' ? 'Inventory Overview' : _section;
    final action = _section == 'Products'
        ? FilledButton(onPressed: _product, child: const Text('Add Product'))
        : FilledButton(
            onPressed: () => _movement(products.docs),
            child: const Text('Record Movement'),
          );
    final visibleRows = rows.docs.take(100).toList();
    final stock = <String, int>{};
    if (_section != 'Stock Movements') {
      for (final row in visibleRows) {
        final item = row.data();
        final id = item['productId'] as String;
        stock.update(id, (q) => q + (item['quantity'] as int),
            ifAbsent: () => item['quantity'] as int);
      }
    }
    final low = visibleRows.where((row) {
      final p = byProduct[row.data()['productId']];
      final reorder = p?['reorder'] as int?;
      return _section != 'Stock Movements' &&
          p?['active'] == true &&
          reorder != null &&
          (row.data()['quantity'] as int) < reorder;
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            action
          ],
        ),
        const SizedBox(height: 14),
        if (_section == 'Overview') ...[
          Text(
              '${products.docs.take(100).length} products shown · ${stock.values.fold<int>(0, (a, b) => a + b)} units in the balances shown'),
          const SizedBox(height: 14),
          Text('Low stock', style: Theme.of(context).textTheme.titleMedium),
          _table([
            'Product',
            'Location',
            'On hand',
            'Reorder at'
          ], [
            for (final row in low)
              [
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                '${row.data()['quantity']}',
                '${byProduct[row.data()['productId']]?['reorder']}'
              ],
          ]),
        ],
        if (_section == 'Products') ...[
          TextFormField(
            initialValue: _query,
            decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Search displayed products by name or SKU'),
            onChanged: (value) => setState(() => _query = value),
          ),
          _table([
            'SKU',
            'Product',
            'Category',
            'Tracked stock',
            'Status',
            ''
          ], [
            for (final row in products.docs.take(100))
              if (['name', 'sku'].any((key) => '${row.data()[key] ?? ''}'
                  .toLowerCase()
                  .contains(_query.toLowerCase().trim())))
                [
                  '${row.data()['sku'] ?? ''}',
                  productName(row.id),
                  '${row.data()['category'] ?? ''}',
                  '${stock[row.id] ?? '—'}',
                  row.data()['active'] == true ? 'Active' : 'Archived',
                  TextButton(
                      onPressed: () => _product(row),
                      child: const Text('Edit')),
                ],
          ]),
        ],
        if (_section == 'Stock Movements') ...[
          _table([
            'When',
            'Product',
            'Location',
            'Movement',
            'Change',
            'Balance'
          ], [
            for (final row in visibleRows)
              [
                _time(row.data()['at']),
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                inventoryMovementTypes[row.data()['type']] ?? '—',
                '${row.data()['delta']}',
                '${row.data()['quantityAfter']}',
              ],
          ]),
          const SizedBox(height: 14),
          Text('Drafts', style: Theme.of(context).textTheme.titleMedium),
          _table([
            'Product',
            'Location',
            'Quantity',
            ''
          ], [
            for (final row in data[2].docs.take(100))
              [
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                '${row.data()['quantity'] ?? '—'}',
                TextButton(
                    onPressed: () => _movement(products.docs, row),
                    child: const Text('Resume')),
              ],
          ]),
        ],
        if (data.any((query) => query.size > 100))
          const Text(
              'Showing the first 100 records in each list. Choose a location to narrow stock results.'),
      ],
    );
  }

  String _time(Object? time) {
    if (time is! Timestamp) return '—';
    final dt = time.toDate().toLocal();
    return '${MaterialLocalizations.of(context).formatShortDate(dt)} '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
  }

  Widget _table(List<String> headings, List<List<Object>> rows) {
    if (rows.isEmpty)
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Text('No records to show.'));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: headings.map((text) => DataColumn(label: Text(text))).toList(),
        rows: rows
            .map((row) => DataRow(
                cells: row
                    .map((cell) =>
                        DataCell(cell is Widget ? cell : Text(cell.toString())))
                    .toList()))
            .toList(),
      ),
    );
  }

  Future<void> _product([InventoryRow? row]) async {
    final values = row?.data() ?? {};
    final name = TextEditingController(text: values['name'] as String?);
    final sku = TextEditingController(text: values['sku'] as String?);
    final category = TextEditingController(text: values['category'] as String?);
    final reorder = TextEditingController(text: values['reorder']?.toString());
    var active = values['active'] != false;
    final result = await _editor(
      title: row == null ? 'Add Product' : 'Edit Product',
      fields: (update) => [
        _input(name, 'Product name'),
        _input(sku, 'SKU'),
        _input(category, 'Category'),
        _input(reorder, 'Reorder level', number: true),
        SwitchListTile(
            title: const Text('Active'),
            value: active,
            onChanged: (v) => update(() => active = v)),
      ],
      action: 'Save Product',
      save: () => _store.saveProduct(
          id: row?.id,
          name: name.text,
          sku: sku.text,
          category: category.text,
          reorder: _optionalInt(reorder.text),
          active: active),
    );
    for (final controller in [name, sku, category, reorder]) {
      controller.dispose();
    }
    if (result) _refresh();
  }

  Future<void> _movement(List<InventoryRow> products,
      [InventoryRow? draft]) async {
    final values = draft?.data() ?? {};
    var location = (values['location'] as String?) ?? _location;
    if (!inventoryLocations.containsKey(location)) location = null;
    var product = values['productId'] as String?;
    if (!products.take(100).any((p) => p.id == product)) product = null;
    var type = values['type'] as String?;
    if (!inventoryMovementTypes.containsKey(type)) type = null;
    final quantity =
        TextEditingController(text: values['quantity']?.toString());
    final note = TextEditingController(text: values['note'] as String?);
    InventoryMovement input() => InventoryMovement(
        type: type,
        productId: product,
        location: location,
        quantity: _optionalInt(quantity.text),
        note: note.text);
    final movementId = _store.newMovementId();
    final draftId = draft?.id ?? _store.newDraftId();
    final result = await _editor(
      title: 'Record Movement',
      fields: (update) => [
        _select('Movement type', type, inventoryMovementTypes,
            (v) => update(() => type = v)),
        _select('Where is the stock kept?', location, inventoryLocations,
            (v) => update(() => location = v)),
        _select(
            'Product',
            product,
            {
              for (final p in products.take(100))
                p.id: '${p.data()['name']}'.trim().isEmpty
                    ? 'Unnamed product'
                    : '${p.data()['name']}'
            },
            (v) => update(() => product = v)),
        _input(quantity, 'Quantity', number: true),
        _input(note, 'Note'),
      ],
      action: 'Post Movement',
      save: () =>
          _store.post(input(), movementId: movementId, draftId: draft?.id),
      saveDraft: () => _store.saveDraft(input(), id: draftId),
    );
    quantity.dispose();
    note.dispose();
    if (result) _refresh();
  }

  int? _optionalInt(String raw) {
    if (raw.trim().isEmpty) return null;
    return int.tryParse(raw.trim()) ??
        (throw const FormatException('Enter a whole number.'));
  }

  Widget _input(TextEditingController controller, String label,
          {bool number = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
            controller: controller,
            maxLength: number ? 9 : 160,
            keyboardType: number
                ? const TextInputType.numberWithOptions(signed: true)
                : null,
            decoration: InputDecoration(labelText: label, counterText: '')),
      );

  Widget _select(String label, String? selected, Map<String, String> options,
          ValueChanged<String?> changed) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: selected,
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem<String>(child: Text('Not selected')),
            ...options.entries.map((entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value))),
          ],
          onChanged: changed,
        ),
      );

  Future<bool> _editor({
    required String title,
    required List<Widget> Function(StateSetter) fields,
    required String action,
    required Future<void> Function() save,
    Future<void> Function()? saveDraft,
  }) async {
    var busy = false;
    String? error;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(builder: (dialog, update) {
        Future<void> submit(Future<void> Function() task) async {
          update(() {
            busy = true;
            error = null;
          });
          try {
            await task();
            if (dialog.mounted) Navigator.of(dialog).pop(true);
          } catch (e) {
            if (dialog.mounted)
              update(() {
                busy = false;
                error = e is FormatException
                    ? e.message
                    : 'Could not save. Check your connection and admin access.';
              });
          }
        }

        return PopScope(
          canPop: !busy,
          child: AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (saveDraft != null)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: Text('Fields are optional for drafts.')),
                    ...fields(update),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(dialog).colorScheme.error)),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.of(dialog).pop(),
                  child: const Text('Cancel')),
              if (saveDraft != null)
                OutlinedButton(
                    onPressed: busy ? null : () => submit(saveDraft),
                    child: const Text('Save Draft')),
              FilledButton(
                  onPressed: busy ? null : () => submit(save),
                  child: Text(busy ? 'Saving…' : action)),
            ],
          ),
        );
      }),
    );
    return result == true;
  }
}
