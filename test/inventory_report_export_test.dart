import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/services/inventory_report_export.dart';

void main() {
  test('filename uses a Windows-safe export timestamp in IST', () {
    expect(stockReportFileName(DateTime.utc(2026, 11, 19, 20, 34, 5)),
        'Stock_Report_2026-11-20_02-04-05_IST.xlsx');
  });

  test('stock report has numeric quantities and literal product names', () {
    final bytes = buildInventoryWorkbook(
      ['Product', 'Location', 'On hand', 'Reorder at'],
      [
        ['=A1 & <sample>', 'SSH Market', 0, ''],
        ['Mixer', 'SSH Warehouse', 12, 5],
      ],
    );
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    String xml(String file) => utf8.decode(archive.findFile(file)!.content);
    expect(xml('[Content_Types].xml'), contains('/xl/worksheets/sheet1.xml'));
    expect(xml('_rels/.rels'), contains('Target="xl/workbook.xml"'));
    expect(xml('xl/workbook.xml'), contains('name="Stock Report"'));
    expect(xml('xl/_rels/workbook.xml.rels'),
        contains('Target="worksheets/sheet1.xml"'));
    final sheet = xml('xl/worksheets/sheet1.xml');
    expect(sheet, contains('On hand'));
    expect(sheet, contains('=A1 &amp; &lt;sample&gt;'));
    expect(sheet, isNot(contains('<f>')));
    expect(sheet, contains('<v>0</v>'));
    expect(sheet, contains('<v>12</v></c><c><v>5</v>'));
  });
}
