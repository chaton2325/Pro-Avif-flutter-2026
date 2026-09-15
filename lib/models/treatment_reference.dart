class TreatmentReference {
  final String? id;
  final String type; // "vaccin" | "medicament"
  final String name;
  final String unit;
  final bool isActive;

  TreatmentReference({
    this.id,
    required this.type,
    required this.name,
    this.unit = 'doses',
    this.isActive = true,
  });

  Map<String, dynamic> toMap() => {
    'type': type,
    'name': name,
    'unit': unit,
    'isActive': isActive,
  };

  factory TreatmentReference.fromMap(Map<String, dynamic> map) {
    return TreatmentReference(
      id: map['_id'] as String?,
      type: map['type'] as String? ?? 'vaccin',
      name: map['name'] as String? ?? '',
      unit: map['unit'] as String? ?? 'doses',
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
