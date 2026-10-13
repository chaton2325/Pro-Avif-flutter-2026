import 'package:flutter/material.dart';
import '../models/building_tracking.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'building_dashboard_screen.dart';

enum _BtSort { alpha, mortality, stockDays, lot }

// Seuils d'alerte volontairement simples (pas de règle métier fournie pour l'instant) :
// à ajuster si l'équipe donne des seuils précis pour la mortalité et l'autonomie en jours.
const _mortalityCritical = 5.0;
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
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Suivi bâtiment', subtitle: 'Choisissez un bâtiment'),
      body: _overviewTab(),
    );
  }

  Widget _overviewTab() {
    final alertCount = _items.where(_isAlert).length;
    final okCount = _items.length - alertCount;

    return _loading
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
            );
  }

  /// Ligne compacte : le détail complet du bâtiment est sur son tableau de bord
  /// (BuildingDashboardScreen), ouvert au toucher.
  Widget _farmCard(BuildingTrackingItem item) {
    final alert = _isAlert(item);
    final accent = alert ? Colors.red.shade600 : DailyReportColors.green600;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        elevation: 1,
        shadowColor: accent.withValues(alpha: 0.3),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => BuildingDashboardScreen(item: item)),
            );
            if (mounted) _load();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 40,
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.farmName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 2),
                      Text(
                        [
                          'Lot ${item.lotNumber ?? "non défini"}',
                          if (item.ageDays != null) '${item.ageDays} j',
                          '${item.currentTotal} sujets',
                        ].join(' · '),
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                if (alert) ...[
                  const DailyReportStatusBadge(label: 'ALERTE', color: Colors.red, icon: Icons.priority_high_rounded, solid: true),
                  const SizedBox(width: 6),
                ],
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
