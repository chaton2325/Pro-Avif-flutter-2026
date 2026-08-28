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
import '../models/simulation.dart';
import '../models/feed_stock.dart';
import '../models/delivery.dart';
import '../models/delivery_resource.dart';
import '../models/usine_stats.dart';
import '../models/daily_report.dart';
import '../models/inventory_session.dart';
import './session_storage.dart';

/// Une ligne de comptage d'inventaire : [batchId] null = comptage global d'une matière,
/// renseigné = comptage d'un lot précis (matière « par lot »).
typedef InventoryCountEntry = ({
  String rawMaterialId,
  double countedQuantity,
  String? batchId,
});

class LicenseBlockedException implements Exception {
  final String reason;
  LicenseBlockedException(this.reason);
  @override
  String toString() => reason;
}

class MongoService {
  static final MongoService _instance = MongoService._internal();
  // TEMPORAIRE (test Partie 0 Usine Aliment) : backend local, remettre l'URL de
  // production ("https://proavif.mirhosty.com") avant tout build/déploiement.
  final String baseUrl = "https://proavif.mirhosty.com";
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
      final response = await http
          .get(Uri.parse('$baseUrl/users'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        _isConnected = true;
        connectionError = null;
      } else {
        _isConnected = false;
        connectionError =
            "Serveur répond avec le statut: ${response.statusCode}";
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
        throw LicenseBlockedException(
          data['detail'] ?? "Application bloquée par l'administrateur.",
        );
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
      final response = await http
          .get(Uri.parse('$baseUrl/license/status'))
          .timeout(const Duration(seconds: 6));
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

  Future<void> changePassword(
    String userId,
    String userName,
    String newPassword,
  ) async {
    // Note: The backend PUT /users/{id} can handle password change
    final response = await http.get(Uri.parse('$baseUrl/users'));
    if (response.statusCode == 200) {
      final List<dynamic> users = jsonDecode(response.body);
      final userData = users.firstWhere(
        (u) => u['_id'] == userId,
        orElse: () => null,
      );
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

  Future<void> updateUserPreferences(
    String userId,
    String language,
    int precision,
  ) async {
    final response = await http.get(Uri.parse('$baseUrl/users'));
    if (response.statusCode == 200) {
      final List<dynamic> users = jsonDecode(response.body);
      final userData = users.firstWhere(
        (u) => u['_id'] == userId,
        orElse: () => null,
      );
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
      throw LicenseBlockedException(
        data['detail'] ?? "Application bloquée par l'administrateur.",
      );
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
  Future<List<PosteAssignment>> getPosteAssignments({
    String? userId,
    String? usineId,
  }) async {
    final queryParams = <String, String>{};
    if (userId != null) queryParams['userId'] = userId;
    if (usineId != null) queryParams['usineId'] = usineId;
    final uri = Uri.parse(
      '$baseUrl/poste-assignments',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
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
    final uri = Uri.parse(
      '$baseUrl/raw-materials',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((m) => RawMaterial.fromMap(m)).toList();
    }
    return [];
  }

  Future<MaterialFiche?> getMaterialFiche(String materialId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/raw-materials/$materialId/fiche'),
    );
    if (response.statusCode == 200) {
      return MaterialFiche.fromMap(jsonDecode(response.body));
    }
    return null;
  }

  Future<void> addRawMaterial(RawMaterial material) async {
    final uri = Uri.parse(
      '$baseUrl/raw-materials',
    ).replace(queryParameters: {'performedBy': _performedBy});
    await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(material.toMap()),
    );
  }

  Future<void> updateRawMaterial(RawMaterial material) async {
    if (material.id == null) return;
    final uri = Uri.parse(
      '$baseUrl/raw-materials/${material.id}',
    ).replace(queryParameters: {'performedBy': _performedBy});
    await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(material.toMap()),
    );
  }

  Future<void> deleteRawMaterial(String id) async {
    final uri = Uri.parse(
      '$baseUrl/raw-materials/$id',
    ).replace(queryParameters: {'performedBy': _performedBy});
    await http.delete(uri);
  }

  // ---- Usine Aliment : Formules CRUD (référentiel par usine) ----
  Future<List<Formula>> getFormulas(String usineId) async {
    final uri = Uri.parse(
      '$baseUrl/formulas',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((f) => Formula.fromMap(f)).toList();
    }
    return [];
  }

  /// Renvoie un message d'erreur (ex. boucle détectée, aliment pas autorisé comme
  /// ingrédient) si le serveur refuse l'enregistrement, ou null si tout s'est bien passé —
  /// sans ça, un refus côté serveur se refermait silencieusement comme un succès.
  Future<String?> addFormula(Formula formula) async {
    final uri = Uri.parse(
      '$baseUrl/formulas',
    ).replace(queryParameters: {'performedBy': _performedBy});
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(formula.toMap()),
    );
    if (response.statusCode == 201) return null;
    return _extractError(response);
  }

  Future<String?> updateFormula(Formula formula) async {
    if (formula.id == null) return 'Formule sans identifiant';
    final uri = Uri.parse(
      '$baseUrl/formulas/${formula.id}',
    ).replace(queryParameters: {'performedBy': _performedBy});
    final response = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(formula.toMap()),
    );
    if (response.statusCode == 200) return null;
    return _extractError(response);
  }

  String _extractError(http.Response response) {
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Réceptions (approvisionnement) ----
  Future<List<Reception>> getReceptions({
    String? usineId,
    String? status,
    String? rawMaterialId,
  }) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (status != null) queryParams['status'] = status;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    final uri = Uri.parse(
      '$baseUrl/receptions',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((r) => Reception.fromMap(r)).toList();
    }
    return [];
  }

  /// Nom affiché comme auteur des écritures du module Usine Aliment (réceptions, pertes,
  /// ajustements, inventaires...) — "Admin" par défaut sur le chemin admin/test, sans
  /// utilisateur usine connecté.
  String get _performedBy => currentUsineUser?.name ?? 'Admin';

  Future<void> addReception(Reception reception) async {
    await http.post(
      Uri.parse('$baseUrl/receptions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(reception.toCreateMap(performedBy: _performedBy)),
    );
  }

  /// Renvoie un message d'erreur (côté serveur) si la valorisation échoue, sinon null.
  Future<String?> valorizeReception(String id, double unitPrice) async {
    final response = await http.post(
      Uri.parse('$baseUrl/receptions/$id/valorize'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'unitPrice': unitPrice, 'performedBy': _performedBy}),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Lots de matières premières (« par lot ») ----
  Future<List<RawMaterialBatch>> getRawMaterialBatches({
    String? usineId,
    String? rawMaterialId,
    String? status,
  }) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    if (status != null) queryParams['status'] = status;
    final uri = Uri.parse(
      '$baseUrl/raw-material-batches',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((b) => RawMaterialBatch.fromMap(b)).toList();
    }
    return [];
  }

  /// Historique paginé de tous les lots d'une usine (toutes matières « par lot »
  /// confondues sauf filtre), trié du plus récent au plus ancien — tout le tri et le
  /// filtrage se font côté serveur, jamais un chargement complet côté client.
  Future<RawMaterialBatchPage> getRawMaterialBatchesHistory({
    required String usineId,
    String? rawMaterialId,
    String? status,
    int limit = 30,
    int skip = 0,
  }) async {
    final queryParams = <String, String>{
      'usineId': usineId,
      'limit': '$limit',
      'skip': '$skip',
    };
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    if (status != null) queryParams['status'] = status;
    final uri = Uri.parse(
      '$baseUrl/raw-material-batches/history',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return RawMaterialBatchPage.fromMap(jsonDecode(response.body));
    }
    return RawMaterialBatchPage(
      totalCount: 0,
      items: [],
      limit: limit,
      skip: skip,
    );
  }

  Future<String?> closeRawMaterialBatch(
    String id,
    double countedQuantity,
    String reason,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/raw-material-batches/$id/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'countedQuantity': countedQuantity,
        'reason': reason,
        'performedBy': _performedBy,
      }),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Pertes / avaries (matières « globales ») ----
  Future<List<StockLoss>> getStockLosses({
    String? usineId,
    String? rawMaterialId,
  }) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    final uri = Uri.parse(
      '$baseUrl/stock-losses',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((l) => StockLoss.fromMap(l)).toList();
    }
    return [];
  }

  Future<String?> declareStockLoss(StockLoss loss) async {
    final body = loss.toCreateMap()..['performedBy'] = _performedBy;
    final response = await http.post(
      Uri.parse('$baseUrl/stock-losses'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 201) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Ajustement manuel du CUMP (matières « globales ») ----
  Future<List<CostAdjustment>> getCostAdjustments({
    String? usineId,
    String? rawMaterialId,
  }) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    final uri = Uri.parse(
      '$baseUrl/cost-adjustments',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((a) => CostAdjustment.fromMap(a)).toList();
    }
    return [];
  }

  Future<String?> adjustRawMaterialCost(
    String rawMaterialId,
    double newCost,
    String reason,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/cost-adjustments/$rawMaterialId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'newCost': newCost,
        'reason': reason,
        'performedBy': _performedBy,
      }),
    );
    if (response.statusCode == 201) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Inventaire ----
  /// Chaque entrée compte soit une matière « globale » ([batchId] null, écart imputé au
  /// CUMP global), soit un lot précis d'une matière « par lot » ([batchId] renseigné,
  /// écart imputé à CE lot) — une matière « par lot » avec plusieurs lots actifs peut donc
  /// avoir plusieurs entrées, une par lot. Renvoie la liste des écarts appliqués.
  Future<List<Map<String, dynamic>>> applyInventory(
    String usineId,
    List<InventoryCountEntry> counts, {
    String? comment,
  }) async {
    final body = {
      'usineId': usineId,
      'counts': counts
          .map(
            (c) => {
              'rawMaterialId': c.rawMaterialId,
              'countedQuantity': c.countedQuantity,
              if (c.batchId != null) 'batchId': c.batchId,
            },
          )
          .toList(),
      'comment': comment,
      'performedBy': _performedBy,
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

  /// Historique paginé (par défaut 50) des inventaires réalisés — y compris ceux sans
  /// le moindre écart, pour que "un inventaire a été fait le XX/XX" reste toujours
  /// traçable. [scope] : "matieres" | "aliments" | null (tous, rarement utile côté écran).
  Future<InventorySessionPage> getInventorySessions(
    String usineId, {
    String? scope,
    int limit = 50,
    int skip = 0,
  }) async {
    final queryParams = {
      'usineId': usineId,
      'limit': '$limit',
      'skip': '$skip',
    };
    if (scope != null) queryParams['scope'] = scope;
    final uri = Uri.parse(
      '$baseUrl/inventory/sessions',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return InventorySessionPage.fromMap(jsonDecode(response.body));
    }
    return InventorySessionPage(totalCount: 0, items: [], limit: limit, skip: skip);
  }

  /// Inventaire du stock d'aliment produit : comptage global par référence (les lots de
  /// production ne sont pas physiquement séparables une fois stockés). L'écart est
  /// réparti automatiquement (FIFO) sur les lots actifs côté serveur.
  Future<List<Map<String, dynamic>>> applyFeedInventory(
    String usineId,
    List<({String formulaId, double countedQuantity})> counts, {
    String? comment,
  }) async {
    final body = {
      'usineId': usineId,
      'counts': counts
          .map(
            (c) => {
              'formulaId': c.formulaId,
              'countedQuantity': c.countedQuantity,
            },
          )
          .toList(),
      'comment': comment,
      'performedBy': _performedBy,
    };
    final response = await http.post(
      Uri.parse('$baseUrl/inventory/apply-feed'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ---- Usine Aliment : Simulation & optimisation ----
  Future<List<SimulationLine>> simulateProduction(String usineId) async {
    final uri = Uri.parse(
      '$baseUrl/simulation',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['lines'] as List<dynamic>)
          .map((l) => SimulationLine.fromMap(l))
          .toList();
    }
    return [];
  }

  /// Plan optimisé (programmation linéaire). Renvoie null si le calcul échoue (ex. pas
  /// de formule active) — le message d'erreur serveur est alors dans [error].
  Future<({OptimizationResult? result, String? error})> optimizeProduction(
    String usineId,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/simulation/optimize',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return (
        result: OptimizationResult.fromMap(jsonDecode(response.body)),
        error: null,
      );
    }
    try {
      return (
        result: null,
        error:
            jsonDecode(response.body)['detail']?.toString() ??
            'Erreur inconnue',
      );
    } catch (_) {
      return (result: null, error: 'Erreur inconnue');
    }
  }

  // ---- Usine Aliment : Production & coût de revient ----
  Future<ProductionCheckResult> checkProduction(
    String usineId,
    String formulaId,
    double quantityTarget,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production/check'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usineId': usineId,
        'formulaId': formulaId,
        'quantityTarget': quantityTarget,
      }),
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
        'performedBy': _performedBy,
      }),
    );
    if (response.statusCode == 201) {
      return (
        batch: ProductionBatch.fromMap(jsonDecode(response.body)),
        error: null,
      );
    }
    try {
      return (
        batch: null,
        error:
            jsonDecode(response.body)['detail']?.toString() ??
            'Erreur inconnue',
      );
    } catch (_) {
      return (batch: null, error: 'Erreur inconnue');
    }
  }

  Future<List<ProductionBatch>> getProductionBatches({
    String? usineId,
    String? status,
  }) async {
    final queryParams = <String, String>{};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (status != null) queryParams['status'] = status;
    final uri = Uri.parse(
      '$baseUrl/production',
    ).replace(queryParameters: queryParams.isEmpty ? null : queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      return data.map((b) => ProductionBatch.fromMap(b)).toList();
    }
    return [];
  }

  Future<String?> validateProduction(
    String id, {
    double adjustment = 0,
    String? adjustmentReason,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production/$id/validate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'adjustment': adjustment,
        'adjustmentReason': adjustmentReason,
        'performedBy': _performedBy,
      }),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  /// Écran 17 — clôture : corrige la quantité réellement produite (pesée de sortie,
  /// souvent connue après le lancement) puis reste en brouillon ou part au comptable.
  Future<String?> closeProduction(
    String id, {
    required double actualQuantityProduced,
    required bool sendToAccountant,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production/$id/close'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'actualQuantityProduced': actualQuantityProduced,
        'sendToAccountant': sendToAccountant,
        'performedBy': _performedBy,
      }),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  /// Écran 19 — « Renvoyer » : la comptabilité signale un problème sur le lot sans toucher
  /// au stock déjà consommé (déjà réel physiquement), un simple drapeau tracé.
  Future<String?> rejectProduction(String id, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/production/$id/reject'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'reason': reason, 'performedBy': _performedBy}),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Stock & livraison ----

  Future<List<FeedStockSummary>> getFeedStock(String usineId) async {
    final uri = Uri.parse(
      '$baseUrl/feed-stock',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['items'] as List<dynamic>)
          .map((i) => FeedStockSummary.fromMap(i))
          .toList();
    }
    return [];
  }

  Future<String?> getCurrentLotForFarm(String farmName) async {
    final uri = Uri.parse(
      '$baseUrl/deliveries/current-lot',
    ).replace(queryParameters: {'farmName': farmName});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['lotNumber'] as String?;
    }
    return null;
  }

  Future<({Delivery? delivery, String? error})> createDelivery({
    required String usineId,
    required String formulaId,
    required String farmName,
    required double quantity,
    String? driverName,
    String? vehicle,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/deliveries'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usineId': usineId,
        'formulaId': formulaId,
        'farmName': farmName,
        'quantity': quantity,
        'driverName': driverName,
        'vehicle': vehicle,
        'performedBy': _performedBy,
      }),
    );
    if (response.statusCode == 201) {
      return (
        delivery: Delivery.fromMap(jsonDecode(response.body)),
        error: null,
      );
    }
    try {
      return (
        delivery: null,
        error:
            jsonDecode(response.body)['detail']?.toString() ??
            'Erreur inconnue',
      );
    } catch (_) {
      return (delivery: null, error: 'Erreur inconnue');
    }
  }

  Future<DeliveryPagedResult> getDeliveries({
    required String usineId,
    String? formulaId,
    String? farmName,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
    int skip = 0,
    int limit = 30,
  }) async {
    final queryParams = <String, String>{
      'usineId': usineId,
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'skip': '$skip',
      'limit': '$limit',
    };
    if (formulaId != null) queryParams['formulaId'] = formulaId;
    if (farmName != null) queryParams['farmName'] = farmName;
    final uri = Uri.parse(
      '$baseUrl/deliveries',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return DeliveryPagedResult.fromMap(jsonDecode(response.body));
    }
    return DeliveryPagedResult(
      totalCount: 0,
      data: [],
      limit: limit,
      skip: skip,
    );
  }

  /// Valide une livraison en attente : c'est ici, pas à la création, que le stock
  /// d'aliment est réellement attribué (FIFO) et déduit.
  Future<String?> validateDelivery(String id) async {
    final response = await http.post(
      Uri.parse('$baseUrl/deliveries/$id/validate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'performedBy': _performedBy}),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  /// Annule (ou rejette, si encore en attente) une livraison : si le stock avait déjà
  /// été déduit (livraison validée), il revient sur les lots d'où il venait — jamais un
  /// simple retrait de l'historique.
  Future<String?> cancelDelivery(String id, String reason) async {
    final response = await http.post(
      Uri.parse('$baseUrl/deliveries/$id/cancel'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'reason': reason, 'performedBy': _performedBy}),
    );
    if (response.statusCode == 200) return null;
    try {
      return jsonDecode(response.body)['detail']?.toString() ??
          'Erreur inconnue';
    } catch (_) {
      return 'Erreur inconnue';
    }
  }

  // ---- Usine Aliment : Chauffeurs & véhicules (référentiel de la logistique) ----

  Future<List<DeliveryResource>> getDrivers(String usineId) async {
    final uri = Uri.parse(
      '$baseUrl/delivery-resources/drivers',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List)
          .map((d) => DeliveryResource.fromMap(d))
          .toList();
    }
    return [];
  }

  Future<String?> createDriver(String usineId, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/delivery-resources/drivers'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usineId': usineId, 'name': name, 'isActive': true}),
    );
    return response.statusCode == 201 ? null : 'Erreur inconnue';
  }

  Future<String?> updateDriver(
    String id,
    String usineId,
    String name,
    bool isActive,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/delivery-resources/drivers/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usineId': usineId,
        'name': name,
        'isActive': isActive,
      }),
    );
    return response.statusCode == 200 ? null : 'Erreur inconnue';
  }

  Future<String?> deleteDriver(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/delivery-resources/drivers/$id'),
    );
    return response.statusCode == 200 ? null : 'Erreur inconnue';
  }

  Future<List<DeliveryResource>> getVehicles(String usineId) async {
    final uri = Uri.parse(
      '$baseUrl/delivery-resources/vehicles',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return (jsonDecode(response.body) as List)
          .map((d) => DeliveryResource.fromMap(d))
          .toList();
    }
    return [];
  }

  Future<String?> createVehicle(String usineId, String name) async {
    final response = await http.post(
      Uri.parse('$baseUrl/delivery-resources/vehicles'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'usineId': usineId, 'name': name, 'isActive': true}),
    );
    return response.statusCode == 201 ? null : 'Erreur inconnue';
  }

  Future<String?> updateVehicle(
    String id,
    String usineId,
    String name,
    bool isActive,
  ) async {
    final response = await http.put(
      Uri.parse('$baseUrl/delivery-resources/vehicles/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usineId': usineId,
        'name': name,
        'isActive': isActive,
      }),
    );
    return response.statusCode == 200 ? null : 'Erreur inconnue';
  }

  Future<String?> deleteVehicle(String id) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/delivery-resources/vehicles/$id'),
    );
    return response.statusCode == 200 ? null : 'Erreur inconnue';
  }

  // ---- Usine Aliment : Statistiques & traçabilité ----

  Future<DashboardStats?> getUsineDashboard(String usineId) async {
    final uri = Uri.parse(
      '$baseUrl/stats/dashboard',
    ).replace(queryParameters: {'usineId': usineId});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return DashboardStats.fromMap(jsonDecode(response.body));
    }
    return null;
  }

  Future<List<RoomConsumption>> getConsumptionByRoom(
    String usineId, {
    int? month,
    int? year,
  }) async {
    final queryParams = <String, String>{'usineId': usineId};
    if (month != null) queryParams['month'] = '$month';
    if (year != null) queryParams['year'] = '$year';
    final uri = Uri.parse(
      '$baseUrl/stats/consumption-by-room',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['rooms'] as List<dynamic>)
          .map((r) => RoomConsumption.fromMap(r))
          .toList();
    }
    return [];
  }

  Future<TraceResult?> traceLot(String lotNumber) async {
    final uri = Uri.parse(
      '$baseUrl/stats/trace',
    ).replace(queryParameters: {'lotNumber': lotNumber});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return TraceResult.fromMap(jsonDecode(response.body));
    }
    return null;
  }

  Future<BudgetsStats?> getBudgets(
    String usineId, {
    int? month,
    int? year,
  }) async {
    final queryParams = <String, String>{'usineId': usineId};
    if (month != null) queryParams['month'] = '$month';
    if (year != null) queryParams['year'] = '$year';
    final uri = Uri.parse(
      '$baseUrl/stats/budgets',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return BudgetsStats.fromMap(jsonDecode(response.body));
    }
    return null;
  }

  Future<void> setBudget({
    required String usineId,
    required String category,
    required int month,
    required int year,
    required double amountFcfa,
  }) async {
    await http.post(
      Uri.parse('$baseUrl/stats/budgets/config'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'usineId': usineId,
        'category': category,
        'month': month,
        'year': year,
        'amountFcfa': amountFcfa,
        'performedBy': _performedBy,
      }),
    );
  }

  Future<TrendsStats?> getTrends(
    String usineId, {
    String? rawMaterialId,
    String? formulaId,
  }) async {
    final queryParams = <String, String>{'usineId': usineId};
    if (rawMaterialId != null) queryParams['rawMaterialId'] = rawMaterialId;
    if (formulaId != null) queryParams['formulaId'] = formulaId;
    final uri = Uri.parse(
      '$baseUrl/stats/trends',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return TrendsStats.fromMap(jsonDecode(response.body));
    }
    return null;
  }

  Future<DailyReport?> getDailyReport(String usineId, DateTime date) async {
    final dateStr =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      '$baseUrl/stats/daily-report',
    ).replace(queryParameters: {'usineId': usineId, 'date': dateStr});
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return DailyReport.fromMap(jsonDecode(response.body));
    }
    return null;
  }

  /// usineId omis (null) = journal global, toutes usines confondues (vue admin) ; sinon
  /// journal d'une seule usine (vue depuis l'intérieur de cette usine).
  Future<AuditLogPagedResult> getUsineJournal({
    String? usineId,
    String? performedBy,
    String? type,
    String? action,
    DateTime? dateFrom,
    DateTime? dateTo,
    int skip = 0,
    int limit = 30,
  }) async {
    final queryParams = <String, String>{'skip': '$skip', 'limit': '$limit'};
    if (usineId != null) queryParams['usineId'] = usineId;
    if (performedBy != null) queryParams['performedBy'] = performedBy;
    if (type != null) queryParams['type'] = type;
    if (action != null) queryParams['action'] = action;
    if (dateFrom != null) {
      queryParams['dateFrom'] = dateFrom.toIso8601String().substring(0, 10);
    }
    if (dateTo != null) {
      queryParams['dateTo'] = dateTo.toIso8601String().substring(0, 10);
    }
    final uri = Uri.parse(
      '$baseUrl/audit-logs/usine',
    ).replace(queryParameters: queryParams);
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return AuditLogPagedResult.fromMap(jsonDecode(response.body));
    }
    return AuditLogPagedResult(
      totalCount: 0,
      data: [],
      limit: limit,
      skip: skip,
    );
  }

  /// Fusion (OR logique) des permissions de tous les postes d'un utilisateur pour une
  /// usine donnée (ou globalement si [usineId] est nul). Utile pour piloter l'affichage
  /// (masquage des coûts...) une fois connecté.
  Future<PostePermissions> getEffectivePermissions(
    String userId, {
    String? usineId,
  }) async {
    final queryParams = usineId != null ? {'usineId': usineId} : null;
    final uri = Uri.parse(
      '$baseUrl/poste-assignments/effective-permissions/$userId',
    ).replace(queryParameters: queryParams);
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

      final response = await http
          .post(
            Uri.parse('$baseUrl/weighings'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 5));

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
      final uri = Uri.parse(
        '$baseUrl/weighings/check-duplicate',
      ).replace(queryParameters: queryParams);
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
      final response = await http.get(
        Uri.parse('$baseUrl/weighings/stats/summary'),
      );
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

      final uri = Uri.parse(
        '$baseUrl/weighings/all',
      ).replace(queryParameters: queryParams);
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
      final uri = Uri.parse(
        '$baseUrl/weighings/analysis/latest',
      ).replace(queryParameters: queryParams);

      print("🔍 API CALL (Latest): $uri");

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("✅ API RESPONSE (Latest): ${data.keys}");
        return data;
      } else {
        print(
          "❌ API ERROR (Latest): ${response.statusCode} - ${response.body}",
        );
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
      final uri = Uri.parse(
        '$baseUrl/weighings/analysis/homogeneity',
      ).replace(queryParameters: queryParams);

      print("🔍 API CALL (Homogeneity): $uri");

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("✅ API RESPONSE (Homogeneity): ${data.keys}");
        return data;
      } else {
        print(
          "❌ API ERROR (Homogeneity): ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      print("Erreur getHomogeneityAnalysis: $e");
    }
    return {};
  }

  Future<Map<String, dynamic>> getClusteringAnalysis(String farmName) async {
    try {
      final uri = Uri.parse(
        '$baseUrl/weighings/analysis/clustering',
      ).replace(queryParameters: {'farmName': farmName});
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print("Erreur getClusteringAnalysis: $e");
    }
    return {};
  }

  Future<List<dynamic>> getRoomHomogeneityHistory(
    String farmName,
    String roomName,
    String sex, {
    String? lotNumber,
  }) async {
    try {
      final queryParams = {
        'farmName': farmName,
        'roomName': roomName,
        'sex': sex,
        if (lotNumber != null) 'lotNumber': lotNumber,
      };
      final uri = Uri.parse(
        '$baseUrl/weighings/analysis/homogeneity',
      ).replace(queryParameters: queryParams);

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
        print(
          "❌ API ERROR (History): ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      print("Erreur getRoomHomogeneityHistory: $e");
    }
    return [];
  }

  Future<Map<String, dynamic>> getPredictiveClustering(
    String weighingId, {
    String? sex,
  }) async {
    try {
      final queryParams = {
        'weighingId': weighingId,
        if (sex != null) 'sex': sex,
      };
      final uri = Uri.parse(
        '$baseUrl/weighings/predict/clustering',
      ).replace(queryParameters: queryParams);
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
      final uri = Uri.parse(
        '$baseUrl/weighings/predict/simulate-move',
      ).replace(queryParameters: queryParams);
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
      final endpoint =
          sex.toLowerCase() == 'mâle' || sex.toLowerCase() == 'male'
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
      final uri = Uri.parse(
        '$baseUrl/weighings/analysis/weight-evolution',
      ).replace(queryParameters: queryParams);

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
      final uri = Uri.parse(
        '$baseUrl/weighings/reports/weekly-summary',
      ).replace(queryParameters: queryParams);
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
