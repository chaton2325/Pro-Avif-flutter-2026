import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import 'login_screen.dart';

/// Écran affiché lorsque l'administrateur a bloqué l'accès à l'application
/// (essai terminé, licence expirée, non-paiement, etc.).
class BlockedScreen extends StatefulWidget {
  final String reason;

  const BlockedScreen({super.key, required this.reason});

  @override
  State<BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<BlockedScreen> {
  bool _checking = false;

  Future<void> _retry() async {
    setState(() => _checking = true);
    final status = await MongoService().getLicenseStatus();
    if (!mounted) return;
    setState(() => _checking = false);

    if (status['is_blocked'] != true) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("L'application est toujours bloquée.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.lock_outline, size: 64, color: Colors.red.shade400),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Accès indisponible',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.reason,
                  style: const TextStyle(fontSize: 15, color: Colors.grey, height: 1.4),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Veuillez contacter votre administrateur pour renouveler l\'accès.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                _checking
                    ? const CircularProgressIndicator(color: Colors.orange)
                    : SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh, color: Colors.orange),
                          label: const Text('Réessayer', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.orange, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
