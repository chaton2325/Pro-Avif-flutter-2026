class FarmStaff {
  final String? id;
  final String farmId;
  final String name;
  final bool isActive;

  FarmStaff({
    this.id,
    required this.farmId,
    required this.name,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
    'farmId': farmId,
    'name': name,
    'isActive': isActive,
  };

  factory FarmStaff.fromMap(Map<String, dynamic> map) {
    return FarmStaff(
      id: map['_id'] as String?,
      farmId: map['farmId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
