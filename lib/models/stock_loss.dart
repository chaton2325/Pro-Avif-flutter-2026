import '../utils/cameroon_time.dart';

class StockLoss {
  final String? id;
  final String usineId;
  final String rawMaterialId;
  final double quantity; // positif = perte, négatif = gain
  final String reason;
  final String? note;
  final String source; // "perte" | "inventaire" | "cloture_lot"
  final String? batchId;
  final DateTime? createdAt;
  final String? performedBy;

  StockLoss({
    this.id,
    required this.usineId,
    required this.rawMaterialId,
    required this.quantity,
    required this.reason,
    this.note,
    this.source = 'perte',
    this.batchId,
    this.createdAt,
    this.performedBy,
  });

  Map<String, dynamic> toCreateMap() {
    return {
      'usineId': usineId,
      'rawMaterialId': rawMaterialId,
      'quantity': quantity,
      'reason': reason,
      'note': note,
      'performedBy': performedBy,
    };
  }

  factory StockLoss.fromMap(Map<String, dynamic> map) {
    return StockLoss(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      rawMaterialId: map['rawMaterialId'] as String,
      quantity: (map['quantity'] as num).toDouble(),
      reason: map['reason'] as String? ?? '',
      note: map['note'] as String?,
      source: map['source'] as String? ?? 'perte',
      batchId: map['batchId'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()),
      performedBy: map['performedBy'] as String?,
    );
  }
}
