class WeeklyReportGroup {
  final String roomName;
  final String sex;
  final double? bodyWeight;
  final double? normalWeight;
  final double? difference;
  final double? gain;
  final double? homogeneity;
  final double? homogeneityDelta;
  final double? nextWeekNormalWeight;
  final DateTime timestamp;

  WeeklyReportGroup({
    required this.roomName,
    required this.sex,
    this.bodyWeight,
    this.normalWeight,
    this.difference,
    this.gain,
    this.homogeneity,
    this.homogeneityDelta,
    this.nextWeekNormalWeight,
    required this.timestamp,
  });

  factory WeeklyReportGroup.fromJson(Map<String, dynamic> json) {
    double? asDouble(dynamic v) => v == null ? null : (v as num).toDouble();
    return WeeklyReportGroup(
      roomName: json['roomName'] as String? ?? '',
      sex: json['sex'] as String? ?? '',
      bodyWeight: asDouble(json['bodyWeight']),
      normalWeight: asDouble(json['normalWeight']),
      difference: asDouble(json['difference']),
      gain: asDouble(json['gain']),
      homogeneity: asDouble(json['homogeneity']),
      homogeneityDelta: asDouble(json['homogeneityDelta']),
      nextWeekNormalWeight: asDouble(json['nextWeekNormalWeight']),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

class WeeklyReport {
  final String farmName;
  final String lotNumber;
  final int week;
  final DateTime dateStart;
  final DateTime dateEnd;
  final List<WeeklyReportGroup> groups;

  WeeklyReport({
    required this.farmName,
    required this.lotNumber,
    required this.week,
    required this.dateStart,
    required this.dateEnd,
    required this.groups,
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> json) {
    return WeeklyReport(
      farmName: json['farmName'] as String? ?? '',
      lotNumber: json['lotNumber'] as String? ?? '',
      week: (json['week'] as num?)?.toInt() ?? 0,
      dateStart: DateTime.parse(json['dateStart'] as String),
      dateEnd: DateTime.parse(json['dateEnd'] as String),
      groups: (json['groups'] as List<dynamic>? ?? []).map((g) => WeeklyReportGroup.fromJson(g as Map<String, dynamic>)).toList(),
    );
  }
}
