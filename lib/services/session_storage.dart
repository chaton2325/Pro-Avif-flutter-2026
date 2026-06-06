import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lot.dart';
import '../models/user.dart';

class SessionStorage {
  static const String _key = 'pending_weighing_sessions_v2';

  /// Generates a unique key for a session to avoid duplicates
  static String _generateSessionId(String userId, String lotNumber, String room, String building) {
    return '${userId}_${lotNumber}_${building}_${room}'.replaceAll(' ', '_');
  }

  /// Save or update a session in the list
  static Future<void> saveSession({
    required User user,
    required Lot lot,
    required String operator,
    required String building,
    required String room,
    required int age,
    required double minWeight,
    required double maxWeight,
    required int precision,
    required List<double> weights,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final String? existingJson = prefs.getString(_key);
    Map<String, dynamic> sessions = {};
    
    if (existingJson != null) {
      sessions = jsonDecode(existingJson);
    }

    final sessionId = _generateSessionId(user.id!, lot.number, room, building);
    
    sessions[sessionId] = {
      'id': sessionId,
      'userId': user.id,
      'lot': lot.toMap(),
      'operator': operator,
      'building': building,
      'room': room,
      'age': age,
      'minWeight': minWeight,
      'maxWeight': maxWeight,
      'precision': precision,
      'weights': weights,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await prefs.setString(_key, jsonEncode(sessions));
  }

  /// Retrieve all pending sessions for a specific user
  static Future<List<Map<String, dynamic>>> getSessionsForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? json = prefs.getString(_key);
    if (json == null) return [];
    
    Map<String, dynamic> allSessions = jsonDecode(json);
    return allSessions.values
        .where((s) => s['userId'] == userId)
        .cast<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
  }

  /// Delete a specific session after successful upload or manual deletion
  static Future<void> clearSession(String userId, String lotNumber, String room, String building) async {
    final sessionId = _generateSessionId(userId, lotNumber, room, building);
    final prefs = await SharedPreferences.getInstance();
    final String? json = prefs.getString(_key);
    if (json == null) return;

    Map<String, dynamic> sessions = jsonDecode(json);
    sessions.remove(sessionId);
    
    await prefs.setString(_key, jsonEncode(sessions));
  }
}
