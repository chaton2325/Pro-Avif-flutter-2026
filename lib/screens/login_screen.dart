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
    if (!MongoService().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur de connexion : ${MongoService().connectionError ?? "Base de données non joignable"}'),
          backgroundColor: Colors.red,
        ),
      );
      setState(() => _isLoading = true);
      try {
        await MongoService().connect();
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
      final user = await MongoService().login(
        _nameController.text,
        _passwordController.text,
      );
      
      if (!mounted) return;
      setState(() => _isLoading = false);

      if (user != null) {
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
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.agriculture, size: 100, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'PRO-AVIF',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const Text(
                'Gestion de Fermes',
                style: TextStyle(color: Colors.grey, fontSize: 18),
              ),
              const SizedBox(height: 60),
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nom d\'utilisateur',
                  prefixIcon: const Icon(Icons.person, color: Colors.orange),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Mot de passe',
                  prefixIcon: const Icon(Icons.lock, color: Colors.orange),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.orange)
                  : SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: _login,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 2,
                        ),
                        child: const Text('SE CONNECTER', style: TextStyle(fontSize: 16, letterSpacing: 1.2)),
                      ),
                    ),
              const SizedBox(height: 32),
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
                    style: TextStyle(color: connected ? Colors.green : Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              if (!connected)
                TextButton(
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    try {
                      await MongoService().connect();
                    } catch (e) {}
                    setState(() => _isLoading = false);
                  },
                  child: const Text('Réessayer la connexion', style: TextStyle(color: Colors.orange)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
