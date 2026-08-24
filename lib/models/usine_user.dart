/// Utilisateur du module Usine Aliment. Distinct de [User] (module Rapport Journalier,
/// rattaché à une ferme) : un UsineUser ne dépend d'aucune ferme, il reçoit des
/// affectations de poste (usine) — voir [PosteAssignment].
class UsineUser {
  final String? id;
  final String name;
  final String password;
  final bool isActive;

  UsineUser({
    this.id,
    required this.name,
    required this.password,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'password': password,
      'isActive': isActive,
    };
  }

  factory UsineUser.fromMap(Map<String, dynamic> map) {
    return UsineUser(
      id: map['_id'] as String?,
      name: map['name'] as String,
      password: map['password'] as String? ?? '',
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
