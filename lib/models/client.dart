/// Client à qui livrer de la matière première directement (hors fermes), choisi dans
/// une liste tenue à jour par la logistique plutôt que saisi en texte libre à chaque
/// livraison — volontairement minimal (juste un nom, par usine).
class Client {
  final String id;
  final String usineId;
  final String name;
  final bool isActive;

  Client({
    required this.id,
    required this.usineId,
    required this.name,
    this.isActive = true,
  });

  factory Client.fromMap(Map<String, dynamic> map) {
    return Client(
      id: map['_id'] as String,
      usineId: map['usineId'] as String,
      name: map['name'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
