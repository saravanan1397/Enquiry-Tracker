import 'dart:typed_data';

import 'package:excel_plus/excel_plus.dart';

import '../models/customer_lead.dart';

class LeadExportService {
  Uint8List buildWorkbook({
    required List<CustomerLead> activeLeads,
    required List<CustomerLead> deletedLeads,
  }) {
    final workbook = Excel.createExcel();
    final customers = workbook['Sheet1'];
    workbook.rename('Sheet1', 'Customers');
    _addHeader(customers);
    for (final lead in activeLeads) {
      _addLead(customers, lead);
    }
    _setWidths(customers);

    final recycleBin = workbook['Recycle Bin'];
    _addHeader(recycleBin);
    for (final lead in deletedLeads) {
      _addLead(recycleBin, lead);
    }
    _setWidths(recycleBin);

    final bytes = workbook.save();
    if (bytes == null) throw StateError('Could not create Excel file.');
    return Uint8List.fromList(bytes);
  }

  void _addHeader(Sheet sheet) {
    sheet.appendRow([
      TextCellValue('Customer name'),
      TextCellValue('Mobile number'),
      TextCellValue('Shop'),
      TextCellValue('Promoter'),
      TextCellValue('Created at'),
      TextCellValue('Follow-up 1'),
      TextCellValue('Follow-up 2'),
      TextCellValue('Follow-up 3'),
      TextCellValue('Current stage'),
      TextCellValue('Deleted at'),
    ]);
  }

  void _addLead(Sheet sheet, CustomerLead lead) {
    sheet.appendRow([
      TextCellValue(lead.name),
      TextCellValue(lead.phone),
      TextCellValue(lead.shopName),
      TextCellValue(lead.promoterName),
      TextCellValue(lead.createdAt.toIso8601String()),
      TextCellValue(lead.followUp1 ?? ''),
      TextCellValue(lead.followUp2 ?? ''),
      TextCellValue(lead.followUp3 ?? ''),
      TextCellValue('Follow-up ${lead.currentStage.index + 1}'),
      TextCellValue(lead.deletedAt?.toIso8601String() ?? ''),
    ]);
  }

  void _setWidths(Sheet sheet) {
    for (var index = 0; index < 10; index++) {
      sheet.setColumnWidth(index, index == 0 || index == 3 ? 24 : 20);
    }
  }
}
