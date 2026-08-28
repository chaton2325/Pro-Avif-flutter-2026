import '../utils/cameroon_time.dart';

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
  final String? materialName; // rempli uniquement par l'historique paginé

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
    this.materialName,
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
      receivedAt: parseCameroonTime(map['receivedAt']?.toString()),
      status: map['status'] as String? ?? 'actif',
      receptionId: map['receptionId'] as String?,
      materialName: map['materialName'] as String?,
    );
  }
}

/// Une page de l'historique des lots (matières « par lot »), triée du plus récent au
/// plus ancien — [totalCount] permet de calculer le nombre de pages sans jamais avoir
/// à charger l'ensemble des lots côté client.
class RawMaterialBatchPage {
  final int totalCount;
  final List<RawMaterialBatch> items;
  final int limit;
  final int skip;

  RawMaterialBatchPage({
    required this.totalCount,
    required this.items,
    required this.limit,
    required this.skip,
  });

  factory RawMaterialBatchPage.fromMap(Map<String, dynamic> map) {
    return RawMaterialBatchPage(
      totalCount: map['total_count'] as int? ?? 0,
      items: (map['data'] as List<dynamic>? ?? [])
          .map((b) => RawMaterialBatch.fromMap(b as Map<String, dynamic>))
          .toList(),
      limit: map['limit'] as int? ?? 30,
      skip: map['skip'] as int? ?? 0,
    );
  }
}
