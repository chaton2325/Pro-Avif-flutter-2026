import '../utils/cameroon_time.dart';

/// Un mouvement de stock (approvisionnement OU décrément) pour une matière première ou un
/// aliment précis — [quantity] est toujours signée : positive = entrée en stock, négative
/// = sortie, quelle que soit la source (réception, fabrication, livraison, perte...).
class StockMovement {
  final DateTime date;
  final String type;
  final String label;
  final double quantity;
  final String unit;
  final String? lotNumber;
  final String? performedBy;
  final String? note;

  StockMovement({
    required this.date,
    required this.type,
    required this.label,
    required this.quantity,
    required this.unit,
    this.lotNumber,
    this.performedBy,
    this.note,
  });

  bool get isEntry => quantity >= 0;

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      date: parseCameroonTime(map['date']?.toString()) ?? DateTime.now(),
      type: map['type'] as String? ?? '',
      label: map['label'] as String? ?? '',
      quantity: (map['quantity'] as num).toDouble(),
      unit: map['unit'] as String? ?? 'kg',
      lotNumber: map['lotNumber'] as String?,
      performedBy: map['performedBy'] as String?,
      note: map['note'] as String?,
    );
  }
}

class StockMovementPage {
  final int totalCount;
  final List<StockMovement> items;
  final int limit;
  final int skip;

  StockMovementPage({
    required this.totalCount,
    required this.items,
    required this.limit,
    required this.skip,
  });

  factory StockMovementPage.fromMap(Map<String, dynamic> map) {
    return StockMovementPage(
      totalCount: map['total_count'] as int? ?? 0,
      items: (map['data'] as List<dynamic>? ?? [])
          .map((m) => StockMovement.fromMap(m as Map<String, dynamic>))
          .toList(),
      limit: map['limit'] as int? ?? 30,
      skip: map['skip'] as int? ?? 0,
    );
  }
}
