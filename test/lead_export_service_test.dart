import 'package:flutter_test/flutter_test.dart';
import 'package:excel_plus/excel_plus.dart';
import 'package:leadloop/models/customer_lead.dart';
import 'package:leadloop/services/lead_export_service.dart';

void main() {
  test('builds a valid Excel workbook for active and deleted leads', () {
    final active = CustomerLead(
      id: 'active-1',
      name: 'Active customer',
      phone: '9000000000',
      shopName: 'Branch 1',
      promoterName: 'Promoter 1',
      createdAt: DateTime(2026, 9, 8, 10),
      followUp1: 'Initial enquiry',
      followUp1At: DateTime(2026, 9, 8, 10),
    );
    final deleted = CustomerLead(
      id: 'deleted-1',
      name: 'Deleted customer',
      phone: '9111111111',
      shopName: 'Branch 2',
      promoterName: 'Promoter 2',
      createdAt: DateTime(2026, 9, 7, 10),
      deletedAt: DateTime(2026, 9, 8, 9),
    );

    final bytes = LeadExportService().buildWorkbook(
      activeLeads: [active],
      deletedLeads: [deleted],
    );

    expect(bytes, isNotEmpty);
    expect(bytes.take(2).toList(), [0x50, 0x4B]);

    final workbook = Excel.decodeBytes(bytes);
    expect(workbook.tables.keys, containsAll(['Customers', 'Recycle Bin']));
    final activeCell = workbook['Customers'].rows[1][0]?.value;
    final deletedCell = workbook['Recycle Bin'].rows[1][0]?.value;
    expect((activeCell as TextCellValue).value.text, 'Active customer');
    expect((deletedCell as TextCellValue).value.text, 'Deleted customer');
  });
}
