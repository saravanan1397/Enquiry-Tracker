part of 'inventory_store.dart';

int? inventoryCostPaise(String value) {
  final input = value.trim();
  if (input.isEmpty) return null;
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(input)) {
    throw const FormatException(
        'Enter a cost in rupees with up to two decimal places.');
  }
  final fields = input.split('.');
  return int.parse(fields.first) * 100 +
      (fields.length == 2 ? int.parse(fields.last.padRight(2, '0')) : 0);
}

String inventoryRupees(int? paise) => paise == null
    ? ''
    : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

String? inventoryStockChangeError(int before, int delta) {
  if (before + delta < 0) {
    return 'Not enough stock at this location. Available: $before.';
  }
  if (before + delta > 1000000000) return 'Stock exceeds the quantity limit.';
  return null;
}

class InventoryPurchaseLine {
  const InventoryPurchaseLine(
      this.id, this.product, this.quantity, this.unitCost);
  final String id;
  final String? product;
  final int? quantity, unitCost;
}

extension InventorySupplyStore on InventoryStore {
  CollectionReference<Map<String, dynamic>> get _suppliers =>
      _db.collection('is_suppliers');
  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('is_orders');
  CollectionReference<Map<String, dynamic>> get _transfers =>
      _db.collection('is_transfers');

  Future<InventoryRows> suppliers() =>
      _suppliers.orderBy('name').limit(101).get(InventoryStore._server);
  Future<InventoryRows> purchaseOrders() => _orders
      .orderBy('at', descending: true)
      .limit(101)
      .get(InventoryStore._server);
  Future<InventoryRows> branchTransfers() => _transfers
      .orderBy('at', descending: true)
      .limit(101)
      .get(InventoryStore._server);

  Future<void> saveSupplier(
      {String? id,
      required String name,
      required String phone,
      required String email,
      required String notes,
      required bool active}) async {
    if (name.trim().isEmpty)
      throw const FormatException('Enter a supplier name.');
    await _suppliers.doc(id).set({
      'name': name.trim(),
      'phone': phone.trim(),
      'email': email.trim(),
      'notes': notes.trim(),
      'active': active,
      'actor': _uid,
      'at': FieldValue.serverTimestamp(),
    });
  }

  String newPurchaseOrderId() => _orders.doc().id;
  String newTransferId() => _transfers.doc().id;

  Future<void> createPurchaseOrder(
      {required String? supplier,
      required String? location,
      required List<InventoryPurchaseLine> lines,
      required String reference}) async {
    if (supplier == null ||
        location == null ||
        lines.isEmpty ||
        lines.length > 5 ||
        lines.any((line) =>
            line.product == null ||
            line.quantity == null ||
            line.quantity! < 1 ||
            line.quantity! > 1000000)) {
      throw const FormatException(
          'Choose a supplier and branch. Each product line needs a quantity from 1 to 1,000,000.');
    }
    if (lines.map((line) => line.product).toSet().length != lines.length) {
      throw const FormatException(
          'List each product only once per purchase order.');
    }
    final referenceLabel = reference.trim().isEmpty
        ? 'PO-' + lines.first.id.substring(0, 8)
        : reference.trim();
    final stamp = FieldValue.serverTimestamp();
    final batch = _db.batch();
    for (final line in lines) {
      batch.set(_orders.doc(line.id), {
        'supplierId': supplier,
        'productId': line.product,
        'location': location,
        'quantity': line.quantity,
        'received': 0,
        'unitCost': line.unitCost,
        'reference': referenceLabel,
        'status': 'ordered',
        'lastReceiptId': null,
        'actor': _uid,
        'at': stamp,
        'updatedAt': stamp,
      });
    }
    await batch.commit();
  }

  Future<void> cancelPurchaseOrder(String id) async {
    final order = _orders.doc(id);
    await _transaction((tx) async {
      final data = (await tx.get(order)).data();
      if (data == null || !['ordered', 'partial'].contains(data['status'])) {
        return 'This purchase order is no longer open.';
      }
      tx.update(order,
          {'status': 'cancelled', 'updatedAt': FieldValue.serverTimestamp()});
      return null;
    });
  }

  Future<void> receivePurchase(
      {required String id,
      required String receiptId,
      required int? quantity}) async {
    if (quantity == null || quantity < 1 || quantity > 1000000) {
      throw const FormatException('Enter a positive receipt quantity.');
    }
    final order = _orders.doc(id), movement = _movements.doc(receiptId);
    await _transaction((tx) async {
      final already = (await tx.get(movement)).data();
      if (already != null) {
        return already['workflowId'] == id &&
                already['type'] == 'purchase_receipt'
            ? null
            : 'Receipt ID already used.';
      }
      final data = (await tx.get(order)).data();
      if (data == null || !['ordered', 'partial'].contains(data['status']))
        return 'This order is no longer open.';
      final received = data['received'] as int,
          ordered = data['quantity'] as int;
      if (quantity > ordered - received)
        return 'Only ${ordered - received} units remain to receive.';
      final error = await _linkedMovement(tx,
          movement: movement,
          type: 'purchase_receipt',
          id: id,
          product: data['productId'] as String,
          location: data['location'] as String,
          units: quantity);
      if (error != null) return error;
      tx.update(order, {
        'received': received + quantity,
        'status': received + quantity == ordered ? 'received' : 'partial',
        'lastReceiptId': receiptId,
        'updatedAt': FieldValue.serverTimestamp()
      });
      return null;
    });
  }

