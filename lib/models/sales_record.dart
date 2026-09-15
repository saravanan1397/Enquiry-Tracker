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

class SalesPersonRecordGroup {
  const SalesPersonRecordGroup({
    required this.personId,
    required this.personName,
    required this.records,
    required this.totalMilli,
  });

  final String personId;
  final String personName;
  final List<SalesRecord> records;
  final int totalMilli;
}

List<SalesPersonRecordGroup> groupSalesRecordsByPerson(
    Iterable<SalesRecord> records) {
  final grouped = <String, List<SalesRecord>>{};
  for (final record in records) {
    grouped.putIfAbsent(record.personId, () => []).add(record);
  }
  final result = grouped.entries.map((entry) {
    entry.value.sort((a, b) {
      final date = a.salesDateKey.compareTo(b.salesDateKey);
      if (date != 0) return date;
      return a.id.compareTo(b.id);
    });
    return SalesPersonRecordGroup(
      personId: entry.key,
      personName: entry.value.first.personName,
      records: List.unmodifiable(entry.value),
      totalMilli: entry.value.fold<int>(
        0,
        (total, record) => total + record.amountMilli,
      ),
    );
  }).toList();
  result.sort((a, b) {
    final name = a.personName.toLowerCase().compareTo(
          b.personName.toLowerCase(),
        );
    return name != 0 ? name : a.personId.compareTo(b.personId);
  });
  return result;
}

List<SalesRecord> filterSalesRecords(
  Iterable<SalesRecord> records, {
  String? personId,
  String? dateKey,
  String? fromDateKey,
  String? toDateKey,
}) =>
    records
        .where((record) =>
            (personId == null || record.personId == personId) &&
            (dateKey == null || record.salesDateKey == dateKey) &&
            (fromDateKey == null ||
                record.salesDateKey.compareTo(fromDateKey) >= 0) &&
            (toDateKey == null ||
                record.salesDateKey.compareTo(toDateKey) <= 0))
        .toList(growable: false);

String salesDateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String salesMonthKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}';

DateTime indiaDateTime(DateTime value) {
  final india = value.toUtc().add(const Duration(hours: 5, minutes: 30));
  return DateTime(
    india.year,
    india.month,
    india.day,
    india.hour,
    india.minute,
    india.second,
    india.millisecond,
    india.microsecond,
  );
}

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
