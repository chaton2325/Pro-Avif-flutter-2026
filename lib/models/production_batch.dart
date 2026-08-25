class ProductionCheckLine {
  final String rawMaterialId;
  final String materialName;
  final String unit;
  final double needed;
  final double available;
  final String status; // "ok" | "limite" | "insuffisant"
  final bool isParLot;
  final List<Map<String, dynamic>> batchPreview;

  ProductionCheckLine({
    required this.rawMaterialId,
    required this.materialName,
    required this.unit,
    required this.needed,
    required this.available,
    required this.status,
    required this.isParLot,
    this.batchPreview = const [],
  });

  factory ProductionCheckLine.fromMap(Map<String, dynamic> map) {
    return ProductionCheckLine(
      rawMaterialId: map['rawMaterialId'] as String,
      materialName: map['materialName'] as String,
      unit: map['unit'] as String? ?? 'kg',
      needed: (map['needed'] as num).toDouble(),
      available: (map['available'] as num).toDouble(),
      status: map['status'] as String? ?? 'ok',
      isParLot: map['isParLot'] as bool? ?? false,
      batchPreview: List<Map<String, dynamic>>.from((map['batchPreview'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
    );
  }
}

class ProductionCheckResult {
  final bool canLaunch;
  final List<ProductionCheckLine> lines;

  ProductionCheckResult({required this.canLaunch, required this.lines});

  factory ProductionCheckResult.fromMap(Map<String, dynamic> map) {
    return ProductionCheckResult(
      canLaunch: map['canLaunch'] as bool? ?? false,
      lines: (map['lines'] as List<dynamic>? ?? []).map((l) => ProductionCheckLine.fromMap(l as Map<String, dynamic>)).toList(),
    );
  }
}

class ProductionConsumptionLine {
  final String rawMaterialId;
  final String materialName;
  final double quantityConsumed;
  final double unitCost;
  final double lineCost;
  final List<Map<String, dynamic>> batchesUsed;

  ProductionConsumptionLine({
    required this.rawMaterialId,
    required this.materialName,
    required this.quantityConsumed,
    required this.unitCost,
    required this.lineCost,
    this.batchesUsed = const [],
  });

  factory ProductionConsumptionLine.fromMap(Map<String, dynamic> map) {
    return ProductionConsumptionLine(
      rawMaterialId: map['rawMaterialId'] as String,
      materialName: map['materialName'] as String,
      quantityConsumed: (map['quantityConsumed'] as num).toDouble(),
      unitCost: (map['unitCost'] as num).toDouble(),
      lineCost: (map['lineCost'] as num).toDouble(),
      batchesUsed: List<Map<String, dynamic>>.from((map['batchesUsed'] as List<dynamic>? ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
    );
  }
}

class ProductionBatch {
  final String? id;
  final String usineId;
  final String formulaId;
  final String formulaName;
  final String lotNumber;
  final double quantityTarget;
  final double actualQuantityProduced;
  final List<ProductionConsumptionLine> consumption;
  final double totalCost;
  final double costAdjustment;
  final String? adjustmentReason;
  final double costPerUnit;
  final String status; // "a_valider" | "valide"
  final DateTime? createdAt;
  final DateTime? validatedAt;

  ProductionBatch({
    this.id,
    required this.usineId,
    required this.formulaId,
    required this.formulaName,
    required this.lotNumber,
    required this.quantityTarget,
    required this.actualQuantityProduced,
    this.consumption = const [],
    required this.totalCost,
    this.costAdjustment = 0,
    this.adjustmentReason,
    required this.costPerUnit,
    this.status = 'a_valider',
    this.createdAt,
    this.validatedAt,
  });

  bool get isValidated => status == 'valide';

  factory ProductionBatch.fromMap(Map<String, dynamic> map) {
    return ProductionBatch(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      quantityTarget: (map['quantityTarget'] as num).toDouble(),
      actualQuantityProduced: (map['actualQuantityProduced'] as num).toDouble(),
      consumption: (map['consumption'] as List<dynamic>? ?? []).map((c) => ProductionConsumptionLine.fromMap(c as Map<String, dynamic>)).toList(),
      totalCost: (map['totalCost'] as num?)?.toDouble() ?? 0,
      costAdjustment: (map['costAdjustment'] as num?)?.toDouble() ?? 0,
      adjustmentReason: map['adjustmentReason'] as String?,
      costPerUnit: (map['costPerUnit'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'a_valider',
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'].toString()) : null,
      validatedAt: map['validatedAt'] != null ? DateTime.tryParse(map['validatedAt'].toString()) : null,
    );
  }
}
