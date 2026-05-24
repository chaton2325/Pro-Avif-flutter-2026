import 'package:mongo_dart/mongo_dart.dart';

class User {
  final ObjectId? id;
  final String name;
  final String password;
  final String role; // 'admin' or 'user'
  final ObjectId? farmId;
  final bool isActive;
  final String language; // 'fr' or 'en'
  final int scalePrecision; // e.g., 1, 2, 3 decimal places

  User({
    this.id,
    required this.name,
    required this.password,
    required this.role,
    this.farmId,
    this.isActive = true,
    this.language = 'fr',
    this.scalePrecision = 2,
  });

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'name': name,
      'password': password,
      'role': role,
      'farmId': farmId,
      'isActive': isActive,
      'language': language,
      'scalePrecision': scalePrecision,
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
      language: map['language'] as String? ?? 'fr',
      scalePrecision: map['scalePrecision'] as int? ?? 2,
    );
  }
}
