// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leadloop/leadloop_app.dart';
import 'package:leadloop/services/local_lead_store.dart';

void main() {
  testWidgets('Enquiry Tracker app launches', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    final store = LocalLeadStore();
    await tester.pumpWidget(LeadloopV2(store: store));
    await tester.pumpAndSettle();

    // Verify that the app launches without crashing
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('Forgot PIN?'), findsOneWidget);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);
  });

  testWidgets('promoter registration offers the four fixed branches',
      (WidgetTester tester) async {
    await tester.pumpWidget(LeadloopV2(store: LocalLeadStore()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('New promoter? Create an account'));
    await tester.tap(find.text('New promoter? Create an account'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Branch 1'));
    await tester.tap(find.text('Branch 1'));
    await tester.pumpAndSettle();

    expect(find.text('Branch 1'), findsWidgets);
    expect(find.text('Branch 2'), findsOneWidget);
    expect(find.text('Branch 3'), findsOneWidget);
    expect(find.text('Branch 4'), findsOneWidget);
  });

  testWidgets(
      'Forgot PIN is visible before sign-in and after an unsuccessful attempt',
      (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(LeadloopV2(store: LocalLeadStore()));
    await tester.pumpAndSettle();
    expect(find.text('Forgot PIN?').hitTestable(), findsOneWidget);
    await tester.enterText(
        find.byWidgetPredicate((w) =>
            w is TextField && w.decoration?.labelText == 'Mobile number'),
        '9876543222');
    await tester.enterText(
        find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Personal PIN'),
        '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    // Firebase is intentionally unconfigured in this test: the attempt fails,
    // but recovery must remain visible and usable for every sign-in error.
    expect(find.text('Forgot PIN?').hitTestable(), findsOneWidget);
    await tester.tap(find.text('Forgot PIN?'));
    await tester.pumpAndSettle();
    expect(find.text('Reset promoter PIN'), findsOneWidget);
  });
}
