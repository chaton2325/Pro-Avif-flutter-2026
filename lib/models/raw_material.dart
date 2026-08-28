import '../utils/cameroon_time.dart';

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

class MaterialFicheHistoryItem {
  final DateTime date;
  final String type; // "reception_attente" | "reception_validee" | "ajustement"
  final String label;
  final String detail;
  final double? amountFcfa;

  MaterialFicheHistoryItem({
    required this.date,
    required this.type,
    required this.label,
    required this.detail,
    this.amountFcfa,
  });

  factory MaterialFicheHistoryItem.fromMap(Map<String, dynamic> map) {
    return MaterialFicheHistoryItem(
      date: toCameroonTime(DateTime.parse(map['date'] as String)),
      type: map['type'] as String? ?? '',
      label: map['label'] as String? ?? '',
      detail: map['detail'] as String? ?? '',
      amountFcfa: (map['amountFcfa'] as num?)?.toDouble(),
    );
  }
}

class MaterialFiche {
  final String materialId;
  final String materialName;
  final String unit;
  final double currentStock;
  final double? weightedCost;
  final double? coverageDays;
  final List<MaterialFicheHistoryItem> history;

  MaterialFiche({
    required this.materialId,
    required this.materialName,
    required this.unit,
    required this.currentStock,
    this.weightedCost,
    this.coverageDays,
    this.history = const [],
  });

  factory MaterialFiche.fromMap(Map<String, dynamic> map) {
    return MaterialFiche(
      materialId: map['materialId'] as String,
      materialName: map['materialName'] as String? ?? '',
      unit: map['unit'] as String? ?? 'kg',
      currentStock: (map['currentStock'] as num?)?.toDouble() ?? 0,
      weightedCost: (map['weightedCost'] as num?)?.toDouble(),
      coverageDays: (map['coverageDays'] as num?)?.toDouble(),
      history: (map['history'] as List<dynamic>? ?? [])
          .map(
            (h) => MaterialFicheHistoryItem.fromMap(h as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}
