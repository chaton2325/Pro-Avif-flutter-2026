import 'package:flutter/material.dart';
import '../models/usine.dart';
import '../services/mongo_service.dart';
import 'admin_dashboard.dart';
import 'blocked_screen.dart';
import 'user_dashboard.dart';
import 'usine_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  void _login() async {
    final mongoService = MongoService();
    if (!mongoService.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de connexion : ${mongoService.connectionError ?? "Base de données non joignable"}'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = true);
      try {
        await mongoService.connect();
      } catch (e) {
        if (!mounted) return;
        setState(() => _isLoading = false);
        return;
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    }

    setState(() => _isLoading = true);
    try {
      // Un seul écran, un seul appel : le serveur cherche le couple (nom, mot de passe)
      // dans les deux collections et dit lequel a matché — jamais d'ambiguïté possible
      // (contrôle fait à la création/édition des comptes, voir credentials_taken_elsewhere).
      final accountType = await mongoService.unifiedLogin(
        _nameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (!mounted) return;

      if (accountType == 'user') {
        final user = mongoService.currentUser!;
        setState(() => _isLoading = false);
        // Sync offline data after login
        mongoService.syncOfflineSessions().then((count) {
          if (count > 0 && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$count pesées synchronisées avec succès !'), backgroundColor: Colors.green),
            );
          }
        });

        if (user.role == 'admin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboard()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => UserDashboard(user: user)),
          );
        }
      } else if (accountType == 'usine_user') {
        await _routeUsineUser();
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identifiants incorrects')),
        );
      }
    } on LicenseBlockedException catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => BlockedScreen(reason: e.reason)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
  }

  /// Post-connexion pour un utilisateur usine : retrouve son (ses) usine(s) affectée(s)
  /// et entre directement dedans (ou propose un choix s'il en a plusieurs) — jamais de
  /// vue "toutes les usines".
  Future<void> _routeUsineUser() async {
    final mongoService = MongoService();
    final user = mongoService.currentUsineUser!;
    final assignments = await mongoService.getPosteAssignments(userId: user.id);
    if (!mounted) return;

    if (assignments.isEmpty) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Aucune usine ni poste ne vous a été affecté. Contactez l'administrateur.")),
      );
      return;
    }

    final usines = await mongoService.getUsines();
    final usineIds = assignments.map((a) => a.usineId).toSet().toList();
    final assignedUsines = usines.where((u) => usineIds.contains(u.id)).toList();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (assignedUsines.length == 1) {
      await _enterUsine(user.id!, assignedUsines.first);
    } else {
      _showUsinePicker(user.id!, assignedUsines);
    }
  }

  Future<void> _enterUsine(String userId, Usine usine) async {
    final mongoService = MongoService();
    setState(() => _isLoading = true);
    final permissions = await mongoService.getEffectivePermissions(userId, usineId: usine.id);
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => UsineHomeScreen(usine: usine, usineUser: mongoService.currentUsineUser!, permissions: permissions)),
    );
  }

  void _showUsinePicker(String userId, List<Usine> usines) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Choisissez une usine', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: usines
                .map((u) => ListTile(
                      leading: const Icon(Icons.factory_rounded, color: Colors.orange),
                      title: Text(u.name),
                      onTap: () {
                        Navigator.pop(context);
                        _enterUsine(userId, u);
                      },
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool connected = MongoService().isConnected;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 88,
                    height: 88,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'PRO-AVIF',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Gestion de Fermes',
                style: TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 48),
              
              // Input fields with modern styling
              _buildTextField(controller: _nameController, label: 'Nom d\'utilisateur', icon: Icons.person),
              const SizedBox(height: 16),
              _buildTextField(controller: _passwordController, label: 'Mot de passe', icon: Icons.lock, obscure: true),
              
              const SizedBox(height: 32),
              
              // Login button
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.orange)
                  : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 4,
                          shadowColor: Colors.orange.withValues(alpha: 0.5),
                        ),
                        child: const Text('SE CONNECTER', style: TextStyle(fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
              
              const SizedBox(height: 32),

              // Status indicator
              _buildConnectionStatus(connected),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({required TextEditingController controller, required String label, required IconData icon, bool obscure = false}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.orange.shade300),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.orange, width: 2),
        ),
      ),
    );
  }

  Widget _buildConnectionStatus(bool connected) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: connected ? Colors.green : Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              connected ? 'Serveur en ligne' : 'Serveur hors ligne',
              style: TextStyle(color: connected ? Colors.green : Colors.red, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        if (!connected)
          TextButton(
            onPressed: () async {
              setState(() => _isLoading = true);
              try { await MongoService().connect(); } catch (e) {}
              setState(() => _isLoading = false);
            },
            child: const Text('Réessayer la connexion', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
