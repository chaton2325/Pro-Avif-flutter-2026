import '../utils/cameroon_time.dart';

class CostAdjustment {
  final String? id;
  final String usineId;
  final String rawMaterialId;
  final double previousCost;
  final double newCost;
  final String reason;
  final DateTime? createdAt;
  final String? performedBy;

  CostAdjustment({
    this.id,
    required this.usineId,
    required this.rawMaterialId,
    required this.previousCost,
    required this.newCost,
    required this.reason,
    this.createdAt,
    this.performedBy,
  });

  factory CostAdjustment.fromMap(Map<String, dynamic> map) {
    return CostAdjustment(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      rawMaterialId: map['rawMaterialId'] as String,
      previousCost: (map['previousCost'] as num).toDouble(),
      newCost: (map['newCost'] as num).toDouble(),
      reason: map['reason'] as String? ?? '',
      createdAt: parseCameroonTime(map['createdAt']?.toString()),
      performedBy: map['performedBy'] as String?,
    );
  }
}
