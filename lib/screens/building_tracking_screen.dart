import 'package:flutter/material.dart';
import '../models/building_tracking.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'building_tracking_detail_screen.dart';

enum _BtSort { alpha, mortality, stockDays, lot }

// Seuils d'alerte volontairement simples (pas de règle métier fournie pour l'instant) :
// à ajuster si l'équipe donne des seuils précis pour la mortalité et l'autonomie en jours.
const _mortalityWarning = 2.0;
const _mortalityCritical = 5.0;
const _stockDaysWarning = 7.0;
const _stockDaysCritical = 3.0;

/// Suivi bâtiment : comment effectif et stock d'aliment s'écoulent depuis le départ, ferme
/// par ferme — les mortalités et consommations saisies chaque jour dans le rapport journalier
/// diminuent respectivement l'effectif de départ et le stock d'aliment de départ. Vue de
/// lecture uniquement, recalculée à la demande (GET /daily-reports/building-tracking).
class BuildingTrackingScreen extends StatefulWidget {
  const BuildingTrackingScreen({super.key});

  @override
  State<BuildingTrackingScreen> createState() => _BuildingTrackingScreenState();
}

class _BuildingTrackingScreenState extends State<BuildingTrackingScreen> {
  final MongoService _mongoService = MongoService();
  List<BuildingTrackingItem> _items = [];
  bool _loading = true;
  _BtSort _sortMode = _BtSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  bool _isAlert(BuildingTrackingItem i) =>
      i.hasReports &&
      (i.mortalityRatePercent >= _mortalityCritical ||
          (i.securityStockDays != null && i.securityStockDays! < _stockDaysCritical));

  List<BuildingTrackingItem> get _visible {
    var list = _items;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((i) => i.farmName.toLowerCase().contains(q)).toList();
    } else {
      list = List.of(list);
    }
    switch (_sortMode) {
      case _BtSort.alpha:
        list.sort((a, b) => a.farmName.toLowerCase().compareTo(b.farmName.toLowerCase()));
      case _BtSort.mortality:
        list.sort((a, b) => b.mortalityRatePercent.compareTo(a.mortalityRatePercent));
      case _BtSort.stockDays:
        list.sort((a, b) {
          final da = a.securityStockDays ?? double.infinity;
          final db = b.securityStockDays ?? double.infinity;
          return da.compareTo(db);
        });
      case _BtSort.lot:
        list.sort((a, b) => (a.lotNumber ?? '').compareTo(b.lotNumber ?? ''));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await _mongoService.getBuildingTracking();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final alertCount = _items.where(_isAlert).length;
    final okCount = _items.length - alertCount;

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Suivi bâtiment', subtitle: 'Effectifs & aliments par ferme'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$alertCount',
                          label: 'En alerte',
                          color: Colors.red.shade700,
                          icon: Icons.warning_amber_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$okCount',
                          label: 'Sous contrôle',
                          color: DailyReportColors.green700,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const DailyReportSectionLabel('Par ferme'),
                  DailySearchSortBar<_BtSort>(
                    controller: _searchController,
                    hintText: 'Rechercher un bâtiment…',
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    sortValue: _sortMode,
                    onSortChanged: (v) => setState(() => _sortMode = v),
                    sortOptions: const [
                      DailySortOption(_BtSort.alpha, 'Alphabétique (A→Z)'),
                      DailySortOption(_BtSort.mortality, 'Mortalité la plus élevée'),
                      DailySortOption(_BtSort.stockDays, 'Autonomie la plus faible'),
                      DailySortOption(_BtSort.lot, 'Numéro de lot'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else
                    for (final item in _visible) _farmCard(item),
                ],
              ),
            ),
    );
  }

  Widget _farmCard(BuildingTrackingItem item) {
    final alert = _isAlert(item);
    return DailyReportCard(
      accentColor: alert ? Colors.red.shade600 : DailyReportColors.green600,
      margin: const EdgeInsets.only(bottom: 12),
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => BuildingTrackingDetailScreen(item: item)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(item.farmName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  if (alert) ...[
                    const DailyReportStatusBadge(label: 'ALERTE', color: Colors.red, icon: Icons.priority_high_rounded, solid: true),
                    const SizedBox(width: 6),
                  ],
                  Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                [
                  if (item.lotNumber != null) 'Lot ${item.lotNumber}',
                  if (item.ageDays != null) 'Âge ${item.ageDays}j (S${item.ageWeeks})',
                  if (!item.hasReports) 'Aucun rapport encore soumis',
                ].join(' · '),
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
              ),
              const SizedBox(height: 14),
              _metricRow(
                icon: Icons.groups_rounded,
                label: 'Effectif',
                current: '${item.currentTotal}',
                initial: '${item.initialTotal}',
                fraction: item.initialTotal > 0 ? item.currentTotal / item.initialTotal : 1,
                barColor: item.mortalityRatePercent >= _mortalityCritical
                    ? Colors.red.shade600
                    : item.mortalityRatePercent >= _mortalityWarning
                        ? DailyReportColors.yellow600
                        : DailyReportColors.green600,
                trailing: 'Mortalité ${item.mortalityRatePercent.toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 10),
              _metricRow(
                icon: Icons.grain_rounded,
                label: 'Aliment',
                current: '${item.currentFeedStockKg.toStringAsFixed(item.currentFeedStockKg == item.currentFeedStockKg.roundToDouble() ? 0 : 1)} kg',
                initial: '${item.initialFeedStockKg.toStringAsFixed(item.initialFeedStockKg == item.initialFeedStockKg.roundToDouble() ? 0 : 1)} kg',
                fraction: item.initialFeedStockKg > 0 ? item.currentFeedStockKg / item.initialFeedStockKg : 1,
                barColor: item.securityStockDays == null
                    ? Colors.grey.shade400
                    : item.securityStockDays! < _stockDaysCritical
                        ? Colors.red.shade600
                        : item.securityStockDays! < _stockDaysWarning
                            ? DailyReportColors.yellow600
                            : DailyReportColors.green600,
                trailing: item.securityStockDays != null ? 'Autonomie ${item.securityStockDays!.toStringAsFixed(1)} j' : 'Autonomie —',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _metricRow({
    required IconData icon,
    required String label,
    required String current,
    required String initial,
    required double fraction,
    required Color barColor,
    required String trailing,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
            const Spacer(),
            Text('$current / $initial', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
          ],
        ),
        const SizedBox(height: 6),
        _ProgressBar(fraction: fraction, color: barColor),
        const SizedBox(height: 4),
        Text(trailing, style: TextStyle(fontSize: 10.5, color: barColor, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Barre de progression simple (piste grise + remplissage coloré, coins arrondis) — pas de
/// dépendance externe, juste ce qu'il faut pour visualiser une fraction 0-1 d'un coup d'œil.
class _ProgressBar extends StatelessWidget {
  final double fraction;
  final Color color;
  const _ProgressBar({required this.fraction, required this.color});

  @override
  Widget build(BuildContext context) {
    final clamped = fraction.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              Container(height: 7, color: Colors.grey.shade200),
              Container(height: 7, width: constraints.maxWidth * clamped, color: color),
            ],
          );
        },
      ),
    );
  }
}
