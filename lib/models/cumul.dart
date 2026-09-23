import '../utils/cameroon_time.dart';
import 'lot_headcount.dart' show RoomHeadcount;

/// Cumul ŒUFS : compteur manuel géré UNIQUEMENT par l'admin, totalement indépendant du stock
/// actuel — une ferme peut avoir un stock d'OAC de 10 en salle 1 et un cumul de 100 sur cette
/// même salle, deux notions qui ne se recalculent jamais l'une depuis l'autre. Chaque saisie
/// ADDITIONNE au cumul déjà existant (jamais un remplacement).
///
/// Cumul ALIMENT : DIFFÉRENT — c'est la consommation cumulée par salle, par ALIMENT
/// (référentiel "formulas" du module Usine Aliment — RL0, RL1, etc., jamais modifié ici,
/// uniquement lu) et par sexe (F/M), qui s'incrémente automatiquement à chaque rapport
/// journalier où une consommation est saisie pour cette salle et cet aliment (voir
/// RoomFeedCumul). lot_feed_cumuls (LotFeedCumul ci-dessous) ne sert que de VALEUR DE DÉPART,
/// lot-scopée comme le stock d'œufs de départ — jamais le cumul actuel lui-même, déjà
/// incrémenté par les rapports validés.

class RoomFeedCumul {
  final String roomName;
  final String? formulaId;
  final String? formulaName;
  final double femaleKg;
  final double maleKg;

  RoomFeedCumul({
    required this.roomName,
    this.formulaId,
    this.formulaName,
    this.femaleKg = 0,
    this.maleKg = 0,
  });

  factory RoomFeedCumul.fromMap(Map<String, dynamic> map) {
    return RoomFeedCumul(
      roomName: map['roomName'] as String? ?? '',
      formulaId: map['formulaId'] as String?,
      formulaName: map['formulaName'] as String?,
      femaleKg: (map['femaleKg'] as num?)?.toDouble() ?? 0,
      maleKg: (map['maleKg'] as num?)?.toDouble() ?? 0,
    );
  }
}

class LotFeedCumul {
  final String? id;
  final String farmName;
  final String lotNumber;
  final List<RoomFeedCumul> rooms;
  final DateTime? updatedAt;

  LotFeedCumul({this.id, required this.farmName, required this.lotNumber, this.rooms = const [], this.updatedAt});

  factory LotFeedCumul.fromMap(Map<String, dynamic> map) {
    return LotFeedCumul(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomFeedCumul.fromMap(r as Map<String, dynamic>))
          .toList(),
      updatedAt: parseCameroonTime(map['updatedAt']?.toString()),
    );
  }
}

class LotFeedCumulHistoryEntry {
  final String? id;
  final String farmName;
  final String lotNumber;
  final String roomName;
  final String formulaName;
  final double femaleKg;
  final double maleKg;
  final String? performedBy;
  final DateTime createdAt;

  LotFeedCumulHistoryEntry({
    this.id,
    required this.farmName,
    required this.lotNumber,
    required this.roomName,
    required this.formulaName,
    this.femaleKg = 0,
    this.maleKg = 0,
    this.performedBy,
    required this.createdAt,
  });

  factory LotFeedCumulHistoryEntry.fromMap(Map<String, dynamic> map) {
    return LotFeedCumulHistoryEntry(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      roomName: map['roomName'] as String? ?? '',
      formulaName: map['formulaName'] as String? ?? '',
      femaleKg: (map['femaleKg'] as num?)?.toDouble() ?? 0,
      maleKg: (map['maleKg'] as num?)?.toDouble() ?? 0,
      performedBy: map['performedBy'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
    );
  }
}

class LotFeedCumulHistoryPagedResult {
  final int totalCount;
  final List<LotFeedCumulHistoryEntry> data;

  LotFeedCumulHistoryPagedResult({this.totalCount = 0, required this.data});

