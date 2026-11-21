import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/inventory_workspace.dart';
import '../lib/services/inventory_store.dart';

void main() {
  test('inventory theme uses separate page and card surfaces in both modes',
      () {
    final light = inventoryTheme(false);
    final dark = inventoryTheme(true);
    expect(light.scaffoldBackgroundColor, const Color(0xFFEBEFF5));
    expect(light.colorScheme.surface, Colors.white);
    expect(dark.scaffoldBackgroundColor, const Color(0xFF151D2D));
    expect(dark.colorScheme.surface, const Color(0xFF202A3D));
    for (final theme in [light, dark]) {
      final scheme = theme.colorScheme;
      final text = scheme.onSurface.computeLuminance();
      for (final surface in [
        scheme.surface,
        scheme.surfaceContainer,
        scheme.surfaceContainerHigh
      ]) {
        final background = surface.computeLuminance();
        final contrast = text > background
            ? (text + .05) / (background + .05)
            : (background + .05) / (text + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
    }
  });

  test('action button palettes have readable contrast in light and dark', () {
    for (final dark in [false, true]) {
      final theme = inventoryTheme(dark);
      for (final style in [
        theme.filledButtonTheme.style!,
        theme.outlinedButtonTheme.style!,
      ]) {
        final foreground = style.foregroundColor!.resolve({})!;
        final background = style.backgroundColor!.resolve({})!;
        final a = foreground.computeLuminance();
        final b = background.computeLuminance();
        final contrast = a > b ? (a + .05) / (b + .05) : (b + .05) / (a + .05);
        expect(contrast, greaterThanOrEqualTo(4.5));
      }
      final accent =
          theme.filledButtonTheme.style!.backgroundColor!.resolve({});
      expect(accent, dark ? const Color(0xFFAFC6FF) : const Color(0xFF234FC8));
    }
  });

  test('sidebar keeps the requested order and preserves Locations', () {
    expect(inventorySections, [
      'Overview',
      'Products',
      'Physical Stocks',
      'Transfers',
      'History',
      'Reports',
      'Locations',
      'Suppliers',
      'Purchase',
    ]);
  });

  testWidgets('desktop uses a sidebar and toggles only the workspace theme',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var dark = false;
    var section = 'Overview';
    String? location;
    Brightness? inside;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light(),
      home: StatefulBuilder(
          builder: (context, setState) => InventoryWorkspace(
                dark: dark,
                section: section,
                location: location,
                locations: inventoryLocations,
                onSection: (value) => setState(() => section = value),
                onLocation: (value) => setState(() => location = value),
                onTheme: () => setState(() => dark = !dark),
                onRefresh: () {},
                child: Builder(builder: (context) {
                  inside = Theme.of(context).brightness;
                  return Text('Showing $section');
                }),
              )),
    ));
    expect(find.text(inventoryTitle), findsOneWidget);
    expect(tester.getTopLeft(find.text('History')).dx, lessThan(207));
    expect(tester.getTopLeft(find.text('Showing Overview')).dx,
        greaterThanOrEqualTo(207));
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Showing History'), findsOneWidget);
    expect(inside, Brightness.light);
    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    expect(inside, Brightness.dark);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Locations'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(Theme.of(tester.element(find.byType(InventoryWorkspace))).brightness,
        Brightness.light);
  });

  testWidgets('narrow layout keeps navigation, location and toggle usable',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 650));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: InventoryWorkspace(
      dark: false,
      section: 'Products',
      location: 'hotelmart',
      locations: inventoryLocations,
      onSection: (_) {},
      onLocation: (_) {},
      onTheme: () {},
      onRefresh: () {},
      child: const Text('Products content'),
    )));
    expect(find.text(inventoryTitle), findsNothing);
    expect(find.text('Products content'), findsOneWidget);
    expect(find.text('Selvan Hotel Mart'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded inventory uses its host controls and theme',
      (tester) async {
    var dark = false;
    Brightness? inventoryBrightness;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          appBar: AppBar(
            title: const Text('Selvan Steel House'),
            actions: [
              IconButton(
                tooltip: 'Admin theme',
                onPressed: () => setState(() => dark = true),
                icon: const Icon(Icons.dark_mode_outlined),
              ),
            ],
          ),
          body: InventoryWorkspace(
            dark: dark,
            embedded: true,
            section: 'Overview',
            location: null,
            locations: inventoryLocations,
            onSection: (_) {},
            onLocation: (_) {},
            onTheme: () {},
            onRefresh: () {},
            child: Builder(builder: (context) {
              inventoryBrightness = Theme.of(context).brightness;
              return const Text('Inventory Overview');
            }),
          ),
        ),
      ),
    ));
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('Selvan Steel House'), findsOneWidget);
    expect(find.text('Inventory Overview'), findsOneWidget);
    expect(find.byTooltip('Back to admin dashboard'), findsNothing);
    expect(find.byTooltip('Switch to dark theme'), findsNothing);
    expect(find.byTooltip('Refresh inventory'), findsOneWidget);
    await tester.tap(find.byTooltip('Admin theme'));
    await tester.pumpAndSettle();
    expect(inventoryBrightness, Brightness.dark);
  });
}
