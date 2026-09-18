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
  final bool hasReports;

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
    this.hasReports = false,
  });

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
      hasReports: map['hasReports'] as bool? ?? false,
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
