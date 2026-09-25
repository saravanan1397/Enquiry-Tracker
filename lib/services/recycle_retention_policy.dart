const recycleBinRetention = Duration(days: 30);

DateTime recycleBinCutoff(DateTime now) => now.subtract(recycleBinRetention);

bool recycleBinItemHasExpired(DateTime? deletedAt, DateTime now) =>
    deletedAt != null && !deletedAt.isAfter(recycleBinCutoff(now));
