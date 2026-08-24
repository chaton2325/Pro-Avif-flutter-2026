class PosteAssignment {
  final String? id;
  final String userId;
  final String posteId;
  final String usineId; // toujours une usine précise : un utilisateur ne voit que son usine

  PosteAssignment({
    this.id,
    required this.userId,
    required this.posteId,
    required this.usineId,
  });

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'posteId': posteId,
      'usineId': usineId,
    };
  }

  factory PosteAssignment.fromMap(Map<String, dynamic> map) {
    return PosteAssignment(
      id: map['_id'] as String?,
      userId: map['userId'] as String,
      posteId: map['posteId'] as String,
      usineId: map['usineId'] as String,
    );
  }
}
