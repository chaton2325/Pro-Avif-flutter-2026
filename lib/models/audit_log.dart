import 'package:mongo_dart/mongo_dart.dart';

class AuditLog {
  final ObjectId? id;
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
      '_id': id,
      'userName': userName,
      'action': action,
      'collection': collection,
      'details': details,
      'timestamp': timestamp,
    };
  }

  factory AuditLog.fromMap(Map<String, dynamic> map) {
    return AuditLog(
      id: map['_id'] as ObjectId?,
      userName: map['userName'] as String,
      action: map['action'] as String,
      collection: map['collection'] as String,
      details: map['details'] as String,
      timestamp: map['timestamp'] as DateTime,
    );
  }
}
