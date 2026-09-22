import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_daily_report.dart';
import '../models/lot_headcount.dart';
import '../utils/daily_report_colors.dart';
import 'daily_report_widgets.dart';

const Map<String, String> _kStaffStatusLabels = {
  'present': 'Présent',
  'repos': 'Repos',
  'absent': 'Absent',
  'malade': 'Malade',
  'permission': 'Permission',
};

/// Contenu complet d'un rapport journalier — effectifs par salle, aliment (reçu +
/// consommation par salle et par sexe), mortalité par salle, transferts, production
/// détaillée, traitements, personnel, observation. Un SEUL endroit pour cet affichage,
/// utilisé à la fois par le rédacteur (DailyReportSummaryScreen, avant envoi) et le
/// validateur (ValidatorReportDetailScreen, avant validation/renvoi) : sans ça, les deux
/// écrans dérivent l'un de l'autre et le validateur finit par voir moins d'informations que
/// le rédacteur qui a rempli le rapport.
class DailyReportFullSummary extends StatelessWidget {
  final FarmDailyReport report;

  const DailyReportFullSummary({super.key, required this.report});

  List<RoomConsumptionEntry> _consumptionFor(String roomName) =>
      report.aliment.consumptionByRoom.where((c) => c.roomName == roomName).toList();

  /// Une couleur par aliment, stable pour tout le récapitulatif — assignée dans l'ordre de
  /// première apparition, jamais réutilisée tant qu'il reste une couleur libre dans la palette.
  Map<String, Color> get _alimentColors {
    final map = <String, Color>{};
    for (final c in report.aliment.consumptionByRoom) {
      final key = c.formulaId ?? c.formulaName ?? '?';
      map.putIfAbsent(key, () => DailyReportColors.alimentPalette[map.length % DailyReportColors.alimentPalette.length]);
    }
    return map;
  }

  RoomHeadcount? _endCountFor(String roomName) {
    for (final e in report.endCounts) {
      if (e.roomName == roomName) return e;
    }
    return null;
  }

  RoomHeadcount? _mortalityFor(String roomName) {
    for (final m in report.mortality.byRoom) {
      if (m.roomName == roomName) return m;
    }
    return null;
  }

