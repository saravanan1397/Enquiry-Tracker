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
  });
}
