class RoomHeadcount {
  final String roomName;
  final int femaleCount;
  final int maleCount;

  RoomHeadcount({
    required this.roomName,
    this.femaleCount = 0,
    this.maleCount = 0,
  });

  Map<String, dynamic> toMap() => {
    'roomName': roomName,
    'femaleCount': femaleCount,
    'maleCount': maleCount,
  };

  factory RoomHeadcount.fromMap(Map<String, dynamic> map) {
    return RoomHeadcount(
      roomName: map['roomName'] as String? ?? '',
      femaleCount: (map['femaleCount'] as num?)?.toInt() ?? 0,
      maleCount: (map['maleCount'] as num?)?.toInt() ?? 0,
    );
  }

  RoomHeadcount copyWith({int? femaleCount, int? maleCount}) => RoomHeadcount(
    roomName: roomName,
    femaleCount: femaleCount ?? this.femaleCount,
    maleCount: maleCount ?? this.maleCount,
  );
}

/// Effectifs de départ d'un lot (saisis une seule fois par l'admin à la mise en place du
/// lot) : chaque jour suivant, le rapport journalier reprend automatiquement l'effectif
/// restant de la veille (voir routers/daily_reports.py côté backend).
class LotHeadcount {
  final String? id;
  final String farmName;
  final String lotNumber;
  final List<RoomHeadcount> rooms;
  final int clinicFemaleCount;
  final int clinicMaleCount;
  final int totalFemale;
  final int totalMale;

  LotHeadcount({
    this.id,
    required this.farmName,
    required this.lotNumber,
    this.rooms = const [],
    this.clinicFemaleCount = 0,
    this.clinicMaleCount = 0,
    this.totalFemale = 0,
    this.totalMale = 0,
  });

  Map<String, dynamic> toCreateMap({String? performedBy}) => {
    'farmName': farmName,
    'lotNumber': lotNumber,
    'rooms': rooms.map((r) => r.toMap()).toList(),
    'clinicFemaleCount': clinicFemaleCount,
    'clinicMaleCount': clinicMaleCount,
    'performedBy': performedBy,
  };

  factory LotHeadcount.fromMap(Map<String, dynamic> map) {
    return LotHeadcount(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomHeadcount.fromMap(r as Map<String, dynamic>))
          .toList(),
      clinicFemaleCount: (map['clinicFemaleCount'] as num?)?.toInt() ?? 0,
      clinicMaleCount: (map['clinicMaleCount'] as num?)?.toInt() ?? 0,
      totalFemale: (map['totalFemale'] as num?)?.toInt() ?? 0,
      totalMale: (map['totalMale'] as num?)?.toInt() ?? 0,
    );
  }
}
