/// Ce qu'un poste autorise dans le module Usine Aliment. Le nom du poste est libre
/// (choisi par l'admin, ex. "Magasinier de l'usine", "Caissier") ; ce sont ces
/// booléens qui pilotent l'accès aux écrans et le masquage des coûts, pas le nom.
class PostePermissions {
  final bool seeCosts;
  final bool manageReception;
  final bool setPrice;
  final bool adjustCost;
  final bool manageProduction;
  final bool validateCost;
  final bool manageDelivery;
  final bool manageAdmin;
  final bool viewStats;

  const PostePermissions({
    this.seeCosts = false,
    this.manageReception = false,
    this.setPrice = false,
    this.adjustCost = false,
    this.manageProduction = false,
    this.validateCost = false,
    this.manageDelivery = false,
    this.manageAdmin = false,
    this.viewStats = false,
  });

  static const List<MapEntry<String, String>> labels = [
    MapEntry('seeCosts', 'Voir les coûts (F/kg, FCFA, CUMP)'),
    MapEntry('manageReception', 'Réceptions, pertes, inventaire (magasinier)'),
    MapEntry('setPrice', "Saisie du prix d'achat (comptabilité)"),
    MapEntry('adjustCost', 'Ajustement manuel du CUMP (comptabilité)'),
    MapEntry('manageProduction', 'Lancer / clôturer une fabrication'),
    MapEntry('validateCost', 'Valider le coût de revient (comptabilité)'),
    MapEntry('manageDelivery', 'Livraisons vers les bâtiments (logistique)'),
    MapEntry('manageAdmin', 'Référentiel matières, formules, usines, postes'),
    MapEntry('viewStats', 'Tableau de bord et statistiques'),
  ];

  bool operator [](String key) {
    switch (key) {
      case 'seeCosts': return seeCosts;
      case 'manageReception': return manageReception;
      case 'setPrice': return setPrice;
      case 'adjustCost': return adjustCost;
      case 'manageProduction': return manageProduction;
      case 'validateCost': return validateCost;
      case 'manageDelivery': return manageDelivery;
      case 'manageAdmin': return manageAdmin;
      case 'viewStats': return viewStats;
      default: return false;
    }
  }

  PostePermissions copyWith(String key, bool value) {
    return PostePermissions(
      seeCosts: key == 'seeCosts' ? value : seeCosts,
      manageReception: key == 'manageReception' ? value : manageReception,
      setPrice: key == 'setPrice' ? value : setPrice,
      adjustCost: key == 'adjustCost' ? value : adjustCost,
      manageProduction: key == 'manageProduction' ? value : manageProduction,
      validateCost: key == 'validateCost' ? value : validateCost,
      manageDelivery: key == 'manageDelivery' ? value : manageDelivery,
      manageAdmin: key == 'manageAdmin' ? value : manageAdmin,
      viewStats: key == 'viewStats' ? value : viewStats,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'seeCosts': seeCosts,
      'manageReception': manageReception,
      'setPrice': setPrice,
      'adjustCost': adjustCost,
      'manageProduction': manageProduction,
      'validateCost': validateCost,
      'manageDelivery': manageDelivery,
      'manageAdmin': manageAdmin,
      'viewStats': viewStats,
    };
  }

  factory PostePermissions.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PostePermissions();
    return PostePermissions(
      seeCosts: map['seeCosts'] as bool? ?? false,
      manageReception: map['manageReception'] as bool? ?? false,
      setPrice: map['setPrice'] as bool? ?? false,
      adjustCost: map['adjustCost'] as bool? ?? false,
      manageProduction: map['manageProduction'] as bool? ?? false,
      validateCost: map['validateCost'] as bool? ?? false,
      manageDelivery: map['manageDelivery'] as bool? ?? false,
      manageAdmin: map['manageAdmin'] as bool? ?? false,
      viewStats: map['viewStats'] as bool? ?? false,
    );
  }
}

/// Modèles rapides repris des 6 profils de la maquette Usine Aliment, pour éviter à
/// l'admin de cocher les permissions une par une à chaque création de poste. Ce sont les
/// mêmes postes déjà pré-créés en base au premier démarrage du backend (voir database.py) ;
/// cette liste ne sert qu'à préremplir le formulaire pour un poste supplémentaire/variante.
class PosteTemplate {
  final String name;
  final PostePermissions permissions;
  const PosteTemplate(this.name, this.permissions);
}

const List<PosteTemplate> posteTemplates = [
  PosteTemplate("Magasinier de l'usine", PostePermissions(manageReception: true)),
  PosteTemplate('Responsable de production', PostePermissions(manageProduction: true)),
  PosteTemplate('Comptable / Caissier', PostePermissions(seeCosts: true, setPrice: true, adjustCost: true, validateCost: true, viewStats: true)),
  PosteTemplate('Logistique', PostePermissions(manageDelivery: true)),
  PosteTemplate('Administrateur usine', PostePermissions(manageAdmin: true, viewStats: true)),
  PosteTemplate('Direction', PostePermissions(seeCosts: true, viewStats: true)),
];

class Poste {
  final String? id;
  final String name;
  final PostePermissions permissions;
  final bool isActive;

  Poste({
    this.id,
    required this.name,
    this.permissions = const PostePermissions(),
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'permissions': permissions.toMap(),
      'isActive': isActive,
    };
  }

  factory Poste.fromMap(Map<String, dynamic> map) {
    return Poste(
      id: map['_id'] as String?,
      name: map['name'] as String,
      permissions: PostePermissions.fromMap(map['permissions'] as Map<String, dynamic>?),
      isActive: map['isActive'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Poste) return false;
    if (id != null || other.id != null) return id == other.id;
    return name == other.name;
  }

  @override
  int get hashCode => id?.hashCode ?? name.hashCode;
}
