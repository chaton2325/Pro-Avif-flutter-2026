import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/farm.dart';
import '../models/audit_log.dart';
import '../models/lot.dart';
import '../models/weighing_session.dart';
import '../models/weight_standard.dart';
import '../models/weight_history_entry.dart';
import '../models/weekly_report.dart';
import '../models/usine.dart';
import '../models/usine_user.dart';
import '../models/poste.dart';
import '../models/poste_assignment.dart';
import '../models/raw_material.dart';
import '../models/formula.dart';
import '../models/reception.dart';
import '../models/raw_material_batch.dart';
import '../models/stock_loss.dart';
import '../models/cost_adjustment.dart';
import '../models/production_batch.dart';
import './session_storage.dart';

class LicenseBlockedException implements Exception {
  final String reason;
  LicenseBlockedException(this.reason);
  @override
  String toString() => reason;
}

class MongoService {
  static final MongoService _instance = MongoService._internal();
  // TEMPORAIRE (test Partie 0 Usine Aliment) : backend local, remettre l'URL de
  // production ("https://backendproavifeletana.mirhosty.com") avant tout build/déploiement.
  final String baseUrl = "http://192.168.1.187:8010";
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
      } else if (response.statusCode == 403) {
        final data = jsonDecode(response.body);
        throw LicenseBlockedException(data['detail'] ?? "Application bloquée par l'administrateur.");
      } else if (response.statusCode == 401) {
        throw Exception("Identifiants incorrects ou compte désactivé.");
      } else {
        throw Exception("Erreur lors de la connexion: ${response.statusCode}");
      }
    } on LicenseBlockedException {
      rethrow;
    } catch (e) {
      print("Erreur login: $e");
      rethrow;
    }
  }

  /// Consulte le statut de licence global de l'application (bloqué/actif, raison, expiration).
  /// En cas d'erreur réseau, retourne "non bloqué" pour ne pas empêcher l'usage hors-ligne.
  Future<Map<String, dynamic>> getLicenseStatus() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/license/status')).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur getLicenseStatus: $e");
    }
    return {"is_blocked": false};
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

  Future<void> updateLot(Lot lot) async {
    if (lot.id == null) return;
    await http.put(
      Uri.parse('$baseUrl/lots/${lot.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(lot.toMap()),
    );
  }

  Future<void> deleteLot(String id) async {
    await http.delete(Uri.parse('$baseUrl/lots/$id'));
  }

  // ---- Usine Aliment : Usines CRUD ----
  Future<List<Usine>> getUsines() async {
    final response = await http.get(Uri.parse('$baseUrl/usines'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((u) => Usine.fromMap(u)).toList();
    }
    return [];
  }

  Future<void> addUsine(Usine usine) async {
    await http.post(
      Uri.parse('$baseUrl/usines'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(usine.toMap()),
    );
  }

  Future<void> updateUsine(Usine usine) async {
    if (usine.id == null) return;
    await http.put(
      Uri.parse('$baseUrl/usines/${usine.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(usine.toMap()),
    );
  }

  Future<void> deleteUsine(String id) async {
    await http.delete(Uri.parse('$baseUrl/usines/$id'));
  }

  // ---- Usine Aliment : session courante (utilisateur usine connecté) ----
  UsineUser? currentUsineUser;

  /// Un seul écran de connexion pour toute l'app : le serveur cherche le couple
  /// (nom, mot de passe) dans les deux collections (users de ferme puis usine_users) et
  /// indique lequel a matché. Comme ce couple ne peut jamais exister dans les deux à la
  /// fois (contrôle fait à la création/édition des comptes), il n'y a jamais d'ambiguïté.
  /// Renvoie 'user' ou 'usine_user' dans `accountType`, null si identifiants incorrects.
  /// Lève [LicenseBlockedException] si l'app est bloquée par l'admin.
  Future<String?> unifiedLogin(String name, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'password': password}),
    );
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final accountType = data['accountType'] as String;
      if (accountType == 'user') {
        currentUser = User.fromMap(data['user']);
      } else {
        currentUsineUser = UsineUser.fromMap(data['user']);
      }
      return accountType;
    } else if (response.statusCode == 403) {
      final data = jsonDecode(response.body);
      throw LicenseBlockedException(data['detail'] ?? "Application bloquée par l'administrateur.");
    }
    return null;
  }

  void logoutUsineUser() {
    currentUsineUser = null;
  }

  // ---- Usine Aliment : Utilisateurs usine CRUD (distincts des users de ferme) ----
  Future<List<UsineUser>> getUsineUsers() async {
    final response = await http.get(Uri.parse('$baseUrl/usine-users'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((u) => UsineUser.fromMap(u)).toList();
    }
    return [];
  }

  /// Renvoie l'utilisateur créé (avec son id) pour permettre une affectation immédiate.
  Future<UsineUser?> addUsineUser(UsineUser user) async {
    final response = await http.post(
      Uri.parse('$baseUrl/usine-users'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(user.toMap()),
    );
    if (response.statusCode == 201) {
      return UsineUser.fromMap(jsonDecode(response.body));
    }
    return null;
  }

  Future<void> updateUsineUser(UsineUser user) async {
    if (user.id == null) return;
    await http.put(
      Uri.parse('$baseUrl/usine-users/${user.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(user.toMap()),
    );
  }

  Future<void> deleteUsineUser(String id) async {
    await http.delete(Uri.parse('$baseUrl/usine-users/$id'));
  }

  // ---- Usine Aliment : Postes CRUD ----
  Future<List<Poste>> getPostes() async {
    final response = await http.get(Uri.parse('$baseUrl/postes'));
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((p) => Poste.fromMap(p)).toList();
    }
    return [];
  }

  Future<void> addPoste(Poste poste) async {
    await http.post(
      Uri.parse('$baseUrl/postes'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(poste.toMap()),
    );
  }

  Future<void> updatePoste(Poste poste) async {
    if (poste.id == null) return;
    await http.put(
      Uri.parse('$baseUrl/postes/${poste.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(poste.toMap()),
    );
  }

  Future<void> deletePoste(String id) async {
    await http.delete(Uri.parse('$baseUrl/postes/$id'));
  }

  // ---- Usine Aliment : Affectations poste <-> utilisateur <-> usine ----
  Future<List<PosteAssignment>> getPosteAssignments({String? userId, String? usineId}) async {
    final queryParams = <String, String>{};
    if (userId != null) queryParams['userId'] = userId;
    if (usineId != null) queryParams['usineId'] = usineId;
    final uri = Uri.parse('$baseUrl/poste-assignments').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((a) => PosteAssignment.fromMap(a)).toList();
    }
    return [];
  }

  Future<void> addPosteAssignment(PosteAssignment assignment) async {
    await http.post(
      Uri.parse('$baseUrl/poste-assignments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(assignment.toMap()),
    );
  }

  Future<void> deletePosteAssignment(String id) async {
    await http.delete(Uri.parse('$baseUrl/poste-assignments/$id'));
  }

  // ---- Usine Aliment : Matières premières CRUD (référentiel par usine) ----
  Future<List<RawMaterial>> getRawMaterials(String usineId) async {
    final uri = Uri.parse('$baseUrl/raw-materials').replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((m) => RawMaterial.fromMap(m)).toList();
    }
    return [];
  }

  Future<void> addRawMaterial(RawMaterial material) async {
    await http.post(
      Uri.parse('$baseUrl/raw-materials'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(material.toMap()),
    );
  }

  Future<void> updateRawMaterial(RawMaterial material) async {
    if (material.id == null) return;
    await http.put(
      Uri.parse('$baseUrl/raw-materials/${material.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(material.toMap()),
    );
  }

  Future<void> deleteRawMaterial(String id) async {
    await http.delete(Uri.parse('$baseUrl/raw-materials/$id'));
  }

  // ---- Usine Aliment : Formules CRUD (référentiel par usine) ----
  Future<List<Formula>> getFormulas(String usineId) async {
    final uri = Uri.parse('$baseUrl/formulas').replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((f) => Formula.fromMap(f)).toList();
    }
    return [];
  }

  Future<void> addFormula(Formula formula) async {
    await http.post(
      Uri.parse('$baseUrl/formulas'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(formula.toMap()),
    );
  }

  Future<void> updateFormula(Formula formula) async {
    if (formula.id == null) return;
    await http.put(
      Uri.parse('$baseUrl/formulas/${formula.id}'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(formula.toMap()),
    );
  }

  Future<void> deleteFormula(String id) async {
    await http.delete(Uri.parse('$baseUrl/formulas/$id'));
  }

  // ---- Usine Aliment : Réceptions (approvisionnement) ----
  Future<List<Reception>> getReceptions({String? usineId, String? status, String? rawMaterialId}) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (status != null) queryParams['status'] = status;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    final uri = Uri.parse('$baseUrl/receptions').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((r) => Reception.fromMap(r)).toList();
    }
    return [];
  }

  Future<void> addReception(Reception reception) async {
    await http.post(
      Uri.parse('$baseUrl/receptions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(reception.toCreateMap()),
    );
  }

  /// Renvoie un message d'erreur (côté serveur) si la valorisation échoue, sinon null.
  Future<String?> valorizeReception(String id, double unitPrice) async {
    final response = await http.post(
      Uri.parse('$baseUrl/receptions/$id/valorize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'unitPrice': unitPrice}),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ?? 'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Lots de matières premières (« par lot ») ----
  Future<List<RawMaterialBatch>> getRawMaterialBatches({String? usineId, String? rawMaterialId, String? status}) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    if (status != null) queryParams['status'] = status;
    final uri = Uri.parse('$baseUrl/raw-material-batches').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((b) => RawMaterialBatch.fromMap(b)).toList();
    }
    return [];
  }

  Future<String?> closeRawMaterialBatch(String id, double countedQuantity, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/raw-material-batches/$id/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'countedQuantity': countedQuantity, 'reason': reason}),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ?? 'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Pertes / avaries (matières « globales ») ----
  Future<List<StockLoss>> getStockLosses({String? usineId, String? rawMaterialId}) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    final uri = Uri.parse('$baseUrl/stock-losses').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((l) => StockLoss.fromMap(l)).toList();
    }
    return [];
  }

  Future<String?> declareStockLoss(StockLoss loss) async {
    final response = await http.post(
      Uri.parse('$baseUrl/stock-losses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(loss.toCreateMap()),
    );
    if (response.statusCode == 201) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ?? 'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Ajustement manuel du CUMP (matières « globales ») ----
  Future<List<CostAdjustment>> getCostAdjustments({String? usineId, String? rawMaterialId}) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    final uri = Uri.parse('$baseUrl/cost-adjustments').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((a) => CostAdjustment.fromMap(a)).toList();
    }
    return [];
  }

  Future<String?> adjustRawMaterialCost(String rawMaterialId, double newCost, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/cost-adjustments/$rawMaterialId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'newCost': newCost, 'reason': reason}),
    );
    if (response.statusCode == 201) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ?? 'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Inventaire ----
  /// [counts] : {rawMaterialId: quantité comptée}. Renvoie la liste des écarts appliqués.
  Future<List<Map<String, dynamic>>> applyInventory(String usineId, Map<String, double> counts, {String? comment}) async {
    final body = {
      'usineId': usineId,
      'counts': counts.entries.map((e) => {'rawMaterialId': e.key, 'countedQuantity': e.value}).toList(),
      'comment': comment,
    };
    final response = await http.post(
      Uri.parse('$baseUrl/inventory/apply'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ---- Usine Aliment : Production & coût de revient ----
  Future<ProductionCheckResult> checkProduction(String usineId, String formulaId, double quantityTarget) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production/check'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usineId': usineId, 'formulaId': formulaId, 'quantityTarget': quantityTarget}),
    );
    if (response.statusCode == 200) {
      return ProductionCheckResult.fromMap(jsonDecode(response.body));
    }
    return ProductionCheckResult(canLaunch: false, lines: []);
  }

  /// Lance la fabrication (consomme réellement le stock / les lots FIFO). Renvoie le lot
  /// créé si succès, ou un message d'erreur serveur sinon.
  Future<({ProductionBatch? batch, String? error})> launchProduction({
    required String usineId,
    required String formulaId,
    required double quantityTarget,
    required double actualQuantityProduced,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production/launch'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usineId': usineId,
        'formulaId': formulaId,
        'quantityTarget': quantityTarget,
        'actualQuantityProduced': actualQuantityProduced,
      }),
    );
    if (response.statusCode == 201) {
      return (batch: ProductionBatch.fromMap(jsonDecode(response.body)), error: null);
    }
    try {
      return (batch: null, error: jsonDecode(response.body)['detail']?.toString() ?? 'Erreur inconnue');
    } catch (_) {
      return (batch: null, error: 'Erreur inconnue');
    }
  }

  Future<List<ProductionBatch>> getProductionBatches({String? usineId, String? status}) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (status != null) queryParams['status'] = status;
    final uri = Uri.parse('$baseUrl/production').replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((b) => ProductionBatch.fromMap(b)).toList();
    }
    return [];
  }

  Future<String?> validateProduction(String id, {double adjustment = 0, String? adjustmentReason}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production/$id/validate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'adjustment': adjustment, 'adjustmentReason': adjustmentReason}),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ?? 'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  /// Fusion (OR logique) des permissions de tous les postes d'un utilisateur pour une
  /// usine donnée (ou globalement si [usineId] est nul). Utile pour piloter l'affichage
  /// (masquage des coûts...) une fois connecté.
  Future<PostePermissions> getEffectivePermissions(String userId, {String? usineId}) async {
    final queryParams = usineId != null ? {'usineId': usineId} : null;
    final uri = Uri.parse('$baseUrl/poste-assignments/effective-permissions/$userId').replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return PostePermissions.fromMap(jsonDecode(response.body));
    }
    return const PostePermissions();
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

  Future<Map<String, dynamic>> checkDuplicateWeighing({
    required String farmName,
    required String roomName,
    required String sex,
    required String lotId,
    required int age,
  }) async {
    try {
      final queryParams = {
        'farmName': farmName,
        'roomName': roomName,
        'sex': sex,
        'lotId': lotId,
        'age': age.toString(),
      };
      final uri = Uri.parse('$baseUrl/weighings/check-duplicate').replace(queryParameters: queryParams);
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur checkDuplicateWeighing: $e");
    }
    return {"exists": false};
  }

  Future<Map<String, dynamic>> getStatsSummary() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/weighings/stats/summary'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur getStatsSummary: $e");
    }
    return {};
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
    String? roomName,
    String? lotNumber,
    String? operator,
    String? sex,
    DateTime? startDate,
    DateTime? endDate,
    String sortBy = 'timestamp',
    String order = 'desc',
  }) async {
    try {
      final queryParams = {
        'skip': skip.toString(),
        'limit': limit.toString(),
        'sortBy': sortBy,
        'order': order,
        if (farmName != null && farmName.isNotEmpty) 'farmName': farmName,
        if (roomName != null && roomName.isNotEmpty) 'roomName': roomName,
        if (lotNumber != null && lotNumber.isNotEmpty) 'lotNumber': lotNumber,
        if (operator != null && operator.isNotEmpty) 'operator': operator,
        if (sex != null && sex.isNotEmpty) 'sex': sex,
        if (startDate != null) 'startDate': startDate.toIso8601String(),
        if (endDate != null) 'endDate': endDate.toIso8601String(),
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

  Future<Map<String, dynamic>> getLatestAnalysis({
    required String farmName,
    required String roomName,
    required String sex,
    String? lotNumber,
  }) async {
    try {
      final queryParams = {
        'farmName': farmName,
        'roomName': roomName,
        'sex': sex,
        if (lotNumber != null) 'lotNumber': lotNumber,
      };
      final uri = Uri.parse('$baseUrl/weighings/analysis/latest').replace(queryParameters: queryParams);
      
      print("🔍 API CALL (Latest): $uri");
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("✅ API RESPONSE (Latest): ${data.keys}");
        return data;
      } else {
        print("❌ API ERROR (Latest): ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Erreur getLatestAnalysis: $e");
    }
    return {};
  }

  Future<Map<String, dynamic>> getHomogeneityAnalysis(
    String? farmName, {
    String? startDate,
    String? endDate,
    String? lotNumber,
    String? sex,
  }) async {
    try {
      final queryParams = {
        if (farmName != null) 'farmName': farmName,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
        if (lotNumber != null) 'lotNumber': lotNumber,
        if (sex != null) 'sex': sex,
      };
      final uri = Uri.parse('$baseUrl/weighings/analysis/homogeneity').replace(queryParameters: queryParams);
      
      print("🔍 API CALL (Homogeneity): $uri");
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("✅ API RESPONSE (Homogeneity): ${data.keys}");
        return data;
      } else {
        print("❌ API ERROR (Homogeneity): ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Erreur getHomogeneityAnalysis: $e");
    }
    return {};
  }

  Future<Map<String, dynamic>> getClusteringAnalysis(String farmName) async {
    try {
      final uri = Uri.parse('$baseUrl/weighings/analysis/clustering').replace(queryParameters: {'farmName': farmName});
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur getClusteringAnalysis: $e");
    }
    return {};
  }

  Future<List<dynamic>> getRoomHomogeneityHistory(String farmName, String roomName, String sex, {String? lotNumber}) async {
    try {
      final queryParams = { 
        'farmName': farmName,
        'roomName': roomName,
        'sex': sex,
        if (lotNumber != null) 'lotNumber': lotNumber,
      };
      final uri = Uri.parse('$baseUrl/weighings/analysis/homogeneity').replace(queryParameters: queryParams);
      
      print("🔍 API CALL (History): $uri");
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        print("✅ API RESPONSE (History): ${data.keys}");
        
        // Format: "Room - Sex (Lot: Number)"
        String keyWithLot = '$roomName - $sex (Lot: $lotNumber)';
        String keySimple = '$roomName - $sex';
        
        if (data.containsKey(keyWithLot)) {
          return List<dynamic>.from(data[keyWithLot]);
        } else if (data.containsKey(keySimple)) {
          return List<dynamic>.from(data[keySimple]);
        }
        
        // Fallback: search for any key containing the room and sex
        for (var k in data.keys) {
          if (k.contains(roomName) && k.contains(sex)) {
            if (lotNumber == null || k.contains(lotNumber)) {
              return List<dynamic>.from(data[k]);
            }
          }
        }
      } else {
        print("❌ API ERROR (History): ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Erreur getRoomHomogeneityHistory: $e");
    }
    return [];
  }

  Future<Map<String, dynamic>> getPredictiveClustering(String weighingId, {String? sex}) async {
    try {
      final queryParams = {
        'weighingId': weighingId,
        if (sex != null) 'sex': sex,
      };
      final uri = Uri.parse('$baseUrl/weighings/predict/clustering').replace(queryParameters: queryParams);
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur getPredictiveClustering: $e");
    }
    return {};
  }

  Future<Map<String, dynamic>> simulateMove({
    required String farmName,
    required String sourceRoom,
    required String targetRoom,
    required String sex,
    required String lotNumber,
    required int clusterId,
  }) async {
    try {
      final queryParams = {
        'farmName': farmName,
        'sourceRoom': sourceRoom,
        'targetRoom': targetRoom,
        'sex': sex,
        'lotNumber': lotNumber,
        'clusterId': clusterId.toString(),
      };
      final uri = Uri.parse('$baseUrl/weighings/predict/simulate-move').replace(queryParameters: queryParams);
      final response = await http.post(uri);
      
      return jsonDecode(response.body);
    } catch (e) {
      print("Erreur simulateMove: $e");
    }
    return {'error': 'Erreur de connexion au serveur'};
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

  // Weight Standards
  Future<List<WeightStandard>> getWeightStandards(String sex) async {
    try {
      final endpoint = sex.toLowerCase() == 'mâle' || sex.toLowerCase() == 'male'
          ? '/standards/weight-evolution/male'
          : '/standards/weight-evolution/female';
      
      final response = await http.get(Uri.parse('$baseUrl$endpoint'));
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((s) => WeightStandard.fromJson(s)).toList();
      }
    } catch (e) {
      print("Erreur getWeightStandards: $e");
    }
    return [];
  }

  // Actual Weight Evolution
  Future<List<WeightHistoryEntry>> getWeightEvolution({
    required String farmName,
    required String roomName,
    required String sex,
    String? lotNumber,
  }) async {
    try {
      final queryParams = {
        'farmName': farmName,
        'roomName': roomName,
        'sex': sex,
        if (lotNumber != null) 'lotNumber': lotNumber,
      };
      final uri = Uri.parse('$baseUrl/weighings/analysis/weight-evolution').replace(queryParameters: queryParams);
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        if (data.containsKey('history')) {
          final List<dynamic> history = data['history'];
          return history.map((e) => WeightHistoryEntry.fromJson(e)).toList();
        }
      }
    } catch (e) {
      print("Erreur getWeightEvolution: $e");
    }
    return [];
  }

  // Rapport hebdomadaire (WhatsApp) : regroupement par salle/sexe, calculs faits côté backend
  Future<WeeklyReport?> getWeeklyReport({
    required String farmName,
    required String lotNumber,
    int? week,
  }) async {
    try {
      final queryParams = {
        'farmName': farmName,
        'lotNumber': lotNumber,
        if (week != null) 'week': week.toString(),
      };
      final uri = Uri.parse('$baseUrl/weighings/reports/weekly-summary').replace(queryParameters: queryParams);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic> && data.containsKey('error')) {
          throw Exception(data['error']);
        }
        return WeeklyReport.fromJson(data);
      }
    } catch (e) {
      print("Erreur getWeeklyReport: $e");
      rethrow;
    }
    return null;
  }

  void logout() {
    currentUser = null;
  }
  
  Future<void> close() async {
    // Nothing to close for http
  }
}
