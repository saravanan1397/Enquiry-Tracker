import 'package:flutter_test/flutter_test.dart';
import 'dart:convert';

import 'package:archive/archive.dart';
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

    final files = ZipDecoder().decodeBytes(bytes).files;
    final customers =
        files.singleWhere((file) => file.name == 'xl/worksheets/sheet1.xml');
    final recycleBin =
        files.singleWhere((file) => file.name == 'xl/worksheets/sheet2.xml');
    final styles = files.singleWhere((file) => file.name == 'xl/styles.xml');
    final customersXml = utf8.decode(customers.content as List<int>);
    expect(customersXml, contains('Active customer'));
    expect(customersXml, contains('Initial enquiry || 08-09-2026 10:00 AM'));
    expect(customersXml, contains('Follow-up 1'));
    expect(customersXml, isNot(contains('Follow-up 1 at')));
    expect(customersXml, contains('s="1"'));
    expect(utf8.decode(styles.content as List<int>), contains('FFFFEB3B'));
    expect(utf8.decode(recycleBin.content as List<int>),
        contains('Deleted customer'));
  });
}
