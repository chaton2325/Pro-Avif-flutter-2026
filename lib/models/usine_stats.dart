class MonthlyPoint {
  final String label;
  final int year;
  final int month;
  final double value;

  MonthlyPoint({
    required this.label,
    required this.year,
    required this.month,
    required this.value,
  });

  factory MonthlyPoint.fromMap(Map<String, dynamic> map) {
    return MonthlyPoint(
      label: map['label'] as String,
      year: (map['year'] as num).toInt(),
      month: (map['month'] as num).toInt(),
      value: (map['value'] as num).toDouble(),
    );
  }
}

class DashboardStats {
  final double productionThisMonthKg;
  final double avgCostPerKg;
  final double stockValueFcfa;
  final List<MonthlyPoint> monthlyProduction;

  DashboardStats({
    required this.productionThisMonthKg,
    required this.avgCostPerKg,
    required this.stockValueFcfa,
    required this.monthlyProduction,
  });

  factory DashboardStats.fromMap(Map<String, dynamic> map) {
    return DashboardStats(
      productionThisMonthKg:
          (map['productionThisMonthKg'] as num?)?.toDouble() ?? 0,
      avgCostPerKg: (map['avgCostPerKg'] as num?)?.toDouble() ?? 0,
      stockValueFcfa: (map['stockValueFcfa'] as num?)?.toDouble() ?? 0,
      monthlyProduction: (map['monthlyProduction'] as List<dynamic>? ?? [])
          .map((m) => MonthlyPoint.fromMap(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RoomConsumptionDetail {
  final String formulaId;
  final String formulaName;
  final String lotsLabel;
  final double quantityKg;

  RoomConsumptionDetail({
    required this.formulaId,
    required this.formulaName,
    required this.lotsLabel,
    required this.quantityKg,
  });

  factory RoomConsumptionDetail.fromMap(Map<String, dynamic> map) {
    return RoomConsumptionDetail(
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String? ?? '',
      lotsLabel: map['lotsLabel'] as String? ?? '',
      quantityKg: (map['quantityKg'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RoomConsumption {
  final String farmName;
  final String roomName;
  final String? lotNumberSujets;
  final double totalKg;
  final List<RoomConsumptionDetail> details;

  RoomConsumption({
    required this.farmName,
    required this.roomName,
    this.lotNumberSujets,
    required this.totalKg,
    this.details = const [],
  });

  factory RoomConsumption.fromMap(Map<String, dynamic> map) {
    return RoomConsumption(
      farmName: map['farmName'] as String? ?? '',
      roomName: map['roomName'] as String? ?? '',
      lotNumberSujets: map['lotNumberSujets'] as String?,
      totalKg: (map['totalKg'] as num?)?.toDouble() ?? 0,
      details: (map['details'] as List<dynamic>? ?? [])
          .map((d) => RoomConsumptionDetail.fromMap(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TraceMaterialOrigin {
  final String lotNumber;
  final String materialName;
  final double quantity;

  TraceMaterialOrigin({
    required this.lotNumber,
    required this.materialName,
    required this.quantity,
  });

  factory TraceMaterialOrigin.fromMap(Map<String, dynamic> map) {
    return TraceMaterialOrigin(
      lotNumber: map['lotNumber'] as String? ?? '',
      materialName: map['materialName'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}

class TraceFabrication {
  final String lotNumber;
  final String formulaName;
  final double quantity;
  final DateTime? validatedAt;
  final List<TraceMaterialOrigin> materials;

  TraceFabrication({
    required this.lotNumber,
    required this.formulaName,
    required this.quantity,
    this.validatedAt,
    this.materials = const [],
  });

  factory TraceFabrication.fromMap(Map<String, dynamic> map) {
    return TraceFabrication(
      lotNumber: map['lotNumber'] as String? ?? '',
      formulaName: map['formulaName'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      validatedAt: map['validatedAt'] != null
          ? DateTime.tryParse(map['validatedAt'].toString())
          : null,
      materials: (map['materials'] as List<dynamic>? ?? [])
          .map((m) => TraceMaterialOrigin.fromMap(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TraceDelivery {
  final DateTime date;
  final String farmName;
  final String roomName;
  final String? lotNumberSujets;
  final double quantity;
  final String lotNumber;

  TraceDelivery({
    required this.date,
    required this.farmName,
    required this.roomName,
    this.lotNumberSujets,
    required this.quantity,
    required this.lotNumber,
  });

  factory TraceDelivery.fromMap(Map<String, dynamic> map) {
    return TraceDelivery(
      date: DateTime.parse(map['date'] as String),
      farmName: map['farmName'] as String? ?? '',
      roomName: map['roomName'] as String? ?? '',
      lotNumberSujets: map['lotNumberSujets'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      lotNumber: map['lotNumber'] as String? ?? '',
    );
  }
}

class TraceResult {
  final String query;
  final String matchType; // "matiere" | "aliment" | "sujets" | "introuvable"
  final List<TraceFabrication> fabrications;
  final List<TraceDelivery> deliveries;

  TraceResult({
    required this.query,
    required this.matchType,
    this.fabrications = const [],
    this.deliveries = const [],
  });

  factory TraceResult.fromMap(Map<String, dynamic> map) {
    return TraceResult(
      query: map['query'] as String? ?? '',
      matchType: map['matchType'] as String? ?? 'introuvable',
      fabrications: (map['fabrications'] as List<dynamic>? ?? [])
          .map((f) => TraceFabrication.fromMap(f as Map<String, dynamic>))
          .toList(),
      deliveries: (map['deliveries'] as List<dynamic>? ?? [])
          .map((d) => TraceDelivery.fromMap(d as Map<String, dynamic>))
          .toList(),
    );
  }
}

class BudgetCategoryStatus {
  final String category;
  final double budgetFcfa;
  final double realizedFcfa;
  final double percentUsed;
  final String status; // "ok" | "depasse" | "sans_budget"
  final String? topMaterial;

  BudgetCategoryStatus({
    required this.category,
    required this.budgetFcfa,
    required this.realizedFcfa,
    required this.percentUsed,
    required this.status,
    this.topMaterial,
  });

  factory BudgetCategoryStatus.fromMap(Map<String, dynamic> map) {
    return BudgetCategoryStatus(
      category: map['category'] as String? ?? '',
      budgetFcfa: (map['budgetFcfa'] as num?)?.toDouble() ?? 0,
      realizedFcfa: (map['realizedFcfa'] as num?)?.toDouble() ?? 0,
      percentUsed: (map['percentUsed'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? 'sans_budget',
      topMaterial: map['topMaterial'] as String?,
    );
  }
}

class FormulaCostTrend {
  final String formulaId;
  final String formulaName;
  final double avgCostPerUnit;
  final double? trendPercent;

  FormulaCostTrend({
    required this.formulaId,
    required this.formulaName,
    required this.avgCostPerUnit,
    this.trendPercent,
  });

  factory FormulaCostTrend.fromMap(Map<String, dynamic> map) {
    return FormulaCostTrend(
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String? ?? '',
      avgCostPerUnit: (map['avgCostPerUnit'] as num?)?.toDouble() ?? 0,
      trendPercent: (map['trendPercent'] as num?)?.toDouble(),
    );
  }
}

class BudgetsStats {
  final int month;
  final int year;
  final double totalBudget;
  final double totalRealized;
  final double variancePercent;
  final List<BudgetCategoryStatus> categories;
  final List<FormulaCostTrend> formulaCosts;

  BudgetsStats({
    required this.month,
    required this.year,
    required this.totalBudget,
    required this.totalRealized,
    required this.variancePercent,
    this.categories = const [],
    this.formulaCosts = const [],
  });

  factory BudgetsStats.fromMap(Map<String, dynamic> map) {
    return BudgetsStats(
      month: (map['month'] as num).toInt(),
      year: (map['year'] as num).toInt(),
      totalBudget: (map['totalBudget'] as num?)?.toDouble() ?? 0,
      totalRealized: (map['totalRealized'] as num?)?.toDouble() ?? 0,
      variancePercent: (map['variancePercent'] as num?)?.toDouble() ?? 0,
      categories: (map['categories'] as List<dynamic>? ?? [])
          .map((c) => BudgetCategoryStatus.fromMap(c as Map<String, dynamic>))
          .toList(),
      formulaCosts: (map['formulaCosts'] as List<dynamic>? ?? [])
          .map((f) => FormulaCostTrend.fromMap(f as Map<String, dynamic>))
          .toList(),
    );
  }
}

class TrendsStats {
  final List<MonthlyPoint> cumpTrend;
  final List<MonthlyPoint> productionTrend;
  final List<MonthlyPoint> lossesTrend;

  TrendsStats({
    this.cumpTrend = const [],
    required this.productionTrend,
    required this.lossesTrend,
  });

  factory TrendsStats.fromMap(Map<String, dynamic> map) {
    return TrendsStats(
      cumpTrend: (map['cumpTrend'] as List<dynamic>? ?? [])
          .map((m) => MonthlyPoint.fromMap(m as Map<String, dynamic>))
          .toList(),
      productionTrend: (map['productionTrend'] as List<dynamic>? ?? [])
          .map((m) => MonthlyPoint.fromMap(m as Map<String, dynamic>))
          .toList(),
      lossesTrend: (map['lossesTrend'] as List<dynamic>? ?? [])
          .map((m) => MonthlyPoint.fromMap(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

class AuditLogEntry {
  final String id;
  final String userName;
  final String action;
  final String collection;
  final String details;
  final DateTime timestamp;

  AuditLogEntry({
    required this.id,
    required this.userName,
    required this.action,
    required this.collection,
    required this.details,
    required this.timestamp,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> map) {
    return AuditLogEntry(
      id: map['_id'] as String,
      userName: map['userName'] as String? ?? '',
      action: map['action'] as String? ?? '',
      collection: map['collection'] as String? ?? '',
      details: map['details'] as String? ?? '',
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}

class AuditLogPagedResult {
  final int totalCount;
  final List<AuditLogEntry> data;
  final int limit;
  final int skip;

  AuditLogPagedResult({
    required this.totalCount,
    required this.data,
    required this.limit,
    required this.skip,
  });

  factory AuditLogPagedResult.fromMap(Map<String, dynamic> map) {
    return AuditLogPagedResult(
      totalCount: (map['total_count'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((d) => AuditLogEntry.fromMap(d as Map<String, dynamic>))
          .toList(),
      limit: (map['limit'] as num?)?.toInt() ?? 30,
      skip: (map['skip'] as num?)?.toInt() ?? 0,
    );
  }
}
