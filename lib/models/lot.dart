import 'package:mongo_dart/mongo_dart.dart';

class Lot {
  final ObjectId? id;
  final String number;
  final DateTime createdAt;

  Lot({
    this.id,
    required this.number,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      '_id': id,
      'number': number,
      'createdAt': createdAt,
    };
  }

  factory Lot.fromMap(Map<String, dynamic> map) {
    return Lot(
      id: map['_id'] as ObjectId?,
      number: map['number'] as String,
      createdAt: map['createdAt'] as DateTime,
    );
  }
}
