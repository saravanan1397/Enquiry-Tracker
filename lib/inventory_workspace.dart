import 'package:flutter/material.dart';

const inventorySections = [
  'Overview',
  'Products',
  physicalStockSection,
  'Transfers',
  'Reports',
  'Locations',
  'Suppliers',
  inventoryPurchaseSection,
  inventoryHistorySection,
];
const inventoryHistorySection = 'History';
const physicalStockSection = 'Physical Stocks';
const inventoryPurchaseSection = 'Purchase';
const inventoryTitle = 'Centralized Inventory';
const inventoryTableHeadingSize = 13.0;
const inventoryTableTextSize = 14.0;
const _inventoryNavigation = Color(0xFF171B25);
const _inventoryNavigationSelected = Color(0xFF303B54);
const _inventoryNavigationText = Color(0xFFD7E0F2);

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
    seedColor: const Color(0xFF2D5BE3),
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFFAFC6FF) : const Color(0xFF234FC8),
    onPrimary: dark ? const Color(0xFF10254F) : Colors.white,
    surface: dark ? const Color(0xFF202A3D) : Colors.white,
    surfaceContainerLow:
        dark ? const Color(0xFF25334B) : const Color(0xFFF4F7FD),
    surfaceContainer: dark ? const Color(0xFF27344D) : const Color(0xFFF6F8FC),
    surfaceContainerHigh:
        dark ? const Color(0xFF34476A) : const Color(0xFFDDE8FF),
    onSurface: dark ? const Color(0xFFF0F4FF) : const Color(0xFF151C35),
    onSurfaceVariant: dark ? const Color(0xFFBCCBEB) : const Color(0xFF4B5874),
    outline: dark ? const Color(0xFF8C9DC4) : const Color(0xFF6C7A98),
    outlineVariant: dark ? const Color(0xFF3E4D69) : const Color(0xFFDCE3EF),
    surfaceTint: Colors.transparent,
  );
  const controlShape = StadiumBorder();
  final actionColor = scheme.primary;
  final actionText = scheme.onPrimary;
  final subtleAction = dark ? const Color(0xFF293A5D) : const Color(0xFFF2F6FF);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  final original = base.textTheme;
  final text = original.copyWith(
    headlineSmall: original.headlineSmall
        ?.copyWith(fontWeight: FontWeight.w700, fontSize: 24),
    titleLarge: original.titleLarge?.copyWith(fontSize: 23),
    titleMedium: original.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700, fontSize: 17),
    titleSmall: original.titleSmall?.copyWith(fontSize: 15),
    bodyLarge: original.bodyLarge?.copyWith(fontSize: 17),
    bodyMedium: original.bodyMedium?.copyWith(fontSize: 15),
    bodySmall: original.bodySmall?.copyWith(fontSize: 13),
    labelLarge: original.labelLarge?.copyWith(fontSize: 15),
    labelMedium: original.labelMedium?.copyWith(fontSize: 13),
    labelSmall: original.labelSmall?.copyWith(fontSize: 12),
  );
  return base.copyWith(
    textTheme: text,
    scaffoldBackgroundColor:
        dark ? const Color(0xFF151D2D) : const Color(0xFFEBEFF5),
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
        backgroundColor: actionColor,
        foregroundColor: actionText,
        minimumSize: const Size(0, 36),
        shape: controlShape,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: subtleAction,
        foregroundColor: actionColor,
        minimumSize: const Size(0, 36),
        shape: controlShape,
        textStyle: text.labelLarge,
      ).copyWith(
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
              color: states.contains(WidgetState.disabled)
                  ? scheme.outlineVariant
                  : actionColor,
            )),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          foregroundColor: actionColor, textStyle: text.labelLarge),
    ),
    dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
  );
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

  Widget _navigation({required bool compact}) {
    final items = [
      for (final item in inventorySections)
        Padding(
          padding:
              EdgeInsets.only(right: compact ? 4 : 0, bottom: compact ? 0 : 2),
          child: Semantics(
              selected: item == section,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: item == section
                      ? _inventoryNavigationSelected
                      : Colors.transparent,
                  foregroundColor:
                      item == section ? Colors.white : _inventoryNavigationText,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: Size(compact ? 0 : double.infinity, 40),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => onSection(item),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_sectionIcons[item],
                      size: 17,
                      color: item == section ? const Color(0xFFAFC6FF) : null),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(item,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
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
        color: _inventoryNavigation,
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
      color: _inventoryNavigation,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 18, 2, 14),
            child: Text(inventoryTitle,
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
          const Divider(height: 12, color: Color(0xFF30394D)),
          ...items,
        ],
      ),
    );
  }

  Widget _header(BuildContext context, bool compact) => Material(
        color: Theme.of(context).colorScheme.surface,
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
                        borderRadius: BorderRadius.circular(16),
                        decoration: InputDecoration(
                          hintText: 'All locations',
                          labelText: compact ? 'Branch' : null,
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide(
                              color: Theme.of(context).colorScheme.primary,
                              width: 2,
                            ),
                          ),
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
              if (compact) _navigation(compact: true),
              Expanded(child: child),
            ]);
            if (compact) return workspace;
            return Row(children: [
              SizedBox(width: 207, child: _navigation(compact: false)),
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
