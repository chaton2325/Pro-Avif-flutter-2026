class WeightHistoryEntry {
  final int age;
  final int week;
  final double averageWeight;
  final DateTime timestamp;

  WeightHistoryEntry({
    required this.age,
    required this.week,
    required this.averageWeight,
    required this.timestamp,
  });

  factory WeightHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WeightHistoryEntry(
      age: (json['age'] as num).toInt(),
      week: (json['week'] as num).toInt(),
      averageWeight: (json['averageWeight'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
