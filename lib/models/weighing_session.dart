class WeighingSession {
  final String? id;
  final String userId;
  final String lotId;
  final String operator;
  final String farmName;
  final String roomName;
  final int age;
  final List<double> weights;
  final DateTime timestamp;
  final bool isSync;
  final double homogeneity;

  WeighingSession({
    this.id,
    required this.userId,
    required this.lotId,
    required this.operator,
    required this.farmName,
    required this.roomName,
    required this.age,
    required this.weights,
    required this.timestamp,
    this.isSync = true,
    this.homogeneity = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'lotId': lotId,
      'operator': operator,
      'farmName': farmName,
      'roomName': roomName,
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
      operator: map['operator'] as String,
      farmName: map['farmName'] as String,
      roomName: map['roomName'] as String,
      age: map['age'] as int,
      weights: List<double>.from(map['weights'].map((x) => x.toDouble())),
      timestamp: DateTime.parse(map['timestamp'] as String),
      isSync: map['isSync'] as bool? ?? true,
      homogeneity: (map['homogeneity'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
