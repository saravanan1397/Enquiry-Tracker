import 'package:flutter_test/flutter_test.dart';

import '../lib/services/inventory_store.dart';

void main() {
  test('all four stock locations match the approved labels', () {
    expect(inventoryLocations.values, [
      'SSH Market',
      'SSH Warehouse',
      'SSH TNHB',
      'Selvan Hotel Mart',
    ]);
  });

  test('a blank draft stays optional but cannot post', () {
    const movement = InventoryMovement();
    expect(movement.draftFields()['quantity'], isNull);
    expect(() => movement.deltaFor(0), throwsFormatException);
  });

  test('stock out cannot make the balance negative', () {
    const movement = InventoryMovement(
      type: 'sale',
      location: 'warehouse',
      productId: 'product',
      quantity: 3,
    );
    expect(movement.deltaFor(5), -3);
    expect(() => movement.deltaFor(2), throwsFormatException);
  });

  test('physical count records the variance and accepts zero on hand', () {
    const movement = InventoryMovement(
      type: 'count',
      location: 'hotelmart',
      productId: 'product',
      quantity: 0,
    );
    expect(movement.deltaFor(6), -6);
    expect(movement.deltaFor(0), 0);
  });
}