  RoomProduction? _productionFor(String roomName) {
    for (final p in report.production) {
      if (p.roomName == roomName) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final totalFemaleProd = report.production.fold<int>(0, (a, p) => a + p.po);
    final totalFemaleEnd = report.endCounts.fold<int>(0, (a, r) => a + r.femaleCount) + report.clinicEnd.femaleCount;
    final totalMaleEnd = report.endCounts.fold<int>(0, (a, r) => a + r.maleCount) + report.clinicEnd.maleCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: DailyReportStatTile(
                value: '$totalFemaleProd',
                label: 'Prod. totale',
                color: DailyReportColors.green700,
                icon: Icons.egg_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DailyReportStatTile(
                value: '$totalFemaleEnd F · $totalMaleEnd M',
                label: 'Effectif restant',
                color: DailyReportColors.green600,
                icon: Icons.groups_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DailyReportStatTile(
                value: report.aliment.securityStockDays != null ? '${report.aliment.securityStockDays!.round()} j' : '—',
                label: 'Sécurité aliment',
                color: DailyReportColors.yellow600,
                icon: Icons.inventory_2_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),

        DailyReportSectionLabel('Effectifs par salle', icon: Icons.groups_rounded),
        DailyReportCard(children: [
          for (final start in report.startCounts) ...[
            _roomHeadcountBlock(
              start.roomName,
              start.femaleCount,
              start.maleCount,
              _endCountFor(start.roomName)?.femaleCount ?? start.femaleCount,
              _endCountFor(start.roomName)?.maleCount ?? start.maleCount,
              _mortalityFor(start.roomName)?.femaleCount ?? 0,
              _mortalityFor(start.roomName)?.maleCount ?? 0,
            ),
            const Divider(),
          ],
          _roomHeadcountBlock(
            'Clinique',
            report.clinicStart.femaleCount,
            report.clinicStart.maleCount,
            report.clinicEnd.femaleCount,
            report.clinicEnd.maleCount,
            report.mortality.clinic.femaleCount,
            report.mortality.clinic.maleCount,
          ),
        ]),

        const SizedBox(height: 16),
        DailyReportSectionLabel('Aliment', icon: Icons.grain_rounded),
        DailyReportCard(children: [
          _row('Reçu aujourd\'hui', '${report.aliment.receivedTotalKg} kg'),
          if (report.aliment.receivedDetail.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: report.aliment.receivedDetail
                    .map((d) => Chip(label: Text('${d.formulaName} · ${d.quantity} kg')))
                    .toList(),
              ),
            ),
          const Divider(),
          Text('Consommation par salle', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          for (final start in report.startCounts) _consumptionBlock(start.roomName),
          const Divider(),
          _row('Stock avant', '${report.aliment.stockBeforeKg} kg'),
          _row('Consommé (total)', '${report.aliment.totalConsumedKg} kg'),
          _row('Stock après', '${report.aliment.stockAfterKg} kg'),
        ]),

        const SizedBox(height: 16),
        DailyReportSectionLabel('Mortalité', icon: Icons.trending_down_rounded),
        DailyReportCard(
          accentColor: Colors.red.shade600,
          children: [
            _rowHighlight(
              'Aujourd\'hui (F/M)',
              '${report.mortality.totalFemale} F · ${report.mortality.totalMale} M',
            ),
            _row('Cumul (F/M)', '${report.mortality.cumulativeFemale} F · ${report.mortality.cumulativeMale} M'),
            if (report.mortality.rateFemalePercent != null || report.mortality.rateMalePercent != null)
              _row(
                'Taux cumulé (F/M)',
                '${report.mortality.rateFemalePercent?.toStringAsFixed(1) ?? "—"}% · '
                    '${report.mortality.rateMalePercent?.toStringAsFixed(1) ?? "—"}%',
              ),
            const Divider(),
            for (final m in report.mortality.byRoom)
              if (m.femaleCount > 0 || m.maleCount > 0) _row(m.roomName, '${m.femaleCount} F · ${m.maleCount} M'),
            if (report.mortality.clinic.femaleCount > 0 || report.mortality.clinic.maleCount > 0)
              _row('Clinique', '${report.mortality.clinic.femaleCount} F · ${report.mortality.clinic.maleCount} M'),
            if (report.mortality.totalFemale == 0 && report.mortality.totalMale == 0)
              Text('Aucune mortalité aujourd\'hui.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
          ],
        ),

        if (report.transfers.isNotEmpty) ...[
          const SizedBox(height: 16),
          DailyReportSectionLabel('Transferts entre salles', icon: Icons.swap_horiz_rounded),
          DailyReportCard(children: [
            for (final t in report.transfers) ...[
              _row('${t.fromRoom} → ${t.toRoom}', '${t.femaleCount} F · ${t.maleCount} M'),
            ],
          ]),
        ],

        const SizedBox(height: 16),
        DailyReportSectionLabel('Production', icon: Icons.egg_outlined),
        DailyReportCard(children: [
          for (final start in report.startCounts) ...[
            _productionBlock(start.roomName),
            const Divider(),
          ],
          _row('Eau consommée', '${report.waterLiters ?? 0} L'),
        ]),

        if (report.treatments.isNotEmpty) ...[
          const SizedBox(height: 16),
          DailyReportSectionLabel('Traitements', icon: Icons.medical_services_outlined),
          DailyReportCard(children: [
            for (final t in report.treatments) ...[
              _row(
                '${t.type} · ${t.name}',
                '${t.dose ?? "—"}${t.date != null ? " · ${DateFormat('dd/MM/yyyy').format(t.date!)}" : ""}',
              ),
            ],
          ]),
        ],

        if (report.staffStatuses.isNotEmpty) ...[
          const SizedBox(height: 16),
          DailyReportSectionLabel('Personnel', icon: Icons.badge_outlined),
          DailyReportCard(children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in report.staffStatuses)
                  Chip(
                    label: Text('${s.name} · ${_kStaffStatusLabels[s.status] ?? s.status}'),
                    backgroundColor: s.status == 'present' ? DailyReportColors.green100 : DailyReportColors.yellow100,
                  ),
              ],
            ),
          ]),
        ],

        if (report.observation != null && report.observation!.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          DailyReportSectionLabel('Observation', icon: Icons.notes_rounded),
          DailyReportCard(children: [
            Text(report.observation!, style: const TextStyle(fontSize: 13)),
          ]),
        ],
      ],
    );
  }

  /// Effectif début → fin d'une salle, avec la mortalité du jour affichée juste en dessous
  /// en rouge quand elle explique la baisse — pour ne pas avoir à aller chercher la raison
  /// dans la carte Mortalité plus bas.
  Widget _roomHeadcountBlock(String roomName, int startF, int startM, int endF, int endM, int mortF, int mortM) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
              Text(
                '$startF F · $startM M  →  $endF F · $endM M',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ],
          ),
          if (mortF > 0 || mortM > 0)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '− $mortF F · $mortM M (mortalité)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11, color: Colors.red.shade700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _consumptionBlock(String roomName) {
    final entries = _consumptionFor(roomName).where((c) => c.quantityKg > 0).toList();
    final colors = _alimentColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
          const SizedBox(height: 6),
          if (entries.isEmpty)
            Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5))
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in entries) _alimentCard(e, colors[e.formulaId ?? e.formulaName ?? '?']!),
              ],
            ),
        ],
      ),
    );
  }

  /// Une carte par aliment : nom, femelles et mâles collés ensemble (pas trois infos
  /// dispersées) — la pastille + couleur de bordure identifient l'aliment sans avoir à relire
  /// le nom quand une salle en consomme plusieurs.
  Widget _alimentCard(RoomConsumptionEntry e, Color color) {
    final hasSplit = e.femaleQuantityKg != null || e.maleQuantityKg != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(e.formulaName ?? '?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasSplit ? 'F ${e.femaleQuantityKg ?? 0} kg · M ${e.maleQuantityKg ?? 0} kg' : '${e.quantityKg} kg (non ventilé)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5),
          ),
        ],
      ),
    );
  }

  Widget _productionBlock(String roomName) {
    final p = _productionFor(roomName);
    if (p == null || (p.oac == 0 && p.po == 0 && p.dj == 0 && p.cas == 0 && p.sal == 0)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Text('—', style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5)),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(roomName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _prodMetric('OAC', '${p.oac}'),
              _prodMetric('PO', '${p.po}'),
              _prodMetric('DJ', '${p.dj}'),
              _prodMetric('CAS', '${p.cas}'),
              _prodMetric('SAL', '${p.sal}'),
              _prodMetric('TP', '${p.tpPercent.toStringAsFixed(1)}%'),
              _prodMetric('%DE', '${p.dePercent.toStringAsFixed(1)}%'),
              if (p.ecartPercent != null) _prodMetric('Écart', '${p.ecartPercent!.toStringAsFixed(1)}%'),
              _prodMetric('Cumul OAC', '${p.cumulativeOac}'),
              _prodMetric('Cumul PO', '${p.cumulativePo}'),
              _prodMetric('Cumul DJ', '${p.cumulativeDj}'),
              _prodMetric('Cumul CAS', '${p.cumulativeCas}'),
              _prodMetric('Cumul SAL', '${p.cumulativeSal}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _prodMetric(String label, String value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label ', style: TextStyle(color: Colors.grey.shade500, fontSize: 11)),
          TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );

  /// Même ligne que _row, mais la valeur ressort en rouge et plus grande — pour le chiffre
  /// qu'on doit voir en premier en ouvrant la carte Mortalité.
  Widget _rowHighlight(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))),
            Text(value, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.red.shade700)),
          ],
        ),
      );
}
