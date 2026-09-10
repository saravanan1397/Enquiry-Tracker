import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/pin_reset_ui.dart';

void main() {
  testWidgets('Forgot PIN rejects incomplete mobile before contacting backend',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPinScreen()));
    await tester.enterText(find.byType(TextFormField), '12345');
    await tester.tap(find.text('Request owner approval'));
    await tester.pump();
    expect(find.text('Enter exactly 10 digits.'), findsOneWidget);
  });
  testWidgets('Mobile input strips letters and limits input to 10 digits',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPinScreen()));
    await tester.enterText(find.byType(TextFormField), 'abc900000000123');
    final field = tester.widget<TextFormField>(find.byType(TextFormField));
    expect(field.controller!.text, '9000000001');
  });
  testWidgets('Existing code view validates code and new PIN', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ForgotPinScreen()));
    await tester.tap(find.text('I already have a reset code'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Set new PIN'));
    await tester.tap(find.text('Set new PIN'));
    await tester.pump();
    expect(find.text('Enter the 8-digit code from the owner.'), findsOneWidget);
    expect(find.text('Enter at least 6 digits.'), findsOneWidget);
  });
}
