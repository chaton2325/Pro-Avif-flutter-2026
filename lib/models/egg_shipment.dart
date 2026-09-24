import '../utils/cameroon_time.dart';

const eggTypes = ['oac', 'po', 'dj', 'cas', 'sal'];
const eggTypeLabels = {'oac': 'OAC', 'po': 'PO', 'dj': 'DJ', 'cas': 'CAS', 'sal': 'SAL'};
const eggTypeCountFields = {
  'oac': 'oacCount',
  'po': 'poCount',
  'dj': 'djCount',
  'cas': 'casCount',
  'sal': 'salCount',
};

/// Expédition d'œufs vers un couvoir, pouvant mélanger plusieurs catégories (OAC/PO/DJ/CAS/SAL)
/// en une seule livraison : une fois VALIDÉE par l'admin, diminue le STOCK actuel de chaque
/// catégorie expédiée (voir CurrentEggStock.stockFor) — jamais le cumul de production qui ne
/// fait qu'accumuler. Tant qu'elle est en attente ou rejetée, aucun effet sur le stock.
///
/// Workflow (même principe que les rapports journaliers) : "en_attente_validation" à la
/// création, puis "valide" (stock décrémenté) ou "rejetee" (motif obligatoire, aucun effet)
/// après passage de l'admin.
class EggShipment {
  final String? id;
  final String farmName;
  final String? lotNumber;
  final String hatcheryId;
  final String hatcheryName;
  final int oacCount;
  final int poCount;
  final int djCount;
  final int casCount;
  final int salCount;
  final String status;
  final String? performedBy;
  final DateTime createdAt;
  final DateTime? validatedAt;
  final String? validatedBy;
  final DateTime? rejectedAt;
  final String? rejectedBy;
  final String? rejectionReason;
  // Coût de revient par œuf (FCFA), PAR CATÉGORIE (ex. {'oac': 25, 'po': 10}) — saisi à la
  // validation, une clé par catégorie présente dans l'expédition.
  final Map<String, double>? costPerEgg;
  // Charges indirectes TOTALES (FCFA) — saisi à la validation, pour toute l'expédition
  final double? indirectCosts;
  // Motif / commentaire de la validation
  final String? motif;
  // Coût total = somme(costPerEgg[categorie] * quantité de cette catégorie) + indirectCosts
  final double? totalCost;

  EggShipment({
    this.id,
    required this.farmName,
    this.lotNumber,
    required this.hatcheryId,
    required this.hatcheryName,
    this.oacCount = 0,
    this.poCount = 0,
    this.djCount = 0,
    this.casCount = 0,
    this.salCount = 0,
    this.status = 'en_attente_validation',
    this.performedBy,
    required this.createdAt,
    this.validatedAt,
    this.validatedBy,
    this.rejectedAt,
    this.rejectedBy,
    this.rejectionReason,
    this.costPerEgg,
    this.indirectCosts,
    this.motif,
    this.totalCost,
  });

  bool get isPending => status == 'en_attente_validation';
  bool get isValidated => status == 'valide';
  bool get isRejected => status == 'rejetee';

  int countFor(String eggType) => switch (eggType) {
    'po' => poCount,
    'dj' => djCount,
    'cas' => casCount,
    'sal' => salCount,
    _ => oacCount,
  };

  /// Toutes les catégories non nulles de cette expédition, dans l'ordre OAC/PO/DJ/CAS/SAL —
  /// une livraison peut désormais en mélanger plusieurs (ex. 50 OAC + 30 PO).
  List<MapEntry<String, int>> get categoryCounts => [
    for (final t in eggTypes)
      if (countFor(t) > 0) MapEntry(t, countFor(t)),
  ];

  int get totalCount => oacCount + poCount + djCount + casCount + salCount;

  /// "50 OAC + 30 PO" — pour l'affichage compact (historique, dialogs de validation/rejet).
  String get summaryLabel =>
      categoryCounts.map((e) => '${e.value} ${eggTypeLabels[e.key]}').join(' + ');

  String get statusLabel => switch (status) {
    'valide' => 'Validée',
    'rejetee' => 'Rejetée',
    _ => 'En attente',
  };

  factory EggShipment.fromMap(Map<String, dynamic> map) {
    return EggShipment(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      hatcheryId: map['hatcheryId'] as String? ?? '',
      hatcheryName: map['hatcheryName'] as String? ?? '',
      oacCount: (map['oacCount'] as num?)?.toInt() ?? 0,
      poCount: (map['poCount'] as num?)?.toInt() ?? 0,
      djCount: (map['djCount'] as num?)?.toInt() ?? 0,
      casCount: (map['casCount'] as num?)?.toInt() ?? 0,
      salCount: (map['salCount'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? 'en_attente_validation',
      performedBy: map['performedBy'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
      validatedAt: parseCameroonTime(map['validatedAt']?.toString()),
      validatedBy: map['validatedBy'] as String?,
      rejectedAt: parseCameroonTime(map['rejectedAt']?.toString()),
      rejectedBy: map['rejectedBy'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
      costPerEgg: (map['costPerEgg'] as Map<String, dynamic>?)
          ?.map((k, v) => MapEntry(k, (v as num).toDouble())),
      indirectCosts: (map['indirectCosts'] as num?)?.toDouble(),
      motif: map['motif'] as String?,
      totalCost: (map['totalCost'] as num?)?.toDouble(),
    );
  }
}

class EggShipmentPagedResult {
  final int totalCount;
  final List<EggShipment> data;

  EggShipmentPagedResult({this.totalCount = 0, required this.data});

  factory EggShipmentPagedResult.fromMap(Map<String, dynamic> map) {
    return EggShipmentPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((s) => EggShipment.fromMap(s as Map<String, dynamic>))
          .toList(),
    );
  }
}
