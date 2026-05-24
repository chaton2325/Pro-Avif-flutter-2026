import 'package:mongo_dart/mongo_dart.dart';

class User {
  final ObjectId? id;
  final String name;
  final String password;
  final String role; // 'admin' or 'user'
  final ObjectId? farmId;
  final bool isActive;

  User({
    this.id,
    required this.name,
    required this.password,
    required this.role,
    this.farmId,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'name': name,
      'password': password,
      'role': role,
      'farmId': farmId,
      'isActive': isActive,
    };
  }

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['_id'] as ObjectId?,
      name: map['name'] as String,
      password: map['password'] as String,
      role: map['role'] as String,
      farmId: map['farmId'] as ObjectId?,
      isActive: map['isActive'] as bool? ?? true,
    );
  }
}
