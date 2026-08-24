class RawMaterial {
  final String? id;
  final String usineId;
  final String name;
  final String unit;
  final String? category;
  final String managementMode; // "global" (CUMP unique) | "par_lot"
  final double lowStockThreshold;
  final List<String> usualSuppliers;
  final bool isActive;
  // Gérés uniquement par les endpoints d'approvisionnement (réceptions, lots, pertes,
  // inventaire) : jamais envoyés par toMap(), pour ne jamais être écrasés par une simple
  // édition du référentiel (nom, catégorie...).
  final double currentStock;
  final double? weightedCost;

  RawMaterial({
    this.id,
    required this.usineId,
    required this.name,
    this.unit = 'kg',
    this.category,
    this.managementMode = 'global',
    this.lowStockThreshold = 0,
    this.usualSuppliers = const [],
    this.isActive = true,
    this.currentStock = 0,
    this.weightedCost,
  });

  bool get isParLot => managementMode == 'par_lot';

  Map<String, dynamic> toMap() {
    return {
      'usineId': usineId,
      'name': name,
      'unit': unit,
      'category': category,
      'managementMode': managementMode,
      'lowStockThreshold': lowStockThreshold,
      'usualSuppliers': usualSuppliers,
      'isActive': isActive,
    };
  }

  factory RawMaterial.fromMap(Map<String, dynamic> map) {
    return RawMaterial(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      name: map['name'] as String,
      unit: map['unit'] as String? ?? 'kg',
      category: map['category'] as String?,
      managementMode: map['managementMode'] as String? ?? 'global',
      lowStockThreshold: (map['lowStockThreshold'] as num?)?.toDouble() ?? 0,
      usualSuppliers: List<String>.from(map['usualSuppliers'] ?? []),
      isActive: map['isActive'] as bool? ?? true,
      currentStock: (map['currentStock'] as num?)?.toDouble() ?? 0,
      weightedCost: (map['weightedCost'] as num?)?.toDouble(),
    );
  }
}
