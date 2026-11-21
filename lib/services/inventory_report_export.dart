import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

Uint8List buildInventoryCsv(List<String> headings, List<List<Object>> rows) {
  final riskyText = RegExp(r'^\s*[=+@-]|^[\t\r\n]');
  String cell(Object value) {
    final text = value.toString();
    final safe = value is num || !riskyText.hasMatch(text) ? text : "'$text";
    return '"${safe.replaceAll('"', '""')}"';
  }

  return Uint8List.fromList(utf8.encode('\uFEFF${[
    headings,
    ...rows
  ].map((row) => row.map(cell).join(',')).join('\r\n')}'));
}

String stockReportFileName(DateTime exportedAt) {
  final ist = exportedAt.toUtc().add(const Duration(hours: 5, minutes: 30));
  String two(int value) => value.toString().padLeft(2, '0');
  return 'Stock_Report_${ist.year}-${two(ist.month)}-${two(ist.day)}_'
      '${two(ist.hour)}-${two(ist.minute)}-${two(ist.second)}_IST.xlsx';
}

Uint8List buildInventoryWorkbook(
    List<String> headers, List<List<Object>> rows) {
  const namespace = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
  const relationship =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const declaration = '<?xml version="1.0" encoding="UTF-8"?>';
  final archive = Archive();
  void addXml(String path, String body) {
    final bytes = utf8.encode('$declaration$body');
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addXml('[Content_Types].xml', '''
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''');
  const relationships =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  addXml('_rels/.rels', '''
<Relationships xmlns="$relationships">
  <Relationship Id="rId1" Type="$relationship/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''');
  addXml('xl/workbook.xml', '''
<workbook xmlns="$namespace" xmlns:r="$relationship">
  <sheets><sheet name="Stock Report" sheetId="1" r:id="rId1"/></sheets>
</workbook>''');
  addXml('xl/_rels/workbook.xml.rels', '''
<Relationships xmlns="$relationships">
  <Relationship Id="rId1" Type="$relationship/worksheet" Target="worksheets/sheet1.xml"/>
</Relationships>''');

  const escape = HtmlEscape(HtmlEscapeMode.element);
  final control = RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]');
  final sheet = StringBuffer('''
<worksheet xmlns="$namespace">
<cols>
  <col min="1" max="2" width="32" customWidth="1"/>
  <col min="3" max="4" width="14" customWidth="1"/>
  <col min="5" max="6" width="22" customWidth="1"/>
</cols><sheetData>''');
  for (final (index, row) in [headers, ...rows].indexed) {
    sheet.write('<row r="${index + 1}">');
    for (final value in row) {
      if (value is num && value.isFinite) {
        sheet.write('<c><v>$value</v></c>');
      } else {
        final literal =
            escape.convert(value.toString().replaceAll(control, ''));
        sheet.write(
            '<c t="inlineStr"><is><t xml:space="preserve">$literal</t></is></c>');
      }
    }
    sheet.write('</row>');
  }
  sheet.write('</sheetData></worksheet>');
  addXml('xl/worksheets/sheet1.xml', sheet.toString());
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
