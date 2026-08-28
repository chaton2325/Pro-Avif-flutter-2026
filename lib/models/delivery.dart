import '../utils/cameroon_time.dart';

class DeliveryBatchUsed {
  final String batchId;
  final String lotNumber;
  final double quantity;

  DeliveryBatchUsed({
    required this.batchId,
    required this.lotNumber,
    required this.quantity,
  });

  factory DeliveryBatchUsed.fromMap(Map<String, dynamic> map) {
    return DeliveryBatchUsed(
      batchId: map['batchId'] as String,
      lotNumber: map['lotNumber'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}

class Delivery {
  final String id;
  final String usineId;
  final String formulaId;
  final String formulaName;
  final String farmName;
  final String?
  roomName; // conservé seulement pour les livraisons historiques (avant que
  // la destination ne devienne la ferme, jamais une salle précise)
  final String? lotNumberSujets;
  final double quantity;
  final String? driverName;
  final String? vehicle;
  final List<DeliveryBatchUsed> batchesUsed;
  final double unitCost;
  final double totalCost;
  final DateTime createdAt;
  final String? performedBy;
  // "en_attente" (créée, stock pas encore touché) | "confirmee" (validée, stock déduit)
  // | "annulee" (annulée/rejetée, à tout moment).
  final String status;
  final DateTime? validatedAt;
  final String? validatedBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;

  Delivery({
    required this.id,
    required this.usineId,
    required this.formulaId,
    required this.formulaName,
    required this.farmName,
    this.roomName,
    this.lotNumberSujets,
    required this.quantity,
    this.driverName,
    this.vehicle,
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
  // On livre à la ferme, jamais à une salle précise ; roomName ne subsiste que sur les
  // livraisons créées avant ce changement.
  String get destinationLabel => (roomName == null || roomName!.isEmpty)
      ? farmName
      : '$farmName — $roomName';

  factory Delivery.fromMap(Map<String, dynamic> map) {
    return Delivery(
      id: map['_id'] as String,
      usineId: map['usineId'] as String,
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      roomName: map['roomName'] as String?,
      lotNumberSujets: map['lotNumberSujets'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      driverName: map['driverName'] as String?,
      vehicle: map['vehicle'] as String?,
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

class DeliveryPagedResult {
  final int totalCount;
  final List<Delivery> data;
  final int limit;
  final int skip;

  DeliveryPagedResult({
    required this.totalCount,
    required this.data,
    required this.limit,
    required this.skip,
  });

  factory DeliveryPagedResult.fromMap(Map<String, dynamic> map) {
    return DeliveryPagedResult(
      totalCount: (map['total_count'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((d) => Delivery.fromMap(d as Map<String, dynamic>))
          .toList(),
      limit: (map['limit'] as num?)?.toInt() ?? 30,
      skip: (map['skip'] as num?)?.toInt() ?? 0,
    );
  }
}
