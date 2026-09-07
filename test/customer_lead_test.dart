import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/customer_lead.dart';

void main() {
  test('copyWith preserves and updates follow-up timestamps', () {
    final createdAt = DateTime.utc(2026, 9, 7, 8, 30);
    final firstFollowUpAt = DateTime.utc(2026, 9, 7, 9, 45);
    final secondFollowUpAt = DateTime.utc(2026, 9, 8, 10, 15);
    final lead = CustomerLead(
      id: 'lead-1',
      name: 'Customer',
      phone: '9000000000',
      shopName: 'Shop',
      promoterName: 'Promoter',
      createdAt: createdAt,
      followUp1: 'Initial enquiry',
      followUp1At: firstFollowUpAt,
    );

    final updated = lead.copyWith(
      followUp2: 'Customer requested a callback',
      followUp2At: secondFollowUpAt,
    );

    expect(updated.createdAt, createdAt);
    expect(updated.followUp1At, firstFollowUpAt);
    expect(updated.followUp2At, secondFollowUpAt);
    expect(updated.followUp3At, isNull);
  });

  test('current stage follows the latest completed follow-up', () {
    final lead = CustomerLead(
      id: 'lead-2',
      name: 'Customer',
      phone: '9000000000',
      shopName: 'Shop',
      promoterName: 'Promoter',
      createdAt: DateTime.utc(2026, 9, 7),
    );

    expect(lead.currentStage, FollowUpStage.first);
    expect(
        lead.copyWith(followUp1: 'Called').currentStage, FollowUpStage.first);
    final second =
        lead.copyWith(followUp1: 'Called', followUp2: 'Called again');
    expect(second.currentStage, FollowUpStage.second);
    expect(second.isCompleted, isFalse);
    final completed = second.copyWith(followUp3: 'Completed');
    expect(completed.currentStage, FollowUpStage.third);
    expect(completed.isCompleted, isTrue);
  });
}
