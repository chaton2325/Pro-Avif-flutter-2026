class FormulaLine {
  final String rawMaterialId;
  final double quantityPerTon;

  FormulaLine({required this.rawMaterialId, required this.quantityPerTon});

  Map<String, dynamic> toMap() => {'rawMaterialId': rawMaterialId, 'quantityPerTon': quantityPerTon};

  factory FormulaLine.fromMap(Map<String, dynamic> map) {
    return FormulaLine(
      rawMaterialId: map['rawMaterialId'] as String,
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

  Formula({
    this.id,
    required this.usineId,
    required this.name,
    this.lines = const [],
    this.isActive = true,
  });

  double get totalPerTon => lines.fold(0, (sum, l) => sum + l.quantityPerTon);

  Map<String, dynamic> toMap() {
    return {
      'usineId': usineId,
      'name': name,
      'lines': lines.map((l) => l.toMap()).toList(),
      'isActive': isActive,
    };
  }

  factory Formula.fromMap(Map<String, dynamic> map) {
    return Formula(
      id: map['_id'] as String?,
      usineId: map['usineId'] as String,
      name: map['name'] as String,
      lines: (map['lines'] as List<dynamic>? ?? []).map((l) => FormulaLine.fromMap(l as Map<String, dynamic>)).toList(),
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
