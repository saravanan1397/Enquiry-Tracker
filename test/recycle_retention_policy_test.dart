import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/services/recycle_retention_policy.dart';

void main() {
  final now = DateTime.utc(2026, 9, 25, 12);

  test('recycle-bin item expires exactly after thirty days', () {
    expect(
      recycleBinItemHasExpired(
        now.subtract(const Duration(days: 30)),
        now,
      ),
      isTrue,
    );
  });

  test('recycle-bin item remains recoverable before thirty days', () {
    expect(
      recycleBinItemHasExpired(
        now.subtract(const Duration(days: 29, hours: 23)),
        now,
      ),
      isFalse,
    );
  });

  test('active item without a deletion time never expires', () {
    expect(recycleBinItemHasExpired(null, now), isFalse);
  });
}
