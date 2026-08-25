/// Chauffeur ou véhicule, choisi dans une liste gérée par la logistique plutôt que
/// saisi en texte libre à chaque livraison.
class DeliveryResource {
  final String id;
  final String usineId;
  final String name;
  final bool isActive;

  DeliveryResource({
    required this.id,
    required this.usineId,
    required this.name,
    this.isActive = true,
  });

  factory DeliveryResource.fromMap(Map<String, dynamic> map) {
    return DeliveryResource(
      id: map['_id'] as String,
      usineId: map['usineId'] as String,
      name: map['name'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
