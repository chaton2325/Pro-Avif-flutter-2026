class WeightStandard {
  final int day;
  final int week;
  final double weight;
  final double minWeight;
  final double maxWeight;

  WeightStandard({
    required this.day,
    required this.week,
    required this.weight,
    required this.minWeight,
    required this.maxWeight,
  });

  factory WeightStandard.fromJson(Map<String, dynamic> json) {
    return WeightStandard(
      day: (json['day'] as num).toInt(),
      week: (json['week'] as num).toInt(),
      weight: (json['weight'] as num).toDouble(),
      minWeight: (json['min_weight'] as num).toDouble(),
      maxWeight: (json['max_weight'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day': day,
      'week': week,
      'weight': weight,
      'min_weight': minWeight,
      'max_weight': maxWeight,
    };
  }
}
