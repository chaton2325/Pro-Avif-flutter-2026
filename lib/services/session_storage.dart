import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/lot.dart';
import '../models/user.dart';
import '../models/weighing_session.dart';

class SessionStorage {
  static const String _key = 'pending_weighing_sessions_v2';
  static const String _offlineKey = 'offline_completed_sessions';

  /// Generates a unique key for an interrupted session
  static String _generateSessionId(String userId, String lotNumber, String room, String building) {
    return '${userId}_${lotNumber}_${building}_${room}'.replaceAll(' ', '_');
  }

  // --- INTERRUPTED SESSIONS LOGIC (Drafts) ---

  static Future<void> saveSession({
    required User user,
    required Lot lot,
    required String operator,
    required String building,
    required String room,
    String? sex,
    double? lowerInterval,
    double? upperInterval,
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
      try {
        sessions = jsonDecode(existingJson);
      } catch (e) {
        sessions = {};
      }
    }

    final sessionId = _generateSessionId(user.id!, lot.number, room, building);
    
    sessions[sessionId] = {
      'id': sessionId,
      'userId': user.id,
      'lot': lot.toMap(),
      'operator': operator,
      'building': building,
      'room': room,
      'sex': sex,
      'lowerInterval': lowerInterval,
      'upperInterval': upperInterval,
      'age': age,
      'minWeight': minWeight,
      'maxWeight': maxWeight,
      'precision': precision,
      'weights': weights,
      'timestamp': DateTime.now().toIso8601String(),
    };

    await prefs.setString(_key, jsonEncode(sessions));
  }

  static Future<List<Map<String, dynamic>>> getSessionsForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    
    try {
      Map<String, dynamic> allSessions = jsonDecode(jsonStr);
      return allSessions.values
          .where((s) => s['userId'] == userId)
          .cast<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
    } catch (e) {
      return [];
    }
  }

  static Future<void> clearSession(String userId, String lotNumber, String room, String building) async {
    final sessionId = _generateSessionId(userId, lotNumber, room, building);
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_key);
    if (jsonStr == null) return;

    try {
      Map<String, dynamic> sessions = jsonDecode(jsonStr);
      sessions.remove(sessionId);
      await prefs.setString(_key, jsonEncode(sessions));
    } catch (e) {}
  }

  // --- OFFLINE COMPLETED SESSIONS LOGIC (Ready for sync) ---

  static Future<void> saveOfflineSession(WeighingSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_offlineKey);
    List<dynamic> list = [];
    if (jsonStr != null) {
      try {
        list = jsonDecode(jsonStr);
      } catch (e) {
        list = [];
      }
    }
    list.add(session.toMap());
    await prefs.setString(_offlineKey, jsonEncode(list));
  }

  static Future<List<WeighingSession>> getOfflineSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? jsonStr = prefs.getString(_offlineKey);
    if (jsonStr == null) return [];
    
    try {
      final List<dynamic> list = jsonDecode(jsonStr);
      return list.map((item) => WeighingSession.fromMap(item)).toList();
    } catch (e) {
      return [];
    }
  }

  static Future<void> clearOfflineSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_offlineKey);
  }
}
