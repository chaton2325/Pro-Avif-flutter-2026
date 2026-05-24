import 'package:flutter/material.dart';
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
  Farm? _assignedFarm;
  bool _isLoading = true;

  void _logout() {
    MongoService().logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadFarm();
  }

  void _loadFarm() async {
    if (widget.user.farmId != null) {
      final farm = await MongoService().getFarmById(widget.user.farmId!);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TABLEAU DE BORD', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.orange),
            onPressed: _logout,
          ),
        ],
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.orange)
            : Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.orange.withOpacity(0.1),
                      child: const Icon(Icons.person, size: 70, color: Colors.orange),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Bienvenue, ${widget.user.name}!',
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4)),
                        ],
                      ),
                      child: Text(
                        widget.user.role.toUpperCase(),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 60),
                    Card(
                      elevation: 4,
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(Icons.agriculture, size: 40, color: Colors.orange),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('FERME ALLOUÉE', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                                  const SizedBox(height: 6),
                                  Text(
                                    _assignedFarm?.name ?? 'Aucune ferme assignée',
                                    style: const TextStyle(color: Colors.black87, fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
