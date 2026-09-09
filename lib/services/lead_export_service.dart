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
      ..addFile(_xmlFile('xl/styles.xml', _stylesXml))
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

  List<List<String>> _rows(List<CustomerLead> leads) {
    final extraCount = leads.fold<int>(
        0,
        (count, lead) => lead.additionalFollowUps.length > count
            ? lead.additionalFollowUps.length
            : count);
    return [
      [
        'Customer name',
        'Mobile number',
        'Shop',
        'Promoter',
        'Created at',
        'Follow-up 1',
        'Follow-up 2',
        'Follow-up 3',
        for (var i = 0; i < extraCount; i++) 'Follow-up ${i + 4}',
        'Status',
        'Completed at',
        'Current stage',
        'Deleted at',
      ],
      ...leads.map((lead) => [
            lead.name,
            lead.phone,
            lead.shopName,
            lead.promoterName,
            _formatDateTime(lead.createdAt),
            _followUpWithTimestamp(lead.followUp1, lead.followUp1At),
            _followUpWithTimestamp(lead.followUp2, lead.followUp2At),
            _followUpWithTimestamp(lead.followUp3, lead.followUp3At),
            for (var i = 0; i < extraCount; i++)
              i < lead.additionalFollowUps.length
                  ? _followUpWithTimestamp(lead.additionalFollowUps[i].comment,
                      lead.additionalFollowUps[i].enteredAt)
                  : '',
            lead.outcomeLabel,
            lead.completedAt == null ? '' : _formatDateTime(lead.completedAt!),
            'Follow-up ${lead.followUpNumber}',
            lead.deletedAt == null ? '' : _formatDateTime(lead.deletedAt!),
          ]),
    ];
  }

  String _followUpWithTimestamp(String? comment, DateTime? timestamp) {
    final trimmedComment = comment?.trim() ?? '';
    if (trimmedComment.isEmpty) {
      return timestamp == null ? '' : _formatFollowUpTimestamp(timestamp);
    }
    if (timestamp == null) return trimmedComment;
    return '$trimmedComment || ${_formatFollowUpTimestamp(timestamp)}';
  }

  String _formatFollowUpTimestamp(DateTime value) {
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final period = value.hour >= 12 ? 'PM' : 'AM';
    return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year} '
        '${hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')} $period';
  }

  String _formatDateTime(DateTime value) {
    return value.toIso8601String().replaceFirst('T', ' ');
  }

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
  <cols>${List.generate(rows.first.length, (index) => '<col min="${index + 1}" max="${index + 1}" width="${index == 0 || index == 3 ? 24 : 30}" customWidth="1"/>').join()}</cols>
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
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>''';

  static const _stylesXml =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>
  <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FFFFEB3B"/><bgColor indexed="64"/></patternFill></fill></fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>
</styleSheet>''';
}
