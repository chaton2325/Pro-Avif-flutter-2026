import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import '../models/user.dart';
import '../models/farm.dart';
import '../models/audit_log.dart';
import '../models/lot.dart';
import '../services/mongo_service.dart';
import 'login_screen.dart';
import 'admin_history_screen.dart';
import 'admin_analysis_screen.dart';
import 'admin_predictive_analysis_screen.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  final MongoService _mongoService = MongoService();
  List<User> _users = [];
  List<User> _filteredUsers = [];
  List<Farm> _farms = [];
  List<Farm> _filteredFarms = [];
  List<Lot> _lots = [];
  List<Lot> _filteredLots = [];
  List<AuditLog> _logs = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _error;
  
  final TextEditingController _userSearchController = TextEditingController();
  final TextEditingController _farmSearchController = TextEditingController();
  final TextEditingController _lotSearchController = TextEditingController();

  void _logout() {
    _mongoService.logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshData();
    _userSearchController.addListener(_filterUsers);
    _farmSearchController.addListener(_filterFarms);
    _lotSearchController.addListener(_filterLots);
  }

  @override
  void dispose() {
    _userSearchController.dispose();
    _farmSearchController.dispose();
    _lotSearchController.dispose();
    super.dispose();
  }

  void _filterUsers() {
    final query = _userSearchController.text.toLowerCase();
    setState(() {
      _filteredUsers = _users.where((u) => u.name.toLowerCase().contains(query)).toList();
    });
  }

  void _filterFarms() {
    final query = _farmSearchController.text.toLowerCase();
    setState(() {
      _filteredFarms = _farms.where((f) => f.name.toLowerCase().contains(query)).toList();
    });
  }

  void _filterLots() {
    final query = _lotSearchController.text.toLowerCase();
    setState(() {
      _filteredLots = _lots.where((l) => l.number.toLowerCase().contains(query)).toList();
    });
  }

  void _refreshData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      if (!_mongoService.isConnected) {
        await _mongoService.connect();
      }
      
      final users = await _mongoService.getUsers();
      final farms = await _mongoService.getFarms();
      final lots = await _mongoService.getLots();
      final logs = await _mongoService.getAuditLogs();
      
      if (!mounted) return;
      setState(() {
        _users = users;
        _filteredUsers = users;
        _farms = farms;
        _filteredFarms = farms;
        _lots = lots;
        _filteredLots = lots;
        _logs = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur de chargement : $e";
        _isLoading = false;
      });
    }
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'user';
    String? selectedFarmId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Ajouter Utilisateur', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom')),
                TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Mot de passe'), obscureText: true),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Rôle'),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('Simple Utilisateur')),
                    DropdownMenuItem(value: 'admin', child: Text('Administrateur')),
                  ],
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  hint: const Text('Allouer à une ferme'),
                  value: selectedFarmId,
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('Aucune ferme')),
                    ..._farms
                        .where((f) => f.id != null)
                        .fold<Map<String, Farm>>({}, (map, f) => map..putIfAbsent(f.id!, () => f))
                        .values
                        .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                        .toList(),
                  ],
                  onChanged: (val) => setDialogState(() => selectedFarmId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                await _mongoService.addUser(User(name: nameController.text, password: passwordController.text, role: selectedRole, farmId: selectedFarmId));
                _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserDialog(User user) {
    final nameController = TextEditingController(text: user.name);
    final passwordController = TextEditingController();
    String selectedRole = user.role;
    String? selectedFarmId = user.farmId;

    if (selectedFarmId != null && !_farms.any((f) => f.id == selectedFarmId)) {
      selectedFarmId = null;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Modifier ${user.name}', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom')),
                TextField(controller: passwordController, decoration: const InputDecoration(labelText: 'Nouveau MDP (laisser vide si inchangé)'), obscureText: true),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Rôle'),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('Simple Utilisateur')),
                    DropdownMenuItem(value: 'admin', child: Text('Administrateur')),
                  ],
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  hint: const Text('Allouer à une ferme'),
                  value: selectedFarmId,
                  items: [
                    const DropdownMenuItem<String>(value: null, child: Text('Aucune ferme')),
                    ..._farms
                        .where((f) => f.id != null)
                        .fold<Map<String, Farm>>({}, (map, f) => map..putIfAbsent(f.id!, () => f))
                        .values
                        .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name)))
                        .toList(),
                  ],
                  onChanged: (val) => setDialogState(() => selectedFarmId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                final updatedUser = User(
                  id: user.id,
                  name: nameController.text,
                  password: passwordController.text.isEmpty ? user.password : passwordController.text,
                  role: selectedRole,
                  farmId: selectedFarmId,
                  isActive: user.isActive,
                  language: user.language,
                  scalePrecision: user.scalePrecision,
                );
                await _mongoService.updateUser(updatedUser);
                _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddFarmDialog() {
    final nameController = TextEditingController();
    final roomController = TextEditingController();
    List<String> rooms = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Créer un Bâtiment', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom du Bâtiment (Site)'),
                ),
                const SizedBox(height: 16),
                const Text('Salles du bâtiment', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: roomController,
                        decoration: const InputDecoration(hintText: 'Nom de la salle'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      onPressed: () {
                        if (roomController.text.isNotEmpty) {
                          setDialogState(() {
                            rooms.add(roomController.text);
                            roomController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: rooms.map((r) => Chip(
                    label: Text(r, style: const TextStyle(fontSize: 10)),
                    onDeleted: () => setDialogState(() => rooms.remove(r)),
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  await _mongoService.addFarm(Farm(name: nameController.text, rooms: rooms));
                  _refreshData();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Créer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditFarmDialog(Farm farm) {
    final nameController = TextEditingController(text: farm.name);
    final roomController = TextEditingController();
    List<String> rooms = List.from(farm.rooms);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Modifier le Bâtiment', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom du Bâtiment'),
                ),
                const SizedBox(height: 16),
                const Text('Salles', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: roomController,
                        decoration: const InputDecoration(hintText: 'Ajouter une salle'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.green),
                      onPressed: () {
                        if (roomController.text.isNotEmpty) {
                          setDialogState(() {
                            rooms.add(roomController.text);
                            roomController.clear();
                          });
                        }
                      },
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  children: rooms.map((r) => Chip(
                    label: Text(r, style: const TextStyle(fontSize: 10)),
                    onDeleted: () => setDialogState(() => rooms.remove(r)),
                  )).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty) {
                  await _mongoService.updateFarm(Farm(id: farm.id, name: nameController.text, rooms: rooms));
                  _refreshData();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                }
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddLotDialog() {
    final numberController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Nouveau numéro de lot', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: numberController,
          decoration: const InputDecoration(labelText: 'Numéro de lot (ex: LOT-2026-001)'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (numberController.text.isNotEmpty) {
                await _mongoService.addLot(Lot(number: numberController.text, createdAt: DateTime.now()));
                _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('PRO-AVIF ADMIN', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: _refreshData),
          IconButton(icon: const Icon(Icons.logout, color: Colors.orange), onPressed: _logout),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
        : _error != null 
          ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)))
          : _buildBody(),
      floatingActionButton: (_currentIndex >= 1 && _currentIndex <= 3) && !_isLoading
          ? FloatingActionButton(
              backgroundColor: Colors.orange,
              elevation: 6,
              onPressed: () {
                if (_currentIndex == 1) _showAddUserDialog();
                else if (_currentIndex == 2) _showAddFarmDialog();
                else if (_currentIndex == 3) _showAddLotDialog();
              },
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      bottomNavigationBar: _buildGoogleNavBar(),
    );
  }

  Widget _buildBody() {
    return IndexedStack(
      index: _currentIndex,
      children: [
        _buildHomeOverview(),
        _buildUserList(),
        _buildFarmList(),
        _buildLotList(),
        _buildAuditLogs(),
      ],
    );
  }

  Widget _buildHomeOverview() {
    return RefreshIndicator(
      onRefresh: () async => _refreshData(),
      color: Colors.orange,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aperçu Général', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildStatCard('Membres', _users.length.toString(), Icons.people, Colors.blue),
                const SizedBox(width: 16),
                _buildStatCard('Bâtiments', _farms.length.toString(), Icons.agriculture, Colors.green),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildStatCard('Lots', _lots.length.toString(), Icons.inventory_2, Colors.purple),
                const SizedBox(width: 16),
                _buildQuickAction(
                  Icons.analytics, 
                  'Historique Global', 
                  Colors.indigo,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHistoryScreen())),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildQuickAction(
                  Icons.show_chart, 
                  'Analyse Qualité', 
                  Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAnalysisScreen())),
                ),
                const SizedBox(width: 16),
                _buildQuickAction(
                  Icons.psychology, 
                  'Optimisation IA', 
                  Colors.purple,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPredictiveAnalysisScreen())),
                ),
              ],
            ),
            const SizedBox(height: 32),
            const Text('Activités Récentes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_logs.isEmpty)
              const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('Aucune activité enregistrée', style: TextStyle(color: Colors.grey))))
            else
              ..._logs.take(5).map((log) => Card(
                elevation: 1,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.info_outline, size: 20),
                  title: Text(log.details, style: const TextStyle(fontSize: 13)),
                  subtitle: Text('${log.userName} | ${log.timestamp.toString().substring(11, 16)}', style: const TextStyle(fontSize: 11)),
                ),
              )),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 12),
              Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: Colors.grey, fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 30),
                const SizedBox(height: 12),
                Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _userSearchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un membre...',
              prefixIcon: const Icon(Icons.search, color: Colors.orange),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _filteredUsers.isEmpty 
            ? const Center(child: Text('Aucun membre trouvé', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                itemCount: _filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredUsers[index];
                  final farm = _farms.cast<Farm?>().firstWhere((f) => f?.id == user.farmId, orElse: () => null);
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ExpansionTile(
                      leading: CircleAvatar(
                        backgroundColor: user.isActive ? (user.role == 'admin' ? Colors.orange.withValues(alpha: 0.2) : Colors.grey[200]) : Colors.red.withValues(alpha: 0.1),
                        child: Icon(user.role == 'admin' ? Icons.security : Icons.person, color: user.isActive ? (user.role == 'admin' ? Colors.orange : Colors.grey[700]) : Colors.red[300]),
                      ),
                      title: Text(user.name, style: TextStyle(fontWeight: FontWeight.bold, decoration: user.isActive ? null : TextDecoration.lineThrough, color: user.isActive ? Colors.black87 : Colors.grey)),
                      subtitle: Text('${user.role.toUpperCase()} | ${farm?.name ?? "Sans ferme"}'),
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              TextButton.icon(icon: Icon(user.isActive ? Icons.block : Icons.check_circle, color: user.isActive ? Colors.red : Colors.green), label: Text(user.isActive ? 'Désactiver' : 'Activer', style: TextStyle(color: user.isActive ? Colors.red : Colors.green)), onPressed: () async { await _mongoService.toggleUserStatus(user); _refreshData(); }),
                              IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showEditUserDialog(user)),
                              IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async { await _mongoService.deleteUser(user.id!); _refreshData(); }),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildFarmList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _farmSearchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un bâtiment...',
              prefixIcon: const Icon(Icons.search, color: Colors.orange),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _filteredFarms.isEmpty
            ? const Center(child: Text('Aucun bâtiment trouvé', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                itemCount: _filteredFarms.length,
                itemBuilder: (context, index) {
                  final farm = _filteredFarms[index];
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.orange.withValues(alpha: 0.2), child: const Icon(Icons.house, color: Colors.orange)),
                      title: Text(farm.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${farm.rooms.length} salle(s) : ${farm.rooms.join(", ")}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showEditFarmDialog(farm)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async { await _mongoService.deleteFarm(farm.id!); _refreshData(); }),
                        ],
                      ),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildLotList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _lotSearchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un numéro de lot...',
              prefixIcon: const Icon(Icons.search, color: Colors.orange),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(30), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: _filteredLots.isEmpty
            ? const Center(child: Text('Aucun lot trouvé', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 100),
                itemCount: _filteredLots.length,
                itemBuilder: (context, index) {
                  final lot = _filteredLots[index];
                  return Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.purple.withValues(alpha: 0.1), child: const Icon(Icons.inventory_2, color: Colors.purple)),
                      title: Text(lot.number, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      subtitle: Text('Créé le : ${lot.createdAt.toString().substring(0, 16)}'),
                      trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async { await _mongoService.deleteLot(lot.id!); _refreshData(); }),
                    ),
                  );
                },
              ),
        ),
      ],
    );
  }

  Widget _buildAuditLogs() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
      itemCount: _logs.length,
      itemBuilder: (context, index) {
        final log = _logs[index];
        IconData actionIcon;
        Color actionColor;
        switch (log.action) {
          case 'create': actionIcon = Icons.add_circle_outline; actionColor = Colors.green; break;
          case 'update': actionIcon = Icons.edit_outlined; actionColor = Colors.blue; break;
          case 'delete': actionIcon = Icons.remove_circle_outline; actionColor = Colors.red; break;
          case 'login': actionIcon = Icons.login_outlined; actionColor = Colors.orange; break;
          default: actionIcon = Icons.info_outline; actionColor = Colors.grey;
        }
        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: ListTile(
            leading: Icon(actionIcon, color: actionColor),
            title: Text(log.details, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            subtitle: Text('Par: ${log.userName} | ${log.timestamp.toString().substring(0, 19)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
        );
      },
    );
  }

  Widget _buildGoogleNavBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 5))]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: GNav(
          rippleColor: Colors.orange[300]!,
          hoverColor: Colors.orange[100]!,
          haptic: true,
          tabBorderRadius: 20,
          curve: Curves.easeOutExpo,
          duration: const Duration(milliseconds: 400),
          gap: 4,
          color: Colors.grey[600],
          activeColor: Colors.orange,
          iconSize: 20,
          tabBackgroundColor: Colors.orange.withValues(alpha: 0.1),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          onTabChange: (index) => setState(() => _currentIndex = index),
          tabs: const [
            GButton(icon: Icons.home, text: 'Accueil'),
            GButton(icon: Icons.people, text: 'Membres'),
            GButton(icon: Icons.agriculture, text: 'Bâtiments'),
            GButton(icon: Icons.inventory_2, text: 'Lots'),
            GButton(icon: Icons.history, text: 'Logs'),
          ],
        ),
      ),
    );
  }
}
