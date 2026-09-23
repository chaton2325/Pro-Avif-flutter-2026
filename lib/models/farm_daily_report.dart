import '../utils/cameroon_time.dart';
import 'lot_headcount.dart';

class SexCount {
  final int femaleCount;
  final int maleCount;

  SexCount({this.femaleCount = 0, this.maleCount = 0});

  Map<String, dynamic> toMap() => {
    'femaleCount': femaleCount,
    'maleCount': maleCount,
  };

  factory SexCount.fromMap(Map<String, dynamic>? map) {
    if (map == null) return SexCount();
    return SexCount(
      femaleCount: (map['femaleCount'] as num?)?.toInt() ?? 0,
      maleCount: (map['maleCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class DailyReportFeedReceivedItem {
  final String deliveryId;
  final String formulaName;
  final double quantity;

  DailyReportFeedReceivedItem({
    required this.deliveryId,
    required this.formulaName,
    required this.quantity,
  });

  factory DailyReportFeedReceivedItem.fromMap(Map<String, dynamic> map) {
    return DailyReportFeedReceivedItem(
      deliveryId: map['deliveryId'] as String? ?? '',
      formulaName: map['formulaName'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RoomConsumptionEntry {
  final String roomName;
  final String? formulaId;
  final String? formulaName;
  final double quantityKg; // total F+M, toujours recalculé côté serveur
  // null = pas encore ventilé par sexe (rapport antérieur à cette fonctionnalité) ; 0 =
  // ventilé, mais aucune quantité saisie pour ce sexe. Distinction importante à l'affichage.
  final double? femaleQuantityKg;
  final double? maleQuantityKg;

  RoomConsumptionEntry({
    required this.roomName,
    this.formulaId,
    this.formulaName,
    this.quantityKg = 0,
    this.femaleQuantityKg,
    this.maleQuantityKg,
  });

  Map<String, dynamic> toMap() => {
    'roomName': roomName,
    'formulaId': formulaId,
    'formulaName': formulaName,
    'quantityKg': quantityKg,
    'femaleQuantityKg': femaleQuantityKg,
    'maleQuantityKg': maleQuantityKg,
  };

  factory RoomConsumptionEntry.fromMap(Map<String, dynamic> map) {
    return RoomConsumptionEntry(
      roomName: map['roomName'] as String? ?? '',
      formulaId: map['formulaId'] as String?,
      formulaName: map['formulaName'] as String?,
      quantityKg: (map['quantityKg'] as num?)?.toDouble() ?? 0,
      femaleQuantityKg: (map['femaleQuantityKg'] as num?)?.toDouble(),
      maleQuantityKg: (map['maleQuantityKg'] as num?)?.toDouble(),
    );
  }

  RoomConsumptionEntry copyWith({
    String? formulaId,
    String? formulaName,
    double? femaleQuantityKg,
    double? maleQuantityKg,
  }) {
    final f = femaleQuantityKg ?? this.femaleQuantityKg ?? 0;
    final m = maleQuantityKg ?? this.maleQuantityKg ?? 0;
    return RoomConsumptionEntry(
      roomName: roomName,
      formulaId: formulaId ?? this.formulaId,
      formulaName: formulaName ?? this.formulaName,
      quantityKg: f + m,
      femaleQuantityKg: f,
      maleQuantityKg: m,
    );
  }
}

/// Cumul de consommation pour une salle + un aliment donnés (F/M) — au niveau de la salle,
/// pas de chaque entrée du jour (une salle peut consommer plusieurs aliments le même jour) :
/// calculé serveur uniquement, continue la chaîne des rapports précédents (voir RoomFeedCumul
/// côté backend).
class RoomFeedConsumptionCumul {
  final String roomName;
  final String? formulaId;
  final String? formulaName;
  final double femaleKg;
  final double maleKg;

  RoomFeedConsumptionCumul({
    required this.roomName,
    this.formulaId,
    this.formulaName,
    this.femaleKg = 0,
    this.maleKg = 0,
  });

  factory RoomFeedConsumptionCumul.fromMap(Map<String, dynamic> map) {
    return RoomFeedConsumptionCumul(
      roomName: map['roomName'] as String? ?? '',
      formulaId: map['formulaId'] as String?,
      formulaName: map['formulaName'] as String?,
      femaleKg: (map['femaleKg'] as num?)?.toDouble() ?? 0,
      maleKg: (map['maleKg'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DailyReportAliment {
  final double receivedTotalKg;
  final List<DailyReportFeedReceivedItem> receivedDetail;
  final List<RoomConsumptionEntry> consumptionByRoom;
  final List<RoomFeedConsumptionCumul> cumulativeConsumptionByRoom;
  final double totalConsumedKg;
  final double stockBeforeKg;
  final double stockAfterKg;
  final double? securityStockDays;

  DailyReportAliment({
    this.receivedTotalKg = 0,
    this.receivedDetail = const [],
    this.consumptionByRoom = const [],
    this.cumulativeConsumptionByRoom = const [],
    this.totalConsumedKg = 0,
    this.stockBeforeKg = 0,
    this.stockAfterKg = 0,
    this.securityStockDays,
  });

  /// receivedDetail a une entrée par livraison reçue (traçabilité), donc le même aliment
  /// apparaît plusieurs fois si plusieurs camions livrent la même formule le même jour —
  /// regroupé ici par aliment pour l'affichage ("Reçu aujourd'hui"), jamais pour le calcul.
  Map<String, double> get receivedTotalsByFormula {
    final totals = <String, double>{};
    for (final d in receivedDetail) {
      totals[d.formulaName] = (totals[d.formulaName] ?? 0) + d.quantity;
    }
    return totals;
  }

  factory DailyReportAliment.fromMap(Map<String, dynamic>? map) {
    if (map == null) return DailyReportAliment();
    return DailyReportAliment(
      receivedTotalKg: (map['receivedTotalKg'] as num?)?.toDouble() ?? 0,
      receivedDetail: (map['receivedDetail'] as List<dynamic>? ?? [])
          .map((d) => DailyReportFeedReceivedItem.fromMap(d as Map<String, dynamic>))
          .toList(),
      consumptionByRoom: (map['consumptionByRoom'] as List<dynamic>? ?? [])
          .map((c) => RoomConsumptionEntry.fromMap(c as Map<String, dynamic>))
          .toList(),
      cumulativeConsumptionByRoom: (map['cumulativeConsumptionByRoom'] as List<dynamic>? ?? [])
          .map((c) => RoomFeedConsumptionCumul.fromMap(c as Map<String, dynamic>))
          .toList(),
      totalConsumedKg: (map['totalConsumedKg'] as num?)?.toDouble() ?? 0,
      stockBeforeKg: (map['stockBeforeKg'] as num?)?.toDouble() ?? 0,
      stockAfterKg: (map['stockAfterKg'] as num?)?.toDouble() ?? 0,
      securityStockDays: (map['securityStockDays'] as num?)?.toDouble(),
    );
  }
}

class DailyReportMortality {
  final List<RoomHeadcount> byRoom;
  final SexCount clinic;
  final int totalFemale;
  final int totalMale;
  // Cumul par salle et par sexe (voir RoomHeadcount, réutilisé tel quel) — le total ferme
  // ci-dessous (cumulativeFemale/Male) en est toujours la somme + la clinique.
  final List<RoomHeadcount> cumulativeByRoom;
  final int cumulativeClinicFemale;
  final int cumulativeClinicMale;
  final int cumulativeFemale;
  final int cumulativeMale;
  final double? rateFemalePercent;
  final double? rateMalePercent;

  DailyReportMortality({
    this.byRoom = const [],
    SexCount? clinic,
    this.totalFemale = 0,
    this.totalMale = 0,
    this.cumulativeByRoom = const [],
    this.cumulativeClinicFemale = 0,
    this.cumulativeClinicMale = 0,
    this.cumulativeFemale = 0,
    this.cumulativeMale = 0,
    this.rateFemalePercent,
    this.rateMalePercent,
  }) : clinic = clinic ?? SexCount();

  factory DailyReportMortality.fromMap(Map<String, dynamic>? map) {
    if (map == null) return DailyReportMortality();
    return DailyReportMortality(
      byRoom: (map['byRoom'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      clinic: SexCount.fromMap(map['clinic'] as Map<String, dynamic>?),
      totalFemale: (map['totalFemale'] as num?)?.toInt() ?? 0,
      totalMale: (map['totalMale'] as num?)?.toInt() ?? 0,
      cumulativeByRoom: (map['cumulativeByRoom'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      cumulativeClinicFemale: (map['cumulativeClinicFemale'] as num?)?.toInt() ?? 0,
      cumulativeClinicMale: (map['cumulativeClinicMale'] as num?)?.toInt() ?? 0,
      cumulativeFemale: (map['cumulativeFemale'] as num?)?.toInt() ?? 0,
      cumulativeMale: (map['cumulativeMale'] as num?)?.toInt() ?? 0,
      rateFemalePercent: (map['rateFemalePercent'] as num?)?.toDouble(),
      rateMalePercent: (map['rateMalePercent'] as num?)?.toDouble(),
    );
  }
}

/// Déplacement de sujets d'une salle à une autre du même bâtiment, le même jour — jamais
/// entre deux fermes. N'affecte que endCounts (start - mortalité - sorti + entré).
class RoomTransferEntry {
  final String fromRoom;
  final String toRoom;
  final int femaleCount;
  final int maleCount;

  RoomTransferEntry({required this.fromRoom, required this.toRoom, this.femaleCount = 0, this.maleCount = 0});

  Map<String, dynamic> toMap() => {
    'fromRoom': fromRoom,
    'toRoom': toRoom,
    'femaleCount': femaleCount,
    'maleCount': maleCount,
  };

  factory RoomTransferEntry.fromMap(Map<String, dynamic> map) {
    return RoomTransferEntry(
      fromRoom: map['fromRoom'] as String? ?? '',
      toRoom: map['toRoom'] as String? ?? '',
      femaleCount: (map['femaleCount'] as num?)?.toInt() ?? 0,
      maleCount: (map['maleCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class RoomProduction {
  final String roomName;
  final int oac;
  final int po;
  final int dj;
  final int cas;
  final int sal;
  final double tpPercent;
  final double? ecartPercent;
  final double dePercent;
  final int cumulativeOac;
  final int cumulativePo;
  final int cumulativeDj;
  final int cumulativeCas;
  final int cumulativeSal;

  RoomProduction({
    required this.roomName,
    this.oac = 0,
    this.po = 0,
    this.dj = 0,
    this.cas = 0,
    this.sal = 0,
    this.tpPercent = 0,
    this.ecartPercent,
    this.dePercent = 0,
    this.cumulativeOac = 0,
    this.cumulativePo = 0,
    this.cumulativeDj = 0,
    this.cumulativeCas = 0,
    this.cumulativeSal = 0,
  });

  Map<String, dynamic> toMap() => {
    'roomName': roomName,
    'oac': oac,
    'po': po,
    'dj': dj,
    'cas': cas,
    'sal': sal,
    // Champs AUTO tolérés en écriture mais toujours recalculés côté serveur.
    'tpPercent': tpPercent,
    'ecartPercent': ecartPercent,
    'dePercent': dePercent,
    'cumulativeOac': cumulativeOac,
    'cumulativePo': cumulativePo,
    'cumulativeDj': cumulativeDj,
    'cumulativeCas': cumulativeCas,
    'cumulativeSal': cumulativeSal,
  };

  factory RoomProduction.fromMap(Map<String, dynamic> map) {
    return RoomProduction(
      roomName: map['roomName'] as String? ?? '',
      oac: (map['oac'] as num?)?.toInt() ?? 0,
      po: (map['po'] as num?)?.toInt() ?? 0,
      dj: (map['dj'] as num?)?.toInt() ?? 0,
      cas: (map['cas'] as num?)?.toInt() ?? 0,
      sal: (map['sal'] as num?)?.toInt() ?? 0,
      tpPercent: (map['tpPercent'] as num?)?.toDouble() ?? 0,
      ecartPercent: (map['ecartPercent'] as num?)?.toDouble(),
      dePercent: (map['dePercent'] as num?)?.toDouble() ?? 0,
      cumulativeOac: (map['cumulativeOac'] as num?)?.toInt() ?? 0,
      cumulativePo: (map['cumulativePo'] as num?)?.toInt() ?? 0,
      cumulativeDj: (map['cumulativeDj'] as num?)?.toInt() ?? 0,
      cumulativeCas: (map['cumulativeCas'] as num?)?.toInt() ?? 0,
      cumulativeSal: (map['cumulativeSal'] as num?)?.toInt() ?? 0,
    );
  }

  RoomProduction copyWith({
    int? oac,
    int? po,
    int? dj,
    int? cas,
    int? sal,
  }) => RoomProduction(
    roomName: roomName,
    oac: oac ?? this.oac,
    po: po ?? this.po,
    dj: dj ?? this.dj,
    cas: cas ?? this.cas,
    sal: sal ?? this.sal,
    tpPercent: tpPercent,
    ecartPercent: ecartPercent,
    dePercent: dePercent,
    cumulativeOac: cumulativeOac,
    cumulativePo: cumulativePo,
    cumulativeDj: cumulativeDj,
    cumulativeCas: cumulativeCas,
    cumulativeSal: cumulativeSal,
  );
}

class TreatmentEntry {
  final String referenceId;
  final String type;
  final String name;
  final String? dose;
  final DateTime? date;

  TreatmentEntry({
    required this.referenceId,
    required this.type,
    required this.name,
    this.dose,
    this.date,
  });

  Map<String, dynamic> toMap() => {
    'referenceId': referenceId,
    'type': type,
    'name': name,
    'dose': dose,
    'date': date?.toIso8601String(),
  };

  factory TreatmentEntry.fromMap(Map<String, dynamic> map) {
    return TreatmentEntry(
      referenceId: map['referenceId'] as String? ?? '',
      type: map['type'] as String? ?? '',
      name: map['name'] as String? ?? '',
      dose: map['dose'] as String?,
      date: parseCameroonTime(map['date']?.toString()),
    );
  }
}

class StaffStatusEntry {
  final String staffId;
  final String name;
  final String status; // present | repos | absent | malade | permission

  StaffStatusEntry({
    required this.staffId,
    required this.name,
    this.status = 'present',
  });

  Map<String, dynamic> toMap() => {
    'staffId': staffId,
    'name': name,
    'status': status,
  };

  factory StaffStatusEntry.fromMap(Map<String, dynamic> map) {
    return StaffStatusEntry(
      staffId: map['staffId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      status: map['status'] as String? ?? 'present',
    );
  }

  StaffStatusEntry copyWith({String? status}) => StaffStatusEntry(
    staffId: staffId,
    name: name,
    status: status ?? this.status,
  );
}

const kEditableReportStatuses = {'brouillon', 'a_corriger'};

class FarmDailyReport {
  final String id;
  final String farmId;
  final String farmName;
  final String date; // "YYYY-MM-DD"
  final String? lotNumber;
  final int? ageDays;
  final int? ageWeeks;
  final List<RoomHeadcount> startCounts;
  final SexCount clinicStart;
  final DailyReportAliment aliment;
  final DailyReportMortality mortality;
  final List<RoomTransferEntry> transfers;
  final List<RoomHeadcount> endCounts;
  final SexCount clinicEnd;
  final List<RoomProduction> production;
  final double? waterLiters;
  final List<TreatmentEntry> treatments;
  final List<StaffStatusEntry> staffStatuses;
  final String? observation;
  final String status;
  final DateTime? submittedAt;
  final String? submittedBy;
  final DateTime? validatedAt;
  final String? validatedBy;
  final String? rejectionReason;
  final List<RejectionFlag> rejectionFlags;
  final DateTime? rejectedAt;
  final String? rejectedBy;

  FarmDailyReport({
    required this.id,
    required this.farmId,
    required this.farmName,
    required this.date,
    this.lotNumber,
    this.ageDays,
    this.ageWeeks,
    this.startCounts = const [],
    SexCount? clinicStart,
    DailyReportAliment? aliment,
    DailyReportMortality? mortality,
    this.transfers = const [],
    this.endCounts = const [],
    SexCount? clinicEnd,
    this.production = const [],
    this.waterLiters,
    this.treatments = const [],
    this.staffStatuses = const [],
    this.observation,
    this.status = 'brouillon',
    this.submittedAt,
    this.submittedBy,
    this.validatedAt,
    this.validatedBy,
    this.rejectionReason,
    this.rejectionFlags = const [],
    this.rejectedAt,
    this.rejectedBy,
  }) : clinicStart = clinicStart ?? SexCount(),
       clinicEnd = clinicEnd ?? SexCount(),
       aliment = aliment ?? DailyReportAliment(),
       mortality = mortality ?? DailyReportMortality();

  bool get isEditable => kEditableReportStatuses.contains(status);

  String get statusLabel => switch (status) {
    'brouillon' => 'À compléter',
    'en_attente_validation' => 'En attente de validation',
    'a_corriger' => 'À corriger',
    'valide' => 'Validé',
    _ => status,
  };

  factory FarmDailyReport.fromMap(Map<String, dynamic> map) {
    return FarmDailyReport(
      id: map['_id'] as String,
      farmId: map['farmId'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      date: map['date'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      ageDays: (map['ageDays'] as num?)?.toInt(),
      ageWeeks: (map['ageWeeks'] as num?)?.toInt(),
      startCounts: (map['startCounts'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      clinicStart: SexCount.fromMap(map['clinicStart'] as Map<String, dynamic>?),
      aliment: DailyReportAliment.fromMap(map['aliment'] as Map<String, dynamic>?),
      mortality: DailyReportMortality.fromMap(map['mortality'] as Map<String, dynamic>?),
      transfers: (map['transfers'] as List<dynamic>? ?? [])
          .map((t) => RoomTransferEntry.fromMap(t as Map<String, dynamic>))
          .toList(),
      endCounts: (map['endCounts'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      clinicEnd: SexCount.fromMap(map['clinicEnd'] as Map<String, dynamic>?),
      production: (map['production'] as List<dynamic>? ?? [])
          .map((p) => RoomProduction.fromMap(p as Map<String, dynamic>))
          .toList(),
      waterLiters: (map['waterLiters'] as num?)?.toDouble(),
      treatments: (map['treatments'] as List<dynamic>? ?? [])
          .map((t) => TreatmentEntry.fromMap(t as Map<String, dynamic>))
          .toList(),
      staffStatuses: (map['staffStatuses'] as List<dynamic>? ?? [])
          .map((s) => StaffStatusEntry.fromMap(s as Map<String, dynamic>))
          .toList(),
      observation: map['observation'] as String?,
      status: map['status'] as String? ?? 'brouillon',
      submittedAt: parseCameroonTime(map['submittedAt']?.toString()),
      submittedBy: map['submittedBy'] as String?,
      validatedAt: parseCameroonTime(map['validatedAt']?.toString()),
      validatedBy: map['validatedBy'] as String?,
      rejectionReason: map['rejectionReason'] as String?,
      rejectionFlags: (map['rejectionFlags'] as List<dynamic>? ?? [])
          .map((f) => RejectionFlag.fromMap(f as Map<String, dynamic>))
          .toList(),
      rejectedAt: parseCameroonTime(map['rejectedAt']?.toString()),
      rejectedBy: map['rejectedBy'] as String?,
    );
  }
}

/// Un endroit précis du rapport que le validateur pointe comme à corriger (ex : salle 1 /
/// PO) — en plus du motif texte libre, pour que le rédacteur sache exactement quoi revoir
/// sans avoir à deviner à partir d'une phrase générique. roomName=null = pas lié à une salle
/// (eau, traitements, personnel, observation, transferts).
class RejectionFlag {
  final String? roomName;
  final String field;
  final String label;

  RejectionFlag({this.roomName, required this.field, required this.label});

  Map<String, dynamic> toMap() => {
    'roomName': roomName,
    'field': field,
    'label': label,
  };

  factory RejectionFlag.fromMap(Map<String, dynamic> map) {
    return RejectionFlag(
      roomName: map['roomName'] as String?,
      field: map['field'] as String? ?? '',
      label: map['label'] as String? ?? '',
    );
  }
}

class FarmReportOverviewItem {
  final String farmId;
  final String farmName;
  final String? lotNumber;
  final String? reportId;
  final String status;

  FarmReportOverviewItem({
    required this.farmId,
    required this.farmName,
    this.lotNumber,
    this.reportId,
    this.status = 'non_fait',
  });

  String get statusLabel => switch (status) {
    'non_fait' => 'Non fait',
    'brouillon' => 'En cours',
    'en_attente_validation' => 'En attente',
    'a_corriger' => 'Renvoyé',
    'valide' => 'Validé',
    _ => status,
  };

  factory FarmReportOverviewItem.fromMap(Map<String, dynamic> map) {
    return FarmReportOverviewItem(
      farmId: map['farmId'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      reportId: map['reportId'] as String?,
      status: map['status'] as String? ?? 'non_fait',
    );
  }
}

class FarmReportOverview {
  final String date;
  final List<FarmReportOverviewItem> farms;

  FarmReportOverview({required this.date, required this.farms});

  factory FarmReportOverview.fromMap(Map<String, dynamic> map) {
    return FarmReportOverview(
      date: map['date'] as String? ?? '',
      farms: (map['farms'] as List<dynamic>? ?? [])
          .map((f) => FarmReportOverviewItem.fromMap(f as Map<String, dynamic>))
          .toList(),
    );
  }
}
