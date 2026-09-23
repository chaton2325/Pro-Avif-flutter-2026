import '../utils/cameroon_time.dart';

/// Expédition d'œufs à couver (OAC) vers un couvoir : une fois VALIDÉE par l'admin, diminue
/// le STOCK actuel (voir CurrentEggStock.currentStockOac) — jamais le cumul de production qui
/// ne fait qu'accumuler. Tant qu'elle est en attente ou rejetée, aucun effet sur le stock.
///
/// Workflow (même principe que les rapports journaliers) : "en_attente_validation" à la
/// création, puis "valide" (stock décrémenté) ou "rejetee" (motif obligatoire, aucun effet)
/// après passage de l'admin.
class EggShipment {
  final String? id;
  final String farmName;
  final String? lotNumber;
  final String hatcheryId;
  final String hatcheryName;
  final int oacCount;
  final String status;
  final String? performedBy;
  final DateTime createdAt;
  final DateTime? validatedAt;
  final String? validatedBy;
  final DateTime? rejectedAt;
  final String? rejectedBy;
  final String? rejectionReason;

  EggShipment({
    this.id,
    required this.farmName,
    this.lotNumber,
    required this.hatcheryId,
    required this.hatcheryName,
    required this.oacCount,
    this.status = 'en_attente_validation',
    this.performedBy,
    required this.createdAt,
    this.validatedAt,
    this.validatedBy,
    this.rejectedAt,
    this.rejectedBy,
    this.rejectionReason,
  });

  bool get isPending => status == 'en_attente_validation';
  bool get isValidated => status == 'valide';
  bool get isRejected => status == 'rejetee';

  String get statusLabel => switch (status) {
    'valide' => 'Validée',
    'rejetee' => 'Rejetée',
    _ => 'En attente',
  };

  factory EggShipment.fromMap(Map<String, dynamic> map) {
    return EggShipment(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      hatcheryId: map['hatcheryId'] as String? ?? '',
      hatcheryName: map['hatcheryName'] as String? ?? '',
      oacCount: (map['oacCount'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'en_attente_validation',
      performedBy: map['performedBy'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
      validatedAt: parseCameroonTime(map['validatedAt']?.toString()),
      validatedBy: map['validatedBy'] as String?,
      rejectedAt: parseCameroonTime(map['rejectedAt']?.toString()),
      rejectedBy: map['rejectedBy'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
    );
  }
}

class EggShipmentPagedResult {
  final int totalCount;
  final List<EggShipment> data;

  EggShipmentPagedResult({this.totalCount = 0, required this.data});

  factory EggShipmentPagedResult.fromMap(Map<String, dynamic> map) {
    return EggShipmentPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((s) => EggShipment.fromMap(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
