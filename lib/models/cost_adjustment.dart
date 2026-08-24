class CostAdjustment {
  final String? id;
  final String usineId;
  final String rawMaterialId;
  final double previousCost;
  final double newCost;
  final String reason;
  final DateTime? createdAt;

  CostAdjustment({
    this.id,
    required this.usineId,
    required this.rawMaterialId,
    required this.previousCost,
    required this.newCost,
    required this.reason,
    this.createdAt,
  });

  factory CostAdjustment.fromMap(Map<String, dynamic> map) {
    return CostAdjustment(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      rawMaterialId: map['rawMaterialId'] as String,
      previousCost: (map['previousCost'] as num).toDouble(),
      newCost: (map['newCost'] as num).toDouble(),
      reason: map['reason'] as String? ?? '',
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'].toString()) : null,
    );
  }
}
