import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/services/device_performance_profile.dart';

void main() {
  test('classifies advertised Android memory tiers', () {
    expect(
      DevicePerformanceProfile.fromTotalMemoryMb(3072).tier,
      DevicePerformanceTier.low,
    );
    expect(
      DevicePerformanceProfile.fromTotalMemoryMb(3700).tier,
      DevicePerformanceTier.medium,
    );
    expect(
      DevicePerformanceProfile.fromTotalMemoryMb(5632).tier,
      DevicePerformanceTier.peak,
    );
  });

  test('uses progressively larger cache budgets', () {
    final low = DevicePerformanceProfile.fromTotalMemoryMb(3072);
    final medium = DevicePerformanceProfile.fromTotalMemoryMb(4096);
    final peak = DevicePerformanceProfile.fromTotalMemoryMb(8192);

    expect(low.imageCacheSizeBytes, lessThan(medium.imageCacheSizeBytes));
    expect(
      medium.imageCacheSizeBytes,
      lessThan(peak.imageCacheSizeBytes),
    );
    expect(
      low.firestoreCacheSizeBytes,
      lessThan(medium.firestoreCacheSizeBytes),
    );
  });
}
