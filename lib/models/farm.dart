import 'package:mongo_dart/mongo_dart.dart';

class Farm {
  final ObjectId? id;
  final String name;
  final List<String> rooms;

  Farm({
    this.id,
    required this.name,
    this.rooms = const [],
  });

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'name': name,
      'rooms': rooms,
    };
  }

  factory Farm.fromMap(Map<String, dynamic> map) {
    return Farm(
      id: map['_id'] as ObjectId?,
      name: map['name'] as String,
      rooms: List<String>.from(map['rooms'] ?? []),
    );
  }
}
