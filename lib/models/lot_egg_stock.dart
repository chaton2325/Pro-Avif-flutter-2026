import '../utils/cameroon_time.dart';

class RoomEggStock {
  final String roomName;
  final int oac;
  final int po;
  final int dj;
  final int cas;
  final int sal;

  RoomEggStock({
    required this.roomName,
    this.oac = 0,
    this.po = 0,
    this.dj = 0,
    this.cas = 0,
    this.sal = 0,
  });

  Map<String, dynamic> toMap() => {
    'roomName': roomName,
    'oac': oac,
    'po': po,
    'dj': dj,
    'cas': cas,
    'sal': sal,
  };

  factory RoomEggStock.fromMap(Map<String, dynamic> map) {
    return RoomEggStock(
      roomName: map['roomName'] as String? ?? '',
      oac: (map['oac'] as num?)?.toInt() ?? 0,
      po: (map['po'] as num?)?.toInt() ?? 0,
      dj: (map['dj'] as num?)?.toInt() ?? 0,
      cas: (map['cas'] as num?)?.toInt() ?? 0,
      sal: (map['sal'] as num?)?.toInt() ?? 0,
    );
  }

  RoomEggStock copyWith({int? oac, int? po, int? dj, int? cas, int? sal}) => RoomEggStock(
    roomName: roomName,
    oac: oac ?? this.oac,
    po: po ?? this.po,
    dj: dj ?? this.dj,
    cas: cas ?? this.cas,
    sal: sal ?? this.sal,
  );
}

/// Photo d'un stock d'œufs de départ juste avant qu'il ne soit écrasé par une resaisie —
/// conservée par le backend dans la collection à part lot_egg_stock_history (jamais embarquée
/// dans LotEggStock : cet historique est voué à grossir sans limite et doit rester paginable,
/// voir GET /lot-egg-stocks/history).
class LotEggStockHistoryEntry {
  final String? id;
  final String farmName;
  final String lotNumber;
  final List<RoomEggStock> rooms;
  final DateTime? recordedAt;
  final String? recordedBy;
  final DateTime replacedAt;
  final String? replacedBy;

  LotEggStockHistoryEntry({
    this.id,
    required this.farmName,
    required this.lotNumber,
    this.rooms = const [],
    this.recordedAt,
    this.recordedBy,
    required this.replacedAt,
    this.replacedBy,
  });

  factory LotEggStockHistoryEntry.fromMap(Map<String, dynamic> map) {
    return LotEggStockHistoryEntry(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggStock.fromMap(r as Map<String, dynamic>))
          .toList(),
      recordedAt: parseCameroonTime(map['recordedAt']?.toString()),
      recordedBy: map['recordedBy'] as String?,
      replacedAt: parseCameroonTime(map['replacedAt']?.toString()) ?? DateTime.now(),
      replacedBy: map['replacedBy'] as String?,
    );
  }
}

class LotEggStockHistoryPagedResult {
  final int totalCount;
  final List<LotEggStockHistoryEntry> data;

  LotEggStockHistoryPagedResult({this.totalCount = 0, required this.data});

  factory LotEggStockHistoryPagedResult.fromMap(Map<String, dynamic> map) {
    return LotEggStockHistoryPagedResult(
      totalCount: (map['totalCount'] as num?)?.toInt() ?? 0,
      data: (map['data'] as List<dynamic>? ?? [])
          .map((h) => LotEggStockHistoryEntry.fromMap(h as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Stock d'œufs de départ d'un lot, par salle (saisi une seule fois par l'admin à la mise en
/// place du lot) : les cumuls du rapport journalier (cumulativePo, etc.) repartent de cette
/// valeur d'origine au lieu de zéro (voir routers/daily_reports.py côté backend).
class LotEggStock {
  final String? id;
  final String farmName;
  final String lotNumber;
  final List<RoomEggStock> rooms;
  final String? performedBy;
  final DateTime? updatedAt;

  LotEggStock({
    this.id,
    required this.farmName,
    required this.lotNumber,
    this.rooms = const [],
    this.performedBy,
    this.updatedAt,
  });

  Map<String, dynamic> toCreateMap({String? performedBy}) => {
    'farmName': farmName,
    'lotNumber': lotNumber,
    'rooms': rooms.map((r) => r.toMap()).toList(),
    'performedBy': performedBy,
  };

  factory LotEggStock.fromMap(Map<String, dynamic> map) {
    return LotEggStock(
      id: map['_id'] as String?,
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String? ?? '',
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggStock.fromMap(r as Map<String, dynamic>))
          .toList(),
      performedBy: map['performedBy'] as String?,
      updatedAt: parseCameroonTime(map['updatedAt']?.toString()),
    );
  }
}
