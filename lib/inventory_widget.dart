import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'inventory_workspace.dart';
import 'services/export_file_downloader.dart';
import 'services/inventory_report_export.dart';
import 'services/inventory_store.dart';

part 'inventory_supply_views.dart';

String inventorySaveError(Object error) {
  if (error is FormatException) return error.message;
  if (error is FirebaseException) {
    return switch (error.code) {
      'permission-denied' =>
        'Firestore rejected this save (permission-denied). Check the inventory rules and admin access.',
      'unauthenticated' =>
        'Your admin session has expired. Sign in and try again.',
      'unavailable' ||
      'deadline-exceeded' =>
        'Firestore did not respond. Check your connection and try again.',
      'aborted' => 'Stock changed while saving. Refresh and try again.',
      _ => 'Could not save to Firestore (${error.code}).',
    };
  }
  return 'Could not save the inventory change.';
}

class InventoryWidgetScreen extends StatefulWidget {
  const InventoryWidgetScreen({super.key, this.store, this.adminDark});

  final InventoryStore? store;
  // When provided, the host admin shell controls the workspace theme.
  final bool? adminDark;

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
  final _search = TextEditingController();
  var _dark = false;
  bool get _workspaceDark => widget.adminDark ?? _dark;
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
    if (widget.adminDark == null) unawaited(_loadTheme());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
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
    if (_section == 'Locations' || _section == 'Suppliers') {
      _data = _section == 'Suppliers'
          ? Future.wait([_store.suppliers()])
          : Future.value(const []);
      return;
    }
    _data = Future.wait([
      _store.products(),
      if (['Overview', 'Products', 'Reports', physicalStockSection]
          .contains(_section))
        _store.balances(location: _location),
      if (_section == inventoryHistorySection) ...[
        _store.movements(location: _location),
        _store.drafts(location: _location),
        _store.legacyTransfers(),
      ],
      if (_section == 'Purchasing') ...[
        _store.purchaseOrders(),
        _store.suppliers(),
      ],
      if (_section == 'Transfers') _store.branchTransfers(),
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
            dark: _workspaceDark,
            embedded: widget.adminDark != null,
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
                _search.clear();
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
                    final data = snapshot.requireData;
                    return switch (_section) {
                      'Locations' => _locationsContent(context),
                      'Suppliers' => _suppliersContent(context, data.first),
                      'Purchasing' => _purchasingContent(context, data),
                      'Transfers' => _transfersContent(context, data),
                      _ => _content(context, data),
                    };
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
          _viewSearch(),
          const Text(
              'Active locations appear in the stock dropdowns. Deleted locations remain in history.'),
          const SizedBox(height: 12),
          _table([
            'Location',
            'Status',
            'Actions'
          ], [
            for (final location in _locations)
              if (_matchesSearch(
                  [location.name, location.active ? 'Active' : 'Deleted']))
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

  String get _searchTerm => _search.text.trim().toLowerCase();

  bool _matchesSearch(Iterable<Object?> values) {
    final term = _searchTerm;
    return term.isEmpty ||
        values.any(
            (value) => (value?.toString() ?? '').toLowerCase().contains(term));
  }

  Widget _viewSearch({double bottom = 12}) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: TextField(
          key: const ValueKey('inventory-view-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            labelText: switch (_section) {
              'Overview' ||
              'Products' =>
                'Search products by name, SKU, barcode or category',
              physicalStockSection => 'Search physical stock',
              inventoryHistorySection => 'Search movements and drafts',
              'Reports' => 'Search stock report',
              'Suppliers' => 'Search suppliers',
              'Purchasing' => 'Search purchase orders',
              'Transfers' => 'Search transfers',
              _ => 'Search locations',
            },
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear view search',
                    onPressed: () => setState(_search.clear),
                    icon: const Icon(Icons.clear),
                  ),
          ),
        ),
      );

  Widget _content(BuildContext context, List<InventoryRows> data) {
    final products = data.first;
    final rows = data[1];
    final byProduct = {for (final p in products.docs) p.id: p.data()};
    final productDocuments = {for (final p in products.docs) p.id: p};
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
    bool matchesRecord(InventoryRow row) {
      final item = row.data();
      final id = item['productId'] as String?;
      return _matchesSearch([
        productName(id),
        byProduct[id]?['sku'],
        byProduct[id]?['category'],
        byProduct[id]?['barcode'],
        locationName(item['location']),
        inventoryMovementLabels[item['type']],
        item['note'],
      ]);
    }

    final title = _section == 'Overview' ? 'Inventory Overview' : _section;
    final reportHeadings = [
      'Product',
      'Location',
      'On hand',
      'Reorder at',
      'Unit cost INR',
      'Stock value INR'
    ];
    final reportRows = <List<Object>>[
      for (final row in rows.docs.take(100))
        if (_section == 'Reports' && matchesRecord(row))
          [
            productName(row.data()['productId'] as String?),
            locationName(row.data()['location']),
            row.data()['quantity'] as int,
            (byProduct[row.data()['productId']]?['reorder'] as int?) ?? '',
            _stockValue(
                byProduct[row.data()['productId']]?['unitCost'] as int?, 1),
            _stockValue(byProduct[row.data()['productId']]?['unitCost'] as int?,
                row.data()['quantity'] as int),
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
            : Wrap(spacing: 8, runSpacing: 8, children: [
                if (_section == physicalStockSection) ...[
                  OutlinedButton(
                    onPressed: () =>
                        _movement(products.docs, stockType: 'sale'),
                    child: const Text('Subtract Outgoing Stock'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        _movement(products.docs, stockType: 'count'),
                    child: const Text('Set Total Stock'),
                  ),
                ] else ...[
                  if (widget.adminDark != null && _section == 'Overview') ...[
                    OutlinedButton(
                      onPressed: _showBackupDeviceOptions,
                      child: const Text('Back up now'),
                    ),
                    OutlinedButton(
                      onPressed: () => _launchTrustedAction('restore'),
                      child: const Text('Restore from backup'),
                    ),
                  ],
                  FilledButton(
                    onPressed: () => _movement(products.docs),
                    child: const Text('Record Movement'),
                  ),
                ],
              ]);
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
      return _section != inventoryHistorySection &&
          p?['active'] == true &&
          reorder != null &&
          (row.data()['quantity'] as int) < reorder &&
          matchesRecord(row);
    });
    final productRows = <List<Object>>[
      for (final row in products.docs.take(100))
        if (_matchesSearch([
          productName(row.id),
          row.data()['sku'],
          row.data()['category'],
          row.data()['barcode']
        ]))
          [
            '${row.data()['sku'] ?? ''}',
            productName(row.id),
            '${row.data()['barcode'] ?? ''}',
            '${row.data()['category'] ?? ''}',
            '${stock[row.id] ?? '—'}',
            row.data()['active'] == true ? 'Active' : 'Archived',
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'Edit stock for ${productName(row.id)}',
                icon: const Icon(Icons.edit_outlined, size: 19),
                onPressed: row.data()['active'] != true
                    ? null
                    : () => _movement(products.docs,
                        stockType: 'count', selectedProduct: row),
              ),
              if (_section != 'Products')
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
        if (_section != inventoryHistorySection) _viewSearch(),
        if (_section == 'Reports') ...[
          const Text(
              'Stock value uses each product’s saved unit cost. A blank value means the cost is missing or the amount exceeds the supported range. Exports contain the rows shown.'),
          const SizedBox(height: 12),
          _table(reportHeadings, reportRows),
        ],
        if (_section == physicalStockSection) ...[
          _table([
            'Product',
            'Location',
            'Balance stock',
            'Actions'
          ], [
            for (final row in visibleRows.where(matchesRecord))
              [
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                row.data()['quantity'] as int,
                if (productDocuments[row.data()['productId']]
                    case final InventoryRow product)
                  IconButton(
                    tooltip: 'Edit details for ${productName(product.id)}',
                    icon: const Icon(Icons.edit_note_outlined, size: 21),
                    onPressed: () => _product(product),
                  )
                else
                  const SizedBox.shrink(),
              ],
          ], compactWidth: 520),
        ],
        if (_section == 'Overview') ...[
          Text(
              '${productRows.length} products shown · ${stock.values.fold<int>(0, (a, b) => a + b)} total units for the location filter'),
          const SizedBox(height: 14),
          Text('Products', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _table([
            'SKU',
            'Product',
            'Barcode',
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
          _table([
            'SKU',
            'Product',
            'Barcode',
            'Category',
            'Tracked stock',
            'Status',
            'Actions'
          ], productRows, compactWidth: 860, columnSpacing: 24),
        ],
        if (_section == inventoryHistorySection) ...[
          LayoutBuilder(builder: (context, limits) {
            final width = limits.maxWidth;
            final compact = width < 640;
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: compact ? width : (width * .42).clamp(260.0, 480.0),
                  child: _viewSearch(bottom: 0),
                ),
                SizedBox(
                  width: width.clamp(0.0, 192.0),
                  child: DropdownButtonFormField<String>(
                    initialValue: _movementType ?? '',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type'),
                    items: [
                      const DropdownMenuItem(
                          value: '', child: Text('All types')),
                      for (final entry in inventoryMovementLabels.entries)
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
            );
          }),
          const SizedBox(height: 12),
          _table([
            'When',
            'Product',
            'Location',
            'Movement',
            'Change',
            'Balance'
          ], [
            for (final row in visibleRows
                .where((row) => _matchesMovement(row) && matchesRecord(row)))
              [
                _time(row.data()['at']),
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                inventoryMovementLabels[row.data()['type']] ?? '—',
                (row.data()['delta'] as int) > 0
                    ? '+${row.data()['delta']}'
                    : '${row.data()['delta']}',
                '${row.data()['quantityAfter']}',
              ],
          ], compactWidth: 880),
          if (data[3].docs.isNotEmpty) ...[
            const SizedBox(height: 14),
            _olderTransferActions(context, data[3], productDocuments),
          ],
          const SizedBox(height: 14),
          Text('Drafts', style: Theme.of(context).textTheme.titleMedium),
          _table([
            'Product',
            'Location',
            'Quantity',
            ''
          ], [
            for (final row in data[2].docs.take(100).where(matchesRecord))
              [
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                '${row.data()['quantity'] ?? '—'}',
                TextButton(
                    onPressed: () => _movement(products.docs, draft: row),
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

  Future<void> _showBackupDeviceOptions() => showDialog<void>(
        context: context,
        builder: (dialog) => Theme(
          data: inventoryTheme(_workspaceDark),
          child: AlertDialog(
            title: const Text('Back up inventory'),
            content: const Text(
              'Do you trust this device to store encrypted backups? '
              'Choose a local folder, or use the folder already saved on this PC. '
              'A new Windows PC needs the backup helper installed first.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: const Text('Cancel'),
              ),
              OutlinedButton(
                onPressed: () {
                  Navigator.of(dialog).pop();
                  unawaited(_launchTrustedAction('backup'));
                },
                child: const Text('Use saved folder'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialog).pop();
                  unawaited(_launchTrustedAction('trust'));
                },
                child: const Text('Trust this device'),
              ),
            ],
          ),
        ),
      );

  Future<void> _launchTrustedAction(String action) async {
    try {
      if (await launchUrl(Uri(scheme: 'centralized-inventory', host: action),
          webOnlyWindowName: '_self')) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text(
                  'Continue in the trusted Windows backup helper. If it does not open, set it up on this PC first.')));
        return;
      }
    } catch (_) {}
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Open Inventory on the trusted Windows PC to use backup and restore.')));
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
          Theme(data: inventoryTheme(_workspaceDark), child: child!),
    );
    if (range != null && mounted) setState(() => _movementDates = range);
  }

  String _time(Object? time) {
    if (time is! Timestamp) return '—';
    final dt = time.toDate().toLocal();
    return '${MaterialLocalizations.of(context).formatShortDate(dt)} '
        '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(dt))}';
  }

  Widget _table(List<String> headings, List<List<Object>> rows,
      {double? compactWidth, double? columnSpacing}) {
    return LayoutBuilder(builder: (context, constraints) {
      final scheme = Theme.of(context).colorScheme;
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Divider(height: 1),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minWidth: constraints.maxWidth
                    .clamp(0.0, compactWidth ?? constraints.maxWidth)),
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 37,
              dataRowMaxHeight: 48,
              headingRowColor:
                  WidgetStatePropertyAll(scheme.surfaceContainerLow),
              headingTextStyle: TextStyle(
                  color: scheme.onSurface, fontWeight: FontWeight.w800),
              horizontalMargin: 14,
              columnSpacing: columnSpacing ?? (compactWidth == null ? 24 : 16),
              dividerThickness: 1,
              columns: headings
                  .map((text) => DataColumn(
                      label: Text(text),
                      numeric: [
                        'Quantity',
                        'Change',
                        'Balance',
                        'Balance stock',
                        'On hand',
                        'Reorder at',
                        'Unit cost INR',
                        'Stock value INR',
                        'Tracked stock'
                      ].contains(text)))
                  .toList(),
              rows: rows
                  .map((row) => DataRow(cells: [
                        for (final (index, cell) in row.indexed)
                          DataCell(cell is Widget
                              ? cell
                              : Text(cell is num &&
                                      headings[index].endsWith(' INR')
                                  ? cell.toStringAsFixed(2)
                                  : cell is num &&
                                          headings[index] == 'Balance stock'
                                      ? cell.toStringAsFixed(0)
                                      : cell.toString())),
                      ]))
                  .toList(),
            ),
          ),
        ),
        if (rows.isEmpty)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              child: Text(_searchTerm.isEmpty
                  ? 'No records to show.'
                  : 'No matching records.')),
      ]);
    });
  }

