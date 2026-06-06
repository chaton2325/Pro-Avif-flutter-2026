class WeighingSession {
  final String? id;
  final String lotId;
  final String operator;
  final String farmName;
  final String roomName;
  final int age;
  final List<double> weights;
  final DateTime timestamp;

  WeighingSession({
    this.id,
    required this.lotId,
    required this.operator,
    required this.farmName,
    required this.roomName,
    required this.age,
    required this.weights,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'lotId': lotId,
      'operator': operator,
      'farmName': farmName,
      'roomName': roomName,
      'age': age,
      'weights': weights,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