  factory LotFeedCumulHistoryPagedResult.fromMap(Map<String, dynamic> map) {
    return LotFeedCumulHistoryPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((h) => LotFeedCumulHistoryEntry.fromMap(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RoomEggCumul {
  final String roomName;
  final int oac;
  final int po;
  final int dj;
  final int cas;
  final int sal;

  RoomEggCumul({required this.roomName, this.oac = 0, this.po = 0, this.dj = 0, this.cas = 0, this.sal = 0});

  factory RoomEggCumul.fromMap(Map<String, dynamic> map) {
    return RoomEggCumul(
      roomName: map['roomName'] as String? ?? '',
      oac: (map['oac'] as num?)?.toInt() ?? 0,
      po: (map['po'] as num?)?.toInt() ?? 0,
      dj: (map['dj'] as num?)?.toInt() ?? 0,
      cas: (map['cas'] as num?)?.toInt() ?? 0,
      sal: (map['sal'] as num?)?.toInt() ?? 0,
    );
  }
}

class LotEggCumul {
  final String? id;
  final String farmName;
  final String lotNumber;
  final List<RoomEggCumul> rooms;
  final DateTime? updatedAt;

  LotEggCumul({this.id, required this.farmName, required this.lotNumber, this.rooms = const [], this.updatedAt});

  factory LotEggCumul.fromMap(Map<String, dynamic> map) {
    return LotEggCumul(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggCumul.fromMap(r as Map<String, dynamic>))
          .toList(),
      updatedAt: parseCameroonTime(map['updatedAt']?.toString()),
    );
  }
}

class LotEggCumulHistoryEntry {
  final String? id;
  final String farmName;
  final String lotNumber;
  final String roomName;
  final int oac;
  final int po;
  final int dj;
  final int cas;
  final int sal;
  final String? performedBy;
  final DateTime createdAt;

  LotEggCumulHistoryEntry({
    this.id,
    required this.farmName,
    required this.lotNumber,
    required this.roomName,
    this.oac = 0,
    this.po = 0,
    this.dj = 0,
    this.cas = 0,
    this.sal = 0,
    this.performedBy,
    required this.createdAt,
  });

  factory LotEggCumulHistoryEntry.fromMap(Map<String, dynamic> map) {
    return LotEggCumulHistoryEntry(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      roomName: map['roomName'] as String? ?? '',
      oac: (map['oac'] as num?)?.toInt() ?? 0,
      po: (map['po'] as num?)?.toInt() ?? 0,
      dj: (map['dj'] as num?)?.toInt() ?? 0,
      cas: (map['cas'] as num?)?.toInt() ?? 0,
      sal: (map['sal'] as num?)?.toInt() ?? 0,
      performedBy: map['performedBy'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
    );
  }
}

class LotEggCumulHistoryPagedResult {
  final int totalCount;
  final List<LotEggCumulHistoryEntry> data;

  LotEggCumulHistoryPagedResult({this.totalCount = 0, required this.data});

  factory LotEggCumulHistoryPagedResult.fromMap(Map<String, dynamic> map) {
    return LotEggCumulHistoryPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((h) => LotEggCumulHistoryEntry.fromMap(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Cumul MORTALITÉ : même principe que le cumul aliment — PAR SALLE et par sexe (F/M),
/// incrémenté automatiquement par chaque rapport journalier validé. Cette classe ne gère que
/// la VALEUR DE DÉPART (lot_mortality_cumuls), lot-scopée comme le stock d'œufs de départ.
class LotMortalityCumul {
  final String? id;
  final String farmName;
  final String lotNumber;
  final List<RoomHeadcount> rooms;
  final DateTime? updatedAt;

  LotMortalityCumul({
    this.id,
    required this.farmName,
    required this.lotNumber,
    this.rooms = const [],
    this.updatedAt,
  });

  factory LotMortalityCumul.fromMap(Map<String, dynamic> map) {
    return LotMortalityCumul(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      updatedAt: parseCameroonTime(map['updatedAt']?.toString()),
    );
  }
}

class LotMortalityCumulHistoryEntry {
  final String? id;
  final String farmName;
  final String lotNumber;
  final String roomName;
  final int femaleCount;
  final int maleCount;
  final String? performedBy;
  final DateTime createdAt;

  LotMortalityCumulHistoryEntry({
    this.id,
    required this.farmName,
    required this.lotNumber,
    required this.roomName,
    this.femaleCount = 0,
    this.maleCount = 0,
    this.performedBy,
    required this.createdAt,
  });

  factory LotMortalityCumulHistoryEntry.fromMap(Map<String, dynamic> map) {
    return LotMortalityCumulHistoryEntry(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      roomName: map['roomName'] as String? ?? '',
      femaleCount: (map['femaleCount'] as num?)?.toInt() ?? 0,
      maleCount: (map['maleCount'] as num?)?.toInt() ?? 0,
      performedBy: map['performedBy'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
    );
  }
}

class LotMortalityCumulHistoryPagedResult {
  final int totalCount;
  final List<LotMortalityCumulHistoryEntry> data;

  LotMortalityCumulHistoryPagedResult({this.totalCount = 0, required this.data});

  factory LotMortalityCumulHistoryPagedResult.fromMap(Map<String, dynamic> map) {
    return LotMortalityCumulHistoryPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((h) => LotMortalityCumulHistoryEntry.fromMap(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Vue combinée pour l'onglet "Cumul" de Suivi Bâtiment : ferme par ferme, salle par salle.
class BuildingCumulItem {
  final String farmId;
  final String farmName;
  final String? lotNumber;
  final List<RoomFeedCumul> feedRooms;
  final List<RoomEggCumul> rooms;
  final List<RoomHeadcount> mortalityRooms;
  final int cumulativeMortalityFemale;
  final int cumulativeMortalityMale;

  BuildingCumulItem({
    required this.farmId,
    required this.farmName,
    this.lotNumber,
    this.feedRooms = const [],
    this.rooms = const [],
    this.mortalityRooms = const [],
    this.cumulativeMortalityFemale = 0,
    this.cumulativeMortalityMale = 0,
  });

  factory BuildingCumulItem.fromMap(Map<String, dynamic> map) {
    return BuildingCumulItem(
      farmId: map['farmId'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      feedRooms: (map['feedRooms'] as List<dynamic>? ?? [])
          .map((r) => RoomFeedCumul.fromMap(r as Map<String, dynamic>))
          .toList(),
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggCumul.fromMap(r as Map<String, dynamic>))
          .toList(),
      mortalityRooms: (map['mortalityRooms'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      cumulativeMortalityFemale: (map['cumulativeMortalityFemale'] as num?)?.toInt() ?? 0,
      cumulativeMortalityMale: (map['cumulativeMortalityMale'] as num?)?.toInt() ?? 0,
    );
  }
}