  Future<void> _product([InventoryRow? row]) async {
    final InventoryRows suppliers;
    try {
      suppliers = await _store.suppliers();
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Could not load suppliers. ${inventorySaveError(error)}')));
      return;
    }
    if (!mounted) return;
    final values = row?.data() ?? {};
    final name = TextEditingController(text: values['name'] as String?);
    final sku = TextEditingController(text: values['sku'] as String?);
    final category = TextEditingController(text: values['category'] as String?);
    final reorder = TextEditingController(text: values['reorder']?.toString());
    final barcode = TextEditingController(text: values['barcode'] as String?);
    final cost = TextEditingController(
        text: inventoryRupees(values['unitCost'] as int?));
    var supplier = values['supplierId'] as String?;
    final supplierOptions = _supplyChoices(suppliers, include: supplier);
    if (supplier != null && !supplierOptions.containsKey(supplier)) {
      supplierOptions[supplier] = 'Previously assigned supplier';
    }
    var active = values['active'] != false;
    final result = await _editor(
      title: row == null ? 'Add Product' : 'Edit Product',
      fields: (update) => [
        _input(name, 'Product name'),
        _input(sku, 'SKU'),
        _input(barcode, 'Barcode (optional)'),
        _input(category, 'Category'),
        _input(reorder, 'Reorder level', number: true),
        _select('Preferred supplier (optional)', supplier, supplierOptions,
            (v) => update(() => supplier = v)),
        _input(cost, 'Unit cost in rupees (optional)'),
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
          barcode: barcode.text,
          supplierId: supplier,
          unitCost: inventoryCostPaise(cost.text),
          reorder: _optionalInt(reorder.text),
          active: active),
    );
    for (final controller in [name, sku, category, reorder, barcode, cost]) {
      controller.dispose();
    }
    if (result) _refresh();
  }

