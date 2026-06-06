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
      rooms: List<String>.from(map['rooms'] ?? []),
    );
  }
}
