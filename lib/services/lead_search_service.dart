import '../models/customer_lead.dart';

class LeadSearchService {
  const LeadSearchService._();

  static bool matches(CustomerLead lead, String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    return [
      lead.name,
      lead.phone,
      lead.followUp1 ?? '',
      lead.followUp2 ?? '',
      lead.followUp3 ?? '',
    ].any((value) => value.toLowerCase().contains(normalizedQuery));
  }
}
