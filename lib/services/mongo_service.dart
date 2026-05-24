import 'package:mongo_dart/mongo_dart.dart';
import '../models/user.dart';
import '../models/farm.dart';
import '../models/audit_log.dart';

class MongoService {
  static final MongoService _instance = MongoService._internal();
  Db? _db;
  DbCollection? _userCollection;
  DbCollection? _farmCollection;
  DbCollection? _auditCollection;
  String? connectionError;
  User? currentUser;

  factory MongoService() {
    return _instance;
  }

  MongoService._internal();

  bool get isConnected => _db != null && _db!.isConnected;

  Future<void> connect() async {
    try {
      _db = await Db.create("mongodb://192.168.1.110:27017/pro-avif-db");
      await _db!.open();
      _userCollection = _db!.collection('users');
      _farmCollection = _db!.collection('fermes');
      _auditCollection = _db!.collection('audit_logs');
      connectionError = null;
      
      await _ensureAdminExists();
    } catch (e) {
      connectionError = e.toString();
      print("Erreur MongoService: $e");
      rethrow;
    }
  }

  Future<void> _logAction(String action, String collection, String details) async {
    if (_auditCollection == null) return;
    await _auditCollection!.insertOne(AuditLog(
      userName: currentUser?.name ?? 'System',
      action: action,
      collection: collection,
      details: details,
      timestamp: DateTime.now(),
    ).toMap());
  }

  Future<void> _ensureAdminExists() async {
    if (_userCollection == null) return;
    final admin = await _userCollection!.findOne(where.eq('role', 'admin'));
    if (admin == null) {
      await _userCollection!.insertOne({
        'name': 'admin',
        'password': 'admin',
        'role': 'admin',
      });
    }
  }

  Future<User?> login(String name, String password) async {
    if (!isConnected || _userCollection == null) {
      throw Exception("Non connecté à la base de données");
    }
    
    final res = await _userCollection!.findOne(
      where.eq('name', name).eq('password', password),
    );
    if (res != null) {
      final user = User.fromMap(res);
      if (!user.isActive) {
        throw Exception("Compte désactivé. Contactez l'administrateur.");
      }
      currentUser = user;
      await _logAction('login', 'users', 'Utilisateur connecté: $name');
      return currentUser;
    }
    return null;
  }

  // Users CRUD
  Future<List<User>> getUsers() async {
    if (_userCollection == null) return [];
    final users = await _userCollection!.find().toList();
    return users.map((u) => User.fromMap(u)).toList();
  }

  Future<void> addUser(User user) async {
    await _userCollection?.insertOne(user.toMap());
    await _logAction('create', 'users', 'Ajout de l\'utilisateur: ${user.name} with role ${user.role}');
  }

  Future<void> updateUser(User user) async {
    if (user.id == null) return;
    await _userCollection?.replaceOne(where.id(user.id!), user.toMap());
    await _logAction('update', 'users', 'Modification de l\'utilisateur: ${user.name}');
  }

  Future<void> toggleUserStatus(User user) async {
    if (user.id == null) return;
    final newStatus = !user.isActive;
    await _userCollection?.update(
      where.id(user.id!),
      modify.set('isActive', newStatus),
    );
    await _logAction('update', 'users', '${newStatus ? "Activation" : "Désactivation"} de l\'utilisateur: ${user.name}');
  }

  Future<void> changePassword(ObjectId userId, String userName, String newPassword) async {
    await _userCollection?.update(
      where.id(userId),
      modify.set('password', newPassword),
    );
    await _logAction('update', 'users', 'Changement de mot de passe pour: $userName');
  }

  Future<void> updateUserPreferences(ObjectId userId, String language, int precision) async {
    await _userCollection?.update(
      where.id(userId),
      modify.set('language', language).set('scalePrecision', precision),
    );
    if (currentUser?.id == userId) {
      currentUser = User(
        id: currentUser!.id,
        name: currentUser!.name,
        password: currentUser!.password,
        role: currentUser!.role,
        farmId: currentUser!.farmId,
        isActive: currentUser!.isActive,
        language: language,
        scalePrecision: precision,
      );
    }
    await _logAction('update', 'users', 'Mise à jour des préférences (Langue: $language, Précision: $precision)');
  }

  Future<void> deleteUser(ObjectId id) async {
    final user = await _userCollection?.findOne(where.id(id));
    await _userCollection?.remove(where.id(id));
    await _logAction('delete', 'users', 'Suppression de l\'utilisateur: ${user?['name']}');
  }

  // Farms CRUD
  Future<List<Farm>> getFarms() async {
    if (_farmCollection == null) return [];
    final farms = await _farmCollection!.find().toList();
    return farms.map((f) => Farm.fromMap(f)).toList();
  }

  Future<Farm?> getFarmById(ObjectId id) async {
    final farm = await _farmCollection?.findOne(where.id(id));
    if (farm != null) return Farm.fromMap(farm);
    return null;
  }

  Future<void> addFarm(Farm farm) async {
    await _farmCollection?.insertOne(farm.toMap());
    await _logAction('create', 'fermes', 'Création de la ferme: ${farm.name}');
  }

  Future<void> updateFarm(Farm farm) async {
    if (farm.id == null) return;
    await _farmCollection?.replaceOne(where.id(farm.id!), farm.toMap());
    await _logAction('update', 'fermes', 'Modification de la ferme: ${farm.name}');
  }

  Future<void> deleteFarm(ObjectId id) async {
    final farm = await _farmCollection?.findOne(where.id(id));
    await _farmCollection?.remove(where.id(id));
    await _logAction('delete', 'fermes', 'Suppression de la ferme: ${farm?['name']}');
  }

  // Audit Logs
  Future<List<AuditLog>> getAuditLogs() async {
    if (_auditCollection == null) return [];
    final logs = await _auditCollection!.find(where.sortBy('timestamp', descending: true)).toList();
    return logs.map((l) => AuditLog.fromMap(l)).toList();
  }

  void logout() {
    currentUser = null;
  }
  
  Future<void> close() async {
    await _db?.close();
  }
}
