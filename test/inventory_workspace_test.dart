import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/inventory_workspace.dart';
import '../lib/services/inventory_store.dart';

void main() {
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
    expect(tester.getTopLeft(find.text('Stock Movements')).dx, lessThan(207));
    expect(tester.getTopLeft(find.text('Showing Overview')).dx,
        greaterThanOrEqualTo(207));
    await tester.tap(find.text('Stock Movements'));
    await tester.pumpAndSettle();
    expect(find.text('Showing Stock Movements'), findsOneWidget);
    expect(inside, Brightness.light);
    await tester.tap(find.byTooltip('Switch to dark theme'));
    await tester.pumpAndSettle();
    expect(inside, Brightness.dark);
    expect(find.byTooltip('Switch to light theme'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'loc');
    await tester.pumpAndSettle();
    expect(find.text('Locations'), findsOneWidget);
    expect(find.text('Products'), findsNothing);
    await tester.tap(find.byTooltip('Clear menu search'));
    await tester.pumpAndSettle();
    expect(find.text('Products'), findsOneWidget);
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
    expect(find.byTooltip('Switch to dark theme'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
