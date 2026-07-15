import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/farm.dart';
import '../models/lot.dart';
import '../services/mongo_service.dart';
import '../services/session_storage.dart';
import '../utils/platform_utils.dart';
import 'login_screen.dart';
import 'new_weighing_screen.dart';
import 'weight_entry_screen.dart';
import 'pending_sessions_screen.dart';
import 'user_history_screen.dart';

class UserDashboard extends StatefulWidget {
  final User user;

  const UserDashboard({super.key, required this.user});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  final MongoService _mongoService = MongoService();
  Farm? _assignedFarm;
  bool _isLoading = true;
  int _currentIndex = 0;
  
  List<Map<String, dynamic>> _pendingSessions = [];
  
  late Timer _timer;
  String _currentTime = '';
  String _currentDateStr = '';

  late String _selectedLanguage;
  final TextEditingController _precisionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.user.language;
    _precisionController.text = widget.user.scalePrecision.toString();
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) => _updateTime());
    _loadData();
    _checkPendingSessions();
  }

  Future<void> _checkPendingSessions() async {
    final sessions = await SessionStorage.getSessionsForUser(widget.user.id!);
    if (!mounted) return;
    setState(() => _pendingSessions = sessions);
  }

  @override
  void dispose() {
    _timer.cancel();
    _precisionController.dispose();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(now);
      _currentDateStr = DateFormat('dd/MM/yyyy').format(now);
    });
  }

  void _loadData() async {
    if (widget.user.farmId != null) {
      final farm = await _mongoService.getFarmById(widget.user.farmId!);
      if (!mounted) return;
      setState(() {
        _assignedFarm = farm;
        _isLoading = false;
      });
    } else {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _logout() {
    _mongoService.logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _saveSettings() async {
    final precision = int.tryParse(_precisionController.text) ?? 2;
    setState(() => _isLoading = true);
    await _mongoService.updateUserPreferences(
      widget.user.id!,
      _selectedLanguage,
      precision,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Paramètres enregistrés avec succès')),
    );
  }

  void _handlePendingAction() {
    if (_pendingSessions.isEmpty) return;

    if (_pendingSessions.length == 1) {
      final session = _pendingSessions.first;
      final lot = Lot.fromMap(session['lot']);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeightEntryScreen(
            user: widget.user,
            lot: lot,
            operator: session['operator'],
            building: session['building'],
            room: session['room'],
            age: session['age'],
            minWeight: session['minWeight'].toDouble(),
            maxWeight: session['maxWeight'].toDouble(),
            precision: session['precision'],
            initialWeights: List<double>.from(session['weights'].map((x) => x.toDouble())),
          ),
        ),
      ).then((_) => _checkPendingSessions());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PendingSessionsScreen(user: widget.user)),
      ).then((_) => _checkPendingSessions());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: !isDesktop,
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'ACCUEIL' : 'PARAMÈTRES',
          style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 18)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.orange),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : isDesktop
              ? Row(
                  children: [
                    _buildSideNavBar(),
                    Expanded(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: [
                          _buildHome(),
                          _buildSettings(),
                        ],
                      ),
                    ),
                  ],
                )
              : IndexedStack(
                  index: _currentIndex,
                  children: [
                    _buildHome(),
                    _buildSettings(),
                  ],
                ),
      bottomNavigationBar: isDesktop ? null : _buildUserNavBar(),
    );
  }

  Widget _buildSideNavBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 0, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: NavigationRail(
          backgroundColor: Colors.transparent,
          selectedIndex: _currentIndex,
          onDestinationSelected: (index) => setState(() => _currentIndex = index),
          extended: true,
          minExtendedWidth: 190,
          indicatorColor: Colors.orange.withValues(alpha: 0.1),
          selectedIconTheme: const IconThemeData(color: Colors.orange, size: 22),
          unselectedIconTheme: IconThemeData(color: Colors.grey[600], size: 22),
          selectedLabelTextStyle: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelTextStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
          destinations: const [
            NavigationRailDestination(icon: Icon(Icons.home_rounded), label: Text('Accueil')),
            NavigationRailDestination(icon: Icon(Icons.settings_rounded), label: Text('Paramètres')),
          ],
        ),
      ),
    );
  }

  Widget _buildHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pendingSessions.isNotEmpty) _buildPendingSessionAlert(),
          _buildHeaderCard(),
          const SizedBox(height: 32),
          
          const Text('VOS RÉGLAGES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.grey, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildInfoCard(Icons.scale, 'Précision', '${_precisionController.text} déc.'),
              const SizedBox(width: 16),
              _buildInfoCard(Icons.language, 'Langue', _selectedLanguage.toUpperCase()),
            ],
          ),
          
          const SizedBox(height: 32),
          const Text('ACTIONS RAPIDES', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.grey, letterSpacing: 1.2)),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildQuickAction(
                Icons.add_circle_outline, 
                'Nouvelle Pesée', 
                Colors.blue,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewWeighingScreen(user: widget.user))).then((_) => _checkPendingSessions()),
              ),
              const SizedBox(width: 16),
              _buildQuickAction(
                Icons.history_rounded, 
                'Historique', 
                Colors.green,
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UserHistoryScreen(user: widget.user))),
              ),
            ],
          ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bienvenue,', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text(widget.user.name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_currentTime, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                  Text(_currentDateStr, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text('SITE DE PRODUCTION', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          const SizedBox(height: 4),
          Text(
            _assignedFarm?.name ?? 'En attente...',
            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.orange, size: 28),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
            Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
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
          padding: const EdgeInsets.symmetric(vertical: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Column(
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

  Widget _buildPendingSessionAlert() {
    final int count = _pendingSessions.length;
    final String message = count == 1 
        ? 'Une pesée interrompue pour le lot ${_pendingSessions.first['lot']['number']}'
        : '$count pesées interrompues en attente';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _handlePendingAction,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade400,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.timer_outlined, color: Colors.white, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          count == 1 ? 'PESÉE INTERROMPUE !' : 'PESÉES INTERROMPUES !',
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          message,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, color: Colors.red, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettings() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('PRÉFÉRENCES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(height: 24),
          _buildSettingCard(
            title: 'Langue',
            icon: Icons.language,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLanguage,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'fr', child: Text('Français')),
                  DropdownMenuItem(value: 'en', child: Text('English')),
                ],
                onChanged: (val) => setState(() => _selectedLanguage = val!),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildSettingCard(
            title: 'Précision de la balance',
            icon: Icons.settings_input_component,
            child: TextField(
              controller: _precisionController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'Entrez un nombre (ex: 2)',
                border: InputBorder.none,
                suffixText: 'décimales',
              ),
            ),
          ),
          const SizedBox(height: 48),
          SizedBox(
            width: double.infinity,
            height: 55,
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: const Text('ENREGISTRER LES MODIFICATIONS', style: TextStyle(letterSpacing: 1.1, color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSettingCard({required String title, required IconData icon, required Widget child}) {
    return Container(
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
          Row(
            children: [
              Icon(icon, color: Colors.orange, size: 20),
              const SizedBox(width: 10),
              Text(title, style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildUserNavBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(30, 0, 30, 30),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(35),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: GNav(
          gap: 10,
          activeColor: Colors.orange,
          iconSize: 24,
          padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
          duration: const Duration(milliseconds: 400),
          tabBackgroundColor: Colors.orange.withValues(alpha: 0.1),
          color: Colors.grey[400],
          tabs: const [
            GButton(icon: Icons.home_rounded, text: 'Accueil'),
            GButton(icon: Icons.settings_rounded, text: 'Paramètres'),
          ],
          onTabChange: (index) => setState(() => _currentIndex = index),
        ),
      ),
    );
  }
}
