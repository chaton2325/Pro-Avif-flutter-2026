import '../utils/cameroon_time.dart';

/// Quantité de départ d'un aliment donné (référentiel "formulas" du module Usine Aliment —
/// jamais retapé, un aliment se crée une seule fois là-bas).
class FeedStartingQuantity {
  final String formulaId;
  final String formulaName;
  final double quantityKg;

  FeedStartingQuantity({
    required this.formulaId,
    required this.formulaName,
    this.quantityKg = 0,
  });

  Map<String, dynamic> toMap() => {
    'formulaId': formulaId,
    'formulaName': formulaName,
    'quantityKg': quantityKg,
  };

  factory FeedStartingQuantity.fromMap(Map<String, dynamic> map) {
    return FeedStartingQuantity(
      formulaId: map['formulaId'] as String? ?? '',
      formulaName: map['formulaName'] as String? ?? '',
      quantityKg: (map['quantityKg'] as num?)?.toDouble() ?? 0,
    );
  }

  FeedStartingQuantity copyWith({double? quantityKg}) => FeedStartingQuantity(
    formulaId: formulaId,
    formulaName: formulaName,
    quantityKg: quantityKg ?? this.quantityKg,
  );
}

/// Photo des aliments de départ juste avant qu'ils ne soient écrasés par une resaisie —
/// conservée par le backend dans la collection à part farm_feed_stock_history (même principe
/// que LotHeadcountHistoryEntry : jamais embarquée, jamais chargée d'un bloc).
class FarmFeedStockHistoryEntry {
  final String? id;
  final String farmName;
  final List<FeedStartingQuantity> quantities;
  final double totalKg;
  final DateTime? recordedAt;
  final String? recordedBy;
  final DateTime replacedAt;
  final String? replacedBy;

  FarmFeedStockHistoryEntry({
    this.id,
    required this.farmName,
    this.quantities = const [],
    this.totalKg = 0,
    this.recordedAt,
    this.recordedBy,
    required this.replacedAt,
    this.replacedBy,
  });

  factory FarmFeedStockHistoryEntry.fromMap(Map<String, dynamic> map) {
    return FarmFeedStockHistoryEntry(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      quantities: (map['quantities'] as List<dynamic>? ?? [])
          .map((q) => FeedStartingQuantity.fromMap(q as Map<String, dynamic>))
          .toList(),
      totalKg: (map['totalKg'] as num?)?.toDouble() ?? 0,
      recordedAt: parseCameroonTime(map['recordedAt']?.toString()),
      recordedBy: map['recordedBy'] as String?,
      replacedAt: parseCameroonTime(map['replacedAt']?.toString()) ?? DateTime.now(),
      replacedBy: map['replacedBy'] as String?,
    );
  }
}

class FarmFeedStockHistoryPagedResult {
  final int totalCount;
  final List<FarmFeedStockHistoryEntry> data;

  FarmFeedStockHistoryPagedResult({this.totalCount = 0, required this.data});

  factory FarmFeedStockHistoryPagedResult.fromMap(Map<String, dynamic> map) {
    return FarmFeedStockHistoryPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((h) => FarmFeedStockHistoryEntry.fromMap(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Aliments de départ d'une ferme (saisis une seule fois par l'admin) : jamais lié à un lot
/// de sujets — ce stock ne redémarre pas à zéro à l'arrivée d'un nouveau lot. Le tout premier
/// rapport journalier de la ferme reprend ce total comme stock de départ (voir
/// routers/daily_reports.py côté backend), les jours suivants reprenant toujours le stock
/// restant de la veille.
class FarmFeedStock {
  final String? id;
  final String farmName;
  final List<FeedStartingQuantity> quantities;
  final double totalKg;
  final String? performedBy;
  final DateTime? updatedAt;

  FarmFeedStock({
    this.id,
    required this.farmName,
    this.quantities = const [],
    this.totalKg = 0,
    this.performedBy,
    this.updatedAt,
  });

  Map<String, dynamic> toCreateMap({String? performedBy}) => {
    'farmName': farmName,
    'quantities': quantities.map((q) => q.toMap()).toList(),
    'performedBy': performedBy,
  };

  factory FarmFeedStock.fromMap(Map<String, dynamic> map) {
    return FarmFeedStock(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      quantities: (map['quantities'] as List<dynamic>? ?? [])
          .map((q) => FeedStartingQuantity.fromMap(q as Map<String, dynamic>))
          .toList(),
      totalKg: (map['totalKg'] as num?)?.toDouble() ?? 0,
      performedBy: map['performedBy'] as String?,
      updatedAt: parseCameroonTime(map['updatedAt']?.toString()),
    );
  }
}
