import 'cumul.dart' show RoomFeedCumul, RoomEggCumul;
import 'farm_daily_report.dart';
import 'lot_headcount.dart';

/// Suivi bâtiment : effectif et stock d'aliment restants (départ - cumul depuis le dernier
/// rapport journalier connu), ferme par ferme — vue calculée côté backend, jamais stockée
/// (voir GET /daily-reports/building-tracking).
class BuildingTrackingItem {
  final String farmId;
  final String farmName;
  final String? lotNumber;
  final int? ageDays;
  final int? ageWeeks;
  final int initialFemale;
  final int initialMale;
  final int currentFemale;
  final int currentMale;
  final int cumulativeMortalityFemale;
  final int cumulativeMortalityMale;
  final double? mortalityRateFemalePercent;
  final double? mortalityRateMalePercent;
  final double initialFeedStockKg;
  final double currentFeedStockKg;
  final double cumulativeConsumedKg;
  final double? securityStockDays;
  final String? lastReportDate;
  final List<RoomHeadcount> currentRooms;
  final SexCount currentClinic;
  // Mêmes cumuls (Aliment consommé / Production d'œufs) que ci-dessus, mais détaillés salle par
  // salle plutôt que seulement totalisés ferme — pour la vue d'ensemble de Suivi Bâtiment.
  final List<RoomFeedCumul> currentFeedRooms;
  final List<RoomEggCumul> currentEggRooms;
  final bool hasReports;
  final int cumulativeOac;
  final int cumulativePo;
  final int cumulativeDj;
  final int cumulativeCas;
  final int cumulativeSal;
  // Stock RÉELLEMENT disponible par catégorie (cumulative* - déjà expédié) : les 5 catégories
  // sont expédiables, cumulative* seul surestimerait ce qu'il reste dès qu'une expédition a été
  // validée.
  final int currentStockOac;
  final int currentStockPo;
  final int currentStockDj;
  final int currentStockCas;
  final int currentStockSal;
  final double? layingRatePercent;
  final double? feedConversionRatio;

  BuildingTrackingItem({
    required this.farmId,
    required this.farmName,
    this.lotNumber,
    this.ageDays,
    this.ageWeeks,
    this.initialFemale = 0,
    this.initialMale = 0,
    this.currentFemale = 0,
    this.currentMale = 0,
    this.cumulativeMortalityFemale = 0,
    this.cumulativeMortalityMale = 0,
    this.mortalityRateFemalePercent,
    this.mortalityRateMalePercent,
    this.initialFeedStockKg = 0,
    this.currentFeedStockKg = 0,
    this.cumulativeConsumedKg = 0,
    this.securityStockDays,
    this.lastReportDate,
    this.currentRooms = const [],
    SexCount? currentClinic,
    this.currentFeedRooms = const [],
    this.currentEggRooms = const [],
    this.hasReports = false,
    this.cumulativeOac = 0,
    this.cumulativePo = 0,
    this.cumulativeDj = 0,
    this.cumulativeCas = 0,
    this.cumulativeSal = 0,
    this.currentStockOac = 0,
    this.currentStockPo = 0,
    this.currentStockDj = 0,
    this.currentStockCas = 0,
    this.currentStockSal = 0,
    this.layingRatePercent,
    this.feedConversionRatio,
  }) : currentClinic = currentClinic ?? SexCount();

  int get initialTotal => initialFemale + initialMale;
  int get currentTotal => currentFemale + currentMale;
  int get cumulativeMortalityTotal => cumulativeMortalityFemale + cumulativeMortalityMale;

  /// Taux de mortalité cumulé (F+M) — recalculé côté client à partir des totaux plutôt que
  /// de moyenner les deux taux séparés du backend (F/M peuvent partir d'effectifs très
  /// différents, une simple moyenne des pourcentages fausserait le résultat).
  double get mortalityRatePercent => initialTotal > 0 ? cumulativeMortalityTotal / initialTotal * 100 : 0;

