import 'package:flutter/material.dart';

const inventorySections = [
  'Overview',
  'Products',
  physicalStockSection,
  'Transfers',
  inventoryHistorySection,
  'Reports',
  'Locations',
  'Suppliers',
  inventoryPurchaseSection,
];
const inventoryHistorySection = 'History';
const physicalStockSection = 'Physical Stocks';
const inventoryPurchaseSection = 'Purchase';
const inventoryTitle = 'Centralized Inventory';
const inventoryHeaderColor = Color(0xFF1A1A1A);

const _sectionIcons = {
  'Overview': Icons.dashboard_outlined,
  'Products': Icons.sell_outlined,
  physicalStockSection: Icons.inventory_2_outlined,
  'Transfers': Icons.swap_horiz,
  inventoryHistorySection: Icons.history,
  'Reports': Icons.bar_chart_outlined,
  'Locations': Icons.place_outlined,
  'Suppliers': Icons.groups_outlined,
  inventoryPurchaseSection: Icons.receipt_long_outlined,
};

ThemeData inventoryTheme(bool dark) {
  final brightness = dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF555555),
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFFF2F2F2) : const Color(0xFF303030),
    onPrimary: dark ? const Color(0xFF202020) : Colors.white,
    surface: dark ? const Color(0xFF252525) : Colors.white,
    surfaceContainerLow:
        dark ? const Color(0xFF2B2B2B) : const Color(0xFFF7F7F7),
    surfaceContainer: dark ? const Color(0xFF292929) : const Color(0xFFEBEBEB),
    surfaceContainerHigh:
        dark ? const Color(0xFF343434) : const Color(0xFFE6E6E6),
    onSurface: dark ? const Color(0xFFF1F1F1) : const Color(0xFF262626),
    onSurfaceVariant: dark ? const Color(0xFFC8C8C8) : const Color(0xFF525252),
    outline: dark ? const Color(0xFF929292) : const Color(0xFF737373),
    outlineVariant: dark ? const Color(0xFF444444) : const Color(0xFFDCDCDC),
    surfaceTint: Colors.transparent,
  );
  final controlShape =
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF1D1D1D) : const Color(0xFFF1F1F1),
    dividerColor: scheme.outlineVariant,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: scheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        shape: controlShape,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: scheme.surface,
        side: BorderSide(color: scheme.outlineVariant),
        minimumSize: const Size(0, 36),
        shape: controlShape,
      ),
    ),
    dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
  );
  return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
    headlineSmall: theme.textTheme.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700, fontSize: 22),
    titleMedium:
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  ));
}

class InventoryWorkspace extends StatelessWidget {
  const InventoryWorkspace({
    super.key,
    required this.dark,
    this.embedded = false,
    required this.section,
    required this.location,
    required this.locations,
    required this.onSection,
    required this.onLocation,
    required this.onTheme,
    required this.onRefresh,
    required this.child,
  });

  final bool dark;
  final bool embedded;
  final String section;
  final String? location;
  final Map<String, String> locations;
  final ValueChanged<String> onSection;
  final ValueChanged<String?> onLocation;
  final VoidCallback onTheme, onRefresh;
  final Widget child;

  Widget _navigation(BuildContext context, {required bool compact}) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      for (final item in inventorySections)
        Padding(
          padding:
              EdgeInsets.only(right: compact ? 4 : 0, bottom: compact ? 0 : 2),
          child: Semantics(
              selected: item == section,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor:
                      item == section ? scheme.surface : Colors.transparent,
                  foregroundColor: item == section
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size(compact ? 0 : double.infinity, 40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => onSection(item),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_sectionIcons[item], size: 17),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(item,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: item == section
                                ? FontWeight.w700
                                : FontWeight.w500)),
                  ),
                ]),
              )),
        ),
    ];
    if (compact) {
      return Material(
        color: scheme.surfaceContainer,
        child: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              scrollDirection: Axis.horizontal,
              child: Row(children: items)),
        ),
      );
    }
    return Material(
      color: scheme.surfaceContainer,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 18, 2, 15),
            child: Text(inventoryTitle,
                style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700)),
          ),
          ...items,
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool compact) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: DecoratedBox(
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Row(
              children: [
                if (!embedded)
                  IconButton(
                    tooltip: 'Back to admin dashboard',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                if (!compact)
                  const Padding(
                    padding: EdgeInsets.only(left: 9, right: 12),
                    child: Text('Branch:',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 230),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                            locations.containsKey(location) ? location : ''),
                        initialValue:
                            locations.containsKey(location) ? location : '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'All locations',
                          labelText: compact ? 'Branch' : null,
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('All locations')),
                          for (final entry in locations.entries)
                            DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) =>
                            onLocation(value == '' ? null : value),
                      ),
                    ),
                  ),
                ),
                if (!embedded)
                  IconButton(
                    tooltip:
                        dark ? 'Switch to light theme' : 'Switch to dark theme',
                    onPressed: onTheme,
                    icon: Icon(dark
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined),
                  ),
                IconButton(
                  tooltip: 'Refresh inventory',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Theme(
        data: inventoryTheme(dark),
        child: Builder(builder: (context) {
          final layout = LayoutBuilder(builder: (context, constraints) {
            final compact = constraints.maxWidth < 750;
            final workspace = Column(children: [
              _header(context, compact),
              if (compact) _navigation(context, compact: true),
              Expanded(child: child),
            ]);
            if (compact) return workspace;
            return Row(children: [
              SizedBox(width: 207, child: _navigation(context, compact: false)),
              Expanded(child: workspace),
            ]);
          });
          return embedded
              ? Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: layout)
              : Scaffold(body: SafeArea(child: layout));
        }),
      );
}
