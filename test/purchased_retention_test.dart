import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/models/customer_lead.dart';
import 'package:leadloop/services/local_lead_store.dart';

CustomerLead purchasedLead({
  required String id,
  required DateTime completedAt,
  DateTime? deletedAt,
}) =>
    CustomerLead(
      id: id,
      name: 'Customer',
      phone: '9999999999',
      shopName: 'Shop',
      promoterName: 'Promoter',
      createdAt: completedAt.subtract(const Duration(days: 1)),
      outcome: EnquiryOutcome.purchased,
      completedAt: completedAt,
      deletedAt: deletedAt,
    );

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  test('purchase becomes recyclable exactly ten days after completion', () {
    final lead = purchasedLead(
      id: 'due',
      completedAt: now.subtract(const Duration(days: 10)),
    );
    expect(LocalLeadStore.shouldRecyclePurchased(lead, now), isTrue);
  });

  test('purchase remains active before ten days', () {
    final lead = purchasedLead(
      id: 'not-due',
      completedAt: now.subtract(const Duration(days: 9, hours: 23)),
    );
    expect(LocalLeadStore.shouldRecyclePurchased(lead, now), isFalse);
  });

  test('already recycled purchase is not processed again', () {
    final lead = purchasedLead(
      id: 'deleted',
      completedAt: now.subtract(const Duration(days: 20)),
      deletedAt: now.subtract(const Duration(days: 1)),
    );
    expect(LocalLeadStore.shouldRecyclePurchased(lead, now), isFalse);
  });

  test('active enquiries are never recycled by purchased retention', () {
    final lead = purchasedLead(
      id: 'active',
      completedAt: now.subtract(const Duration(days: 20)),
    ).copyWith(outcome: EnquiryOutcome.active);
    expect(LocalLeadStore.shouldRecyclePurchased(lead, now), isFalse);
  });

  test('restoring a purchased enquiry restarts its ten-day retention period',
      () {
    final restoredAt = DateTime.utc(2026, 9, 25, 8);
    final restored = LocalLeadStore.restoredLead(
      purchasedLead(
        id: 'restored',
        completedAt: DateTime.utc(2026, 9, 1),
      ),
      now: restoredAt,
    );

    expect(restored.deletedAt, isNull);
    expect(restored.isSynced, isFalse);
    expect(restored.completedAt, restoredAt);
    expect(
      LocalLeadStore.shouldRecyclePurchased(
        restored,
        restoredAt.add(const Duration(days: 9)),
      ),
      isFalse,
    );
  });
}
