import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/owner_home.dart';

void main() {
  for (final width in [360.0, 1280.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('Admin cards at $width in $brightness open their modules',
          (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var openedFollowups = false;
        var openedSales = false;
        var openedInventory = false;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: OwnerHome(
              leads: const [],
              onFollowup: () => openedFollowups = true,
              onSales: () => openedSales = true,
              onInventory: () => openedInventory = true,
            ),
          ),
        ));

        expect(find.text('Followup widget'), findsOneWidget);
        expect(find.text('Sales tracker'), findsOneWidget);
        expect(find.text('Open follow-ups'), findsOneWidget);
        expect(find.text('Open sales tracker'), findsOneWidget);
        expect(find.text('SCHEDULE'), findsOneWidget);
        expect(find.text('WORKSPACE'), findsNothing);
        expect(find.text('IS'), findsNothing);
        final followupPosition =
            tester.getTopLeft(find.text('Followup widget'));
        final salesPosition = tester.getTopLeft(find.text('Sales tracker'));
        if (width < 920) {
          expect(salesPosition.dy, greaterThan(followupPosition.dy));
        } else {
          expect(salesPosition.dy, closeTo(followupPosition.dy, 1));
          expect(salesPosition.dx, greaterThan(followupPosition.dx));
        }
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Open follow-ups'));
        expect(openedFollowups, isTrue);
        await tester.tap(find.text('Open sales tracker'));
        expect(openedSales, isTrue);
        if (kIsWeb) {
          expect(find.text('Centralized Inventory'), findsOneWidget);
          final inventory = find.text('Open inventory');
          await tester.ensureVisible(inventory);
          await tester.tap(inventory);
          expect(openedInventory, isTrue);
        }
      });
    }
  }
}
