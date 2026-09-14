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

  test('sales totals are grouped separately for each person', () {
    SalesRecord record(String id, String personId, String name, String date,
            int amountMilli) =>
        SalesRecord(
          id: id,
          personId: personId,
          personName: name,
          salesDateKey: date,
          monthKey: '2026-09',
          amountMilli: amountMilli,
          enteredByUid: 'owner',
          enteredByName: 'Owner',
        );

    final groups = groupSalesRecordsByPerson([
      record('one-14', 'one', 'Name1', '2026-09-14', 15000000),
      record('two-14', 'two', 'Person2', '2026-09-14', 10000000),
      record('one-13', 'one', 'Name1', '2026-09-13', 12000000),
      record('alpha-14', 'alpha', 'alpha Person', '2026-09-14', 5000000),
    ]);

    expect(groups, hasLength(3));
    expect(groups.map((group) => group.personName),
        ['alpha Person', 'Name1', 'Person2']);
    expect(groups[1].records.map((record) => record.salesDateKey),
        ['2026-09-13', '2026-09-14']);
    expect(groups[1].totalMilli, 27000000);
    expect(groups[2].totalMilli, 10000000);

    expect(
      filterSalesRecords(
        groups.expand((group) => group.records),
        personId: 'one',
        dateKey: '2026-09-14',
      ).map((record) => record.id),
      ['one-14'],
    );
  });
}
