import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/email_recovery_ui.dart';
import 'package:leadloop/services/email_recovery_service.dart';

void main() {
  test('accepts real email and numeric PIN only', () {
    expect(RecoveryValidation.email('promoter@example.com'), isTrue);
    expect(RecoveryValidation.email('9000000000@auth.leadloop.app'), isFalse);
    expect(RecoveryValidation.email('invalid'), isFalse);
    expect(RecoveryValidation.pin('123456'), isTrue);
    expect(RecoveryValidation.pin('12345'), isFalse);
    expect(RecoveryValidation.pin('12345a'), isFalse);
    expect(RecoveryValidation.optionalEmail(''), isTrue);
    expect(RecoveryValidation.optionalEmail('promoter@example.com'), isTrue);
    expect(RecoveryValidation.optionalEmail('invalid'), isFalse);
  });

  testWidgets('password reset action rejects non-numeric and mismatched PINs',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EmailActionScreen(
        mode: 'resetPassword',
        code: 'test-code',
        verifyResetCode: (_) async => 'promoter@example.com',
        confirmReset: (_, __) async {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Choose a new PIN'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '123456');
    await tester.enterText(fields.at(1), '654321');
    await tester.tap(find.text('Save new PIN'));
    await tester.pump();
    expect(find.text('PINs do not match.'), findsOneWidget);
  });

  testWidgets('valid reset action saves one numeric PIN', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: EmailActionScreen(
        mode: 'resetPassword',
        code: 'test-code',
        verifyResetCode: (_) async => 'promoter@example.com',
        confirmReset: (_, pin) async => saved = pin,
      ),
    ));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '123456');
    await tester.enterText(fields.at(1), '123456');
    await tester.tap(find.text('Save new PIN'));
    await tester.pumpAndSettle();
    expect(saved, '123456');
    expect(find.textContaining('PIN changed successfully'), findsOneWidget);
  });

  testWidgets('owner reset accepts a non-numeric password', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(
      home: EmailActionScreen(
        mode: 'resetPassword',
        code: 'owner-code',
        ownerPassword: true,
        verifyResetCode: (_) async => 'owner@example.com',
        confirmReset: (_, password) async => saved = password,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Choose a new password'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Owner@123');
    await tester.enterText(fields.at(1), 'Owner@123');
    await tester.tap(find.text('Save new password'));
    await tester.pumpAndSettle();

    expect(saved, 'Owner@123');
    expect(
        find.textContaining('Password changed successfully'), findsOneWidget);
  });

  testWidgets('owner forgot-password screen sends the entered email',
      (tester) async {
    String? sentTo;
    await tester.pumpWidget(MaterialApp(
      home: OwnerForgotPasswordScreen(
        sendReset: (email) async => sentTo = email,
      ),
    ));
    await tester.enterText(find.byType(TextFormField), 'owner@example.com');
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(sentTo, 'owner@example.com');
    expect(find.textContaining('password reset link has been sent'),
        findsOneWidget);
  });
}
