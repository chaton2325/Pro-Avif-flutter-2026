class User {
  final String? id;
  final String name;
  final String password;
  final String role; // 'admin' or 'user'
  final String? farmId;
  final bool isActive;
  final String language; // 'fr' or 'en'
  final int scalePrecision; // e.g., 1, 2, 3 decimal places
  // Module Rapport Journalier — un rédacteur (role='user') ne voit "Expédier des œufs" sur son
  // accueil que si ce champ est true (voir AdminDailyReportUsersScreen). Sans effet pour
  // 'admin'/'validateur'. Défaut true pour ne rien changer aux comptes déjà en place.
  final bool canCreateEggShipments;

  User({
    this.id,
    required this.name,
    required this.password,
    required this.role,
    this.farmId,
    this.isActive = true,
    this.language = 'fr',
    this.scalePrecision = 2,
    this.canCreateEggShipments = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'password': password,
      'role': role,
      'farmId': farmId,
      'isActive': isActive,
      'language': language,
      'scalePrecision': scalePrecision,
      'canCreateEggShipments': canCreateEggShipments,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    String? farmIdStr;
    if (map['farmId'] is String) {
      farmIdStr = map['farmId'];
    } else if (map['farmId'] is Map && map['farmId'].containsKey('\$oid')) {
      farmIdStr = map['farmId']['\$oid'];
    }

    return User(
      id: map['_id'] as String?,
      name: map['name'] as String,
      password: map['password'] as String? ?? '',
      role: map['role'] as String,
      farmId: farmIdStr,
      isActive: map['isActive'] as bool? ?? true,
      language: map['language'] as String? ?? 'fr',
      scalePrecision: map['scalePrecision'] as int? ?? 2,
      canCreateEggShipments: map['canCreateEggShipments'] as bool? ?? true,
    );
  }
}
