class RoomEggStockCurrent {
  final String roomName;
  final int cumulativeOac;
  final int cumulativePo;
  final int cumulativeDj;
  final int cumulativeCas;
  final int cumulativeSal;

  RoomEggStockCurrent({
    required this.roomName,
    this.cumulativeOac = 0,
    this.cumulativePo = 0,
    this.cumulativeDj = 0,
    this.cumulativeCas = 0,
    this.cumulativeSal = 0,
  });

  factory RoomEggStockCurrent.fromMap(Map<String, dynamic> map) {
    return RoomEggStockCurrent(
      roomName: map['roomName'] as String? ?? '',
      cumulativeOac: (map['cumulativeOac'] as num?)?.toInt() ?? 0,
      cumulativePo: (map['cumulativePo'] as num?)?.toInt() ?? 0,
      cumulativeDj: (map['cumulativeDj'] as num?)?.toInt() ?? 0,
      cumulativeCas: (map['cumulativeCas'] as num?)?.toInt() ?? 0,
      cumulativeSal: (map['cumulativeSal'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Stock d'œufs ACTUEL (cumuls OAC/PO/DJ/CAS/SAL) pour le tableau de bord du rédacteur de sa
/// propre ferme (bouton "Stock œufs") — jamais juste le stock de départ. Si aucun rapport
/// journalier n'a encore été soumis pour le lot en cours, retombe sur le stock de départ
/// (hasReports: false), même principe que CurrentHeadcount.
///
/// totalOac est le cumul de PRODUCTION pur (ne diminue jamais). currentStockOac est ce qui
/// reste réellement disponible pour une expédition vers un couvoir (totalOac -
/// totalShippedOac) — à utiliser partout où on affiche "le stock", jamais totalOac seul.
class CurrentEggStock {
  final String farmName;
  final String? lotNumber;
  final List<RoomEggStockCurrent> rooms;
  final int totalOac;
  final int totalPo;
  final int totalDj;
  final int totalCas;
  final int totalSal;
  final int totalShippedOac;
  final int currentStockOac;
  final bool hasReports;

  CurrentEggStock({
    required this.farmName,
    this.lotNumber,
    this.rooms = const [],
    this.totalOac = 0,
    this.totalPo = 0,
    this.totalDj = 0,
    this.totalCas = 0,
    this.totalSal = 0,
    this.totalShippedOac = 0,
    this.currentStockOac = 0,
    this.hasReports = false,
  });

  factory CurrentEggStock.fromMap(Map<String, dynamic> map) {
    return CurrentEggStock(
      farmName: map['farmName'] as String? ?? '',
      lotNumber: map['lotNumber'] as String?,
      rooms: (map['rooms'] as List<dynamic>? ?? [])
          .map((r) => RoomEggStockCurrent.fromMap(r as Map<String, dynamic>))
          .toList(),
      totalOac: (map['totalOac'] as num?)?.toInt() ?? 0,
      totalPo: (map['totalPo'] as num?)?.toInt() ?? 0,
      totalDj: (map['totalDj'] as num?)?.toInt() ?? 0,
      totalCas: (map['totalCas'] as num?)?.toInt() ?? 0,
      totalSal: (map['totalSal'] as num?)?.toInt() ?? 0,
      totalShippedOac: (map['totalShippedOac'] as num?)?.toInt() ?? 0,
      currentStockOac: (map['currentStockOac'] as num?)?.toInt() ?? 0,
      hasReports: map['hasReports'] as bool? ?? false,
    );
  }
}
