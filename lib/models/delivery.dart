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
  final String roomName;
  final String? lotNumberSujets;
  final double quantity;
  final String? driverName;
  final String? vehicle;
  final List<DeliveryBatchUsed> batchesUsed;
  final double unitCost;
  final double totalCost;
  final DateTime createdAt;
  final String? performedBy;
  final String status; // "confirmee" | "annulee"
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;

  Delivery({
    required this.id,
    required this.usineId,
    required this.formulaId,
    required this.formulaName,
    required this.farmName,
    required this.roomName,
    this.lotNumberSujets,
    required this.quantity,
    this.driverName,
    this.vehicle,
    this.batchesUsed = const [],
    required this.unitCost,
    required this.totalCost,
    required this.createdAt,
    this.performedBy,
    this.status = 'confirmee',
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
  });

  String get lotsLabel => batchesUsed.map((b) => b.lotNumber).join('+');
  bool get isCancelled => status == 'annulee';

  factory Delivery.fromMap(Map<String, dynamic> map) {
    return Delivery(
      id: map['_id'] as String,
      usineId: map['usineId'] as String,
      formulaId: map['formulaId'] as String,
      formulaName: map['formulaName'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      roomName: map['roomName'] as String? ?? '',
      lotNumberSujets: map['lotNumberSujets'] as String?,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
      driverName: map['driverName'] as String?,
      vehicle: map['vehicle'] as String?,
      batchesUsed: (map['batchesUsed'] as List<dynamic>? ?? [])
          .map((b) => DeliveryBatchUsed.fromMap(b as Map<String, dynamic>))
          .toList(),
      unitCost: (map['unitCost'] as num?)?.toDouble() ?? 0,
      totalCost: (map['totalCost'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(map['createdAt'] as String),
      performedBy: map['performedBy'] as String?,
      status: map['status'] as String? ?? 'confirmee',
      cancelledAt: map['cancelledAt'] != null
          ? DateTime.tryParse(map['cancelledAt'].toString())
          : null,
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
