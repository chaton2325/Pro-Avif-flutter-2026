import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'admin_farm_staff_screen.dart';
import 'admin_feed_receptions_screen.dart';
import 'admin_farm_feed_stocks_screen.dart';
import 'admin_lot_headcounts_screen.dart';
import 'admin_treatment_references_screen.dart';
import 'building_tracking_screen.dart';
import 'validator_overview_screen.dart';

/// Point d'entrée admin du module Rapport Journalier : l'administrateur a accès complet aux
/// deux modules (cahier des charges section 4) — tableau de suivi + tous les référentiels.
class AdminDailyReportHubScreen extends StatelessWidget {
  const AdminDailyReportHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = [
      (
        icon: Icons.fact_check_rounded,
        color: DailyReportColors.green700,
        title: 'Tableau de suivi',
        subtitle: 'Valider ou renvoyer les rapports du jour',
        builder: (BuildContext c) => ValidatorOverviewScreen(user: MongoService().currentUser!),
      ),
      (
        icon: Icons.insights_rounded,
        color: DailyReportColors.green900,
        title: 'Suivi bâtiment',
        subtitle: 'Effectifs & aliments : ce qui reste, par ferme',
        builder: (BuildContext c) => const BuildingTrackingScreen(),
      ),
      (
        icon: Icons.local_shipping_rounded,
        color: DailyReportColors.yellow600,
        title: 'Réceptions — toutes fermes',
        subtitle: 'En attente et historique, tous bâtiments',
        builder: (BuildContext c) => const AdminFeedReceptionsScreen(),
      ),
      (
        icon: Icons.groups_rounded,
        color: DailyReportColors.green600,
        title: 'Effectifs de départ',
        subtitle: "Saisir l'effectif initial d'un lot",
        builder: (BuildContext c) => const AdminLotHeadcountsScreen(),
      ),
      (
        icon: Icons.grain_rounded,
        color: DailyReportColors.yellow500,
        title: 'Aliments de départ',
        subtitle: "Saisir le stock d'aliment initial d'une ferme",
        builder: (BuildContext c) => const AdminFarmFeedStocksScreen(),
      ),
      (
        icon: Icons.medical_services_rounded,
        color: DailyReportColors.green900,
        title: 'Vaccins & médicaments',
        subtitle: 'Référentiel des traitements',
        builder: (BuildContext c) => const AdminTreatmentReferencesScreen(),
      ),
      (
        icon: Icons.badge_rounded,
        color: DailyReportColors.green700,
        title: 'Personnel',
        subtitle: 'Personnel affecté par ferme',
        builder: (BuildContext c) => const AdminFarmStaffScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Rapport Journalier', subtitle: 'Espace administrateur'),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final e = entries[i];
          return DailyReportMenuTile(
            icon: e.icon,
            color: e.color,
            title: e.title,
            subtitle: e.subtitle,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: e.builder)),
          );
        },
      ),
    );
  }
}
