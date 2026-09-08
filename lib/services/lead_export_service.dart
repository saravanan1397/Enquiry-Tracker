import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/customer_lead.dart';

class LeadExportService {
  Uint8List buildWorkbook({
    required List<CustomerLead> activeLeads,
    required List<CustomerLead> deletedLeads,
  }) {
    final archive = Archive()
      ..addFile(_xmlFile('[Content_Types].xml', _contentTypesXml))
      ..addFile(_xmlFile('_rels/.rels', _rootRelationshipsXml))
      ..addFile(_xmlFile('xl/workbook.xml', _workbookXml))
      ..addFile(
          _xmlFile('xl/_rels/workbook.xml.rels', _workbookRelationshipsXml))
      ..addFile(_xmlFile(
          'xl/worksheets/sheet1.xml', _worksheetXml(_rows(activeLeads))))
      ..addFile(_xmlFile(
          'xl/worksheets/sheet2.xml', _worksheetXml(_rows(deletedLeads))));

    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes);
  }

  ArchiveFile _xmlFile(String name, String xml) {
    final bytes = utf8.encode(xml);
    return ArchiveFile(name, bytes.length, bytes);
  }

  List<List<String>> _rows(List<CustomerLead> leads) => [
        const [
          'Customer name',
          'Mobile number',
          'Shop',
          'Promoter',
          'Created at',
          'Follow-up 1',
          'Follow-up 1 at',
          'Follow-up 2',
          'Follow-up 2 at',
          'Follow-up 3',
          'Follow-up 3 at',
          'Status',
          'Current stage',
          'Deleted at',
        ],
        ...leads.map((lead) => [
              lead.name,
              lead.phone,
              lead.shopName,
              lead.promoterName,
              lead.createdAt.toIso8601String(),
              lead.followUp1 ?? '',
              lead.followUp1At?.toIso8601String() ?? '',
              lead.followUp2 ?? '',
              lead.followUp2At?.toIso8601String() ?? '',
              lead.followUp3 ?? '',
              lead.followUp3At?.toIso8601String() ?? '',
              lead.isCompleted ? 'Completed' : 'Active',
              'Follow-up ${lead.currentStage.index + 1}',
              lead.deletedAt?.toIso8601String() ?? '',
            ]),
      ];

  String _worksheetXml(List<List<String>> rows) {
    final rowsXml = <String>[];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final cells = <String>[];
      for (var columnIndex = 0;
          columnIndex < rows[rowIndex].length;
          columnIndex++) {
        final reference = '${_columnName(columnIndex)}${rowIndex + 1}';
        cells.add(
            '<c r="$reference" t="inlineStr"><is><t>${_escape(rows[rowIndex][columnIndex])}</t></is></c>');
      }
      rowsXml.add('<row r="${rowIndex + 1}">${cells.join()}</row>');
    }
    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <cols>${List.generate(14, (index) => '<col min="${index + 1}" max="${index + 1}" width="${index == 0 || index == 3 ? 24 : 20}" customWidth="1"/>').join()}</cols>
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
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
</Types>''';

  static const _rootRelationshipsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>''';

  static const _workbookXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="Customers" sheetId="1" r:id="rId1"/>
    <sheet name="Recycle Bin" sheetId="2" r:id="rId2"/>
  </sheets>
</workbook>''';

  static const _workbookRelationshipsXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>
</Relationships>''';
}
