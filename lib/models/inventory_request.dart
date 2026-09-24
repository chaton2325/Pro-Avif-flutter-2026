import '../utils/cameroon_time.dart';
import 'farm_feed_stock.dart';
import 'lot_egg_stock.dart';

const inventoryTypeLabels = {'aliment': 'Aliment', 'oeufs': 'Œufs'};

/// Demande d'inventaire (correction du stock aliment ou œufs suite à un comptage physique) —
/// mécaniquement la même resaisie « remplace + archive » que la saisie admin directe des
/// valeurs de départ (voir routers/feed_starting_stock.py, routers/lot_egg_stocks.py), mais
/// passée par un circuit de validation quand ce n'est pas l'admin qui la déclenche : le
/// rédacteur ne peut que SOUMETTRE ("en_attente_validation", aucun effet sur le stock tant que
/// l'admin n'a pas validé) ; l'admin l'applique directement (autoValidate=true à la création).
class InventoryRequest {
  final String? id;
  final String farmName;
  final String type; // 'aliment' | 'oeufs'
  final List<FeedStartingQuantity> feedQuantities;
  final String? lotNumber;
  final List<RoomEggStock> eggRooms;
  final String? note;
  final String status; // 'en_attente_validation' | 'valide' | 'rejetee'
  final String? performedBy;
  final DateTime createdAt;
  final DateTime? validatedAt;
  final String? validatedBy;
  final DateTime? rejectedAt;
  final String? rejectedBy;
  final String? rejectionReason;

  InventoryRequest({
    this.id,
    required this.farmName,
    required this.type,
    this.feedQuantities = const [],
    this.lotNumber,
    this.eggRooms = const [],
    this.note,
    this.status = 'en_attente_validation',
    this.performedBy,
    required this.createdAt,
    this.validatedAt,
    this.validatedBy,
    this.rejectedAt,
    this.rejectedBy,
    this.rejectionReason,
  });

  bool get isPending => status == 'en_attente_validation';
  bool get isValidated => status == 'valide';
  bool get isRejected => status == 'rejetee';
  bool get isFeed => type == 'aliment';

  String get statusLabel => switch (status) {
    'valide' => 'Validé',
    'rejetee' => 'Rejeté',
    _ => 'En attente',
  };

  String get typeLabel => inventoryTypeLabels[type] ?? type;

  /// "120 kg RL0 + 40 kg RL1" ou "Salle 1: 50 OAC · 200 PO — Salle 2: 30 OAC" — pour
  /// l'affichage compact dans l'historique.
  String get summaryLabel {
    if (isFeed) {
      return feedQuantities
          .where((q) => q.quantityKg > 0)
          .map((q) => '${q.quantityKg} kg ${q.formulaName}')
          .join(' + ');
    }
    return eggRooms
        .where((r) => r.oac > 0 || r.po > 0 || r.dj > 0 || r.cas > 0 || r.sal > 0)
        .map((r) {
          final parts = [
            if (r.oac > 0) '${r.oac} OAC',
            if (r.po > 0) '${r.po} PO',
            if (r.dj > 0) '${r.dj} DJ',
            if (r.cas > 0) '${r.cas} CAS',
            if (r.sal > 0) '${r.sal} SAL',
          ].join(' · ');
          return '${r.roomName}: $parts';
        })
        .join(' — ');
  }

  factory InventoryRequest.fromMap(Map<String, dynamic> map) {
    return InventoryRequest(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      type: map['type'] as String? ?? 'aliment',
      feedQuantities: (map['feedQuantities'] as List<dynamic>? ?? [])
          .map((q) => FeedStartingQuantity.fromMap(q as Map<String, dynamic>))
          .toList(),
      lotNumber: map['lotNumber'] as String?,
      eggRooms: (map['eggRooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggStock.fromMap(r as Map<String, dynamic>))
          .toList(),
      note: map['note'] as String?,
      status: map['status'] as String? ?? 'en_attente_validation',
      performedBy: map['performedBy'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
      validatedAt: parseCameroonTime(map['validatedAt']?.toString()),
      validatedBy: map['validatedBy'] as String?,
      rejectedAt: parseCameroonTime(map['rejectedAt']?.toString()),
      rejectedBy: map['rejectedBy'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
    );
  }
}

class InventoryRequestPagedResult {
  final int totalCount;
  final List<InventoryRequest> data;

  InventoryRequestPagedResult({this.totalCount = 0, required this.data});

  factory InventoryRequestPagedResult.fromMap(Map<String, dynamic> map) {
    return InventoryRequestPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((r) => InventoryRequest.fromMap(r as Map<String, dynamic>))
          .toList(),
    );
  }
}
