import 'feed_stock.dart';

class DailyReportMaterialLine {
  final String? rawMaterialId;
  final String materialName;
  final String unit;
  final double quantity;

  DailyReportMaterialLine({
    this.rawMaterialId,
    required this.materialName,
    this.unit = 'kg',
    required this.quantity,
  });

  factory DailyReportMaterialLine.fromMap(Map<String, dynamic> map) {
    return DailyReportMaterialLine(
      rawMaterialId: map['rawMaterialId'] as String?,
      materialName: map['materialName'] as String? ?? '',
      unit: map['unit'] as String? ?? 'kg',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DailyReportProductionLine {
  final String formulaId;
  final String formulaName;
  final String lotNumber;
  final double quantityTarget;
  final double actualQuantityProduced;
  final String status; // "brouillon" | "a_valider" | "valide"

  DailyReportProductionLine({
    required this.formulaId,
    required this.formulaName,
    required this.lotNumber,
    required this.quantityTarget,
    required this.actualQuantityProduced,
    required this.status,
  });

  factory DailyReportProductionLine.fromMap(Map<String, dynamic> map) {
    return DailyReportProductionLine(
      formulaId: map['formulaId'] as String? ?? '',
      formulaName: map['formulaName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      quantityTarget: (map['quantityTarget'] as num?)?.toDouble() ?? 0,
      actualQuantityProduced:
          (map['actualQuantityProduced'] as num?)?.toDouble() ?? 0,
      status: map['status'] as String? ?? '',
    );
  }
}

class DailyReportDeliveryLine {
  final String formulaId;
  final String formulaName;
  final String farmName;
  final double quantity;
  final String lotsLabel;

  DailyReportDeliveryLine({
    required this.formulaId,
    required this.formulaName,
    required this.farmName,
    required this.quantity,
    required this.lotsLabel,
  });

  factory DailyReportDeliveryLine.fromMap(Map<String, dynamic> map) {
    return DailyReportDeliveryLine(
      formulaId: map['formulaId'] as String? ?? '',
      formulaName: map['formulaName'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      lotsLabel: map['lotsLabel'] as String? ?? '',
    );
  }
}

class DailyReportStockLine {
  final String materialName;
  final String unit;
  final double quantity;

  DailyReportStockLine({
    required this.materialName,
    this.unit = 'kg',
    required this.quantity,
  });

  factory DailyReportStockLine.fromMap(Map<String, dynamic> map) {
    return DailyReportStockLine(
      materialName: map['materialName'] as String? ?? '',
      unit: map['unit'] as String? ?? 'kg',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Rapport de production journalier — même structure que le rapport papier tenu à
/// l'usine : matière reçue / matière sortie (production) / production / livraison
/// aliment / stock aliment usine / matière en stock.
class DailyReport {
  final String usineId;
  final String date; // "YYYY-MM-DD"
  final List<DailyReportMaterialLine> receptions;
  final List<DailyReportMaterialLine> consumption;
  final List<DailyReportProductionLine> production;
  final List<DailyReportDeliveryLine> deliveries;
  final List<FeedStockSummary> feedStock;
  final List<DailyReportStockLine> materialStock;

  DailyReport({
    required this.usineId,
    required this.date,
    this.receptions = const [],
    this.consumption = const [],
    this.production = const [],
    this.deliveries = const [],
    this.feedStock = const [],
    this.materialStock = const [],
  });

  factory DailyReport.fromMap(Map<String, dynamic> map) {
    return DailyReport(
      usineId: map['usineId'] as String? ?? '',
      date: map['date'] as String? ?? '',
      receptions: (map['receptions'] as List<dynamic>? ?? [])
          .map(
            (e) => DailyReportMaterialLine.fromMap(e as Map<String, dynamic>),
          )
          .toList(),
      consumption: (map['consumption'] as List<dynamic>? ?? [])
          .map(
            (e) => DailyReportMaterialLine.fromMap(e as Map<String, dynamic>),
          )
          .toList(),
      production: (map['production'] as List<dynamic>? ?? [])
          .map(
            (e) =>
                DailyReportProductionLine.fromMap(e as Map<String, dynamic>),
          )
          .toList(),
      deliveries: (map['deliveries'] as List<dynamic>? ?? [])
          .map(
            (e) =>
                DailyReportDeliveryLine.fromMap(e as Map<String, dynamic>),
          )
          .toList(),
      feedStock: (map['feedStock'] as List<dynamic>? ?? [])
          .map((e) => FeedStockSummary.fromMap(e as Map<String, dynamic>))
          .toList(),
      materialStock: (map['materialStock'] as List<dynamic>? ?? [])
          .map(
            (e) => DailyReportStockLine.fromMap(e as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
