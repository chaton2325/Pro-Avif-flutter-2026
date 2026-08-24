class Reception {
  final String? id;
  final String usineId;
  final String rawMaterialId;
  final String? supplier;
  final double quantity;
  final String? note;
  final String lotNumber;
  final String status; // "en_attente" | "valorisee"
  final double? unitPrice;
  final double? totalAmount;
  final DateTime? createdAt;
  final DateTime? valorizedAt;

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
  });

  bool get isPending => status == 'en_attente';

  Map<String, dynamic> toCreateMap() {
    return {
      'usineId': usineId,
      'rawMaterialId': rawMaterialId,
      'supplier': supplier,
      'quantity': quantity,
      'note': note,
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
      createdAt: map['createdAt'] != null ? DateTime.tryParse(map['createdAt'].toString()) : null,
      valorizedAt: map['valorizedAt'] != null ? DateTime.tryParse(map['valorizedAt'].toString()) : null,
    );
  }
}
