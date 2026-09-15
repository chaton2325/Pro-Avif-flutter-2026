import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import 'daily_report_home_screen.dart';
import 'login_screen.dart';
import 'user_dashboard.dart';

/// Écran de choix d'espace après connexion (maquette écran 01) : Pesées (module existant,
/// inchangé) ou Rapport Journalier (nouveau). Tout compte "user" avec une ferme assignée
/// voit les deux — un rédacteur a toujours accès aux pesées de son bâtiment.
class ModuleChoiceScreen extends StatelessWidget {
  final User user;

  const ModuleChoiceScreen({super.key, required this.user});

  void _logout(BuildContext context) {
    MongoService().logout();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
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
                Text(
                  'Bonjour, ${user.name}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22),
                ),
                const SizedBox(height: 6),
                Text(
                  'Choisissez un espace',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
                const SizedBox(height: 32),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    children: [
                      _ModuleCard(
                        icon: Icons.monitor_weight_outlined,
                        color: Colors.orange.shade700,
                        title: 'Pesées',
                        subtitle: 'Suivi hebdo des poids',
                        tag: 'Existant',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => UserDashboard(user: user)),
                        ),
                      ),
                      const SizedBox(height: 18),
                      _ModuleCard(
                        icon: Icons.assignment_outlined,
                        color: DailyReportColors.green700,
                        title: 'Rapport Journalier',
                        subtitle: 'Aliment, mortalité, production, personnel',
                        tag: 'Nouveau',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DailyReportHomeScreen(user: user)),
                        ),
                      ),
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

class _ModuleCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String tag;
  final VoidCallback onTap;

  const _ModuleCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.tag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.25), width: 1.4),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tag,
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
