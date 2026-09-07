enum FollowUpStage { first, second, third }

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

  bool get isCompleted => followUp3?.trim().isNotEmpty == true;

  FollowUpStage get currentStage {
    if (isCompleted) return FollowUpStage.third;
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
    );
  }
}
