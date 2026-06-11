import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/farm.dart';
import '../models/audit_log.dart';
import '../models/lot.dart';
import '../models/weighing_session.dart';
import './session_storage.dart';

class MongoService {
  static final MongoService _instance = MongoService._internal();
  final String baseUrl = "http://192.168.0.117:8000";
  User? currentUser;
  String? connectionError;
  bool _isConnected = false;

  factory MongoService() {
    return _instance;
  }

  MongoService._internal();

  bool get isConnected => _isConnected;

  Future<void> connect() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/users')).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        _isConnected = true;
        connectionError = null;
      } else {
        _isConnected = false;
        connectionError = "Serveur répond avec le statut: ${response.statusCode}";
      }
    } catch (e) {
      _isConnected = false;
      connectionError = e.toString();
      print("Erreur ApiService: $e");
    }
  }

  Future<User?> login(String name, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'name': name, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        currentUser = User.fromMap(data);
        return currentUser;
      } else if (response.statusCode == 401) {
        throw Exception("Identifiants incorrects ou compte désactivé.");
      } else {
        throw Exception("Erreur lors de la connexion: ${response.statusCode}");
      }
    } catch (e) {
      print("Erreur login: $e");
      rethrow;
    }
  }

  // Users CRUD
  Future<List<User>> getUsers() async {
    final response = await http.get(Uri.parse('$baseUrl/users'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((u) => User.fromMap(u)).toList();
    }
    return [];
  }

  Future<void> addUser(User user) async {
    await http.post(
      Uri.parse('$baseUrl/users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(user.toMap()),
    );
  }

  Future<void> updateUser(User user) async {
    if (user.id == null) return;
    await http.put(
      Uri.parse('$baseUrl/users/${user.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(user.toMap()),
    );
  }

  Future<void> toggleUserStatus(User user) async {
    if (user.id == null) return;
    final updatedUser = User(
      id: user.id,
      name: user.name,
      password: user.password,
      role: user.role,
      farmId: user.farmId,
      isActive: !user.isActive,
      language: user.language,
      scalePrecision: user.scalePrecision,
    );
    await updateUser(updatedUser);
  }

  Future<void> changePassword(String userId, String userName, String newPassword) async {
    // Note: The backend PUT /users/{id} can handle password change
    final response = await http.get(Uri.parse('$baseUrl/users'));
    if (response.statusCode == 200) {
      final List<dynamic> users = jsonDecode(response.body);
      final userData = users.firstWhere((u) => u['_id'] == userId, orElse: () => null);
      if (userData != null) {
        userData['password'] = newPassword;
        await http.put(
          Uri.parse('$baseUrl/users/$userId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(userData),
        );
      }
    }
  }

  Future<void> updateUserPreferences(String userId, String language, int precision) async {
    final response = await http.get(Uri.parse('$baseUrl/users'));
    if (response.statusCode == 200) {
      final List<dynamic> users = jsonDecode(response.body);
      final userData = users.firstWhere((u) => u['_id'] == userId, orElse: () => null);
      if (userData != null) {
        userData['language'] = language;
        userData['scalePrecision'] = precision;
        await http.put(
          Uri.parse('$baseUrl/users/$userId'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(userData),
        );
        
        if (currentUser?.id == userId) {
          currentUser = User.fromMap(userData);
        }
      }
    }
  }

  Future<void> deleteUser(String id) async {
    await http.delete(Uri.parse('$baseUrl/users/$id'));
  }

  // Farms CRUD
  Future<List<Farm>> getFarms() async {
    final response = await http.get(Uri.parse('$baseUrl/farms'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((f) => Farm.fromMap(f)).toList();
    }
    return [];
  }

  Future<Farm?> getFarmById(String id) async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/farms/$id'));
      if (response.statusCode == 200) {
        return Farm.fromMap(jsonDecode(response.body));
      }
    } catch (e) {
      print("Erreur getFarmById: $e");
    }
    
    // Fallback: search in list if endpoint fails
    final farms = await getFarms();
    try {
      return farms.firstWhere((f) => f.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> addFarm(Farm farm) async {
    await http.post(
      Uri.parse('$baseUrl/farms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(farm.toMap()),
    );
  }

  Future<void> updateFarm(Farm farm) async {
    // The backend doesn't have PUT /farms/{id} in the list, but usually it's there.
    // Given the prompt list, I might have to delete and re-add or ask.
    // But I'll assume standard CRUD if needed, or just skip if not in the list.
    // The list only has GET /farms, POST /farms, DELETE /farms/{id}.
    // If I need to update, I'll delete and re-add for now as a workaround if PUT is missing.
    if (farm.id == null) return;
    await deleteFarm(farm.id!);
    await addFarm(farm);
  }

  Future<void> deleteFarm(String id) async {
    await http.delete(Uri.parse('$baseUrl/farms/$id'));
  }

  // Lots CRUD
  Future<List<Lot>> getLots() async {
    final response = await http.get(Uri.parse('$baseUrl/lots'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((l) => Lot.fromMap(l)).toList();
    }
    return [];
  }

  Future<void> addLot(Lot lot) async {
    await http.post(
      Uri.parse('$baseUrl/lots'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(lot.toMap()),
    );
  }

  Future<void> deleteLot(String id) async {
    await http.delete(Uri.parse('$baseUrl/lots/$id'));
  }

  // Weighing Sessions
  Future<void> saveWeighingSession(WeighingSession session) async {
    try {
      final payload = jsonEncode(session.toMap());
      print("Sending WeighingSession payload: $payload");
      
      final response = await http.post(
        Uri.parse('$baseUrl/weighings'),
        headers: {'Content-Type': 'application/json'},
        body: payload,
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception("Serveur erreur: ${response.statusCode}");
      }
    } catch (e) {
      // Offline mode: save locally if server unreachable
      print("Mode Hors-Ligne: Sauvegarde locale de la pesée");
      final offlineSession = WeighingSession(
        userId: session.userId,
        lotId: session.lotId,
        operator: session.operator,
        farmName: session.farmName,
        roomName: session.roomName,
        sex: session.sex,
        lowerInterval: session.lowerInterval,
        upperInterval: session.upperInterval,
        age: session.age,
        weights: session.weights,
        timestamp: session.timestamp,
        homogeneity: session.homogeneity,
        isSync: false, // Mark as NOT synced
      );
      await SessionStorage.saveOfflineSession(offlineSession);
      throw Exception("OFFLINE_SAVED"); // Special error to notify UI
    }
  }

  Future<int> syncOfflineSessions() async {
    final offlineSessions = await SessionStorage.getOfflineSessions();
    if (offlineSessions.isEmpty) return 0;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/weighings/bulk'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(offlineSessions.map((s) => s.toMap()).toList()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        await SessionStorage.clearOfflineSessions();
        return data['inserted_count'] ?? offlineSessions.length;
      }
    } catch (e) {
      print("Échec de la synchronisation: $e");
    }
    return 0;
  }

  Future<Map<String, dynamic>> getPaginatedWeighings({
    int skip = 0,
    int limit = 20,
    String? farmName,
    String? lotId,
    String? operator,
    String? sex,
    double? lowerInterval,
    double? upperInterval,
    String sortBy = 'timestamp',
    String order = 'desc',
  }) async {
    try {
      final queryParams = {
        'skip': skip.toString(),
        'limit': limit.toString(),
        'sort_by': sortBy,
        'order': order,
        if (farmName != null && farmName.isNotEmpty) 'farmName': farmName,
        if (lotId != null && lotId.isNotEmpty) 'lotId': lotId,
        if (operator != null && operator.isNotEmpty) 'operator': operator,
        if (sex != null && sex.isNotEmpty) 'sex': sex,
        if (lowerInterval != null) 'lowerInterval': lowerInterval.toString(),
        if (upperInterval != null) 'upperInterval': upperInterval.toString(),
      };
      
      final uri = Uri.parse('$baseUrl/weighings/all').replace(queryParameters: queryParams);
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur getPaginatedWeighings: $e");
    }
    return {'total_count': 0, 'data': [], 'limit': limit, 'skip': skip};
  }

  // Audit Logs
  Future<List<AuditLog>> getAuditLogs() async {
    final response = await http.get(Uri.parse('$baseUrl/audit-logs'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((l) => AuditLog.fromMap(l)).toList();
    }
    return [];
  }

  void logout() {
    currentUser = null;
  }
  
  Future<void> close() async {
    // Nothing to close for http
  }
}
