import 'inventory_store.dart';

typedef InventoryReport = ({List<String> headings, List<List<Object>> rows});
typedef _StockKey = ({String product, String location});

InventoryReport buildInventoryReport(
  InventoryReportSource source, {
  required Map<String, String> locations,
  required bool Function(Iterable<Object?>) matches,
}) {
  final products = {for (final row in source.products) row.id: row.data()};
  final balances = <_StockKey, int>{};
  final movements = <_StockKey, Map<String, int>>{};
  final keys = <_StockKey>{};

  _StockKey? keyOf(Map<String, dynamic> data) {
    final product = data['productId'], location = data['location'];
    if (product is! String ||
        location is! String ||
        products[product]?['deletedAt'] != null) return null;
    final values = products[product];
    if (!matches([
      _reportProductName(values?['name']),
      values?['sku'],
      values?['category'],
      values?['barcode'],
      locations[location] ?? location,
    ])) return null;
    return (product: product, location: location);
  }

  for (final doc in source.balances) {
    final data = doc.data();
    final key = keyOf(data);
    if (key == null || data['quantity'] is! int) continue;
    keys.add(key);
    balances[key] = data['quantity'] as int;
  }

  final present = <String>{};
  for (final doc in source.movements) {
    final data = doc.data();
    final type = data['type'];
    if (type is! String ||
        type.isEmpty ||
        type == 'opening' ||
        type == 'count') {
      continue;
    }
    final key = keyOf(data);
    final delta = data['delta'];
    final units = data['quantity'];
    if (key == null) continue;
    final amount = switch (type) {
      'adjustment' => delta is int ? delta : null,
      _ => units is int ? units.abs() : (delta is int ? delta.abs() : null),
    };
    if (amount == null) continue;
    keys.add(key);
    present.add(type);
    final totals = movements.putIfAbsent(key, () => {});
    totals.update(type, (total) => total + amount, ifAbsent: () => amount);
  }

  final extra =
      present.difference(inventoryMovementLabels.keys.toSet()).toList()..sort();
  final types = [
    ...inventoryMovementLabels.keys.where(present.contains),
    ...extra,
  ];
  return (
    headings: [
      'Product',
      'Location',
      'Total Stock',
      'Reorder at',
      'Unit cost INR',
      'Stock value INR',
      for (final type in types)
        type == 'damage' ? 'Damaged' : inventoryMovementLabels[type] ?? type,
    ],
    rows: [
      for (final key in keys)
        [
          _reportProductName(products[key.product]?['name']),
          locations[key.location] ?? key.location,
          balances[key] ?? '',
          products[key.product]?['reorder'] ?? '',
          inventoryStockValue(products[key.product]?['unitCost'] as int?, 1),
          if (balances[key] case final int count)
            inventoryStockValue(
                products[key.product]?['unitCost'] as int?, count)
          else
            '',
          for (final type in types) movements[key]?[type] ?? 0,
        ],
    ],
  );
}

String _reportProductName(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : 'Unnamed product';

Object inventoryStockValue(int? cost, int quantity) {
  if (cost == null || (cost > 0 && quantity > 9007199254740991 ~/ cost)) {
    return '';
  }
  return cost * quantity / 100;
}
