import 'package:flutter/material.dart';
import '../models/building_tracking.dart';
import '../models/cumul.dart';
import '../models/lot_headcount.dart' show RoomHeadcount;
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'building_tracking_detail_screen.dart';
import 'farm_feed_cumul_history_screen.dart';
import 'lot_egg_cumul_history_screen.dart';
import 'lot_mortality_cumul_history_screen.dart';

enum _BtSort { alpha, mortality, stockDays, lot }
enum _CumulSort { alpha, lot }

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

class _BuildingTrackingScreenState extends State<BuildingTrackingScreen> with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  List<BuildingTrackingItem> _items = [];
  bool _loading = true;
  _BtSort _sortMode = _BtSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  late final TabController _tabController;
  // Onglet "Cumul" : indépendant de la vue d'ensemble ci-dessus, ne lit jamais
  // rapports_journaliers (voir GET /cumuls/building-tracking) — chargé une seule fois.
  List<BuildingCumulItem> _cumulItems = [];
  bool _cumulLoading = true;
  _CumulSort _cumulSortMode = _CumulSort.alpha;
  final _cumulSearchController = TextEditingController();
  String _cumulSearchQuery = '';

  List<BuildingCumulItem> get _visibleCumulItems {
    var list = _cumulItems;
    if (_cumulSearchQuery.trim().isNotEmpty) {
      final q = _cumulSearchQuery.trim().toLowerCase();
      list = list.where((i) => i.farmName.toLowerCase().contains(q)).toList();
    } else {
      list = List.of(list);
    }
    switch (_cumulSortMode) {
      case _CumulSort.alpha:
        list.sort((a, b) => a.farmName.toLowerCase().compareTo(b.farmName.toLowerCase()));
      case _CumulSort.lot:
        list.sort((a, b) => (a.lotNumber ?? '').compareTo(b.lotNumber ?? ''));
    }
    return list;
  }

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
    _tabController = TabController(length: 2, vsync: this);
    _load();
    _loadCumuls();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _cumulSearchController.dispose();
    _tabController.dispose();
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

  Future<void> _loadCumuls() async {
    setState(() => _cumulLoading = true);
    final items = await _mongoService.getBuildingCumuls();
    if (!mounted) return;
    setState(() {
      _cumulItems = items;
      _cumulLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        'Suivi bâtiment',
        subtitle: 'Effectifs & aliments par ferme',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "Vue d'ensemble"),
            Tab(text: 'Cumuls'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _overviewTab(),
          _cumulsTab(),
        ],
      ),
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

  Widget _cumulsTab() {
    final totalFeedKg = _cumulItems.fold<double>(
      0,
      (a, i) => a + i.feedRooms.fold<double>(0, (b, r) => b + r.femaleKg + r.maleKg),
    );
    final totalMortality = _cumulItems.fold<int>(0, (a, i) => a + i.cumulativeMortalityFemale + i.cumulativeMortalityMale);
    final totalEggs = _cumulItems.fold<int>(
      0,
      (a, i) => a + i.rooms.fold<int>(0, (b, r) => b + r.oac + r.po + r.dj + r.cas + r.sal),
    );
    return _cumulLoading
        ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
        : RefreshIndicator(
            onRefresh: _loadCumuls,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DailyReportStatTile(
                        value: '${totalFeedKg.toStringAsFixed(totalFeedKg == totalFeedKg.roundToDouble() ? 0 : 2)} kg',
                        label: 'Aliment consommé',
                        color: DailyReportColors.purple600,
                        icon: Icons.grain_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DailyReportStatTile(
                        value: '$totalMortality',
                        label: 'Mortalité cumulée',
                        color: Colors.red.shade600,
                        icon: Icons.dangerous_outlined,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DailyReportStatTile(
                        value: '$totalEggs',
                        label: 'Œufs (cumul manuel)',
                        color: DailyReportColors.purple600,
                        icon: Icons.egg_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const DailyReportSectionLabel('Par ferme, par salle'),
                DailySearchSortBar<_CumulSort>(
                  controller: _cumulSearchController,
                  hintText: 'Rechercher un bâtiment…',
                  onSearchChanged: (v) => setState(() => _cumulSearchQuery = v),
                  sortValue: _cumulSortMode,
                  onSortChanged: (v) => setState(() => _cumulSortMode = v),
                  sortOptions: const [
                    DailySortOption(_CumulSort.alpha, 'Alphabétique (A→Z)'),
                    DailySortOption(_CumulSort.lot, 'Numéro de lot'),
                  ],
                ),
                const SizedBox(height: 12),
                if (_visibleCumulItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                  )
                else
                  for (final item in _visibleCumulItems) _cumulCard(item),
              ],
            ),
          );
  }

  Widget _cumulCard(BuildingCumulItem item) {
    final totalFeedKg = item.feedRooms.fold<double>(0, (a, r) => a + r.femaleKg + r.maleKg);
    return DailyReportCard(
      accentColor: DailyReportColors.purple600,
      margin: const EdgeInsets.only(bottom: 12),
      children: [
        Row(
          children: [
            Expanded(child: Text(item.farmName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15))),
            if (item.lotNumber != null)
              Text('Lot ${item.lotNumber}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.grain_rounded, size: 14, color: DailyReportColors.purple600),
            const SizedBox(width: 6),
            Text(
              'Consommation cumulée : ${totalFeedKg.toStringAsFixed(totalFeedKg == totalFeedKg.roundToDouble() ? 0 : 2)} kg',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: DailyReportColors.purple600),
            ),
          ],
        ),
        if (item.feedRooms.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in item.feedRooms)
                if (r.femaleKg > 0 || r.maleKg > 0) _feedCumulChip(r),
            ],
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text('Aucune consommation cumulée pour l\'instant.', style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5)),
        ],
        const SizedBox(height: 12),
        const Row(
          children: [
            Icon(Icons.egg_rounded, size: 14, color: DailyReportColors.purple600),
            SizedBox(width: 6),
            Text('Cumul œufs (manuel)', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: DailyReportColors.purple600)),
          ],
        ),
        if (item.rooms.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in item.rooms)
                if (r.oac + r.po + r.dj + r.cas + r.sal > 0) _eggCumulChip(r),
            ],
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text('Aucun cumul œufs enregistré.', style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5)),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.dangerous_outlined, size: 14, color: Colors.red),
            const SizedBox(width: 6),
            Text(
              'Mortalité cumulée : F ${item.cumulativeMortalityFemale} · M ${item.cumulativeMortalityMale}',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.red),
            ),
          ],
        ),
        if (item.mortalityRooms.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in item.mortalityRooms)
                if (r.femaleCount > 0 || r.maleCount > 0) _mortalityCumulChip(r),
            ],
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text('Aucune mortalité cumulée pour l\'instant.', style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5)),
        ],
        if (item.lotNumber != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _historyButton(
                'Aliment',
                DailyReportColors.purple600,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FarmFeedCumulHistoryScreen(farmName: item.farmName, lotNumber: item.lotNumber!)),
                ),
              ),
              _historyButton(
                'Œufs',
                DailyReportColors.purple600,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LotEggCumulHistoryScreen(farmName: item.farmName, lotNumber: item.lotNumber!)),
                ),
              ),
              _historyButton(
                'Mortalité',
                Colors.red.shade600,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => LotMortalityCumulHistoryScreen(farmName: item.farmName, lotNumber: item.lotNumber!)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _historyButton(String label, Color color, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.history_rounded, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _mortalityCumulChip(RoomHeadcount r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(
        '${r.roomName} · F ${r.femaleCount} · M ${r.maleCount}',
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.red.shade700),
      ),
    );
  }

  Widget _feedCumulChip(RoomFeedCumul r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: DailyReportColors.purple600.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(
        '${r.roomName} · ${r.formulaName ?? 'aliment non renseigné'} · F ${r.femaleKg} kg · M ${r.maleKg} kg',
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: DailyReportColors.purple600),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: DailyReportColors.green900)),
          ],
        ),
      ),
    );
  }

  Widget _eggCumulChip(RoomEggCumul r) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: DailyReportColors.purple600.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(
        '${r.roomName} · OAC ${r.oac} · PO ${r.po} · DJ ${r.dj} · CAS ${r.cas} · SAL ${r.sal}',
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: DailyReportColors.purple600),
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
                  if (!item.hasReports) 'Aucun rapport encore validé',
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
              if (item.currentRooms.isNotEmpty || item.currentClinic.femaleCount > 0 || item.currentClinic.maleCount > 0) ...[
                const SizedBox(height: 8),
                _roomBreakdown(item),
              ],
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
              if (item.hasReports && item.cumulativePo > 0) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.egg_rounded, size: 14, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text('Ponte', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                    const Spacer(),
                    Text('PO cumulé ${item.cumulativePo}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _statChip('Taux de ponte', item.layingRatePercent != null ? '${item.layingRatePercent!.toStringAsFixed(1)}%' : '—'),
                    _statChip('Indice conso.', item.feedConversionRatio != null ? '${item.feedConversionRatio!.toStringAsFixed(2)} kg/œuf' : '—'),
                    _statChip('OAC cumulé', '${item.cumulativeOac}'),
                    _statChip('DJ+CAS cumulés', '${item.cumulativeDj + item.cumulativeCas}'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Effectif actuel par salle et par sexe, directement sur la carte — pas seulement le
  /// total agrégé (important pour repérer où l'effectif se concentre).
  Widget _roomBreakdown(BuildingTrackingItem item) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in item.currentRooms)
          if (r.femaleCount > 0 || r.maleCount > 0) _roomChip(r.roomName, r.femaleCount, r.maleCount),
        if (item.currentClinic.femaleCount > 0 || item.currentClinic.maleCount > 0)
          _roomChip('Clinique', item.currentClinic.femaleCount, item.currentClinic.maleCount),
      ],
    );
  }

  Widget _roomChip(String label, int female, int male) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: DailyReportColors.green100, borderRadius: BorderRadius.circular(8)),
      child: Text(
        '$label · $female F · $male M',
        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: DailyReportColors.green900),
      ),
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
