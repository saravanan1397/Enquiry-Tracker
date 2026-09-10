import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/promoter_deletion_dialog.dart';

void main() {
  testWidgets('deletion requires exact confirmation; warns enquiries are kept',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: PromoterDeletionDialog(
                name: 'Test promoter', mobile: '9000000001'))));
    expect(find.textContaining('Customer enquiries and history are kept.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.enterText(find.byType(TextField), 'DELETE');
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
  testWidgets('Cancel returns false without approval', (tester) async {
    bool? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                        context: context,
                        builder: (_) => const PromoterDeletionDialog(
                            name: 'Test', mobile: '9000000001'));
                  },
                  child: const Text('Open'),
                ))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, false);
  });
}
