import 'package:flutter/material.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
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
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 8, 16, 28),
              decoration: const BoxDecoration(
                gradient: dailyReportHeaderGradient,
                borderRadius: BorderRadius.only(bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Pro Avif',
                          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12.5, letterSpacing: 1.2),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout, color: Colors.white70, size: 20),
                        onPressed: () => _logout(context),
                        tooltip: 'Déconnexion',
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Bonjour, ${user.name}',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 24, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choisissez un espace de travail',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 13.5),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      children: [
                        DailyReportMenuTile(
                          icon: Icons.monitor_weight_outlined,
                          color: Colors.orange.shade700,
                          title: 'Pesées',
                          subtitle: 'Suivi hebdomadaire des poids',
                          tag: 'EXISTANT',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => UserDashboard(user: user)),
                          ),
                        ),
                        const SizedBox(height: 16),
                        DailyReportMenuTile(
                          icon: Icons.assignment_outlined,
                          color: DailyReportColors.green700,
                          title: 'Rapport Journalier',
                          subtitle: 'Aliment, mortalité, production, personnel',
                          tag: 'NOUVEAU',
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => DailyReportHomeScreen(user: user)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
