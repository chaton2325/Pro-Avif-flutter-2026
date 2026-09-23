/// Couvoir (référentiel admin) : vers où les œufs à couver (OAC) sont expédiés — juste un
/// nom, géré une seule fois par l'admin, jamais de texte libre à l'expédition.
class Hatchery {
  final String? id;
  final String name;
  final bool isActive;

  Hatchery({this.id, required this.name, this.isActive = true});

  Map<String, dynamic> toMap() => {'name': name, 'isActive': isActive};

  factory Hatchery.fromMap(Map<String, dynamic> map) {
    return Hatchery(
      id: map['_id'] as String?,
      name: map['name'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
