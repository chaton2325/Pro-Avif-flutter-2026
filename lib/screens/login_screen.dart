import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import 'admin_dashboard.dart';
import 'user_dashboard.dart';

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
      final user = await mongoService.login(
        _nameController.text,
        _passwordController.text,
      );
      
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (user != null) {
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
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Identifiants incorrects')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
      );
    }
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
