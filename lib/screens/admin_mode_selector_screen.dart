import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import '../utils/platform_utils.dart';
import 'admin_dashboard.dart';
import 'usine_admin_screen.dart';
import 'login_screen.dart';

/// Premier écran après connexion admin : au lieu de retomber directement dans l'immense
/// tableau de bord Fermes (utilisateurs, pesées, analyses, licence...), l'admin choisit
/// d'abord de quel côté il travaille. "Fermes" ouvre exactement ce tableau de bord tel
/// quel ; "Usine" ouvre l'administration transverse du module Usine Aliment (usines,
/// postes, utilisateurs usine, affectations). Aucun des deux écrans de destination n'est
/// modifié — seul le point d'entrée change.
class AdminModeSelectorScreen extends StatelessWidget {
  const AdminModeSelectorScreen({super.key});

  void _logout(BuildContext context) {
    MongoService().logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminName = MongoService().currentUser?.name ?? 'Admin';
    final cards = [
      _ModeCard(
        icon: Icons.agriculture_rounded,
        color: Colors.green.shade700,
        title: 'Fermes',
        subtitle: 'Utilisateurs, pesées, analyses, licence',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboard()),
        ),
      ),
      _ModeCard(
        icon: Icons.factory_rounded,
        color: Colors.orange.shade700,
        title: 'Usine',
        subtitle: 'Usines, postes, utilisateurs, affectations',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UsineAdminScreen()),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: Icon(Icons.logout, color: Colors.grey.shade400),
                      onPressed: () => _logout(context),
                      tooltip: 'Déconnexion',
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Bonjour, $adminName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Que voulez-vous gérer aujourd\'hui ?',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
                const SizedBox(height: 36),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 680 : 440),
                  child: isDesktop
                      ? Row(
                          children: [
                            Expanded(child: cards[0]),
                            const SizedBox(width: 24),
                            Expanded(child: cards[1]),
                          ],
                        )
                      : Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 18),
                            cards[1],
                          ],
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

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: color.withValues(alpha: 0.15),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withValues(alpha: 0.7)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Ouvrir',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_rounded, color: color, size: 15),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
