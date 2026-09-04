import '../utils/cameroon_time.dart';

class Reception {
  final String? id;
  final String usineId;
  final String rawMaterialId;
  final String? supplier;
  final double quantity;
  final String? note;
  final String lotNumber;
  final String status; // "en_attente" | "valorisee" | "annulee"
  final double? unitPrice;
  final double? totalAmount;
  final DateTime? createdAt;
  final DateTime? valorizedAt;
  final String? createdBy;
  final String? valorizedBy;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String? cancelReason;

  Reception({
    this.id,
    required this.usineId,
    required this.rawMaterialId,
    this.supplier,
    required this.quantity,
    this.note,
    this.lotNumber = '',
    this.status = 'en_attente',
    this.unitPrice,
    this.totalAmount,
    this.createdAt,
    this.valorizedAt,
    this.createdBy,
    this.valorizedBy,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason,
  });

  bool get isPending => status == 'en_attente';
  bool get isCancelled => status == 'annulee';

  Map<String, dynamic> toCreateMap({String? performedBy}) {
    return {
      'usineId': usineId,
      'rawMaterialId': rawMaterialId,
      'supplier': supplier,
      'quantity': quantity,
      'note': note,
      'performedBy': performedBy,
    };
  }

  factory Reception.fromMap(Map<String, dynamic> map) {
    return Reception(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      rawMaterialId: map['rawMaterialId'] as String,
      supplier: map['supplier'] as String?,
      quantity: (map['quantity'] as num).toDouble(),
      note: map['note'] as String?,
      lotNumber: map['lotNumber'] as String? ?? '',
      status: map['status'] as String? ?? 'en_attente',
      unitPrice: (map['unitPrice'] as num?)?.toDouble(),
      totalAmount: (map['totalAmount'] as num?)?.toDouble(),
      createdAt: parseCameroonTime(map['createdAt']?.toString()),
      valorizedAt: parseCameroonTime(map['valorizedAt']?.toString()),
      createdBy: map['createdBy'] as String?,
      valorizedBy: map['valorizedBy'] as String?,
      cancelledAt: parseCameroonTime(map['cancelledAt']?.toString()),
      cancelledBy: map['cancelledBy'] as String?,
      cancelReason: map['cancelReason'] as String?,
    );
  }
}
