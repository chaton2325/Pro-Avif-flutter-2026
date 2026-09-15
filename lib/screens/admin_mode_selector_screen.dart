import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import 'admin_dashboard.dart';
import 'admin_daily_report_hub_screen.dart';
import 'usine_admin_screen.dart';
import 'login_screen.dart';

/// Premier écran après connexion admin : au lieu de retomber directement dans l'immense
/// tableau de bord Fermes (utilisateurs, pesées, analyses, licence...), l'admin choisit
/// d'abord de quel côté il travaille. "Fermes" ouvre exactement ce tableau de bord tel
/// quel ; "Usine" ouvre l'administration transverse du module Usine Aliment (usines,
/// postes, utilisateurs usine, affectations) — le suivi opérationnel usine (stock,
/// livraisons, production) reste accessible en se connectant directement avec un compte
/// usine, pas dupliqué ici ; "Rapport Journalier" ouvre le tableau de suivi + les
/// référentiels de ce module (l'admin a accès complet aux deux modules ferme).
/// Aucun des écrans de destination existants n'est modifié — seul le point d'entrée change.
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
      _ModeCard(
        icon: Icons.assignment_rounded,
        color: DailyReportColors.green700,
        title: 'Rapport Journalier',
        subtitle: 'Suivi, validation, effectifs, référentiels',
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminDailyReportHubScreen()),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/images/logo.png',
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Bonjour, $adminName',
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Que voulez-vous gérer aujourd\'hui ?',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 22),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                    childAspectRatio: 0.92,
                    children: cards,
                  ),
                ],
              ),
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
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withValues(alpha: 0.15), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [color, color.withValues(alpha: 0.7)],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5, height: 1.2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
