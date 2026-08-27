class FeedStockBatch {
  final String id;
  final String usineId;
  final String formulaId;
  final String formulaName;
  final String lotNumber;
  final double producedQuantity;
  final double remainingQuantity;
  final double unitCost;
  final DateTime validatedAt;
  final String status; // "actif" | "epuise"

  FeedStockBatch({
    required this.id,
    required this.usineId,
    required this.formulaId,
    required this.formulaName,
    required this.lotNumber,
    required this.producedQuantity,
    required this.remainingQuantity,
    required this.unitCost,
    required this.validatedAt,
    required this.status,
  });

  factory FeedStockBatch.fromMap(Map<String, dynamic> map) {
    return FeedStockBatch(
      id: map['_id'] as String,
      usineId: map['usineId'] as String,
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      producedQuantity: (map['producedQuantity'] as num?)?.toDouble() ?? 0,
      remainingQuantity: (map['remainingQuantity'] as num?)?.toDouble() ?? 0,
      unitCost: (map['unitCost'] as num?)?.toDouble() ?? 0,
      validatedAt: DateTime.parse(map['validatedAt'] as String),
      status: map['status'] as String? ?? 'actif',
    );
  }
}

class FeedStockLoss {
  final String? id;
  final String usineId;
  final String formulaId;
  final String? batchId;
  final String? lotNumber;
  final double quantity; // positif = perte, négatif = gain (écart d'inventaire)
  final String reason;
  final String? note;
  final String source;
  final DateTime? createdAt;
  final String? performedBy;

  FeedStockLoss({
    this.id,
    required this.usineId,
    required this.formulaId,
    this.batchId,
    this.lotNumber,
    required this.quantity,
    required this.reason,
    this.note,
    this.source = 'inventaire',
    this.createdAt,
    this.performedBy,
  });

  factory FeedStockLoss.fromMap(Map<String, dynamic> map) {
    return FeedStockLoss(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      formulaId: map['formulaId'] as String,
      batchId: map['batchId'] as String?,
      lotNumber: map['lotNumber'] as String?,
      quantity: (map['quantity'] as num).toDouble(),
      reason: map['reason'] as String? ?? '',
      note: map['note'] as String?,
      source: map['source'] as String? ?? 'inventaire',
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      performedBy: map['performedBy'] as String?,
    );
  }
}

class FeedStockSummary {
  final String formulaId;
  final String formulaName;
  final double totalStock;
  final double lowStockThreshold;
  final String status; // "ok" | "bas" | "rupture"
  final List<FeedStockBatch> batches;

  FeedStockSummary({
    required this.formulaId,
    required this.formulaName,
    required this.totalStock,
    required this.lowStockThreshold,
    required this.status,
    this.batches = const [],
  });

  factory FeedStockSummary.fromMap(Map<String, dynamic> map) {
    return FeedStockSummary(
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String? ?? '',
      totalStock: (map['totalStock'] as num?)?.toDouble() ?? 0,
      lowStockThreshold: (map['lowStockThreshold'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'ok',
      batches: (map['batches'] as List<dynamic>? ?? [])
          .map((b) => FeedStockBatch.fromMap(b as Map<String, dynamic>))
          .toList(),
    );
  }
}
