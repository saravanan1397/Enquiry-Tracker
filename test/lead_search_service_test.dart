import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/customer_lead.dart';
import 'package:leadloop/services/lead_search_service.dart';

void main() {
  final lead = CustomerLead(
    id: 'lead-1',
    name: 'Vivo Customer',
    phone: '9889998889',
    shopName: 'Branch 1',
    promoterName: 'Promoter',
    createdAt: DateTime(2026, 9, 9),
    followUp1: 'Checked Vivo V70',
    followUp2: 'Requested weekend callback',
  );

  test('partially matches name, mobile number, and follow-up comments', () {
    expect(LeadSearchService.matches(lead, 'vivo cust'), isTrue);
    expect(LeadSearchService.matches(lead, '99988'), isTrue);
    expect(LeadSearchService.matches(lead, 'weekend call'), isTrue);
  });

  test('does not match unrelated text', () {
    expect(LeadSearchService.matches(lead, 'Samsung refrigerator'), isFalse);
  });
}
