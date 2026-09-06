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
}
