import '../utils/cameroon_time.dart';

/// Cumul de départ (aliments ou œufs) : notion DISTINCTE du stock de départ / stock actuel —
/// un compteur manuel géré uniquement par l'admin qui ne bouge jamais avec la consommation ou
/// la ponte du rapport journalier. Une ferme peut avoir un stock d'OAC de 10 en salle 1 et un
/// cumul de 100 sur cette même salle : deux notions indépendantes. Chaque saisie ADDITIONNE au
/// cumul déjà existant (jamais un remplacement).

class FarmFeedCumul {
  final String? id;
  final String farmName;
  final double totalKg;
  final DateTime? updatedAt;

  FarmFeedCumul({this.id, required this.farmName, this.totalKg = 0, this.updatedAt});

  factory FarmFeedCumul.fromMap(Map<String, dynamic> map) {
    return FarmFeedCumul(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      totalKg: (map['totalKg'] as num?)?.toDouble() ?? 0,
      updatedAt: parseCameroonTime(map['updatedAt']?.toString()),
    );
  }
}

class FarmFeedCumulHistoryEntry {
  final String? id;
  final String farmName;
  final double quantityKg;
  final double totalAfterKg;
  final String? performedBy;
  final DateTime createdAt;

  FarmFeedCumulHistoryEntry({
    this.id,
    required this.farmName,
    this.quantityKg = 0,
    this.totalAfterKg = 0,
    this.performedBy,
    required this.createdAt,
  });

  factory FarmFeedCumulHistoryEntry.fromMap(Map<String, dynamic> map) {
    return FarmFeedCumulHistoryEntry(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      quantityKg: (map['quantityKg'] as num?)?.toDouble() ?? 0,
      totalAfterKg: (map['totalAfterKg'] as num?)?.toDouble() ?? 0,
      performedBy: map['performedBy'] as String?,
      createdAt: parseCameroonTime(map['createdAt']?.toString()) ?? DateTime.now(),
    );
  }
}

class FarmFeedCumulHistoryPagedResult {
  final int totalCount;
  final List<FarmFeedCumulHistoryEntry> data;

  FarmFeedCumulHistoryPagedResult({this.totalCount = 0, required this.data});

  factory FarmFeedCumulHistoryPagedResult.fromMap(Map<String, dynamic> map) {
    return FarmFeedCumulHistoryPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((h) => FarmFeedCumulHistoryEntry.fromMap(h as Map<String, dynamic>))
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

/// Vue combinée pour l'onglet "Cumul" de Suivi Bâtiment : ferme par ferme, salle par salle.
class BuildingCumulItem {
  final String farmId;
  final String farmName;
  final String? lotNumber;
  final double feedCumulKg;
  final List<RoomEggCumul> rooms;

  BuildingCumulItem({
    required this.farmId,
    required this.farmName,
    this.lotNumber,
    this.feedCumulKg = 0,
    this.rooms = const [],
  });

  factory BuildingCumulItem.fromMap(Map<String, dynamic> map) {
    return BuildingCumulItem(
      farmId: map['farmId'] as String? ?? '',
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      feedCumulKg: (map['feedCumulKg'] as num?)?.toDouble() ?? 0,
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggCumul.fromMap(r as Map<String, dynamic>))
          .toList(),
    );
  }
}
