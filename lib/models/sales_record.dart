class SalesPerson {
  const SalesPerson({
    required this.id,
    required this.name,
    required this.normalizedName,
    this.createdAt,
  });

  final String id;
  final String name;
  final String normalizedName;
  final DateTime? createdAt;
}

class SalesRecord {
  const SalesRecord({
    required this.id,
    required this.personId,
    required this.personName,
    required this.salesDateKey,
    required this.monthKey,
    required this.amountMilli,
    required this.enteredByUid,
    required this.enteredByName,
    this.reference = '',
    this.createdAt,
    this.updatedAt,
    this.previousAmountMilli,
    this.lastEditedByUid,
    this.lastEditedByName,
  });

  final String id;
  final String personId;
  final String personName;
  final String salesDateKey;
  final String monthKey;
  final int amountMilli;
  final String reference;
  final String enteredByUid;
  final String enteredByName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final int? previousAmountMilli;
  final String? lastEditedByUid;
  final String? lastEditedByName;

  DateTime get salesDate => DateTime.parse(salesDateKey);
  double get amount => amountMilli / 1000;
}

class SalesMonthState {
  const SalesMonthState({
    required this.monthKey,
    this.finalized = false,
    this.finalizedAt,
    this.finalizedByUid,
  });

  final String monthKey;
  final bool finalized;
  final DateTime? finalizedAt;
  final String? finalizedByUid;
}

String salesDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String salesMonthKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}';

DateTime indiaDateTime(DateTime value) =>
    value.toUtc().add(const Duration(hours: 5, minutes: 30));

DateTime indiaNow() => indiaDateTime(DateTime.now());

int? parseAmountMilli(String input) {
  final trimmed = input.trim().replaceAll(',', '');
  if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(trimmed)) return null;
  final parts = trimmed.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null) return null;
  final fraction = parts.length == 1 ? '000' : parts.last.padRight(3, '0');
  final result = whole * 1000 + int.parse(fraction);
  return result > 0 ? result : null;
}

String formatAmountMilli(int value) {
  final whole = value ~/ 1000;
  final fraction = (value % 1000).toString().padLeft(3, '0');
  return '$whole.$fraction';
}