  Future<void> _movement(List<InventoryRow> products,
      {InventoryRow? draft,
      String? stockType,
      InventoryRow? selectedProduct}) async {
    final values = draft?.data() ?? {};
    var location = (values['location'] as String?) ?? _location;
    String? destination;
    if (!_activeLocations.containsKey(location)) location = null;
    var product = selectedProduct?.id ?? values['productId'] as String?;
    if (!products.take(100).any((p) => p.id == product)) product = null;
    var type = stockType ?? values['type'] as String?;
    final entryTypes = {
      ...inventoryMovementTypes,
      'transfer': 'Transfer to another branch'
    };
    if (!entryTypes.containsKey(type)) type = null;
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
    String? transferId;
    String? incomingId;
    final draftId = draft?.id ?? _store.newDraftId();
    final result = await _editor(
      title: selectedProduct != null
          ? 'Edit Stock'
          : switch (stockType) {
              'count' => 'Set Total Stock',
              'sale' => 'Subtract Outgoing Stock',
              'transfer' => 'New Transfer',
              _ => 'Record Movement',
            },
      fields: (update) => [
        if (stockType == null)
          _select(
              'Movement type', type, entryTypes, (v) => update(() => type = v)),
        _select(
            type == 'transfer' ? 'Source branch' : 'Where is the stock kept?',
            location,
            _activeLocations,
            (v) => update(() {
                  location = v;
                  if (destination == v) destination = null;
                })),
        if (type == 'transfer')
          _select(
              'Destination branch',
              destination,
              {
                for (final branch in _activeLocations.entries)
                  if (branch.key != location) branch.key: branch.value,
              },
              (v) => update(() => destination = v),
              resetKey: location),
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
                for (final p in products)
                  p.id: '${p.data()['name']}'.trim().isEmpty
                      ? 'Unnamed product'
                      : '${p.data()['name']}'
              },
              (v) => update(() => product = v)),
        _input(
            quantity,
            selectedProduct != null
                ? 'New quantity on hand'
                : switch (stockType) {
                    'count' => 'Total stock',
                    'sale' => 'Outgoing stock',
                    _ => 'Quantity',
                  },
            number: true),
        if (stockType == null && type != 'transfer') _input(note, 'Note'),
      ],
      action: selectedProduct != null
          ? 'Save Stock'
          : switch (stockType) {
              'count' => 'Save Total',
              'sale' => 'Subtract Stock',
              _ => 'Post Movement',
            },
      actionLabel: () => type == 'transfer' ? 'Transfer Stock' : null,
      confirmBeforeSave: (dialog) async {
        if (type != 'transfer') return true;
        final units = _optionalInt(quantity.text);
        if (location == null ||
            destination == null ||
            product == null ||
            units == null ||
            units < 1 ||
            units > 1000000) {
          throw const FormatException(
              'Choose a source, destination, product, and a quantity from 1 to 1,000,000.');
        }
        final name = products.where((row) => row.id == product).firstOrNull;
        return await showDialog<bool>(
              context: dialog,
              builder: (confirmation) => AlertDialog(
                title: const Text('Confirm transfer'),
                content: Text(
                    'Transfer $units units of ${name == null ? 'this product' : _supplyName(name)} from ${_supplyLocation(location)} to ${_supplyLocation(destination)} now?'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(confirmation).pop(false),
                    child: const Text('No'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(confirmation).pop(true),
                    child: const Text('Yes, transfer'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      save: () => type == 'transfer'
          ? _store.transferStock(
              id: transferId ??= _store.newTransferId(),
              outgoingId: movementId,
              incomingId: incomingId ??= _store.newMovementId(),
              from: location!,
              to: destination!,
              product: product!,
              quantity: _optionalInt(quantity.text)!,
              draftId: draft?.id)
          : _store.post(input(), movementId: movementId, draftId: draft?.id),
      showDraft: () => type != 'transfer',
      saveDraft: stockType != null
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
          ValueChanged<String?> changed,
          {Object? resetKey}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<String>(
          key: resetKey == null ? ValueKey(label) : ValueKey((label, resetKey)),
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
    String? Function()? actionLabel,
    required Future<void> Function() save,
    Future<bool> Function(BuildContext)? confirmBeforeSave,
    Future<void> Function()? saveDraft,
    bool Function()? showDraft,
  }) async {
    var busy = false;
    String? error;
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => Theme(
          data: inventoryTheme(_workspaceDark),
          child: StatefulBuilder(builder: (dialog, update) {
            Future<void> submit(Future<void> Function() task,
                {bool confirm = false}) async {
              update(() {
                busy = true;
                error = null;
              });
              try {
                if (confirm && confirmBeforeSave != null) {
                  final accepted = await confirmBeforeSave(dialog);
                  if (!dialog.mounted) return;
                  if (!accepted) {
                    update(() => busy = false);
                    return;
                  }
                }
                await task();
                if (dialog.mounted) Navigator.of(dialog).pop(true);
              } catch (e) {
                if (dialog.mounted)
                  update(() {
                    busy = false;
                    error = inventorySaveError(e);
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
                        if (saveDraft != null && (showDraft?.call() ?? true))
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
                  if (saveDraft != null && (showDraft?.call() ?? true))
                    OutlinedButton(
                        onPressed: busy ? null : () => submit(saveDraft),
                        child: const Text('Save Draft')),
                  FilledButton(
                      onPressed:
                          busy ? null : () => submit(save, confirm: true),
                      child: Text(
                          busy ? 'Saving…' : actionLabel?.call() ?? action)),
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
