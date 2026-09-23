import 'package:flutter/material.dart';
import '../models/usine.dart';
import '../models/usine_user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'login_screen.dart';
import 'usine_home_screen.dart';
import 'daily_report_validator_home_screen.dart';

/// Écran de choix de module pour un utilisateur usine qui a accès aux deux :
/// - Usine Aliment (modules production, stock, livraisons...)
/// - Validations Expéditions (validation expéditions œufs vers couvoir)
class UsineModuleChoiceScreen extends StatelessWidget {
  final UsineUser user;

  const UsineModuleChoiceScreen({super.key, required this.user});

  void _logout(BuildContext context) {
    MongoService().logoutUsineUser();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  Future<void> _enterUsine(BuildContext context, Usine usine) async {
    final mongoService = MongoService();
    final permissions = await mongoService.getEffectivePermissions(
      user.id!,
      usineId: usine.id,
    );
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => UsineHomeScreen(
          usine: usine,
          usineUser: user,
          permissions: permissions,
        ),
      ),
    );
  }

  Future<void> _enterValidator(BuildContext context, Usine usine) async {
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DailyReportValidatorHomeScreen(
          usineUser: user,
          usine: usine,
        ),
      ),
    );
  }

  Future<void> _pickUsineAndEnter(
    BuildContext context,
    Future<void> Function(BuildContext, Usine) onEnter,
  ) async {
    final mongoService = MongoService();
    final assignments = await mongoService.getPosteAssignments(userId: user.id);
    final usines = await mongoService.getUsines();
    final usineIds = assignments.map((a) => a.usineId).toSet().toList();
    final assignedUsines = usines.where((u) => usineIds.contains(u.id)).toList();

    if (!context.mounted) return;
    if (assignedUsines.length == 1) {
      await onEnter(context, assignedUsines.first);
    } else {
      _showUsinePicker(context, assignedUsines, onEnter);
    }
  }

  void _showUsinePicker(
    BuildContext context,
    List<Usine> usines,
    Future<void> Function(BuildContext, Usine) onEnter,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Choisissez une usine',
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: usines
                .map(
                  (u) => ListTile(
                    leading: const Icon(Icons.factory_rounded, color: Colors.orange),
                    title: Text(u.name),
                    onTap: () {
                      Navigator.pop(context);
                      onEnter(context, u);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
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
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Pro Avif',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            letterSpacing: 1.2,
                          ),
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
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Choisissez un espace de travail',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 13.5,
                    ),
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
                          icon: Icons.factory_outlined,
                          color: Colors.orange.shade700,
                          title: 'Usine Aliment',
                          subtitle: 'Production, stock, livraisons, référentiel...',
                          tag: 'MODULE USINE',
                          onTap: () => _pickUsineAndEnter(context, _enterUsine),
                        ),
                        const SizedBox(height: 16),
                        DailyReportMenuTile(
                          icon: Icons.egg_rounded,
                          color: DailyReportColors.purple600,
                          title: 'Validations Expéditions',
                          subtitle: 'Valider les expéditions d\'œufs vers couvoir',
                          tag: 'VALIDATION ŒUFS',
                          onTap: () => _pickUsineAndEnter(context, _enterValidator),
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