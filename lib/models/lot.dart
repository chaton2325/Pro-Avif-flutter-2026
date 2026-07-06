class Lot {
  final String? id;
  final String number;
  final DateTime createdAt;
  final int startAge;
  final DateTime? startDate;

  Lot({
    this.id,
    required this.number,
    required this.createdAt,
    this.startAge = 1,
    this.startDate,
  });

  /// Âge courant du lot (en semaines), calculé à partir de l'âge et de la date de départ.
  int get currentAge {
    if (startDate == null) return startAge;
    final weeksElapsed = DateTime.now().difference(startDate!).inDays ~/ 7;
    return startAge + weeksElapsed;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'number': number,
      'createdAt': createdAt.toIso8601String(),
      'startAge': startAge,
      'startDate': startDate?.toIso8601String(),
    };
  }

  factory Lot.fromMap(Map<String, dynamic> map) {
    return Lot(
      id: map['_id'] as String?,
      number: map['number'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      startAge: (map['startAge'] as num?)?.toInt() ?? 1,
      startDate: map['startDate'] != null ? DateTime.parse(map['startDate'] as String) : null,
    );
  }
}
