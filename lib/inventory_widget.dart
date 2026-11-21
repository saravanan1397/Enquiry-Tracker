import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'inventory_workspace.dart';
import 'services/export_file_downloader.dart';
import 'services/inventory_report.dart';
import 'services/inventory_report_export.dart';
import 'services/inventory_store.dart';

part 'inventory_supply_views.dart';

typedef _InventoryViewData = ({
  List<InventoryRows> tables,
  InventoryReportSource? report,
});

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
  late Future<_InventoryViewData> _data;
  late Future<List<InventoryLocation>> _locationData;
  List<InventoryLocation> _locations = mergeInventoryLocations(const []);
  Map<String, String> get _activeLocations => {
        for (final location in _locations)
          if (location.active) location.id: location.name,
      };
  var _section = physicalStockSection;
  var _productBin = false;
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

  void _load() => _data = _loadView();

  Future<_InventoryViewData> _loadView() async {
    if (_section == 'Reports') {
      return (
        tables: const <InventoryRows>[],
        report: await _store.reportSource(location: _location)
      );
    }
    if (_productBin) {
      return (tables: [await _store.deletedProducts()], report: null);
    }
    if (_section == 'Locations' || _section == 'Suppliers') {
      return (
        tables: [if (_section == 'Suppliers') await _store.suppliers()],
        report: null
      );
    }
    final tables = await Future.wait([
      _store.products(),
      if (['Overview', 'Products', physicalStockSection].contains(_section))
        _store.balances(location: _location),
      if (_section == inventoryHistorySection) ...[
        _store.movements(location: _location),
        _store.drafts(location: _location),
        _store.legacyTransfers(),
      ],
      if (_section == inventoryPurchaseSection) ...[
        _store.purchaseOrders(),
        _store.suppliers(),
      ],
      if (_section == 'Transfers') _store.branchTransfers(),
    ]);
    return (tables: tables, report: null);
  }

  void _refresh() {
    if (mounted)
      setState(() {
        _loadLocations();
        _load();
      });
  }

  void _showProductBin(bool show) {
    setState(() {
      _productBin = show;
      _search.clear();
      _load();
    });
  }

  Future<void> _setProductRecycled(InventoryRow product,
      {required bool recycled}) async {
    final saved = await _editor(
      title: recycled ? 'Move product to Recycle Bin?' : 'Restore product?',
      fields: (_) => [
        Text(_supplyName(product)),
        const SizedBox(height: 8),
        Text(recycled
            ? 'The product will be hidden from current stock views. Its quantities, purchase records and movement history will be kept.'
            : 'The product will return to Products with its previous active or archived status and its existing stock.'),
      ],
      action: recycled ? 'Move to Recycle Bin' : 'Restore Product',
      save: () => _store.setProductRecycled(product.id, recycled: recycled),
    );
    if (saved) _refresh();
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
              if (_section == section && !_productBin) return;
              setState(() {
                _section = section;
                _productBin = false;
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
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 26),
              children: [
                FutureBuilder<_InventoryViewData>(
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
                    final (tables: data, :report) = snapshot.requireData;
                    if (report != null) return _reportContent(report);
                    if (_productBin)
                      return _productBinContent(context, data.first);
                    return switch (_section) {
                      'Locations' => _locationsContent(context),
                      'Suppliers' => _suppliersContent(context, data.first),
                      inventoryPurchaseSection =>
                        _purchasingContent(context, data),
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
          _pageHeading(
            'Locations',
            FilledButton.icon(
                onPressed: _editLocation,
                icon: const Icon(Icons.add),
                label: const Text('Add Location')),
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

  Widget _viewSearch({double bottom = 12}) => Builder(builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        const pill = BorderRadius.all(Radius.circular(24));
        return Padding(
          padding: EdgeInsets.only(bottom: bottom),
          child: TextField(
            key: const ValueKey('inventory-view-search'),
            controller: _search,
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              enabledBorder: OutlineInputBorder(
                  borderRadius: pill,
                  borderSide: BorderSide(color: scheme.outlineVariant)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: pill,
                  borderSide: BorderSide(color: scheme.primary, width: 2)),
              prefixIcon: const Icon(Icons.search),
              labelText: _productBin
                  ? 'Search deleted products'
                  : switch (_section) {
                      'Overview' ||
                      'Products' =>
                        'Search products by name, SKU, barcode or category',
                      physicalStockSection => 'Search physical stock',
                      inventoryHistorySection => 'Search movements and drafts',
                      'Reports' => 'Search stock report',
                      'Suppliers' => 'Search suppliers',
                      inventoryPurchaseSection => 'Search purchase orders',
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
      });

  Widget _content(BuildContext context, List<InventoryRows> data) {
    final products = data.first;
    final rows = data[1];
    final byProduct = {for (final p in products.docs) p.id: p.data()};
    final productDocuments = {for (final p in products.docs) p.id: p};
    bool productInBin(Object? id) => byProduct[id]?['deletedAt'] != null;
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
    final action = _section == 'Products'
        ? Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () => _showProductBin(true),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Recycle Bin'),
            ),
            FilledButton(onPressed: _product, child: const Text('Add Product')),
          ])
        : Wrap(spacing: 8, runSpacing: 8, children: [
            if (_section == physicalStockSection) ...[
              OutlinedButton(
                onPressed: () => _movement(products.docs, stockType: 'sale'),
                child: const Text('Subtract Outgoing Stock'),
              ),
              FilledButton(
                onPressed: () => _movement(products.docs),
                child: const Text('Record Movement'),
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
            ],
          ]);
    final visibleRows = rows.docs.take(100).toList();
    final stock = <String, int>{};
    if (['Overview', 'Products'].contains(_section)) {
      for (final row in visibleRows) {
        final item = row.data();
        final id = item['productId'] as String;
        if (productInBin(id)) continue;
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
        if (!productInBin(row.id) &&
            _matchesSearch([
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
            if (_section == 'Products')
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Edit details for ${productName(row.id)}',
                  icon: const Icon(Icons.edit_note_outlined, size: 21),
                  onPressed: () => _product(row),
                ),
                IconButton(
                  tooltip: 'Delete ${productName(row.id)}',
                  icon: const Icon(Icons.delete_outline, size: 21),
                  onPressed: () => _setProductRecycled(row, recycled: true),
                ),
              ]),
          ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _pageHeading(title, action),
        const SizedBox(height: 14),
        if (_section != inventoryHistorySection) _viewSearch(),
        if (_section == physicalStockSection) ...[
          _table([
            'Product',
            'Location',
            'Balance stock',
            'Actions'
          ], [
            for (final row in visibleRows.where(matchesRecord))
              if (!productInBin(row.data()['productId']))
                [
                  productName(row.data()['productId'] as String?),
                  locationName(row.data()['location']),
                  row.data()['quantity'] as int,
                  if (productDocuments[row.data()['productId']]
                      case final InventoryRow product)
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        flex: 2,
                        child: Tooltip(
                          message: 'Edit stock for ${productName(product.id)}',
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: product.data()['active'] == true &&
                                    _activeLocations
                                        .containsKey(row.data()['location'])
                                ? () => _movement(products.docs,
                                    stockType: 'count',
                                    selectedProduct: product,
                                    selectedLocation:
                                        row.data()['location'] as String,
                                    selectedQuantity:
                                        row.data()['quantity'] as int)
                                : null,
                            child: const Text('Edit stock',
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        flex: 3,
                        child: Tooltip(
                          message:
                              'Set stock at a chosen branch for ${productName(product.id)}',
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: product.data()['active'] == true
                                ? () => _movement(products.docs,
                                    stockType: 'count',
                                    selectedProduct: product)
                                : null,
                            child: const Text('Add stock in new location',
                                textAlign: TextAlign.center),
                          ),
                        ),
                      ),
                    ])
                  else
                    const SizedBox.shrink(),
                ],
          ], centeredWidths: const [
            190,
            180,
            114,
            410
          ]),
        ],
        if (_section == 'Overview') ...[
          Text(
              '${productRows.length} products shown · ${stock.values.fold<int>(0, (a, b) => a + b)} total units for the location filter'),
          const SizedBox(height: 14),
          Text('Products', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          _productsTable(productRows, showActions: false),
          const SizedBox(height: 20),
          Text('Low stock', style: Theme.of(context).textTheme.titleMedium),
          _table([
            'Product',
            'Location',
            'In hand',
            'Reorder at'
          ], [
            for (final row in low)
              [
                productName(row.data()['productId'] as String?),
                locationName(row.data()['location']),
                '${row.data()['quantity']}',
                '${byProduct[row.data()['productId']]?['reorder']}'
              ],
          ], centeredWidths: const [
            190,
            180,
            110,
            116
          ]),
        ],
        if (_section == 'Products') ...[
          _productsTable(productRows),
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
          ], centeredWidths: const [
            192,
            190,
            164,
            158,
            90,
            90
          ]),
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
            'Actions'
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
          ], centeredWidths: const [
            190,
            174,
            122,
            133
          ]),
        ],
        if (data.any((query) => query.size > 100))
          const Text(
              'Showing the first 100 records in each list. Choose a location to narrow stock results.'),
      ],
    );
  }

  Widget _reportContent(InventoryReportSource source) {
    final (:headings, :rows) = buildInventoryReport(
      source,
      locations: {
        for (final location in _locations) location.id: location.name
      },
      matches: _matchesSearch,
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _pageHeading(
          'Reports',
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton(
                onPressed:
                    rows.isEmpty ? null : () => _exportReport(headings, rows),
                child: const Text('Export CSV')),
            FilledButton(
                onPressed: rows.isEmpty
                    ? null
                    : () => _exportReport(headings, rows, excel: true),
                child: const Text('Export Excel')),
          ])),
      const SizedBox(height: 14),
      _viewSearch(),
      const Text('Movement totals cover all recorded history for these rows. '
          'Stock out, returns, damage and transfers show units moved; physical counts '
          'and adjustments show net stock change. Exports match the report.'),
      const SizedBox(height: 6),
      const Text('Stock value uses the saved unit cost. A blank balance means '
          'no balance was recorded; a blank value means it could not be calculated.'),
      const SizedBox(height: 12),
      _table(headings, rows),
    ]);
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
    try {
      final fileName = excel
          ? stockReportFileName(DateTime.now())
          : 'ssh-inventory-stock.csv';
      final bytes = excel
          ? buildInventoryWorkbook(headers, rows)
          : buildInventoryCsv(headers, rows);
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

  Widget _pageHeading(String title, Widget action) =>
      LayoutBuilder(builder: (context, limits) {
        final heading =
            Text(title, style: Theme.of(context).textTheme.headlineSmall);
        if (limits.maxWidth < 640) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 10,
            children: [heading, action],
          );
        }
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          spacing: 10,
          children: [
            Flexible(flex: 2, child: heading),
            Flexible(flex: 3, child: action),
          ],
        );
      });

  Widget _productsTable(List<List<Object>> rows, {bool showActions = true}) =>
      _table(
        [
          'SKU',
          'Product',
          'Barcode',
          'Category',
          'Tracked stock',
          'Status',
          if (showActions) 'Actions'
        ],
        rows,
        centeredWidths: [92, 194, 126, 128, 118, 92, if (showActions) 126],
      );

  Widget _table(List<String> headings, List<List<Object>> rows,
      {List<double>? centeredWidths}) {
    return LayoutBuilder(builder: (context, constraints) {
      final scheme = Theme.of(context).colorScheme;
      final fixedWidths = centeredWidths != null;
      final minimum = centeredWidths?.fold<double>(0, (a, b) => a + b) ?? 0.0;
      final extraPerColumn = fixedWidths && constraints.maxWidth > minimum
          ? (constraints.maxWidth - minimum) / headings.length
          : 0.0;
      return Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  minWidth: fixedWidths ? 0 : constraints.maxWidth),
              child: DataTable(
                headingRowHeight: 42,
                dataRowMinHeight: 46,
                dataRowMaxHeight: 56,
                headingRowColor:
                    WidgetStatePropertyAll(scheme.surfaceContainerHigh),
                headingTextStyle: TextStyle(
                    color: scheme.onSurface,
                    fontSize: inventoryTableHeadingSize,
                    fontWeight: FontWeight.w600),
                dataTextStyle: TextStyle(
                    color: scheme.onSurface, fontSize: inventoryTableTextSize),
                dataRowColor: WidgetStateProperty.resolveWith((states) =>
                    states.contains(WidgetState.hovered)
                        ? scheme.surfaceContainerLow
                        : null),
                horizontalMargin: 12,
                columnSpacing: 24,
                dividerThickness: 1,
                columns: headings.indexed.map(((int, String) column) {
                  final (index, text) = column;
                  final label = Text(text,
                      textAlign: TextAlign.center,
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis);
                  return DataColumn(
                      label: fixedWidths ? Flexible(child: label) : label,
                      headingRowAlignment: MainAxisAlignment.center,
                      columnWidth: fixedWidths
                          ? FixedColumnWidth(
                              centeredWidths[index] + extraPerColumn)
                          : null);
                }).toList(),
                rows: rows
                    .map((row) => DataRow(cells: [
                          for (final (index, cell) in row.indexed)
                            DataCell(_tableCell(cell, headings[index])),
                        ]))
                    .toList(),
              ),
            ),
          ),
          if (rows.isEmpty)
            Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
                child: Text(_searchTerm.isEmpty
                    ? 'No records to show.'
                    : 'No matching records.')),
        ]),
      );
    });
  }

  Widget _tableCell(Object value, String heading) {
    if (value is Widget) return Center(child: value);
    final text = value is num && heading.endsWith(' INR')
        ? value.toStringAsFixed(2)
        : value is num && heading == 'Balance stock'
            ? value.toStringAsFixed(0)
            : value.toString();
    final isStatus = heading == 'Status' && text.isNotEmpty;
    final label = Text(text,
        textAlign: TextAlign.center,
        style: heading == 'Product' || isStatus
            ? const TextStyle(fontWeight: FontWeight.w600)
            : null,
        maxLines: 2,
        overflow: TextOverflow.ellipsis);
    final shown =
        text.length >= 14 ? Tooltip(message: text, child: label) : label;
    final content = isStatus
        ? Builder(builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            return DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: shown,
              ),
            );
          })
        : shown;
    return Center(child: content);
  }

  Future<void> _product([
    InventoryRow? row,
    ({String? location, String quantity})? carried,
  ]) async {
    final InventoryRows suppliers;
    final Map<String, int> stockByLocation;
    final List<InventoryRow> catalog;
    try {
      (suppliers, stockByLocation, catalog) = await (
        _store.suppliers(),
        row == null
            ? Future.value(const <String, int>{})
            : _store.productStockByLocation(row.id),
        _store.productSuggestions(),
      ).wait;
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Could not load product options. ${inventorySaveError(error)}')));
      return;
    }
    if (!mounted) return;
    final available =
        catalog.where((item) => item.data()['deletedAt'] == null).toList();
    if (row != null) {
      final editId = row.id;
      row = available.where((item) => item.id == editId).firstOrNull;
      if (row == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('This product is no longer available to edit.')));
        return;
      }
    }
    final values = row?.data() ?? {};
    String catalogName(InventoryRow item) =>
        (item.data()['name'] as String? ?? '').trim();
    final names = available
        .where((item) => catalogName(item).isNotEmpty)
        .toList()
      ..sort((a, b) => _suggestionKey(catalogName(a))
          .compareTo(_suggestionKey(catalogName(b))));
    final byCategory = <String, String>{};
    for (final item in available) {
      final label = (item.data()['category'] as String? ?? '').trim();
      if (label.isNotEmpty) {
        byCategory.putIfAbsent(_suggestionKey(label), () => label);
      }
    }
    final categories = byCategory.values.toList()
      ..sort((a, b) => _suggestionKey(a).compareTo(_suggestionKey(b)));
    String productOption(InventoryRow item) {
      final sku = (item.data()['sku'] as String? ?? '').trim();
      final barcode = (item.data()['barcode'] as String? ?? '').trim();
      return '${catalogName(item)}${sku.isNotEmpty ? ' · SKU $sku' : barcode.isNotEmpty ? ' · Barcode $barcode' : ''}';
    }

    final name = TextEditingController(text: values['name'] as String?);
    final quantity = TextEditingController(
        text: carried?.location == null ? null : carried?.quantity);
    final nameFocus = FocusNode(), categoryFocus = FocusNode();
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
    final assigned =
        stockByLocation.keys.where(_activeLocations.containsKey).toList();
    String? storageLocation = _activeLocations.containsKey(carried?.location)
        ? carried!.location
        : row == null
            ? (_activeLocations.containsKey(_location) ? _location : null)
            : (assigned.contains(_location)
                ? _location
                : assigned.length == 1
                    ? assigned.single
                    : null);
    InventoryRow? selectedExisting;
    final result = await _editor(
      title: row == null ? 'Add Product' : 'Edit Product',
      fields: (update) => [
        if (row == null)
          _suggestedInput(
            name,
            nameFocus,
            'Product name',
            names,
            productOption,
            (existing) {
              selectedExisting = existing;
              Navigator.of(context, rootNavigator: true).pop(true);
            },
          )
        else
          _input(name, 'Product name'),
        _select(
            row == null
                ? 'Where is the product stored? (required)'
                : 'Where is the product stored?',
            storageLocation,
            _activeLocations,
            (v) => update(() {
                  if (storageLocation != null && v != storageLocation)
                    quantity.clear();
                  storageLocation = v;
                })),
        if (row != null && storageLocation != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(stockByLocation.containsKey(storageLocation)
                ? 'Current stock here: ${stockByLocation[storageLocation]}'
                : 'No stock is recorded at this location yet.'),
          ),
        _input(quantity, 'Total quantity in hand (optional)', number: true),
        if (row != null)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('Leave quantity blank to keep existing stock. '
                'Stock at other locations is not moved.'),
          ),
        _input(sku, 'SKU'),
        _input(barcode, 'Barcode (optional)'),
        _suggestedInput(category, categoryFocus, 'Category', categories,
            (label) => label, (_) {}),
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
      save: () async {
        if (row == null && name.text.trim().isNotEmpty) {
          final exact = names
              .where((item) =>
                  _suggestionKey(catalogName(item)) ==
                  _suggestionKey(name.text))
              .toList();
          if (exact.length > 1) {
            throw const FormatException(
                'More than one product has this name. Choose the correct entry from the suggestions.');
          }
          if (exact.isNotEmpty) {
            selectedExisting = exact.single;
            return;
          }
        }
        final stockQuantity = _optionalInt(quantity.text);
        if ((row == null || stockQuantity != null || storageLocation != null) &&
            !_activeLocations.containsKey(storageLocation)) {
          throw const FormatException('Choose where the product is stored.');
        }
        await _store.saveProduct(
            id: row?.id,
            storageLocation: storageLocation,
            stockQuantity: stockQuantity,
            expectedStockQuantity: stockByLocation[storageLocation],
            name: name.text,
            sku: sku.text,
            category:
                byCategory[_suggestionKey(category.text)] ?? category.text,
            barcode: barcode.text,
            supplierId: supplier,
            unitCost: inventoryCostPaise(cost.text),
            reorder: _optionalInt(reorder.text),
            active: active);
      },
    );
    final stockEntry = (location: storageLocation, quantity: quantity.text);
    for (final controller in [
      name,
      quantity,
      sku,
      category,
      reorder,
      barcode,
      cost
    ]) {
      controller.dispose();
    }
    nameFocus.dispose();
    categoryFocus.dispose();
    if (result && selectedExisting != null && mounted) {
      await _product(selectedExisting, stockEntry);
    } else if (result) {
      _refresh();
    }
  }

  String _suggestionKey(String text) => text.trim().toLowerCase();

  Widget _suggestedInput<T extends Object>(
    TextEditingController controller,
    FocusNode focus,
    String label,
    List<T> options,
    String Function(T) optionLabel,
    ValueChanged<T> selected,
  ) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Autocomplete<T>(
          textEditingController: controller,
          focusNode: focus,
          optionsMaxHeight: 192,
          optionsViewOpenDirection: label == 'Category'
              ? OptionsViewOpenDirection.up
              : OptionsViewOpenDirection.down,
          displayStringForOption: optionLabel,
          optionsBuilder: (value) {
            final input = _suggestionKey(value.text);
            return options
                .where(
                    (item) => _suggestionKey(optionLabel(item)).contains(input))
                .take(20);
          },
          onSelected: selected,
          fieldViewBuilder: (context, text, node, submit) => TextField(
            controller: text,
            focusNode: node,
            maxLength: 160,
            onSubmitted: (_) => submit(),
            decoration: InputDecoration(
              labelText: label,
              counterText: '',
              suffixIcon: options.isEmpty
                  ? null
                  : PopupMenuButton<T>(
                      tooltip: '$label suggestions',
                      icon: const Icon(Icons.arrow_drop_down),
                      constraints:
                          const BoxConstraints(maxWidth: 380, maxHeight: 240),
                      onOpened: node.unfocus,
                      onSelected: (value) {
                        text.text = optionLabel(value);
                        selected(value);
                      },
                      itemBuilder: (_) => [
                        for (final option in options)
                          PopupMenuItem(
                              value: option, child: Text(optionLabel(option))),
                      ],
                    ),
            ),
          ),
        ),
      );

  Future<void> _movement(List<InventoryRow> products,
      {InventoryRow? draft,
      String? stockType,
      InventoryRow? selectedProduct,
      String? selectedLocation,
      int? selectedQuantity}) async {
    final values = draft?.data() ?? {};
    var location =
        selectedLocation ?? (values['location'] as String?) ?? _location;
    String? destination;
    if (!_activeLocations.containsKey(location)) location = null;
    var product = selectedProduct?.id ?? values['productId'] as String?;
    if (!products.any((p) =>
        p.id == product &&
        p.data()['active'] == true &&
        p.data()['deletedAt'] == null)) product = null;
    var type = stockType ?? values['type'] as String?;
    final entryTypes = {
      ...inventoryMovementTypes,
      'transfer': 'Transfer to another branch'
    };
    if (!entryTypes.containsKey(type)) type = null;
    final quantity = TextEditingController(
        text: (selectedQuantity ?? values['quantity'])?.toString());
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
              'sale' => 'Subtract Outgoing Stock',
              'transfer' => 'New Transfer',
              _ => 'Record Movement',
            },
      fields: (update) => [
        if (stockType == null)
          _select(
              'Movement type', type, entryTypes, (v) => update(() => type = v)),
        if (selectedLocation != null)
          Text('Location: ${_supplyLocation(selectedLocation)}')
        else
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
                  if (p.data()['active'] == true &&
                      p.data()['deletedAt'] == null)
                    p.id: '${p.data()['name']}'.trim().isEmpty
                        ? 'Unnamed product'
                        : '${p.data()['name']}'
              },
              (v) => update(() => product = v)),
        _input(
            quantity,
            selectedProduct != null
                ? 'New quantity in hand'
                : switch (stockType) {
                    'sale' => 'Outgoing stock',
                    _ => 'Quantity',
                  },
            number: true),
        if (stockType == null && type != 'transfer') _input(note, 'Note'),
      ],
      action: selectedProduct != null
          ? 'Save Stock'
          : switch (stockType) {
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
