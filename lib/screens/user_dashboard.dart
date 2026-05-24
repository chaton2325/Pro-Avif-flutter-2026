import 'package:flutter/material.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import '../models/user.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';
import 'login_screen.dart';

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
  
  // Settings controllers
  late String _selectedLanguage;
  final TextEditingController _precisionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.user.language;
    _precisionController.text = widget.user.scalePrecision.toString();
    _loadData();
  }

  @override
  void dispose() {
    _precisionController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'ACCUEIL' : 'PARAMÈTRES', 
          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.orange),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : IndexedStack(
              index: _currentIndex,
              children: [
                _buildHome(),
                _buildSettings(),
              ],
            ),
      bottomNavigationBar: _buildUserNavBar(),
    );
  }

  Widget _buildHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Card (Integrated Profile + Farm)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.orange.shade600, Colors.orangeAccent.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(color: Colors.orange.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      child: const Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Bienvenue,', style: TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(
                          widget.user.name,
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('SITE DE PRODUCTION', style: TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.agriculture, color: Colors.white, size: 24),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _assignedFarm?.name ?? 'En attente...',
                        style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          
          const Text('VOS RÉGLAGES ACTUELS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey, letterSpacing: 1.1)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoCard(Icons.scale, 'Précision', '${_precisionController.text} déc.'),
              const SizedBox(width: 16),
              _buildInfoCard(Icons.language, 'Langue', _selectedLanguage.toUpperCase()),
            ],
          ),
          const SizedBox(height: 32),
          
          const Text('ACTIONS RAPIDES', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey, letterSpacing: 1.1)),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildQuickAction(Icons.add_shopping_cart, 'Nouvelle Pesée', Colors.blue),
              const SizedBox(width: 16),
              _buildQuickAction(Icons.bar_chart, 'Rapports', Colors.green),
            ],
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildInfoCard(IconData icon, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.orange, size: 24),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickAction(IconData icon, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
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
          
          // Language Setting
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
          
          // Precision Setting
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              child: const Text('ENREGISTRER LES MODIFICATIONS', style: TextStyle(letterSpacing: 1.1)),
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
        border: Border.all(color: Colors.grey.shade200),
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
