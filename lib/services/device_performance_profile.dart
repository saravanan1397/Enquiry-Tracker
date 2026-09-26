import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum DevicePerformanceTier { low, medium, peak }

@immutable
class DevicePerformanceProfile {
  const DevicePerformanceProfile({
    required this.tier,
    required this.nominalMemoryGb,
  });

  static const _channel = MethodChannel('enquiry_tracker/device_profile');

  static const medium = DevicePerformanceProfile(
    tier: DevicePerformanceTier.medium,
    nominalMemoryGb: 4,
  );

  final DevicePerformanceTier tier;
  final int nominalMemoryGb;

  bool get isLow => tier == DevicePerformanceTier.low;
  bool get isPeak => tier == DevicePerformanceTier.peak;

  int get firestoreCacheSizeBytes => switch (tier) {
        DevicePerformanceTier.low => 20 * 1024 * 1024,
        DevicePerformanceTier.medium => 35 * 1024 * 1024,
        DevicePerformanceTier.peak => 50 * 1024 * 1024,
      };

  int get imageCacheSizeBytes => switch (tier) {
        DevicePerformanceTier.low => 16 * 1024 * 1024,
        DevicePerformanceTier.medium => 32 * 1024 * 1024,
        DevicePerformanceTier.peak => 64 * 1024 * 1024,
      };

  int get imageCacheEntries => switch (tier) {
        DevicePerformanceTier.low => 50,
        DevicePerformanceTier.medium => 100,
        DevicePerformanceTier.peak => 180,
      };

  factory DevicePerformanceProfile.fromTotalMemoryMb(int? totalMemoryMb) {
    if (totalMemoryMb == null || totalMemoryMb <= 0) return medium;

    // Android reports usable physical memory, which is normally lower than the
    // advertised RAM. Rounding maps common 3.6 GB and 5.5 GB readings back to
    // their advertised 4 GB and 6 GB device classes.
    final nominalMemoryGb = (totalMemoryMb / 1024).round().clamp(1, 64);
    final tier = nominalMemoryGb >= 6
        ? DevicePerformanceTier.peak
        : nominalMemoryGb >= 4
            ? DevicePerformanceTier.medium
            : DevicePerformanceTier.low;
    return DevicePerformanceProfile(
      tier: tier,
      nominalMemoryGb: nominalMemoryGb,
    );
  }

  static Future<DevicePerformanceProfile> detect() async {
    if (kIsWeb) {
      return const DevicePerformanceProfile(
        tier: DevicePerformanceTier.peak,
        nominalMemoryGb: 8,
      );
    }
    if (defaultTargetPlatform != TargetPlatform.android) return medium;

    try {
      final totalMemoryMb = await _channel.invokeMethod<int>('totalMemoryMb');
      return DevicePerformanceProfile.fromTotalMemoryMb(totalMemoryMb);
    } on PlatformException {
      return medium;
    } on MissingPluginException {
      return medium;
    }
  }
}
