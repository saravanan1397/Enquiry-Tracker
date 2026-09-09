import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/customer_lead.dart';
import 'package:leadloop/services/follow_up_deadline_service.dart';

CustomerLead _lead({
  required DateTime firstFollowUpAt,
  String? followUp2,
}) =>
    CustomerLead(
      id: 'lead-1',
      name: 'Customer',
      phone: '9000000000',
      shopName: 'Branch 1',
      promoterName: 'Promoter',
      createdAt: firstFollowUpAt,
      followUp1: 'Initial response',
      followUp1At: firstFollowUpAt,
      followUp2: followUp2,
    );

void main() {
  test('F2 allowance includes both Saturday and Sunday business hours', () {
    // Friday 9 PM: 1 hour Friday + 13 Saturday + 1 Sunday.
    final dueAt = FollowUpDeadlineService.followUp2DueAt(
      _lead(firstFollowUpAt: DateTime(2026, 9, 11, 21)),
    );
    expect(dueAt, DateTime(2026, 9, 13, 10));
  });

  test('F2 deadline counts only time from 9 AM to 10 PM', () {
    final dueAt = FollowUpDeadlineService.followUp2DueAt(
      _lead(firstFollowUpAt: DateTime(2026, 9, 7, 10)),
    );

    expect(dueAt, DateTime(2026, 9, 8, 12));
  });

  test('F2 deadline starts at 9 AM when F1 is saved before business hours', () {
    final dueAt = FollowUpDeadlineService.followUp2DueAt(
      _lead(firstFollowUpAt: DateTime(2026, 9, 7, 8)),
    );

    expect(dueAt, DateTime(2026, 9, 8, 11));
  });

  test('only missing F2 is marked overdue after the deadline', () {
    final firstFollowUpAt = DateTime(2026, 9, 7, 21);
    final overdueLead = _lead(firstFollowUpAt: firstFollowUpAt);
    final completedLead = _lead(
      firstFollowUpAt: firstFollowUpAt,
      followUp2: 'Called customer',
    );
    final afterDueAt = DateTime(2026, 9, 9, 10, 1);

    expect(
        FollowUpDeadlineService.isFollowUp2Overdue(overdueLead,
            now: afterDueAt),
        isTrue);
    expect(
        FollowUpDeadlineService.isFollowUp2Overdue(completedLead,
            now: afterDueAt),
        isFalse);
  });
}
