import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import 'blocked_screen.dart';
import 'login_screen.dart';

/// Vérifie le statut de licence global avant d'afficher l'écran de connexion,
/// afin qu'un utilisateur bloqué par l'administrateur voie directement la raison.
class SplashGateScreen extends StatefulWidget {
  const SplashGateScreen({super.key});

  @override
  State<SplashGateScreen> createState() => _SplashGateScreenState();
}

class _SplashGateScreenState extends State<SplashGateScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkStatus());
  }

  Future<void> _checkStatus() async {
    final status = await MongoService().getLicenseStatus();
    if (!mounted) return;

    if (status['is_blocked'] == true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => BlockedScreen(
            reason: status['block_reason'] ?? "Application bloquée par l'administrateur.",
          ),
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator(color: Colors.orange)),
    );
  }
}
