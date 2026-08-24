class RawMaterialBatch {
  final String? id;
  final String usineId;
  final String rawMaterialId;
  final String lotNumber;
  final double receivedQuantity;
  final double remainingQuantity;
  final double unitCost;
  final DateTime? receivedAt;
  final String status; // "actif" | "cloture"
  final String? receptionId;

  RawMaterialBatch({
    this.id,
    required this.usineId,
    required this.rawMaterialId,
    required this.lotNumber,
    required this.receivedQuantity,
    required this.remainingQuantity,
    required this.unitCost,
    this.receivedAt,
    this.status = 'actif',
    this.receptionId,
  });

  bool get isActive => status == 'actif';

  factory RawMaterialBatch.fromMap(Map<String, dynamic> map) {
    return RawMaterialBatch(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      rawMaterialId: map['rawMaterialId'] as String,
      lotNumber: map['lotNumber'] as String,
      receivedQuantity: (map['receivedQuantity'] as num).toDouble(),
      remainingQuantity: (map['remainingQuantity'] as num).toDouble(),
      unitCost: (map['unitCost'] as num).toDouble(),
      receivedAt: map['receivedAt'] != null ? DateTime.tryParse(map['receivedAt'].toString()) : null,
      status: map['status'] as String? ?? 'actif',
      receptionId: map['receptionId'] as String?,
    );
  }
}