  Future<void> dispatchTransfer(
      {required String id,
      required String movementId,
      required String? from,
      required String? to,
      required String? product,
      required int? quantity,
      String? draftId}) async {
    if (from == null ||
        to == null ||
        product == null ||
        quantity == null ||
        quantity < 1 ||
        quantity > 1000000) {
      throw const FormatException(
          'Choose an origin, destination, product, and a positive quantity.');
    }
    if (from == to)
      throw const FormatException('Choose two different locations.');
    final transfer = _transfers.doc(id), movement = _movements.doc(movementId);
    await _transaction((tx) async {
      final already = (await tx.get(transfer)).data();
      if (already != null) {
        return already['dispatchId'] == movementId && already['actor'] == _uid
            ? null
            : 'Transfer ID already used.';
      }
      if ((await tx.get(movement)).exists) return 'Movement ID already used.';
      if (!await _activeBranch(tx, to)) return 'Choose an active destination.';
      final error = await _linkedMovement(tx,
          movement: movement,
          type: 'transfer_out',
          id: id,
          product: product,
          location: from,
          units: quantity);
      if (error != null) return error;
      tx.set(transfer, {
        'productId': product,
        'from': from,
        'to': to,
        'quantity': quantity,
        'status': 'in_transit',
        'dispatchId': movementId,
        'receiveId': null,
        'receiptActor': null,
        'receivedAt': null,
        'actor': _uid,
        'at': FieldValue.serverTimestamp()
      });
      if (draftId != null) tx.delete(_drafts.doc(draftId));
      return null;
    });
  }

  Future<void> receiveTransfer(String id, String receiptId) async {
    final transfer = _transfers.doc(id), movement = _movements.doc(receiptId);
    await _transaction((tx) async {
      final data = (await tx.get(transfer)).data();
      if (data == null) return 'Transfer was not found.';
      if (data['status'] != 'in_transit') {
        return data['receiveId'] == receiptId
            ? null
            : 'This transfer has already been received.';
      }
      if ((await tx.get(movement)).exists) return 'Receipt ID already used.';
      final error = await _linkedMovement(tx,
          movement: movement,
          type: 'transfer_in',
          id: id,
          product: data['productId'] as String,
          location: data['to'] as String,
          units: data['quantity'] as int);
      if (error != null) return error;
      tx.update(transfer, {
        'status': 'received',
        'receiveId': receiptId,
        'receiptActor': _uid,
        'receivedAt': FieldValue.serverTimestamp()
      });
      return null;
    });
  }

  Future<void> _transaction(Future<String?> Function(Transaction) body) async {
    final error = await _db.runTransaction<String?>((tx) => body(tx));
    if (error != null) throw FormatException(error);
  }

  Future<bool> _activeBranch(Transaction tx, String id) async {
    final location = await tx.get(_locations.doc(id));
    return location.exists
        ? (location.data()?['active'] == true)
        : inventoryLocations.containsKey(id);
  }

  Future<String?> _linkedMovement(Transaction tx,
      {required DocumentReference<Map<String, dynamic>> movement,
      required String type,
      required String id,
      required String product,
      required String location,
      required int units}) async {
    final item = await tx.get(_products.doc(product));
    if (item.data()?['active'] != true) return 'Choose an active product.';
    if (!await _activeBranch(tx, location))
      return 'Choose an active stock location.';
    final balance = _balances.doc('${location}_${product}');
    final before = (await tx.get(balance)).data()?['quantity'] as int? ?? 0;
    final delta = type == 'transfer_out' ? -units : units;
    final error = inventoryStockChangeError(before, delta);
    if (error != null) return error;
    final stamp = FieldValue.serverTimestamp();
    tx.set(balance, {
      'productId': product,
      'location': location,
      'quantity': before + delta,
      'lastMovementId': movement.id,
      'at': stamp
    });
    tx.set(movement, {
      'type': type,
      'location': location,
      'productId': product,
      'quantity': units,
      'note': '',
      'workflowId': id,
      'balanceId': balance.id,
      'before': before,
      'delta': delta,
      'quantityAfter': before + delta,
      'actor': _uid,
      'at': stamp
    });
    return null;
  }
}
