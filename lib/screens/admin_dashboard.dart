import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/farm.dart';
import '../models/audit_log.dart';
import '../models/lot.dart';
import '../services/mongo_service.dart';
import 'login_screen.dart';
import 'admin_history_screen.dart';
import 'admin_analysis_screen.dart';
import 'admin_predictive_analysis_screen.dart';
import 'admin_weight_standards_screen.dart';
import 'performance_selector_screen.dart';

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
  Map<String, dynamic>? _statsSummary;
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
      final stats = await _mongoService.getStatsSummary();

      if (!mounted) return;
      setState(() {
        _users = users;
        _filteredUsers = users;
        _farms = farms;
        _filteredFarms = farms;
        _lots = lots;
        _filteredLots = lots;
        _logs = logs;
        _statsSummary = stats;
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom du Bâtiment (Site)', prefixIcon: Icon(Icons.apartment)),
                ),
                const SizedBox(height: 24),
                const Text('Salles du bâtiment', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: roomController,
                        decoration: const InputDecoration(hintText: 'Nom de la salle', prefixIcon: Icon(Icons.meeting_room)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.orange, size: 32),
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
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: rooms.map((r) => Chip(
                      label: Text(r),
                      backgroundColor: Colors.orange.shade50,
                      deleteIconColor: Colors.red,
                      onDeleted: () => setDialogState(() => rooms.remove(r)),
                    )).toList(),
                  ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom du Bâtiment', prefixIcon: Icon(Icons.apartment)),
                ),
                const SizedBox(height: 24),
                const Text('Salles', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: roomController,
                        decoration: const InputDecoration(hintText: 'Ajouter une salle', prefixIcon: Icon(Icons.meeting_room)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.add_circle, color: Colors.orange, size: 32),
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
                const SizedBox(height: 16),
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: rooms.map((r) => Chip(
                      label: Text(r),
                      backgroundColor: Colors.orange.shade50,
                      deleteIconColor: Colors.red,
                      onDeleted: () => setDialogState(() => rooms.remove(r)),
                    )).toList(),
                  ),
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
    final startAgeController = TextEditingController(text: '1');
    DateTime startDate = DateTime.now();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Nouveau numéro de lot', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: numberController,
                  decoration: const InputDecoration(labelText: 'Numéro de lot (ex: LOT-2026-001)'),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: startAgeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Âge de départ (semaines)'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Date de départ : ${DateFormat('dd/MM/yyyy').format(startDate)}')),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setDialogState(() => startDate = picked);
                      },
                      child: const Text('Choisir'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (numberController.text.isNotEmpty) {
                  await _mongoService.addLot(Lot(
                    number: numberController.text,
                    createdAt: DateTime.now(),
                    startAge: int.tryParse(startAgeController.text) ?? 1,
                    startDate: startDate,
                  ));
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

  void _showEditLotDialog(Lot lot) {
    final numberController = TextEditingController(text: lot.number);
    final startAgeController = TextEditingController(text: lot.startAge.toString());
    DateTime startDate = lot.startDate ?? lot.createdAt;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Modifier le lot', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: numberController,
                  decoration: const InputDecoration(labelText: 'Numéro de lot'),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: startAgeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Âge de départ (semaines)'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Text('Date de départ : ${DateFormat('dd/MM/yyyy').format(startDate)}')),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: startDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setDialogState(() => startDate = picked);
                      },
                      child: const Text('Choisir'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (numberController.text.isNotEmpty) {
                  await _mongoService.updateLot(Lot(
                    id: lot.id,
                    number: numberController.text,
                    createdAt: lot.createdAt,
                    startAge: int.tryParse(startAgeController.text) ?? 1,
                    startDate: startDate,
                  ));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: const Text('ADMINISTRATION', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
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
      floatingActionButton: (_currentIndex == 1 || _currentIndex == 2 || _currentIndex == 3) && !_isLoading
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
      ],
    );
  }

  Widget _buildHomeOverview() {
    return RefreshIndicator(
      onRefresh: () async => _refreshData(),
      color: Colors.orange,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAdminHeaderCard(),
            const SizedBox(height: 32),
            const Text('STATISTIQUES (TEMPS RÉEL)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 20),
            _buildStatsRow(),
            const SizedBox(height: 32),
            const Text('ACTIONS RAPIDES', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.grey, letterSpacing: 1.2)),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildQuickAction(
                  Icons.analytics_rounded, 
                  'Historique', 
                  Colors.indigo,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminHistoryScreen())),
                ),
                const SizedBox(width: 16),
                _buildQuickAction(
                  Icons.show_chart_rounded, 
                  'Analyse', 
                  Colors.orange,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAnalysisScreen())),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildQuickAction(
                  Icons.psychology_rounded, 
                  'IA', 
                  Colors.purple,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPredictiveAnalysisScreen())),
                ),
                const SizedBox(width: 16),
                _buildQuickAction(
                  Icons.rule_rounded, 
                  'Standards', 
                  Colors.teal,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminWeightStandardsScreen())),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildQuickAction(
                  Icons.auto_graph_rounded, 
                  'Croissance', 
                  Colors.blue.shade700,
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminPerformanceSelectorScreen())),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 120),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.orange.shade600,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: Colors.orange.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('ADMINISTRATEUR', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
              Text(
                '${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Système de Gestion Pro-Avif', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = _statsSummary ?? {};
    final total = stats['totalCount'] ?? 0;
    final lastHour = stats['lastHourCount'] ?? 0;
    final avgHomogeneity = (stats['avgHomogeneity'] as num?)?.toDouble() ?? 0.0;
    String lastWeighingAgo = '-';
    final lastTs = stats['lastWeighingTimestamp'];
    if (lastTs != null) {
      final lastDate = DateTime.tryParse(lastTs.toString());
      if (lastDate != null) {
        final diff = DateTime.now().difference(lastDate);
        if (diff.inMinutes < 60) {
          lastWeighingAgo = 'il y a ${diff.inMinutes} min';
        } else if (diff.inHours < 24) {
          lastWeighingAgo = 'il y a ${diff.inHours} h';
        } else {
          lastWeighingAgo = 'il y a ${diff.inDays} j';
        }
      }
    }

    return Column(
      children: [
        Row(
          children: [
            _buildStatCard('Total Pesées', '$total', Icons.inventory_2_rounded, Colors.indigo),
            const SizedBox(width: 16),
            _buildStatCard('Dernière heure', '$lastHour', Icons.bolt_rounded, Colors.orange),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            _buildStatCard('Dernière pesée', lastWeighingAgo, Icons.history_toggle_off_rounded, Colors.teal),
            const SizedBox(width: 16),
            _buildStatCard('Homogénéité moy.', '${avgHomogeneity.toStringAsFixed(1)}%', Icons.auto_graph_rounded, Colors.green),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color, {VoidCallback? onTap}) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 12),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: TextField(
            controller: _userSearchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un membre...',
              prefixIcon: const Icon(Icons.search, color: Colors.orange),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade100, width: 1)),
            ),
          ),
        ),
        Expanded(
          child: _filteredUsers.isEmpty 
            ? const Center(child: Text('Aucun membre trouvé', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                itemCount: _filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredUsers[index];
                  final farm = _farms.cast<Farm?>().firstWhere((f) => f?.id == user.farmId, orElse: () => null);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade100),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(
                        backgroundColor: user.isActive ? (user.role == 'admin' ? Colors.orange.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1)) : Colors.grey.withValues(alpha: 0.1),
                        child: Icon(user.role == 'admin' ? Icons.security_rounded : Icons.person_rounded, color: user.isActive ? (user.role == 'admin' ? Colors.orange : Colors.blue) : Colors.grey),
                      ),
                      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      subtitle: Text('${user.role.toUpperCase()} • ${farm?.name ?? "Sans site"}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: Icon(user.isActive ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, color: user.isActive ? Colors.green : Colors.grey, size: 32), onPressed: () async { await _mongoService.toggleUserStatus(user); _refreshData(); }),
                          IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20), onPressed: () => _showEditUserDialog(user)),
                          IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20), onPressed: () async { await _mongoService.deleteUser(user.id!); _refreshData(); }),
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

  Widget _buildFarmList() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(20.0),
          child: TextField(
            controller: _farmSearchController,
            decoration: InputDecoration(
              hintText: 'Rechercher un bâtiment...',
              prefixIcon: const Icon(Icons.search, color: Colors.orange),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.grey.shade100, width: 1)),
            ),
          ),
        ),
        Expanded(
          child: _filteredFarms.isEmpty
            ? const Center(child: Text('Aucun bâtiment trouvé', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                itemCount: _filteredFarms.length,
                itemBuilder: (context, index) {
                  final farm = _filteredFarms[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade100),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      leading: CircleAvatar(backgroundColor: Colors.green.withValues(alpha: 0.1), child: const Icon(Icons.agriculture_rounded, color: Colors.green)),
                      title: Text(farm.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                      subtitle: Text('${farm.rooms.length} salle(s) : ${farm.rooms.join(", ")}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20), onPressed: () => _showEditFarmDialog(farm)),
                          IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20), onPressed: () async { await _mongoService.deleteFarm(farm.id!); _refreshData(); }),
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
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade100)),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: Colors.purple.withValues(alpha: 0.1), child: const Icon(Icons.inventory_2, color: Colors.purple)),
                      title: Text(lot.number, style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                      subtitle: Text('Âge actuel : ${lot.currentAge} sem. • Départ : ${lot.startDate != null ? DateFormat('dd/MM/yyyy').format(lot.startDate!) : '-'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20), onPressed: () => _showEditLotDialog(lot)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () async { await _mongoService.deleteLot(lot.id!); _refreshData(); }),
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

  Widget _buildGoogleNavBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(30, 0, 30, 30),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(35), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10))]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
            GButton(icon: Icons.home_rounded, text: 'Accueil'),
            GButton(icon: Icons.people_rounded, text: 'Membres'),
            GButton(icon: Icons.agriculture_rounded, text: 'Bâtiments'),
            GButton(icon: Icons.inventory_2_rounded, text: 'Lots'),
          ],
        ),
      ),
    );
  }
}
