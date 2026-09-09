import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/leadloop_app.dart';
import 'package:leadloop/models/customer_lead.dart';
import 'package:leadloop/services/local_lead_store.dart';
import 'package:leadloop/services/follow_up_deadline_service.dart';

class MemoryStore extends LocalLeadStore {
  CustomerLead? saved;
  @override
  Future<void> save(CustomerLead lead) async {
    saved = lead;
  }
}

CustomerLead sample() => CustomerLead(
      id: '1',
      name: 'Customer',
      phone: '9000000000',
      shopName: 'Branch 1',
      promoterName: 'Promoter',
      promoterId: 'p1',
      createdAt: DateTime.utc(2026, 9, 11, 15, 30),
      followUp1: 'Initial',
      followUp1At: DateTime.utc(2026, 9, 11, 15, 30),
      followUp2: 'Second',
      followUp2At: DateTime.utc(2026, 9, 11, 15, 30),
      followUp3: 'Third',
      followUp3At: DateTime.utc(2026, 9, 11, 15, 30),
    );

void main() {
  test('F3 and F4 have deadlines; completion and deletion stop them', () {
    final lead = sample();
    expect(FollowUpDeadlineService.nextDueAt(lead)?.toUtc(),
        DateTime.utc(2026, 9, 13, 4, 30));
    final extra = lead.copyWith(additionalFollowUps: [
      FollowUpEntry(
          comment: 'Call next month',
          enteredAt: DateTime.utc(2026, 9, 13, 4, 30))
    ]);
    expect(extra.followUpNumber, 4);
    expect(FollowUpDeadlineService.nextDueAt(extra)?.toUtc(),
        DateTime.utc(2026, 9, 14, 6, 30));
    for (final outcome in [
      EnquiryOutcome.purchased,
      EnquiryOutcome.closedWithoutPurchase
    ]) {
      expect(
          FollowUpDeadlineService.nextDueAt(extra.copyWith(outcome: outcome)),
          isNull);
    }
    expect(
        FollowUpDeadlineService.nextDueAt(
            extra.copyWith(deletedAt: DateTime.now())),
        isNull);
  });

  testWidgets('save F4 before F5 becomes available', (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStore();
    await tester.pumpWidget(MaterialApp(
        home: LeadloopFollowUpScreen(store: store, lead: sample())));
    await tester.pumpAndSettle();
    expect(find.text('Add follow-up 4'), findsOneWidget);
    await tester.tap(find.text('Add follow-up 4'));
    await tester.pumpAndSettle();
    expect(find.text('Add follow-up 5'), findsNothing);
    final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Follow-up 4');
    await tester.enterText(input, 'Still interested');
    await tester.ensureVisible(find.text('Save follow-ups'));
    await tester.tap(find.text('Save follow-ups'));
    await tester.pumpAndSettle();
    expect(store.saved?.additionalFollowUps.single.comment, 'Still interested');
    expect(store.saved?.followUpNumber, 4);
    expect(find.text('Add follow-up 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
