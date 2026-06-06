class AuditLog {
  final String? id;
  final String userName;
  final String action; // 'create', 'update', 'delete', 'login'
  final String collection;
  final String details;
  final DateTime timestamp;

  AuditLog({
    this.id,
    required this.userName,
    required this.action,
    required this.collection,
    required this.details,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userName': userName,
      'action': action,
      'collection': collection,
      'details': details,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['_id'] as String?,
      userName: map['userName'] as String,
      action: map['action'] as String,
      collection: map['collection'] as String,
      details: map['details'] as String,
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }
}
