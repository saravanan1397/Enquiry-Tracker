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
    this.followUp2,
    this.followUp3,
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
  final String? followUp2;
  final String? followUp3;
  final bool isSynced;
  final DateTime? deletedAt;

  FollowUpStage get currentStage {
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
    String? followUp2,
    String? followUp3,
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
      followUp2: followUp2 ?? this.followUp2,
      followUp3: followUp3 ?? this.followUp3,
      isSynced: isSynced ?? this.isSynced,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }
}
