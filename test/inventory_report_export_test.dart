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
      ['Product', 'Location', 'Total Stock', 'Reorder at'],
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
    expect(sheet, contains('Total Stock'));
    expect(sheet, contains('=A1 &amp; &lt;sample&gt;'));
    expect(sheet, isNot(contains('<f>')));
    expect(sheet, contains('<v>0</v>'));
    expect(sheet, contains('<v>12</v></c><c><v>5</v>'));
  });

  test('both export formats keep dynamic headings and signed totals', () {
    const headings = ['Product', 'Damaged', 'Adjustment'];
    const rows = <List<Object>>[
      ['=sample', 1, -3]
    ];
    final csv = utf8.decode(buildInventoryCsv(headings, rows));
    expect(csv, contains('"Product","Damaged","Adjustment"'));
    expect(csv, contains('"\'=sample","1","-3"'));
    final zip =
        ZipDecoder().decodeBytes(buildInventoryWorkbook(headings, rows));
    final sheet =
        utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content);
    expect(sheet, contains('Damaged'));
    expect(sheet, contains('<v>1</v>'));
    expect(sheet, contains('<v>-3</v>'));
  });
}