  /// Part du stock de départ déjà consommée (0-100) — 0 si aucun stock de départ saisi.
  double get feedConsumedPercent =>
      initialFeedStockKg > 0 ? (cumulativeConsumedKg / initialFeedStockKg * 100).clamp(0, 100) : 0;

  factory BuildingTrackingItem.fromMap(Map<String, dynamic> map) {
    return BuildingTrackingItem(
      farmId: map['farmId'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      ageDays: (map['ageDays'] as num?)?.toInt(),
      ageWeeks: (map['ageWeeks'] as num?)?.toInt(),
      initialFemale: (map['initialFemale'] as num?)?.toInt() ?? 0,
      initialMale: (map['initialMale'] as num?)?.toInt() ?? 0,
      currentFemale: (map['currentFemale'] as num?)?.toInt() ?? 0,
      currentMale: (map['currentMale'] as num?)?.toInt() ?? 0,
      cumulativeMortalityFemale: (map['cumulativeMortalityFemale'] as num?)?.toInt() ?? 0,
      cumulativeMortalityMale: (map['cumulativeMortalityMale'] as num?)?.toInt() ?? 0,
      mortalityRateFemalePercent: (map['mortalityRateFemalePercent'] as num?)?.toDouble(),
      mortalityRateMalePercent: (map['mortalityRateMalePercent'] as num?)?.toDouble(),
      initialFeedStockKg: (map['initialFeedStockKg'] as num?)?.toDouble() ?? 0,
      currentFeedStockKg: (map['currentFeedStockKg'] as num?)?.toDouble() ?? 0,
      cumulativeConsumedKg: (map['cumulativeConsumedKg'] as num?)?.toDouble() ?? 0,
      securityStockDays: (map['securityStockDays'] as num?)?.toDouble(),
      lastReportDate: map['lastReportDate'] as String?,
      currentRooms: (map['currentRooms'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      currentClinic: SexCount.fromMap(map['currentClinic'] as Map<String, dynamic>?),
      currentFeedRooms: (map['currentFeedRooms'] as List<dynamic>? ?? [])
          .map((r) => RoomFeedCumul.fromMap(r as Map<String, dynamic>))
          .toList(),
      currentEggRooms: (map['currentEggRooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggCumul.fromMap(r as Map<String, dynamic>))
          .toList(),
      hasReports: map['hasReports'] as bool? ?? false,
      cumulativeOac: (map['cumulativeOac'] as num?)?.toInt() ?? 0,
      cumulativePo: (map['cumulativePo'] as num?)?.toInt() ?? 0,
      cumulativeDj: (map['cumulativeDj'] as num?)?.toInt() ?? 0,
      cumulativeCas: (map['cumulativeCas'] as num?)?.toInt() ?? 0,
      cumulativeSal: (map['cumulativeSal'] as num?)?.toInt() ?? 0,
      currentStockOac: (map['currentStockOac'] as num?)?.toInt() ?? 0,
      currentStockPo: (map['currentStockPo'] as num?)?.toInt() ?? 0,
      currentStockDj: (map['currentStockDj'] as num?)?.toInt() ?? 0,
      currentStockCas: (map['currentStockCas'] as num?)?.toInt() ?? 0,
      currentStockSal: (map['currentStockSal'] as num?)?.toInt() ?? 0,
      layingRatePercent: (map['layingRatePercent'] as num?)?.toDouble(),
      feedConversionRatio: (map['feedConversionRatio'] as num?)?.toDouble(),
    );
  }
}

/// Consommation et mortalité d'une salle précise, pour une semaine d'âge donnée — permet de
/// filtrer les graphiques sur une salle (ex. repérer où la mortalité se concentre) sans
/// reformuler de requête.
class RoomWeeklyValue {
  final String roomName;
  final double totalConsumedKg;
  final int mortalityFemale;
  final int mortalityMale;

  RoomWeeklyValue({
    required this.roomName,
    this.totalConsumedKg = 0,
    this.mortalityFemale = 0,
    this.mortalityMale = 0,
  });

  factory RoomWeeklyValue.fromMap(Map<String, dynamic> map) {
    return RoomWeeklyValue(
      roomName: map['roomName'] as String? ?? '',
      totalConsumedKg: (map['totalConsumedKg'] as num?)?.toDouble() ?? 0,
      mortalityFemale: (map['mortalityFemale'] as num?)?.toInt() ?? 0,
      mortalityMale: (map['mortalityMale'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Un point de graphique : consommation d'aliment et mortalité cumulées pour une semaine
/// d'âge donnée (agrégées côté serveur — voir GET .../building-tracking/{farmId}/weekly-chart).
class WeeklyTrackingPoint {
  final int ageWeeks;
  final double totalConsumedKg;
  final int mortalityFemale;
  final int mortalityMale;
  final List<RoomWeeklyValue> byRoom;

  WeeklyTrackingPoint({
    required this.ageWeeks,
    this.totalConsumedKg = 0,
    this.mortalityFemale = 0,
    this.mortalityMale = 0,
    this.byRoom = const [],
  });

  int get mortalityTotal => mortalityFemale + mortalityMale;

  RoomWeeklyValue? roomValue(String roomName) {
    for (final r in byRoom) {
      if (r.roomName == roomName) return r;
    }
    return null;
  }

  factory WeeklyTrackingPoint.fromMap(Map<String, dynamic> map) {
    return WeeklyTrackingPoint(
      ageWeeks: (map['ageWeeks'] as num?)?.toInt() ?? 0,
      totalConsumedKg: (map['totalConsumedKg'] as num?)?.toDouble() ?? 0,
      mortalityFemale: (map['mortalityFemale'] as num?)?.toInt() ?? 0,
      mortalityMale: (map['mortalityMale'] as num?)?.toInt() ?? 0,
      byRoom: (map['byRoom'] as List<dynamic>? ?? [])
          .map((r) => RoomWeeklyValue.fromMap(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Une ligne de l'historique des transferts de sujets entre salles — jamais stockée à part,
/// une simple extraction paginée des rapports journaliers existants (voir GET
/// .../building-tracking/{farmId}/transfers-history).
class TransferHistoryEntry {
  final String date;
  final String farmId;
  final String farmName;
  final String? lotNumber;
  final String fromRoom;
  final String toRoom;
  final int femaleCount;
  final int maleCount;
  final String? performedBy;

  TransferHistoryEntry({
    required this.date,
    required this.farmId,
    required this.farmName,
    this.lotNumber,
    required this.fromRoom,
    required this.toRoom,
    this.femaleCount = 0,
    this.maleCount = 0,
    this.performedBy,
  });

  factory TransferHistoryEntry.fromMap(Map<String, dynamic> map) {
    return TransferHistoryEntry(
      date: map['date'] as String? ?? '',
      farmId: map['farmId'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      fromRoom: map['fromRoom'] as String? ?? '',
      toRoom: map['toRoom'] as String? ?? '',
      femaleCount: (map['femaleCount'] as num?)?.toInt() ?? 0,
      maleCount: (map['maleCount'] as num?)?.toInt() ?? 0,
      performedBy: map['performedBy'] as String?,
    );
  }
}

class TransferHistoryPagedResult {
  final int totalCount;
  final List<TransferHistoryEntry> data;

  TransferHistoryPagedResult({this.totalCount = 0, required this.data});

  factory TransferHistoryPagedResult.fromMap(Map<String, dynamic> map) {
    return TransferHistoryPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((t) => TransferHistoryEntry.fromMap(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Récapitulatif d'un lot (en cours ou passé) d'un bâtiment, tel qu'au dernier rapport validé
/// de ce lot — GET /daily-reports/building-tracking/{farmId}/lots.
class BuildingLotSummary {
  final String lotNumber;
  final bool isCurrent;
  final int initialFemale;
  final int initialMale;
  final int currentFemale;
  final int currentMale;
  final int reportCount;
  final String? firstReportDate;
  final String? lastReportDate;
  final int? ageDays;
  final int? ageWeeks;
  final int cumulativeMortalityFemale;
  final int cumulativeMortalityMale;
  final double cumulativeConsumedKg;
  final int cumulativeOac;
  final int cumulativePo;
  final int cumulativeDj;
  final int cumulativeCas;
  final int cumulativeSal;
  final double? feedConversionRatio;

  BuildingLotSummary({
    required this.lotNumber,
    this.isCurrent = false,
    this.initialFemale = 0,
    this.initialMale = 0,
    this.currentFemale = 0,
    this.currentMale = 0,
    this.reportCount = 0,
    this.firstReportDate,
    this.lastReportDate,
    this.ageDays,
    this.ageWeeks,
    this.cumulativeMortalityFemale = 0,
    this.cumulativeMortalityMale = 0,
    this.cumulativeConsumedKg = 0,
    this.cumulativeOac = 0,
    this.cumulativePo = 0,
    this.cumulativeDj = 0,
    this.cumulativeCas = 0,
    this.cumulativeSal = 0,
    this.feedConversionRatio,
  });

  int get initialTotal => initialFemale + initialMale;
  int get currentTotal => currentFemale + currentMale;
  int get cumulativeMortalityTotal => cumulativeMortalityFemale + cumulativeMortalityMale;
  double get mortalityRatePercent => initialTotal > 0 ? cumulativeMortalityTotal / initialTotal * 100 : 0;

  /// Forme attendue par les écrans de détail existants (courbes hebdomadaires du lot).
  BuildingTrackingItem toTrackingItem({required String farmId, required String farmName}) {
    return BuildingTrackingItem(
      farmId: farmId,
      farmName: farmName,
      lotNumber: lotNumber,
      ageDays: ageDays,
      ageWeeks: ageWeeks,
      initialFemale: initialFemale,
      initialMale: initialMale,
      currentFemale: currentFemale,
      currentMale: currentMale,
      cumulativeMortalityFemale: cumulativeMortalityFemale,
      cumulativeMortalityMale: cumulativeMortalityMale,
      cumulativeConsumedKg: cumulativeConsumedKg,
      lastReportDate: lastReportDate,
      hasReports: reportCount > 0,
    );
  }

  factory BuildingLotSummary.fromMap(Map<String, dynamic> map) {
    int i(String k) => (map[k] as num?)?.toInt() ?? 0;
    return BuildingLotSummary(
      lotNumber: map['lotNumber'] as String? ?? '',
      isCurrent: map['isCurrent'] as bool? ?? false,
      initialFemale: i('initialFemale'),
      initialMale: i('initialMale'),
      currentFemale: i('currentFemale'),
      currentMale: i('currentMale'),
      reportCount: i('reportCount'),
      firstReportDate: map['firstReportDate'] as String?,
      lastReportDate: map['lastReportDate'] as String?,
      ageDays: (map['ageDays'] as num?)?.toInt(),
      ageWeeks: (map['ageWeeks'] as num?)?.toInt(),
      cumulativeMortalityFemale: i('cumulativeMortalityFemale'),
      cumulativeMortalityMale: i('cumulativeMortalityMale'),
      cumulativeConsumedKg: (map['cumulativeConsumedKg'] as num?)?.toDouble() ?? 0,
      cumulativeOac: i('cumulativeOac'),
      cumulativePo: i('cumulativePo'),
      cumulativeDj: i('cumulativeDj'),
      cumulativeCas: i('cumulativeCas'),
      cumulativeSal: i('cumulativeSal'),
      feedConversionRatio: (map['feedConversionRatio'] as num?)?.toDouble(),
    );
  }
}
