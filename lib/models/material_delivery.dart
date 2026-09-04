import '../utils/cameroon_time.dart';
import 'delivery.dart' show DeliveryBatchUsed;

/// Livraison de matière première directement à un client (hors production), même cycle
/// de vie qu'une livraison d'aliment vers une ferme (voir delivery.dart) : "en_attente"
/// (créée, stock pas encore touché) -> "confirmee" (validée, stock déduit) ou "annulee".
class MaterialDelivery {
  final String id;
  final String usineId;
  final String rawMaterialId;
  final String materialName;
  final String unit;
  final String clientName;
  final double quantity;
  final String? driverName;
  final String? vehicle;
  // true = matière « par lot » consommée en FIFO (batchesUsed rempli à la validation) ;
  // false = matière en gestion globale, décrémentée directement au CUMP en vigueur.
  final bool isParLot;
  final List<DeliveryBatchUsed> batchesUsed;
  final double unitCost;
  final double totalCost;
  final DateTime createdAt;
  final String? performedBy;
  final String status;
  final DateTime? validatedAt;
  final String? validatedBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;

  MaterialDelivery({
    required this.id,
    required this.usineId,
    required this.rawMaterialId,
    required this.materialName,
    this.unit = 'kg',
    required this.clientName,
    required this.quantity,
    this.driverName,
    this.vehicle,
    this.isParLot = false,
    this.batchesUsed = const [],
    required this.unitCost,
    required this.totalCost,
    required this.createdAt,
    this.performedBy,
    this.status = 'en_attente',
    this.validatedAt,
    this.validatedBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
  });

  String get lotsLabel => batchesUsed.map((b) => b.lotNumber).join('+');
  bool get isCancelled => status == 'annulee';
  bool get isPending => status == 'en_attente';

  factory MaterialDelivery.fromMap(Map<String, dynamic> map) {
    return MaterialDelivery(
      id: map['_id'] as String,
      usineId: map['usineId'] as String,
      rawMaterialId: map['rawMaterialId'] as String,
      materialName: map['materialName'] as String? ?? '',
      unit: map['unit'] as String? ?? 'kg',
      clientName: map['clientName'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      driverName: map['driverName'] as String?,
      vehicle: map['vehicle'] as String?,
      isParLot: map['isParLot'] as bool? ?? false,
      batchesUsed: (map['batchesUsed'] as List<dynamic>? ?? [])
          .map((b) => DeliveryBatchUsed.fromMap(b as Map<String, dynamic>))
          .toList(),
      unitCost: (map['unitCost'] as num?)?.toDouble() ?? 0,
      totalCost: (map['totalCost'] as num?)?.toDouble() ?? 0,
      createdAt: toCameroonTime(DateTime.parse(map['createdAt'] as String)),
      performedBy: map['performedBy'] as String?,
      status: map['status'] as String? ?? 'en_attente',
      validatedAt: parseCameroonTime(map['validatedAt']?.toString()),
      validatedBy: map['validatedBy'] as String?,
      cancelledAt: parseCameroonTime(map['cancelledAt']?.toString()),
      cancelledBy: map['cancelledBy'] as String?,
      cancelReason: map['cancelReason'] as String?,
    );
  }
}

class MaterialDeliveryPagedResult {
  final int totalCount;
  final List<MaterialDelivery> data;
  final int limit;
  final int skip;

  MaterialDeliveryPagedResult({
    required this.totalCount,
    required this.data,
    required this.limit,
    required this.skip,
  });

  factory MaterialDeliveryPagedResult.fromMap(Map<String, dynamic> map) {
    return MaterialDeliveryPagedResult(
      totalCount: (map['total_count'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((d) => MaterialDelivery.fromMap(d as Map<String, dynamic>))
          .toList(),
      limit: (map['limit'] as num?)?.toInt() ?? 30,
      skip: (map['skip'] as num?)?.toInt() ?? 0,
    );
  }
}
