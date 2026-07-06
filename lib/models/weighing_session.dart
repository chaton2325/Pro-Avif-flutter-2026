class WeighingSession {
  final String? id;
  final String userId;
  final String lotId;
  final String? lotNumber;
  final String operator;
  final String farmName;
  final String roomName;
  final String? sex;
  final double? lowerInterval;
  final double? upperInterval;
  final int age;
  final List<double> weights;
  final DateTime timestamp;
  final bool isSync;
  final double homogeneity;
  final bool? isSuperseded;

  WeighingSession({
    this.id,
    required this.userId,
    required this.lotId,
    this.lotNumber,
    required this.operator,
    required this.farmName,
    required this.roomName,
    this.sex,
    this.lowerInterval,
    this.upperInterval,
    required this.age,
    required this.weights,
    required this.timestamp,
    this.isSync = true,
    this.homogeneity = 0.0,
    this.isSuperseded,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'lotId': lotId,
      'lotNumber': lotNumber,
      'operator': operator,
      'farmName': farmName,
      'roomName': roomName,
      'sex': sex,
      'lowerInterval': lowerInterval,
      'upperInterval': upperInterval,
      'age': age,
      'weights': weights,
      'timestamp': timestamp.toIso8601String(),
      'isSync': isSync,
      'homogeneity': homogeneity,
    };
  }

  factory WeighingSession.fromMap(Map<String, dynamic> map) {
    return WeighingSession(
      id: map['_id'] as String? ?? map['id'] as String?,
      userId: map['userId'] as String? ?? '',
      lotId: map['lotId'] as String,
      lotNumber: map['lotNumber'] as String?,
      operator: map['operator'] as String,
      farmName: map['farmName'] as String,
      roomName: map['roomName'] as String,
      sex: map['sex'] as String?,
      lowerInterval: (map['lowerInterval'] as num?)?.toDouble(),
      upperInterval: (map['upperInterval'] as num?)?.toDouble(),
      age: map['age'] as int,
      weights: List<double>.from(map['weights'].map((x) => x.toDouble())),
      timestamp: DateTime.parse(map['timestamp'] as String),
      isSync: map['isSync'] as bool? ?? true,
      homogeneity: (map['homogeneity'] as num?)?.toDouble() ?? 0.0,
      isSuperseded: map['isSuperseded'] as bool?,
    );
  }
}
