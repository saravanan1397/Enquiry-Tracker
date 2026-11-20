import 'package:flutter/material.dart';

const inventorySections = [
  'Overview',
  'Products',
  'Locations',
  'Stock Movements',
  'Stock Counts',
  'Reports'
];
const inventoryTitle = 'SSH Centralized Inventory';

ThemeData inventoryTheme(bool dark) {
  final brightness = dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF007D73),
    brightness: brightness,
  ).copyWith(
    primary: dark ? const Color(0xFF73DFD1) : const Color(0xFF007368),
    onPrimary: dark ? const Color(0xFF062722) : Colors.white,
    surface: dark ? const Color(0xFF121C28) : Colors.white,
    onSurface: dark ? const Color(0xFFEAF1F8) : const Color(0xFF142239),
    outline: dark ? const Color(0xFF6D8293) : const Color(0xFF788B9C),
    outlineVariant: dark ? const Color(0xFF344454) : const Color(0xFFD5DFE7),
  );
  final theme = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    dividerColor: scheme.outlineVariant,
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
  );
  return theme.copyWith(
      textTheme: theme.textTheme.copyWith(
    headlineSmall:
        theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
    titleMedium:
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  ));
}

class InventoryWorkspace extends StatefulWidget {
  const InventoryWorkspace({
    super.key,
    required this.dark,
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
  final String section;
  final String? location;
  final Map<String, String> locations;
  final ValueChanged<String> onSection;
  final ValueChanged<String?> onLocation;
  final VoidCallback onTheme, onRefresh;
  final Widget child;

  @override
  State<InventoryWorkspace> createState() => _InventoryWorkspaceState();
}

class _InventoryWorkspaceState extends State<InventoryWorkspace> {
  static const _navy = Color(0xFF0F1B30);
  static const _teal = Color(0xFF00766D);
  final _menuSearch = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _menuSearch.dispose();
    super.dispose();
  }

  Widget _navigation({required bool compact}) {
    final search = Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: TextField(
        controller: _menuSearch,
        onChanged: (value) =>
            setState(() => _query = value.trim().toLowerCase()),
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search menu',
          hintStyle: const TextStyle(color: Color(0xFFC5D4E5)),
          prefixIcon:
              const Icon(Icons.search, color: Color(0xFFC5D4E5), size: 19),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear menu search',
                  icon: const Icon(Icons.clear,
                      size: 17, color: Color(0xFFC5D4E5)),
                  onPressed: () {
                    _menuSearch.clear();
                    setState(() => _query = '');
                  },
                ),
          fillColor: const Color(0xFF202F45),
          filled: true,
        ),
      ),
    );
    final items = [
      for (final item in inventorySections)
        if (item.toLowerCase().contains(_query))
          Semantics(
            selected: item == widget.section,
            child: TextButton(
              style: TextButton.styleFrom(
                backgroundColor:
                    item == widget.section ? _teal : Colors.transparent,
                foregroundColor: Colors.white,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 18),
                minimumSize: Size(compact ? 0 : double.infinity, 44),
                shape: const RoundedRectangleBorder(),
              ),
              onPressed: () => widget.onSection(item),
              child: Text(item,
                  style: TextStyle(
                      fontWeight: item == widget.section
                          ? FontWeight.w700
                          : FontWeight.w500)),
            ),
          ),
    ];
    final empty = const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child:
          Text('No matching menus', style: TextStyle(color: Color(0xFFC5D4E5))),
    );
    if (compact)
      return Material(
        color: _navy,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          search,
          if (items.isEmpty)
            empty
          else
            SingleChildScrollView(
                scrollDirection: Axis.horizontal, child: Row(children: items)),
        ]),
      );
    return Material(
      color: _navy,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 23, 10, 24),
            child: Text(inventoryTitle,
                style: TextStyle(
                    fontSize: 15,
                    color: Colors.white,
                    fontWeight: FontWeight.w800)),
          ),
          search,
          if (items.isEmpty) empty else ...items,
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
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
                            widget.locations.containsKey(widget.location)
                                ? widget.location
                                : ''),
                        initialValue:
                            widget.locations.containsKey(widget.location)
                                ? widget.location
                                : '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          hintText: 'All locations',
                          labelText: compact ? 'Branch' : null,
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('All locations')),
                          for (final entry in widget.locations.entries)
                            DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (value) =>
                            widget.onLocation(value == '' ? null : value),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: widget.dark
                      ? 'Switch to light theme'
                      : 'Switch to dark theme',
                  onPressed: widget.onTheme,
                  icon: Icon(widget.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined),
                ),
                IconButton(
                  tooltip: 'Refresh inventory',
                  onPressed: widget.onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Theme(
        data: inventoryTheme(widget.dark),
        child: Builder(
            builder: (context) => Scaffold(
                  body: SafeArea(
                    child: LayoutBuilder(builder: (context, constraints) {
                      final compact = constraints.maxWidth < 750;
                      final workspace = Column(children: [
                        _header(context, compact),
                        if (compact) _navigation(compact: true),
                        Expanded(child: widget.child),
                      ]);
                      if (compact) return workspace;
                      return Row(children: [
                        SizedBox(
                            width: 207, child: _navigation(compact: false)),
                        Expanded(child: workspace),
                      ]);
                    }),
                  ),
                )),
      );
}
