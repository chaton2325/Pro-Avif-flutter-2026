import 'package:mongo_dart/mongo_dart.dart';

class Farm {
  final ObjectId? id;
  final String name;

  Farm({
    this.id,
    required this.name,
  });

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'name': name,
    };
  }

  factory Farm.fromMap(Map<String, dynamic> map) {
    return Farm(
      id: map['_id'] as ObjectId?,
      name: map['name'] as String,
    );
  }
}
