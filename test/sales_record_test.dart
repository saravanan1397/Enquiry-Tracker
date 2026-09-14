import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/sales_record.dart';

void main() {
  test('amount accepts a maximum of three decimal places', () {
    expect(parseAmountMilli('10000'), 10000000);
    expect(parseAmountMilli('10.1'), 10100);
    expect(parseAmountMilli('10.125'), 10125);
    expect(parseAmountMilli('10.1250'), isNull);
    expect(parseAmountMilli('-1'), isNull);
    expect(parseAmountMilli('abc'), isNull);
    expect(parseAmountMilli('0'), isNull);
  });

  test('sales keys use calendar date and month', () {
    final date = DateTime(2026, 9, 14, 23, 59);
    expect(salesDateKey(date), '2026-09-14');
    expect(salesMonthKey(date), '2026-09');
  });

  test('timestamps are converted to Asia Kolkata time', () {
    expect(
      indiaDateTime(DateTime.utc(2026, 9, 14, 10, 30)),
      DateTime(2026, 9, 14, 16),
    );
  });
}
