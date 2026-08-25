class SimulationLine {
  final String formulaId;
  final String formulaName;
  final double maxProducibleKg;
  final String? limitingMaterialId;
  final String? limitingMaterialName;
  final String status; // "ok" | "limite" | "rupture"

  SimulationLine({
    required this.formulaId,
    required this.formulaName,
    required this.maxProducibleKg,
    this.limitingMaterialId,
    this.limitingMaterialName,
    required this.status,
  });

  factory SimulationLine.fromMap(Map<String, dynamic> map) {
    return SimulationLine(
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String,
      maxProducibleKg: (map['maxProducibleKg'] as num).toDouble(),
      limitingMaterialId: map['limitingMaterialId'] as String?,
      limitingMaterialName: map['limitingMaterialName'] as String?,
      status: map['status'] as String? ?? 'ok',
    );
  }
}

class OptimizationLine {
  final String formulaId;
  final String formulaName;
  final double quantityKg;

  OptimizationLine({
    required this.formulaId,
    required this.formulaName,
    required this.quantityKg,
  });

  factory OptimizationLine.fromMap(Map<String, dynamic> map) {
    return OptimizationLine(
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String,
      quantityKg: (map['quantityKg'] as num).toDouble(),
    );
  }
}

class MaterialUtilization {
  final String rawMaterialId;
  final String materialName;
  final double utilizationPercent;
  final bool isLimiting;

  MaterialUtilization({
    required this.rawMaterialId,
    required this.materialName,
    required this.utilizationPercent,
    this.isLimiting = false,
  });

  factory MaterialUtilization.fromMap(Map<String, dynamic> map) {
    return MaterialUtilization(
      rawMaterialId: map['rawMaterialId'] as String,
      materialName: map['materialName'] as String,
      utilizationPercent: (map['utilizationPercent'] as num).toDouble(),
      isLimiting: map['isLimiting'] as bool? ?? false,
    );
  }
}

class OptimizationResult {
  final List<OptimizationLine> plan;
  final List<MaterialUtilization> utilization;
  final String? limitingMaterialName;
  final double totalOptimizedKg;
  final double totalEqualSplitKg;
  final double wasteAvoidedKg;
  final double wasteAvoidedPercent;

  OptimizationResult({
    required this.plan,
    required this.utilization,
    this.limitingMaterialName,
    required this.totalOptimizedKg,
    required this.totalEqualSplitKg,
    required this.wasteAvoidedKg,
    required this.wasteAvoidedPercent,
  });

  factory OptimizationResult.fromMap(Map<String, dynamic> map) {
    return OptimizationResult(
      plan: (map['plan'] as List<dynamic>? ?? [])
          .map((l) => OptimizationLine.fromMap(l as Map<String, dynamic>))
          .toList(),
      utilization: (map['utilization'] as List<dynamic>? ?? [])
          .map((u) => MaterialUtilization.fromMap(u as Map<String, dynamic>))
          .toList(),
      limitingMaterialName: map['limitingMaterialName'] as String?,
      totalOptimizedKg: (map['totalOptimizedKg'] as num?)?.toDouble() ?? 0,
      totalEqualSplitKg: (map['totalEqualSplitKg'] as num?)?.toDouble() ?? 0,
      wasteAvoidedKg: (map['wasteAvoidedKg'] as num?)?.toDouble() ?? 0,
      wasteAvoidedPercent:
          (map['wasteAvoidedPercent'] as num?)?.toDouble() ?? 0,
    );
  }
}
