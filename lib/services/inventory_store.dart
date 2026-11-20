import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

part 'inventory_supply_store.dart';

typedef InventoryRow = QueryDocumentSnapshot<Map<String, dynamic>>;
typedef InventoryRows = QuerySnapshot<Map<String, dynamic>>;

const inventoryLocations = {
  'avadi': 'SSH Market',
  'warehouse': 'SSH Warehouse',
  'tnhb': 'SSH TNHB',
  'hotelmart': 'Selvan Hotel Mart',
};

class InventoryLocation {
  const InventoryLocation(this.id, this.name, {this.active = true});
  final String id, name;
  final bool active;
}

List<InventoryLocation> mergeInventoryLocations(
    Iterable<InventoryLocation> stored) {
  final byId = {
    for (final entry in inventoryLocations.entries)
      entry.key: InventoryLocation(entry.key, entry.value),
  };
  for (final location in stored) {
    byId[location.id] = location;
  }
  return byId.values.toList()
    ..sort((a, b) {
      if (a.active != b.active) return a.active ? -1 : 1;
      final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
}

const inventoryMovementTypes = {
  'opening': 'Opening stock',
  'receipt': 'Stock in',
  'sale': 'Stock out',
  'customer_return': 'Customer return',
  'supplier_return': 'Supplier return',
  'damage': 'Damage',
  'adjustment': 'Adjustment',
  'count': 'Physical count',
};
const inventoryMovementLabels = {
  ...inventoryMovementTypes,
  'purchase_receipt': 'Purchase receipt',
  'transfer_out': 'Transfer out',
  'transfer_in': 'Transfer in',
};

class InventoryMovement {
  const InventoryMovement(
      {this.type,
      this.location,
      this.productId,
      this.quantity,
      this.note = ''});

  final String? type, location, productId;
  final int? quantity;
  final String note;

  Map<String, dynamic> draftFields() => {
        'type': type,
        'location': location,
        'productId': productId,
        'quantity': quantity,
        'note': note.trim(),
      };

  int deltaFor(int current) {
    final q = quantity;
    if (!inventoryMovementTypes.containsKey(type) ||
        location == null ||
        location!.isEmpty ||
        productId == null ||
        productId!.isEmpty ||
        q == null) {
      throw const FormatException(
          'Select a movement type, product, location, and quantity to post.');
    }
    if (q.abs() > 1000000 ||
        (type == 'count'
            ? q < 0
            : type == 'adjustment'
                ? q == 0
                : q <= 0)) {
      throw const FormatException('Enter a valid quantity for this movement.');
    }
    final delta = switch (type) {
      'count' => q - current,
      'sale' || 'supplier_return' || 'damage' => -q,
      _ => q,
    };
    if (current + delta < 0) {
      throw const FormatException('Not enough stock at this location.');
    }
    if (current + delta > 1000000000) {
      throw const FormatException('Stock exceeds the quantity limit.');
    }
    return delta;
  }
}

class InventoryStore {
  InventoryStore({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  static const _server = GetOptions(source: Source.server);

  String get _uid =>
      _auth.currentUser?.uid ??
      (throw const FormatException(
          'Sign in as an admin before updating inventory.'));

  CollectionReference<Map<String, dynamic>> get _products =>
      _db.collection('is_products');
  CollectionReference<Map<String, dynamic>> get _balances =>
      _db.collection('is_balances');
  CollectionReference<Map<String, dynamic>> get _movements =>
      _db.collection('is_movements');
  CollectionReference<Map<String, dynamic>> get _drafts =>
      _db.collection('is_drafts');
  CollectionReference<Map<String, dynamic>> get _locations =>
      _db.collection('is_locations');

  String newMovementId() => _movements.doc().id;
  String newDraftId() => _drafts.doc().id;
  String newTransferId() => _transfers.doc().id;

  Future<InventoryRows> products() => _products.limit(101).get(_server);

  Future<InventoryRows> deletedProducts() =>
      _products.orderBy('deletedAt', descending: true).limit(101).get(_server);

  Future<void> setProductRecycled(String id, {required bool recycled}) async {
    final product = _products.doc(id);
    final actor = _uid;
    final error = await _db.runTransaction<String?>((tx) async {
      final data = (await tx.get(product)).data();
      if (data == null) return 'This product no longer exists.';
      if ((data['deletedAt'] != null) == recycled) return null;
      final stamp = FieldValue.serverTimestamp();
      tx.update(product, {
        'active': recycled ? false : data['activeBeforeDelete'] == true,
        'deletedAt': recycled ? stamp : FieldValue.delete(),
        'activeBeforeDelete':
            recycled ? data['active'] == true : FieldValue.delete(),
        'actor': actor,
        'at': stamp,
      });
      return null;
    });
    if (error != null) throw FormatException(error);
  }

  Future<InventoryRows> suppliers() =>
      _suppliers.orderBy('name').limit(101).get(_server);

  Future<InventoryRows> legacyTransfers() => _db
      .collection('is_transfers')
      .where('status', isEqualTo: 'in_transit')
      .limit(101)
      .get(_server);

  Future<void> transferStock(
          {required String id,
          required String outgoingId,
          required String incomingId,
          required String from,
          required String to,
          required String product,
          required int quantity,
          String? draftId}) =>
      _transferNow(
          id: id,
          outgoingId: outgoingId,
          incomingId: incomingId,
          from: from,
          to: to,
          product: product,
          quantity: quantity,
          draftId: draftId);

  Future<List<InventoryLocation>> locations() async {
    final stored = <InventoryLocation>[];
    DocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> query =
          _locations.orderBy(FieldPath.documentId).limit(100);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final page = await query.get(_server);
      for (final doc in page.docs) {
        stored.add(InventoryLocation(doc.id, doc.data()['name'] as String,
            active: doc.data()['active'] == true));
      }
      if (page.docs.length < 100) return mergeInventoryLocations(stored);
      cursor = page.docs.last;
    }
  }

  Future<void> saveLocation(
      {String? id, required String name, bool active = true}) {
    final value = name.trim();
    if (value.isEmpty || value.length > 120) {
      throw const FormatException(
          'Enter a location name up to 120 characters.');
    }
    return _locations.doc(id).set({
      'name': value,
      'active': active,
      'actor': _uid,
      'at': FieldValue.serverTimestamp(),
    });
  }

  Future<InventoryRows> balances({String? location}) => (location == null
          ? _balances
          : _balances.where('location', isEqualTo: location))
      .limit(101)
      .get(_server);

  Future<InventoryRows> movements({String? location}) => (location == null
          ? _movements.orderBy('at', descending: true)
          : _movements.where('location', isEqualTo: location))
      .limit(101)
      .get(_server);

  Future<InventoryRows> counts({String? location}) => (location == null
          ? _movements.where('type', isEqualTo: 'count')
          : _movements
              .where('type', isEqualTo: 'count')
              .where('location', isEqualTo: location))
      .limit(101)
      .get(_server);

  Future<InventoryRows> drafts({String? location}) {
    Query<Map<String, dynamic>> query = _drafts.where('actor', isEqualTo: _uid);
    if (location != null) query = query.where('location', isEqualTo: location);
    return query.limit(101).get(_server);
  }

  Future<void> saveProduct(
      {String? id,
      required String name,
      required String sku,
      required String category,
      String barcode = '',
      String? supplierId,
      int? unitCost,
      required int? reorder,
      required bool active}) {
    if (reorder != null && (reorder < 0 || reorder > 1000000)) {
      throw const FormatException(
          'Use a non-negative reorder level up to 1,000,000.');
    }
    return _products.doc(id).set({
      'name': name.trim(),
      'sku': sku.trim(),
      'category': category.trim(),
      'barcode': barcode.trim(),
      'supplierId': supplierId,
      'unitCost': unitCost,
      'reorder': reorder,
      'active': active,
      'actor': _uid,
      'at': FieldValue.serverTimestamp(),
    });
  }

  Future<void> saveDraft(InventoryMovement entry, {required String id}) {
    if ((entry.quantity?.abs() ?? 0) > 1000000) {
      throw const FormatException(
          'Use a quantity between -1,000,000 and 1,000,000.');
    }
    return _drafts.doc(id).set({
      ...entry.draftFields(),
      'actor': _uid,
      'at': FieldValue.serverTimestamp()
    });
  }

  Future<void> post(InventoryMovement entry,
      {required String movementId, String? draftId}) async {
    entry.deltaFor(100000000);
    final actor = _uid;
    final product = _products.doc(entry.productId);
    final balance = _balances.doc('${entry.location}_${entry.productId}');
    final movement = _movements.doc(movementId);
    // Return input errors from the transaction without writes. Throwing inside
    // the web transaction callback can hide the original validation message.
    final validation = await _db.runTransaction<String?>((tx) async {
      final alreadyPosted = await tx.get(movement);
      if (alreadyPosted.exists) {
        if (alreadyPosted.data()?['actor'] != actor)
          return 'This movement ID is already used.';
        return null;
      }
      final item = await tx.get(product);
      if (item.data()?['active'] != true) return 'Choose an active product.';
      final location = await tx.get(_locations.doc(entry.location));
      final isActive = location.exists
          ? (location.data()?['active'] == true)
          : inventoryLocations.containsKey(entry.location);
      if (!isActive) {
        return 'Choose an active stock location.';
      }
      final stock = await tx.get(balance);
      final before = stock.data()?['quantity'] as int? ?? 0;
      final int change;
      try {
        change = entry.deltaFor(before);
      } on FormatException catch (error) {
        if (error.message == 'Not enough stock at this location.') {
          return 'Not enough stock at this location. Available: $before.';
        }
        return error.message;
      }
      final next = before + change;
      final stamp = FieldValue.serverTimestamp();
      tx.set(balance, {
        'productId': entry.productId,
        'location': entry.location,
        'quantity': next,
        'lastMovementId': movement.id,
        'at': stamp,
      });
      tx.set(movement, {
        ...entry.draftFields(),
        'balanceId': balance.id,
        'before': before,
        'delta': change,
        'quantityAfter': next,
        'actor': actor,
        'at': stamp,
      });
      if (draftId != null) tx.delete(_drafts.doc(draftId));
      return null;
    });
    if (validation != null) throw FormatException(validation);
  }
}
