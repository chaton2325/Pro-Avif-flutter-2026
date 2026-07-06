class Farm {
  final String? id;
  final String name;
  final List<String> rooms;

  Farm({
    this.id,
    required this.name,
    this.rooms = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'rooms': rooms,
    };
  }

  factory Farm.fromMap(Map<String, dynamic> map) {
    return Farm(
      id: map['_id'] as String?,
      name: map['name'] as String,
      // Dédoublonnage défensif : une salle en double dans les données ferait planter
      // tout DropdownButtonFormField basé sur farm.rooms (valeur non unique).
      rooms: List<String>.from(map['rooms'] ?? []).toSet().toList(),
    );
  }

  // Sans cette égalité par id, un DropdownButtonFormField<Farm> plante ("zero ou 2+ items
  // avec cette valeur") dès que la liste des fermes est rechargée : les objets Farm sont
  // recréés à chaque appel API, et l'égalité par défaut (identité) ne matche plus la
  // sélection courante bien qu'il s'agisse de la même ferme.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Farm) return false;
    if (id != null || other.id != null) return id == other.id;
    return name == other.name;
  }

  @override
  int get hashCode => id?.hashCode ?? name.hashCode;
}
