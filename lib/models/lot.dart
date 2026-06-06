class Lot {
  final String? id;
  final String number;
  final DateTime createdAt;

  Lot({
    this.id,
    required this.number,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'number': number,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Lot.fromMap(Map<String, dynamic> map) {
    return Lot(
      id: map['_id'] as String?,
      number: map['number'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }
}
