import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';

import 'inventory_workspace.dart';
import 'services/export_file_downloader.dart';
import 'services/inventory_report_export.dart';
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
  late Future<List<InventoryLocation>> _locationData;
  List<InventoryLocation> _locations = mergeInventoryLocations(const []);
  Map<String, String> get _activeLocations => {
        for (final location in _locations)
          if (location.active) location.id: location.name,
      };
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
    _loadLocations();
    _load();
    unawaited(_loadTheme());
  }

  void _loadLocations() {
    _locationData = _store.locations().then((locations) {
      if (mounted) _locations = locations;
      return locations;
    });
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
    if (_section == 'Locations') {
      _data = Future.value(const []);
      return;
    }
    _data = Future.wait([
      _store.products(),
      if (['Overview', 'Products', 'Reports'].contains(_section))
        _store.balances(location: _location),
      if (_section == physicalStockSection) _store.counts(location: _location),
      if (_section == 'Stock Movements') ...[
        _store.movements(location: _location),
        _store.drafts(location: _location),
      ],
    ]);
  }

  void _refresh() {
    if (mounted)
      setState(() {
        _loadLocations();
        _load();
      });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<InventoryLocation>>(
      future: _locationData,
      builder: (context, locationSnapshot) => InventoryWorkspace(
            dark: _dark,
            section: _section,
            location: _location,
            locations: _activeLocations,
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
                    if (snapshot.connectionState != ConnectionState.done ||
                        locationSnapshot.connectionState !=
                            ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError ||
                        !snapshot.hasData ||
                        locationSnapshot.hasError) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'Inventory could not be loaded. Check your connection and admin access.'),
                          TextButton(
                              onPressed: _refresh,
                              child: const Text('Try again')),
                        ],
                      );
                    }
                    return _section == 'Locations'
                        ? _locationsContent(context)
                        : _content(context, snapshot.requireData);
                  },
                ),
              ],
            ),
          ));

  Widget _locationsContent(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Locations',
                  style: Theme.of(context).textTheme.headlineSmall),
              FilledButton.icon(
                  onPressed: _editLocation,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Location')),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
              'Active locations appear in the stock dropdowns. Deleted locations remain in history.'),
          const SizedBox(height: 12),
          _table([
            'Location',
            'Status',
            'Actions'
          ], [
            for (final location in _locations)
              [
                location.name,
                location.active ? 'Active' : 'Deleted',
                Wrap(children: [
                  TextButton(
                      onPressed: () => _editLocation(location),
                      child: const Text('Edit')),
                  TextButton(
                      onPressed: () => _changeLocationStatus(location),
                      child: Text(location.active ? 'Delete' : 'Restore')),
                ]),
              ],
          ]),
        ],
      );

  Future<void> _editLocation([InventoryLocation? location]) async {
    final name = TextEditingController(text: location?.name);
    final saved = await _editor(
      title: location == null ? 'Add Location' : 'Edit Location',
      fields: (_) => [_input(name, 'Location name')],
      action: 'Save Location',
      save: () => _store.saveLocation(
          id: location?.id, name: name.text, active: location?.active ?? true),
    );
    name.dispose();
    if (saved) _refresh();
  }

  Future<void> _changeLocationStatus(InventoryLocation location) async {
    final removing = location.active;
    final saved = await _editor(
      title: removing ? 'Delete location?' : 'Restore location?',
      fields: (_) => [
        Text(removing
            ? 'Remove ${location.name} from new stock entries? Existing stock and movement history will be preserved.'
            : 'Show ${location.name} in the stock dropdowns again?')
      ],
      action: removing ? 'Delete Location' : 'Restore Location',
      save: () => _store.saveLocation(
          id: location.id, name: location.name, active: !removing),
    );
    if (saved && mounted) {
      if (removing && _location == location.id) _location = null;
      _refresh();
    }
  }

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
    final locationNames = {
      for (final location in _locations) location.id: location.name
    };
    String locationName(Object? id) =>
        locationNames[id] ?? (id as String? ?? '—');
    final title = _section == 'Overview' ? 'Inventory Overview' : _section;
    final reportHeadings = ['Product', 'Location', 'On hand', 'Reorder at'];
    final reportRows = <List<Object>>[
      for (final row in rows.docs.take(100))
        if (_section == 'Reports')
          [
            productName(row.data()['productId'] as String?),
            locationName(row.data()['location']),
            row.data()['quantity'] as int,
            (byProduct[row.data()['productId']]?['reorder'] as int?) ?? '',
          ],
    ];
    final action = _section == 'Products'
        ? FilledButton(onPressed: _product, child: const Text('Add Product'))
        : _section == 'Reports'
            ? Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(
                    onPressed: reportRows.isEmpty
                        ? null
                        : () => _exportReport(reportHeadings, reportRows),
                    child: const Text('Export CSV')),
                FilledButton(
                    onPressed: reportRows.isEmpty
                        ? null
                        : () => _exportReport(reportHeadings, reportRows,
                            excel: true),
                    child: const Text('Export Excel')),
              ])
            : FilledButton(
                onPressed: () => _movement(
                    products.docs, null, _section == physicalStockSection),
                child: Text(_section == physicalStockSection
                    ? 'Record Count'
                    : 'Record Movement'),
              );
    final visibleRows = rows.docs.take(100).toList();
    final stock = <String, int>{};
    if (['Overview', 'Products'].contains(_section)) {
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
    final normalizedQuery = _query.trim().toLowerCase();
    final productRows = <List<Object>>[
      for (final row in products.docs.take(100))
        if (['name', 'sku'].any((key) =>
            '${row.data()[key] ?? ''}'.toLowerCase().contains(normalizedQuery)))
          [
            '${row.data()['sku'] ?? ''}',
            productName(row.id),
            '${row.data()['category'] ?? ''}',
            '${stock[row.id] ?? '—'}',
            row.data()['active'] == true ? 'Active' : 'Archived',
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Edit stock for ${productName(row.id)}',
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: row.data()['active'] != true
                    ? null
                    : () => _movement(products.docs, null, true, row),
              ),
              IconButton(
                tooltip: 'Edit details for ${productName(row.id)}',
                icon: const Icon(Icons.edit_note_outlined, size: 21),
                onPressed: () => _product(row),
              ),
            ]),
          ],
    ];
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
        if (_section == 'Reports') ...[
          const Text(
              'Stock on hand by location · CSV contains the rows shown here.'),
          const SizedBox(height: 12),
          _table(reportHeadings, reportRows),
        ],
        if (_section == physicalStockSection) ...[
          const Text(
              'A physical count records the difference and updates stock when posted.'),
          const SizedBox(height: 12),
          _table([
            'When',
            'Product',
            'Location',
            'Expected',
            'Counted',
            'Variance'
          ], [
            for (final row in visibleRows)
              [
                _time(row.data()['at']),
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                '${row.data()['before']}',
                '${row.data()['quantityAfter']}',
                '${row.data()['delta']}',
              ],
          ]),
        ],
        if (_section == 'Overview') ...[
          Text(
              '${products.docs.take(100).length} products shown · ${stock.values.fold<int>(0, (a, b) => a + b)} units in the balances shown'),
          const SizedBox(height: 14),
          Text('Products', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _table([
            'SKU',
            'Product',
            'Category',
            'Tracked stock',
            'Status',
            'Actions'
          ], productRows),
          const SizedBox(height: 20),
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
            'Actions'
          ], productRows),
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

  Future<void> _exportReport(List<String> headers, List<List<Object>> rows,
      {bool excel = false}) async {
    String cell(String value) {
      final safe =
          RegExp(r'^\s*[=+@-]|^[\t\r\n]').hasMatch(value) ? "'$value" : value;
      return '"${safe.replaceAll('"', '""')}"';
    }

    try {
      final fileName = excel
          ? stockReportFileName(DateTime.now())
          : 'ssh-inventory-stock.csv';
      final bytes = excel
          ? buildInventoryWorkbook(headers, rows)
          : Uint8List.fromList(utf8.encode('\uFEFF' +
              [headers, ...rows]
                  .map((row) =>
                      row.map((value) => cell(value.toString())).join(','))
                  .join('\r\n')));
      if (excel && kIsWeb) {
        await downloadExcelExport(bytes, fileName);
        return;
      }
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile.fromData(bytes,
              mimeType: excel
                  ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                  : 'text/csv')
        ],
        fileNameOverrides: [fileName],
        downloadFallbackEnabled: true,
      ));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not export the inventory report.')));
    }
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
      [InventoryRow? draft,
      bool countOnly = false,
      InventoryRow? selectedProduct]) async {
    final values = draft?.data() ?? {};
    var location = (values['location'] as String?) ?? _location;
    if (!_activeLocations.containsKey(location)) location = null;
    var product = selectedProduct?.id ?? values['productId'] as String?;
    if (!products.take(100).any((p) => p.id == product)) product = null;
    var type = countOnly ? 'count' : values['type'] as String?;
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
      title: selectedProduct != null
          ? 'Edit Stock'
          : countOnly
              ? 'Record Physical Count'
              : 'Record Movement',
      fields: (update) => [
        if (!countOnly)
          _select('Movement type', type, inventoryMovementTypes,
              (v) => update(() => type = v)),
        _select('Where is the stock kept?', location, _activeLocations,
            (v) => update(() => location = v)),
        if (selectedProduct != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                'Product: ${selectedProduct.data()['name'] ?? ''}\nEnter the new total for the selected location. A stock movement will record the difference.'),
          )
        else
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
        _input(
            quantity,
            selectedProduct != null
                ? 'New quantity on hand'
                : countOnly
                    ? 'Counted quantity'
                    : 'Quantity',
            number: true),
        _input(note, 'Note'),
      ],
      action: selectedProduct != null
          ? 'Save Stock'
          : countOnly
              ? 'Post Count'
              : 'Post Movement',
      save: () =>
          _store.post(input(), movementId: movementId, draftId: draft?.id),
      saveDraft: selectedProduct != null
          ? null
          : () => _store.saveDraft(input(), id: draftId),
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
    final route = DialogRoute<bool>(
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
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    return result == true;
  }
}
