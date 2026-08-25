/// Une ligne référence SOIT une matière première achetée, SOIT un autre aliment produit
/// en interne (ex. SUPER PLUS, un concentré utilisé comme ingrédient d'une autre
/// formule) — jamais les deux, jamais aucun.
class FormulaLine {
  final String? rawMaterialId;
  final String? ingredientFormulaId;
  final double quantityPerTon;

  FormulaLine({
    this.rawMaterialId,
    this.ingredientFormulaId,
    required this.quantityPerTon,
  });

  bool get isIngredientAliment => ingredientFormulaId != null;

  /// L'id de la source (matière ou aliment), quel que soit son type — pratique pour les
  /// dropdowns et comparaisons sans avoir à tester les deux champs à chaque fois.
  String? get sourceId => rawMaterialId ?? ingredientFormulaId;

  Map<String, dynamic> toMap() => {
    'rawMaterialId': rawMaterialId,
    'ingredientFormulaId': ingredientFormulaId,
    'quantityPerTon': quantityPerTon,
  };

  factory FormulaLine.fromMap(Map<String, dynamic> map) {
    return FormulaLine(
      rawMaterialId: map['rawMaterialId'] as String?,
      ingredientFormulaId: map['ingredientFormulaId'] as String?,
      quantityPerTon: (map['quantityPerTon'] as num).toDouble(),
    );
  }
}

class Formula {
  final String? id;
  final String usineId;
  final String name;
  final List<FormulaLine> lines;
  final bool isActive;
  final double lowStockThreshold;
  // False par défaut : un aliment (ex. RL0, produit fini vendu) n'est pas utilisable comme
  // ingrédient d'un autre par défaut — seul un aliment explicitement marqué (ex. SUPER
  // PLUS) peut apparaître dans la composition d'une autre formule.
  final bool canBeIngredient;

  Formula({
    this.id,
    required this.usineId,
    required this.name,
    this.lines = const [],
    this.isActive = true,
    this.lowStockThreshold = 0,
    this.canBeIngredient = false,
  });

  double get totalPerTon => lines.fold(0, (sum, l) => sum + l.quantityPerTon);

  Map<String, dynamic> toMap() {
    return {
      'usineId': usineId,
      'name': name,
      'lines': lines.map((l) => l.toMap()).toList(),
      'isActive': isActive,
      'lowStockThreshold': lowStockThreshold,
      'canBeIngredient': canBeIngredient,
    };
  }

  factory Formula.fromMap(Map<String, dynamic> map) {
    return Formula(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      name: map['name'] as String,
      lines: (map['lines'] as List<dynamic>? ?? [])
          .map((l) => FormulaLine.fromMap(l as Map<String, dynamic>))
          .toList(),
      isActive: map['isActive'] as bool? ?? true,
      lowStockThreshold: (map['lowStockThreshold'] as num?)?.toDouble() ?? 0,
      canBeIngredient: map['canBeIngredient'] as bool? ?? false,
    );
  }
}
