import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/sales_record.dart';

class SalesExportService {
  Uint8List buildWorkbook({
    required List<SalesRecord> records,
    required DateTime exportedAt,
  }) {
    final rows = <List<String>>[
      [
        'Person ID',
        'Salesperson name',
        'Sales date',
        'Daily sales amount (INR)',
        'Reference / remarks',
        'Entered at',
        'Last edited at',
        'Previous amount (INR)',
        'Entered by',
        'Last edited by',
      ],
      ...records.map((record) => [
            record.personId,
            record.personName,
            _date(record.salesDate),
            formatAmountMilli(record.amountMilli),
            record.reference,
            _timestamp(record.createdAt),
            _timestamp(record.updatedAt),
            record.previousAmountMilli == null
                ? ''
                : formatAmountMilli(record.previousAmountMilli!),
            record.enteredByName,
            record.lastEditedByName ?? '',
          ]),
      [
        '',
        'TOTAL',
        '',
        formatAmountMilli(
            records.fold<int>(0, (total, row) => total + row.amountMilli)),
        '',
        '',
        '',
        '',
        '',
        '',
      ],
      ['', 'Exported at', '', _timestamp(exportedAt), '', '', '', '', '', ''],
    ];

    final archive = Archive()
      ..addFile(_xmlFile('[Content_Types].xml', _contentTypesXml))
      ..addFile(_xmlFile('_rels/.rels', _rootRelationshipsXml))
      ..addFile(_xmlFile('xl/workbook.xml', _workbookXml))
      ..addFile(
          _xmlFile('xl/_rels/workbook.xml.rels', _workbookRelationshipsXml))
      ..addFile(_xmlFile('xl/styles.xml', _stylesXml))
      ..addFile(_xmlFile('xl/worksheets/sheet1.xml', _worksheetXml(rows)));
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  ArchiveFile _xmlFile(String name, String xml) {
    final bytes = utf8.encode(xml);
    return ArchiveFile(name, bytes.length, bytes);
  }

  String _timestamp(DateTime? value) {
    if (value == null) return '';
    final local = indiaDateTime(value);
    return '${_date(local)} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _date(DateTime value) => '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _worksheetXml(List<List<String>> rows) {
    final rowsXml = <String>[];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final cells = <String>[];
      for (var columnIndex = 0;
          columnIndex < rows[rowIndex].length;
          columnIndex++) {
        final reference = '${_columnName(columnIndex)}${rowIndex + 1}';
        final style = rowIndex == 0 ? ' s="1"' : '';
        cells.add(
            '<c r="$reference"$style t="inlineStr"><is><t>${_escape(rows[rowIndex][columnIndex])}</t></is></c>');
      }
      rowsXml.add('<row r="${rowIndex + 1}">${cells.join()}</row>');
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cols>${List.generate(rows.first.length, (index) => '<col min="${index + 1}" max="${index + 1}" width="${index == 0 ? 28 : index == 1 ? 24 : 22}" customWidth="1"/>').join()}</cols>
  <sheetData>${rowsXml.join()}</sheetData>
</worksheet>''';
  }

  String _columnName(int index) {
    var value = index + 1;
    var name = '';
    while (value > 0) {
      final remainder = (value - 1) % 26;
      name = String.fromCharCode(65 + remainder) + name;
      value = (value - 1) ~/ 26;
    }
    return name;
  }

  String _escape(String value) => value
      .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static const _contentTypesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';

  static const _rootRelationshipsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static const _workbookXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets><sheet name="Daily Sales" sheetId="1" r:id="rId1"/></sheets>
</workbook>''';

  static const _workbookRelationshipsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  static const _stylesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF4F46E5"/><bgColor indexed="64"/></patternFill></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>
</styleSheet>''';
}
