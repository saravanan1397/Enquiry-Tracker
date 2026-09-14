import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/sales_record.dart';
import 'package:leadloop/services/sales_export_service.dart';

void main() {
  test('exports sales details, timestamps and total to one workbook', () {
    final bytes = SalesExportService().buildWorkbook(
      records: [
        SalesRecord(
          id: 'person-1_2026-09-14',
          personId: 'person-1',
          personName: 'PersonName',
          salesDateKey: '2026-09-14',
          monthKey: '2026-09',
          amountMilli: 10000125,
          reference: 'POS-14',
          enteredByUid: 'owner-1',
          enteredByName: 'Owner',
          createdAt: DateTime(2026, 9, 14, 18, 30),
          updatedAt: DateTime(2026, 9, 14, 18, 35),
          previousAmountMilli: 9000000,
          lastEditedByName: 'Owner',
        ),
      ],
      exportedAt: DateTime(2026, 9, 14, 19),
    );

    expect(bytes.take(2).toList(), [0x50, 0x4B]);
    final sheet = ZipDecoder()
        .decodeBytes(bytes)
        .files
        .singleWhere((file) => file.name == 'xl/worksheets/sheet1.xml');
    final xml = utf8.decode(sheet.content as List<int>);
    expect(xml, contains('Person ID'));
    expect(xml, contains('PersonName'));
    expect(xml, contains('14/09/2026'));
    expect(xml, contains('10000.125'));
    expect(xml, contains('9000.000'));
    expect(xml, contains('POS-14'));
    expect(xml, contains('TOTAL'));
    expect(xml, contains('Entered at'));
  });
}
