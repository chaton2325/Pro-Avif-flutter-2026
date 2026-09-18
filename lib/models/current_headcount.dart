import 'farm_daily_report.dart';
import 'lot_headcount.dart';

/// Effectif ACTUEL par salle pour le tableau de bord du rédacteur de sa propre ferme (bouton
/// "Effectifs en cours") — jamais l'effectif de départ. Si aucun rapport journalier n'a
/// encore été soumis pour le lot en cours, retombe sur l'effectif de départ (hasReports:
/// false) : rien n'a encore bougé, mais l'écran reste utile plutôt que vide.
class CurrentHeadcount {
  final String farmName;
  final String? lotNumber;
  final int? ageDays;
  final int? ageWeeks;
  final List<RoomHeadcount> rooms;
  final SexCount clinicCurrent;
  final int totalFemale;
  final int totalMale;
  final bool hasReports;

  CurrentHeadcount({
    required this.farmName,
    this.lotNumber,
    this.ageDays,
    this.ageWeeks,
    this.rooms = const [],
    SexCount? clinicCurrent,
    this.totalFemale = 0,
    this.totalMale = 0,
    this.hasReports = false,
  }) : clinicCurrent = clinicCurrent ?? SexCount();

  int get total => totalFemale + totalMale;

  factory CurrentHeadcount.fromMap(Map<String, dynamic> map) {
    return CurrentHeadcount(
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      ageDays: (map['ageDays'] as num?)?.toInt(),
      ageWeeks: (map['ageWeeks'] as num?)?.toInt(),
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      clinicCurrent: SexCount.fromMap(map['clinicCurrent'] as Map<String, dynamic>?),
      totalFemale: (map['totalFemale'] as num?)?.toInt() ?? 0,
      totalMale: (map['totalMale'] as num?)?.toInt() ?? 0,
      hasReports: map['hasReports'] as bool? ?? false,
    );
  }
}
