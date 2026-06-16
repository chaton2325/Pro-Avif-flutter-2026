class WeightHistoryEntry {
  final int age;
  final int week;
  final double averageWeight;
  final double homogeneity;
  final DateTime timestamp;

  WeightHistoryEntry({
    required this.age,
    required this.week,
    required this.averageWeight,
    required this.homogeneity,
    required this.timestamp,
  });

  factory WeightHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WeightHistoryEntry(
      age: (json['age'] as num).toInt(),
      week: (json['week'] as num).toInt(),
      averageWeight: (json['averageWeight'] as num).toDouble(),
      homogeneity: (json['homogeneity'] as num?)?.toDouble() ?? 0.0,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
