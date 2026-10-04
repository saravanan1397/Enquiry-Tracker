enum FollowUpStage { first, second, third, later }

enum EnquiryOutcome { active, purchased, closedWithoutPurchase }

class FollowUpEntry {
  const FollowUpEntry({
    required this.comment,
    required this.enteredAt,
    this.editedAt,
  });
  final String comment;
  final DateTime enteredAt;
  final DateTime? editedAt;
  Map<String, dynamic> toMap() => {
        'comment': comment,
        'enteredAt': enteredAt.toUtc().toIso8601String(),
        'editedAt': editedAt?.toUtc().toIso8601String(),
      };
  factory FollowUpEntry.fromMap(Map<String, dynamic> map) => FollowUpEntry(
        comment: map['comment'] as String,
        enteredAt: DateTime.parse(map['enteredAt'] as String).toLocal(),
        editedAt:
            DateTime.tryParse(map['editedAt'] as String? ?? '')?.toLocal(),
      );
}

class PendingFollowUpEdit {
  const PendingFollowUpEdit({
    required this.id,
    required this.followUpNumber,
    required this.promoterId,
    required this.promoterName,
    required this.changedAt,
    required this.beforeComment,
    required this.afterComment,
  });

  final String id;
  final int followUpNumber;
  final String promoterId;
  final String promoterName;
  final DateTime changedAt;
  final String beforeComment;
  final String afterComment;

  Map<String, dynamic> toMap() => {
        'id': id,
        'followUpNumber': followUpNumber,
        'promoterId': promoterId,
        'promoterName': promoterName,
        'changedAt': changedAt.toUtc().toIso8601String(),
        'beforeComment': beforeComment,
        'afterComment': afterComment,
      };

  factory PendingFollowUpEdit.fromMap(Map<String, dynamic> map) =>
      PendingFollowUpEdit(
        id: map['id'] as String,
        followUpNumber: (map['followUpNumber'] as num).toInt(),
        promoterId: map['promoterId'] as String,
        promoterName: map['promoterName'] as String,
        changedAt: DateTime.parse(map['changedAt'] as String).toLocal(),
        beforeComment: map['beforeComment'] as String,
        afterComment: map['afterComment'] as String,
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
    this.followUp1EditedAt,
    this.followUp2,
    this.followUp2At,
    this.followUp2EditedAt,
    this.followUp3,
    this.followUp3At,
    this.followUp3EditedAt,
    this.isSynced = false,
    this.deletedAt,
    this.additionalFollowUps = const [],
    this.pendingFollowUpEdits = const [],
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
  final DateTime? followUp1EditedAt;
  final String? followUp2;
  final DateTime? followUp2At;
  final DateTime? followUp2EditedAt;
  final String? followUp3;
  final DateTime? followUp3At;
  final DateTime? followUp3EditedAt;
  final bool isSynced;
  final DateTime? deletedAt;
  final List<FollowUpEntry> additionalFollowUps;
  final List<PendingFollowUpEdit> pendingFollowUpEdits;
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
    DateTime? followUp1EditedAt,
    String? followUp2,
    DateTime? followUp2At,
    DateTime? followUp2EditedAt,
    String? followUp3,
    DateTime? followUp3At,
    DateTime? followUp3EditedAt,
    bool? isSynced,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    List<FollowUpEntry>? additionalFollowUps,
    List<PendingFollowUpEdit>? pendingFollowUpEdits,
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
      followUp1EditedAt: followUp1EditedAt ?? this.followUp1EditedAt,
      followUp2: followUp2 ?? this.followUp2,
      followUp2At: followUp2At ?? this.followUp2At,
      followUp2EditedAt: followUp2EditedAt ?? this.followUp2EditedAt,
      followUp3: followUp3 ?? this.followUp3,
      followUp3At: followUp3At ?? this.followUp3At,
      followUp3EditedAt: followUp3EditedAt ?? this.followUp3EditedAt,
      isSynced: isSynced ?? this.isSynced,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
      additionalFollowUps: additionalFollowUps ?? this.additionalFollowUps,
      pendingFollowUpEdits: pendingFollowUpEdits ?? this.pendingFollowUpEdits,
      outcome: outcome ?? this.outcome,
      completedAt: outcome == EnquiryOutcome.active
          ? null
          : completedAt ?? this.completedAt,
    );
  }
}
