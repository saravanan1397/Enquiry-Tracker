enum FollowUpStage { first, second, third, later }

enum EnquiryOutcome { active, purchased, closedWithoutPurchase }

class FollowUpEntry {
  const FollowUpEntry({required this.comment, required this.enteredAt});
  final String comment;
  final DateTime enteredAt;
  Map<String, dynamic> toMap() => {
        'comment': comment,
        'enteredAt': enteredAt.toUtc().toIso8601String(),
      };
  factory FollowUpEntry.fromMap(Map<String, dynamic> map) => FollowUpEntry(
        comment: map['comment'] as String,
        enteredAt: DateTime.parse(map['enteredAt'] as String).toLocal(),
      );
}

class CustomerLead {
  const CustomerLead({
    required this.id,
    required this.name,
    required this.phone,
    required this.shopName,
    required this.promoterName,
    this.shopId = '',
    this.promoterId = '',
    required this.createdAt,
    this.followUp1,
    this.followUp1At,
    this.followUp2,
    this.followUp2At,
    this.followUp3,
    this.followUp3At,
    this.isSynced = false,
    this.deletedAt,
    this.additionalFollowUps = const [],
    this.outcome = EnquiryOutcome.active,
    this.completedAt,
  });

  final String id;
  final String name;
  final String phone;
  final String shopName;
  final String promoterName;
  final String shopId;
  final String promoterId;
  final DateTime createdAt;
  final String? followUp1;
  final DateTime? followUp1At;
  final String? followUp2;
  final DateTime? followUp2At;
  final String? followUp3;
  final DateTime? followUp3At;
  final bool isSynced;
  final DateTime? deletedAt;
  final List<FollowUpEntry> additionalFollowUps;
  final EnquiryOutcome outcome;
  final DateTime? completedAt;

  bool get isCompleted => outcome != EnquiryOutcome.active;
  String get outcomeLabel => switch (outcome) {
        EnquiryOutcome.active => 'Active',
        EnquiryOutcome.purchased => 'Purchased',
        EnquiryOutcome.closedWithoutPurchase => 'Closed without purchase',
      };
  int get followUpNumber => additionalFollowUps.isNotEmpty
      ? 3 + additionalFollowUps.length
      : currentStage.index + 1;
  DateTime? get lastFollowUpAt => additionalFollowUps.isNotEmpty
      ? additionalFollowUps.last.enteredAt
      : followUp3?.trim().isNotEmpty == true
          ? followUp3At
          : followUp2?.trim().isNotEmpty == true
              ? followUp2At
              : followUp1?.trim().isNotEmpty == true
                  ? followUp1At
                  : null;

  FollowUpStage get currentStage {
    if (additionalFollowUps.isNotEmpty) return FollowUpStage.later;
    if (followUp3?.trim().isNotEmpty == true) return FollowUpStage.third;
    if (followUp2?.trim().isNotEmpty == true) return FollowUpStage.second;
    return FollowUpStage.first;
  }

  CustomerLead copyWith({
    String? name,
    String? phone,
    String? shopName,
    String? promoterName,
    String? shopId,
    String? promoterId,
    DateTime? createdAt,
    String? followUp1,
    DateTime? followUp1At,
    String? followUp2,
    DateTime? followUp2At,
    String? followUp3,
    DateTime? followUp3At,
    bool? isSynced,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    List<FollowUpEntry>? additionalFollowUps,
    EnquiryOutcome? outcome,
    DateTime? completedAt,
  }) {
    return CustomerLead(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      shopName: shopName ?? this.shopName,
      promoterName: promoterName ?? this.promoterName,
      shopId: shopId ?? this.shopId,
      promoterId: promoterId ?? this.promoterId,
      createdAt: createdAt ?? this.createdAt,
      followUp1: followUp1 ?? this.followUp1,
      followUp1At: followUp1At ?? this.followUp1At,
      followUp2: followUp2 ?? this.followUp2,
      followUp2At: followUp2At ?? this.followUp2At,
      followUp3: followUp3 ?? this.followUp3,
      followUp3At: followUp3At ?? this.followUp3At,
      isSynced: isSynced ?? this.isSynced,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      additionalFollowUps: additionalFollowUps ?? this.additionalFollowUps,
      outcome: outcome ?? this.outcome,
      completedAt: outcome == EnquiryOutcome.active
          ? null
          : completedAt ?? this.completedAt,
    );
  }
}
