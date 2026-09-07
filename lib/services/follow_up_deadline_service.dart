import '../models/customer_lead.dart';

/// Calculates the deadline for Follow-up 2 using the Enquiry Tracker's
/// operating window. Every calendar day is counted; only time from 09:00 to
/// 22:00 is treated as business time.
class FollowUpDeadlineService {
  static const int businessStartHour = 9;
  static const int businessEndHour = 22;
  static const Duration followUp2Allowance = Duration(hours: 15);

  static DateTime? followUp2DueAt(CustomerLead lead) {
    final firstFollowUpAt = lead.followUp1At;
    if (lead.followUp1?.trim().isEmpty != false || firstFollowUpAt == null) {
      return null;
    }
    return addBusinessTime(firstFollowUpAt, followUp2Allowance);
  }

  static bool isFollowUp2Overdue(CustomerLead lead, {DateTime? now}) {
    if (lead.followUp2?.trim().isNotEmpty == true) return false;
    final dueAt = followUp2DueAt(lead);
    return dueAt != null && !(now ?? DateTime.now()).isBefore(dueAt);
  }

  static DateTime addBusinessTime(DateTime start, Duration duration) {
    var cursor = start;
    var remaining = duration;

    while (remaining > Duration.zero) {
      final businessStart = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        businessStartHour,
      );
      final businessEnd = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        businessEndHour,
      );

      if (!cursor.isBefore(businessEnd)) {
        cursor = businessStart.add(const Duration(days: 1));
        continue;
      }

      final availableStart =
          cursor.isBefore(businessStart) ? businessStart : cursor;
      final available = businessEnd.difference(availableStart);
      if (remaining <= available) return availableStart.add(remaining);

      remaining -= available;
      cursor = businessStart.add(const Duration(days: 1));
    }

    return cursor;
  }
}
