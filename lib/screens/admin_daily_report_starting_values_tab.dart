import 'package:flutter/material.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'admin_cumuls_screen.dart';
import 'admin_farm_feed_stocks_screen.dart';
import 'admin_lot_egg_stocks_screen.dart';
import 'admin_lot_headcounts_screen.dart';

/// Onglet « Valeurs de départ » du hub admin du Rapport Journalier : tout ce que l'admin
/// saisit une fois pour démarrer le suivi d'un lot (effectifs, aliments, œufs, cumuls).
class AdminDailyReportStartingValuesTab extends StatelessWidget {
  const AdminDailyReportStartingValuesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final items = [
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
        icon: Icons.egg_rounded,
        color: DailyReportColors.purple600,
        title: "Stock d'œufs de départ",
        subtitle: "Saisir OAC/PO/DJ/CAS/SAL initiaux d'un lot",
        builder: (BuildContext c) => const AdminLotEggStocksScreen(),
      ),
      (
        icon: Icons.stacked_line_chart_rounded,
        color: DailyReportColors.purple600,
        title: 'Cumuls de départ',
        subtitle: "S'ajoutent au cumul existant — aliments et œufs",
        builder: (BuildContext c) => const AdminCumulsScreen(),
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
