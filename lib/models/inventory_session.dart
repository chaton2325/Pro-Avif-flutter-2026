/// Une ligne comptée pendant une session d'inventaire. [name] est le nom de la
/// matière/de l'aliment tel qu'il était au moment de l'inventaire (dénormalisé côté
/// serveur), pour que l'historique reste exact même après un renommage.
class InventorySessionDetail {
  final String? rawMaterialId;
  final String? formulaId;
  final String name;
  final String unit;
  final String? batchId;
  final String? lotNumber;
  final double systemQuantity;
  final double countedQuantity;
  final double variance;

  InventorySessionDetail({
    this.rawMaterialId,
    this.formulaId,
    required this.name,
    this.unit = 'kg',
    this.batchId,
    this.lotNumber,
    required this.systemQuantity,
    required this.countedQuantity,
    required this.variance,
  });

  factory InventorySessionDetail.fromMap(Map<String, dynamic> map) {
    return InventorySessionDetail(
      rawMaterialId: map['rawMaterialId'] as String?,
      formulaId: map['formulaId'] as String?,
      name: map['name'] as String? ?? '?',
      unit: map['unit'] as String? ?? 'kg',
      batchId: map['batchId'] as String?,
      lotNumber: map['lotNumber'] as String?,
      systemQuantity: (map['systemQuantity'] as num?)?.toDouble() ?? 0,
      countedQuantity: (map['countedQuantity'] as num?)?.toDouble() ?? 0,
      variance: (map['variance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class InventorySession {
  final String? id;
  final String usineId;
  final int materialsCount;
  final int varianceCount;
  final String? comment;
  final DateTime? createdAt;
  final String? performedBy;
  final String? scope; // "matieres" | "aliments"
  final List<InventorySessionDetail> details;

  InventorySession({
    this.id,
    required this.usineId,
    required this.materialsCount,
    required this.varianceCount,
    this.comment,
    this.createdAt,
    this.performedBy,
    this.scope,
    this.details = const [],
  });

  factory InventorySession.fromMap(Map<String, dynamic> map) {
    return InventorySession(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      materialsCount: map['materialsCount'] as int? ?? 0,
      varianceCount: map['varianceCount'] as int? ?? 0,
      comment: map['comment'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString())
          : null,
      performedBy: map['performedBy'] as String?,
      scope: map['scope'] as String?,
      details: (map['details'] as List<dynamic>? ?? [])
          .map(
            (d) => InventorySessionDetail.fromMap(d as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

/// Une page (par défaut 50) de l'historique d'inventaire, triée du plus récent au plus
/// ancien — [totalCount] permet de calculer le nombre de pages sans jamais charger tout
/// l'historique côté client.
class InventorySessionPage {
  final int totalCount;
  final List<InventorySession> items;
  final int limit;
  final int skip;

  InventorySessionPage({
    required this.totalCount,
    required this.items,
    required this.limit,
    required this.skip,
  });

  factory InventorySessionPage.fromMap(Map<String, dynamic> map) {
    return InventorySessionPage(
      totalCount: map['total_count'] as int? ?? 0,
      items: (map['data'] as List<dynamic>? ?? [])
          .map((s) => InventorySession.fromMap(s as Map<String, dynamic>))
          .toList(),
      limit: map['limit'] as int? ?? 50,
      skip: map['skip'] as int? ?? 0,
    );
  }
}
