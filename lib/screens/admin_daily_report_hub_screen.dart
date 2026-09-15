import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import 'admin_farm_staff_screen.dart';
import 'admin_feed_receptions_screen.dart';
import 'admin_lot_headcounts_screen.dart';
import 'admin_treatment_references_screen.dart';
import 'validator_overview_screen.dart';

/// Point d'entrée admin du module Rapport Journalier : l'administrateur a accès complet aux
/// deux modules (cahier des charges section 4) — tableau de suivi + tous les référentiels.
class AdminDailyReportHubScreen extends StatelessWidget {
  const AdminDailyReportHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = [
      (
        icon: Icons.fact_check_outlined,
        title: 'Tableau de suivi',
        subtitle: 'Valider ou renvoyer les rapports du jour',
        builder: (BuildContext c) => ValidatorOverviewScreen(user: MongoService().currentUser!),
      ),
      (
        icon: Icons.local_shipping_outlined,
        title: 'Réceptions — toutes fermes',
        subtitle: "En attente et historique, tous bâtiments",
        builder: (BuildContext c) => const AdminFeedReceptionsScreen(),
      ),
      (
        icon: Icons.groups_outlined,
        title: 'Effectifs de départ',
        subtitle: "Saisir l'effectif initial d'un lot",
        builder: (BuildContext c) => const AdminLotHeadcountsScreen(),
      ),
      (
        icon: Icons.medical_services_outlined,
        title: 'Vaccins & médicaments',
        subtitle: 'Référentiel des traitements',
        builder: (BuildContext c) => const AdminTreatmentReferencesScreen(),
      ),
      (
        icon: Icons.badge_outlined,
        title: 'Personnel',
        subtitle: 'Personnel affecté par ferme',
        builder: (BuildContext c) => const AdminFarmStaffScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Rapport Journalier — Admin'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final e = entries[i];
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: e.builder)),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(e.icon, color: DailyReportColors.green700),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text(e.subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
