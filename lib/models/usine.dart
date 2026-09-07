class Usine {
  final String? id;
  final String name;
  final String? address;
  final bool isActive;
  final String? supplyValidatorWhatsapp;
  final String? productionValidatorWhatsapp;

  Usine({
    this.id,
    required this.name,
    this.address,
    this.isActive = true,
    this.supplyValidatorWhatsapp,
    this.productionValidatorWhatsapp,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'isActive': isActive,
      'supplyValidatorWhatsapp': supplyValidatorWhatsapp,
      'productionValidatorWhatsapp': productionValidatorWhatsapp,
    };
  }

  factory Usine.fromMap(Map<String, dynamic> map) {
    return Usine(
      id: map['_id'] as String?,
      name: map['name'] as String,
      address: map['address'] as String?,
      isActive: map['isActive'] as bool? ?? true,
      supplyValidatorWhatsapp: map['supplyValidatorWhatsapp'] as String?,
      productionValidatorWhatsapp:
          map['productionValidatorWhatsapp'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Usine) return false;
    if (id != null || other.id != null) return id == other.id;
    return name == other.name;
  }

  @override
  int get hashCode => id?.hashCode ?? name.hashCode;
}
