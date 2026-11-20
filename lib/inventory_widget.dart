import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'inventory_workspace.dart';
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
  var _dark = false;
  var _themeChanged = false;
  String? _movementType;
  DateTimeRange? _movementDates;
  static const _themeKey = 'inventory_workspace_theme';
  static const _storage = FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(_loadTheme());
  }

  Future<void> _loadTheme() async {
    try {
      final saved = await _storage.read(key: _themeKey);
      if (mounted && !_themeChanged && saved != null) {
        setState(() => _dark = saved == 'dark');
      }
    } catch (_) {
      // The workspace still supports in-session switching.
    }
  }

  Future<void> _saveTheme(bool dark) async {
    try {
      await _storage.write(key: _themeKey, value: dark ? 'dark' : 'light');
    } catch (_) {
      // A local storage failure should not prevent switching themes.
    }
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
  Widget build(BuildContext context) => InventoryWorkspace(
        dark: _dark,
        section: _section,
        location: _location,
        onRefresh: _refresh,
        onTheme: () {
          setState(() {
            _themeChanged = true;
            _dark = !_dark;
          });
          unawaited(_saveTheme(_dark));
        },
        onSection: (section) {
          if (_section == section) return;
          setState(() {
            _section = section;
            _query = '';
            _load();
          });
        },
        onLocation: (value) {
          if (_location == value) return;
          setState(() {
            _location = value;
            _load();
          });
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 26),
          children: [
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
                return _content(context, snapshot.requireData);
              },
            ),
          ],
        ),
      );

  Widget _content(BuildContext context, List<InventoryRows> data) {
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
        LayoutBuilder(builder: (context, limits) {
          final headline =
              Text(title, style: Theme.of(context).textTheme.headlineSmall);
          if (limits.maxWidth < 420) {
            return Wrap(
                spacing: 16,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [headline, action]);
          }
          return Row(children: [
            Expanded(child: headline),
            const SizedBox(width: 12),
            action
          ]);
        }),
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
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _movementType ?? '',
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('All types')),
                    for (final entry in inventoryMovementTypes.entries)
                      DropdownMenuItem(
                          value: entry.key, child: Text(entry.value)),
                  ],
                  onChanged: (value) => setState(
                      () => _movementType = value == '' ? null : value),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _pickDates(context),
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_movementDates == null
                    ? 'Any date'
                    : '${MaterialLocalizations.of(context).formatCompactDate(_movementDates!.start)} – ${MaterialLocalizations.of(context).formatCompactDate(_movementDates!.end)}'),
              ),
              if (_movementDates != null)
                TextButton(
                    onPressed: () => setState(() => _movementDates = null),
                    child: const Text('Clear dates')),
            ],
          ),
          const SizedBox(height: 12),
          _table([
            'When',
            'Product',
            'Location',
            'Movement',
            'Change',
            'Balance'
          ], [
            for (final row in visibleRows.where(_matchesMovement))
              [
                _time(row.data()['at']),
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                inventoryMovementTypes[row.data()['type']] ?? '—',
                (row.data()['delta'] as int) > 0
                    ? '+${row.data()['delta']}'
                    : '${row.data()['delta']}',
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

  bool _matchesMovement(InventoryRow row) {
    final data = row.data();
    if (_movementType != null && data['type'] != _movementType) return false;
    final range = _movementDates;
    if (range == null) return true;
    final stamp = data['at'];
    if (stamp is! Timestamp) return false;
    final dt = stamp.toDate().toLocal();
    final exclusiveEnd =
        DateTime(range.end.year, range.end.month, range.end.day + 1);
    return !dt.isBefore(range.start) && dt.isBefore(exclusiveEnd);
  }

  Future<void> _pickDates(BuildContext context) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _movementDates,
      builder: (context, child) =>
          Theme(data: inventoryTheme(_dark), child: child!),
    );
    if (range != null && mounted) setState(() => _movementDates = range);
  }

  String _time(Object? time) {
    if (time is! Timestamp) return '—';
    final dt = time.toDate().toLocal();
    return '${MaterialLocalizations.of(context).formatShortDate(dt)} '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
  }

  Widget _table(List<String> headings, List<List<Object>> rows) {
    return LayoutBuilder(builder: (context, constraints) {
      final scheme = Theme.of(context).colorScheme;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 37,
              dataRowMaxHeight: 48,
              headingRowColor:
                  WidgetStatePropertyAll(scheme.surfaceContainerLow),
              headingTextStyle: TextStyle(
                  color: scheme.onSurface, fontWeight: FontWeight.w800),
              horizontalMargin: 14,
              columnSpacing: 24,
              dividerThickness: 1,
              columns: headings
                  .map((text) => DataColumn(
                      label: Text(text),
                      numeric: [
                        'Quantity',
                        'Change',
                        'Balance',
                        'On hand',
                        'Reorder at',
                        'Tracked stock'
                      ].contains(text)))
                  .toList(),
              rows: rows
                  .map((row) => DataRow(
                      cells: row
                          .map((cell) => DataCell(
                              cell is Widget ? cell : Text(cell.toString())))
                          .toList()))
                  .toList(),
            ),
          ),
        ),
        if (rows.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: Text('No records to show.')),
      ]);
    });
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
      builder: (dialog) => Theme(
          data: inventoryTheme(_dark),
          child: StatefulBuilder(builder: (dialog, update) {
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
          })),
    );
    return result == true;
  }
}
