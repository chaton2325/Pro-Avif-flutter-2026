import 'package:flutter/material.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'admin_daily_report_users_screen.dart';
import 'admin_farm_staff_screen.dart';
import 'admin_farms_settings_screen.dart';
import 'admin_hatcheries_screen.dart';
import 'admin_treatment_references_screen.dart';

/// Onglet « Paramètres » du hub admin du Rapport Journalier : référentiels rarement modifiés
/// (bâtiments, personnel, utilisateurs, couvoirs, traitements).
class AdminDailyReportSettingsTab extends StatelessWidget {
  const AdminDailyReportSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        icon: Icons.home_work_rounded,
        color: DailyReportColors.green600,
        title: 'Bâtiments',
        subtitle: 'En production ou non, lot en cours',
        builder: (BuildContext c) => const AdminFarmsSettingsScreen(),
      ),
      (
        icon: Icons.badge_rounded,
        color: DailyReportColors.green700,
        title: 'Personnel',
        subtitle: 'Créer, affecter, gérer par ferme',
        builder: (BuildContext c) => const AdminFarmStaffScreen(),
      ),
      (
        icon: Icons.admin_panel_settings_rounded,
        color: DailyReportColors.green900,
        title: 'Utilisateurs',
        subtitle: 'Comptes rédacteurs & validateurs, accès expéditions',
        builder: (BuildContext c) => const AdminDailyReportUsersScreen(),
      ),
      (
        icon: Icons.egg_rounded,
        color: DailyReportColors.blue600,
        title: 'Couvoirs',
        subtitle: 'Vers où sont expédiés les œufs à couver',
        builder: (BuildContext c) => const AdminHatcheriesScreen(),
      ),
      (
        icon: Icons.medical_services_rounded,
        color: DailyReportColors.blue600,
        title: 'Vaccins & médicaments',
        subtitle: 'Référentiel des traitements',
        builder: (BuildContext c) => const AdminTreatmentReferencesScreen(),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final tileWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final e in items)
                  SizedBox(
                    width: tileWidth,
                    child: DailyReportSquareMenuTile(
                      icon: e.icon,
                      color: e.color,
                      title: e.title,
                      subtitle: e.subtitle,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: e.builder)),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
