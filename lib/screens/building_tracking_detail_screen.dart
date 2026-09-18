import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/building_tracking.dart';
import '../models/farm_daily_report.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

const _pageSize = 20;

// Mortalité = rouge (cohérent avec le reste de l'écran de suivi bâtiment), deux nuances
// pour distinguer femelles/mâles ; aliment = jaune (couleur déjà associée à ce domaine dans
// tout le module Rapport Journalier). Une seule teinte par série, jamais recolorée par valeur.
const _consumptionColor = DailyReportColors.yellow600;
final _mortalityFemaleColor = Colors.red.shade400;
final _mortalityMaleColor = Colors.red.shade800;

/// Détail du suivi bâtiment pour une ferme : le récapitulatif (effectif/stock actuels vs
/// départ) en tête, puis l'historique jour par jour du lot en cours — paginé (bouton
/// "Charger plus"), même pattern que les écrans d'historique effectifs/aliments de départ.
class BuildingTrackingDetailScreen extends StatefulWidget {
  final BuildingTrackingItem item;

  const BuildingTrackingDetailScreen({super.key, required this.item});

  @override
  State<BuildingTrackingDetailScreen> createState() => _BuildingTrackingDetailScreenState();
}

class _BuildingTrackingDetailScreenState extends State<BuildingTrackingDetailScreen> {
  final MongoService _mongoService = MongoService();
  List<FarmDailyReport> _reports = [];
  List<WeeklyTrackingPoint> _weeklyPoints = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  int _totalCount = 0;
  // null = toutes les salles cumulées ; sinon filtre les deux graphiques sur une salle
  // précise (utile pour repérer où la mortalité ou la consommation se concentre).
  String? _selectedRoom;

  bool get _hasMore => _reports.length < _totalCount;

  List<String> get _availableRooms {
    final rooms = <String>{};
    for (final p in _weeklyPoints) {
      for (final r in p.byRoom) {
        rooms.add(r.roomName);
      }
    }
    final list = rooms.toList()..sort();
    return list;
  }

  double _consumedFor(WeeklyTrackingPoint p) =>
      _selectedRoom == null ? p.totalConsumedKg : (p.roomValue(_selectedRoom!)?.totalConsumedKg ?? 0);

  int _femaleMortalityFor(WeeklyTrackingPoint p) =>
      _selectedRoom == null ? p.mortalityFemale : (p.roomValue(_selectedRoom!)?.mortalityFemale ?? 0);

  int _maleMortalityFor(WeeklyTrackingPoint p) =>
      _selectedRoom == null ? p.mortalityMale : (p.roomValue(_selectedRoom!)?.mortalityMale ?? 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final history = await _mongoService.getBuildingTrackingHistory(
      widget.item.farmId,
      lotNumber: widget.item.lotNumber,
      skip: 0,
      limit: _pageSize,
    );
    final weeklyPoints = await _mongoService.getBuildingTrackingWeeklyChart(
      widget.item.farmId,
      lotNumber: widget.item.lotNumber,
    );
    if (!mounted) return;
    setState(() {
      _reports = history.data;
      _totalCount = history.totalCount;
      _weeklyPoints = weeklyPoints;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final result = await _mongoService.getBuildingTrackingHistory(
      widget.item.farmId,
      lotNumber: widget.item.lotNumber,
      skip: _reports.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _reports = [..._reports, ...result.data];
      _totalCount = result.totalCount;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(item.farmName, subtitle: item.lotNumber != null ? 'Lot ${item.lotNumber}' : 'Suivi bâtiment'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCard(item),
                  const SizedBox(height: 18),
                  if (_availableRooms.length > 1) ...[
                    DailyReportSectionLabel('Filtrer les graphiques par salle', icon: Icons.meeting_room_rounded),
                    _roomFilterChips(),
                    const SizedBox(height: 10),
                  ],
                  DailyReportSectionLabel('Consommation par semaine d\'âge', icon: Icons.show_chart_rounded),
                  _consumptionChartCard(),
                  const SizedBox(height: 18),
                  DailyReportSectionLabel('Mortalité par semaine d\'âge', icon: Icons.show_chart_rounded),
                  _mortalityChartCard(),
                  const SizedBox(height: 18),
                  DailyReportSectionLabel('Jour par jour ($_totalCount)', icon: Icons.event_note_rounded),
                  if (_reports.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Aucun rapport pour ce lot.', style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else ...[
                    for (final r in _reports) _dayCard(r),
                    if (_hasMore)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Center(
                          child: _loadingMore
                              ? const CircularProgressIndicator(color: DailyReportColors.green700)
                              : OutlinedButton(
                                  onPressed: _loadMore,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: DailyReportColors.green700,
                                    side: const BorderSide(color: DailyReportColors.green600),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  child: Text('Charger plus (${_totalCount - _reports.length} restants)'),
                                ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _summaryCard(BuildingTrackingItem item) {
    return DailyReportCard(
      accentColor: DailyReportColors.green700,
      children: [
        Row(
          children: [
            Expanded(
              child: DailyReportStatTile(
                value: '${item.currentTotal}',
                label: 'Effectif actuel / ${item.initialTotal}',
                color: DailyReportColors.green700,
                icon: Icons.groups_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DailyReportStatTile(
                value: '${item.mortalityRatePercent.toStringAsFixed(1)}%',
                label: 'Mortalité cumulée',
                color: item.mortalityRatePercent >= 5 ? Colors.red.shade700 : DailyReportColors.yellow600,
                icon: Icons.trending_down_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DailyReportStatTile(
                value: '${item.currentFeedStockKg.toStringAsFixed(0)} kg',
                label: 'Stock actuel / ${item.initialFeedStockKg.toStringAsFixed(0)} kg',
                color: DailyReportColors.green600,
                icon: Icons.grain_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DailyReportStatTile(
                value: item.securityStockDays != null ? '${item.securityStockDays!.toStringAsFixed(1)} j' : '—',
                label: 'Autonomie estimée',
                color: (item.securityStockDays ?? 99) < 3 ? Colors.red.shade700 : DailyReportColors.yellow600,
                icon: Icons.hourglass_bottom_rounded,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _roomFilterChips() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _roomChip('Toutes les salles', null),
        for (final room in _availableRooms) _roomChip(room, room),
      ],
    );
  }

  Widget _roomChip(String label, String? room) {
    final selected = _selectedRoom == room;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _selectedRoom = room),
      selectedColor: DailyReportColors.green600,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w700,
        fontSize: 12,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: Colors.grey.shade300)),
    );
  }

  /// Un seul repère toutes les [step] semaines pour ne pas surcharger l'axe quand le lot
  /// dure plusieurs mois (30-50 semaines) — jamais un label par semaine dans ce cas.
  int get _weekLabelStep => (_weeklyPoints.length / 10).ceil().clamp(1, 100);

  AxisTitles _weekAxisTitles() => AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          getTitlesWidget: (value, meta) {
            final i = value.toInt();
            if (i < 0 || i >= _weeklyPoints.length || i % _weekLabelStep != 0) return const SizedBox();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('S${_weeklyPoints[i].ageWeeks}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            );
          },
        ),
      );

  Widget _emptyChartCard() {
    return DailyReportCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('Pas encore de données.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5))),
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      ],
    );
  }

  Widget _consumptionChartCard() {
    if (_weeklyPoints.isEmpty || _weeklyPoints.every((p) => _consumedFor(p) <= 0)) {
      return _emptyChartCard();
    }
    final maxY = _weeklyPoints.map(_consumedFor).reduce((a, b) => a > b ? a : b);
    return DailyReportCard(
      accentColor: _consumptionColor,
      children: [
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY <= 0 ? 1 : maxY * 1.25,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                    'S${_weeklyPoints[group.x.toInt()].ageWeeks} · ${rod.toY.toStringAsFixed(1)} kg',
                    const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: _weekAxisTitles().sideTitles),
              ),
              barGroups: [
                for (int i = 0; i < _weeklyPoints.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: _consumedFor(_weeklyPoints[i]),
                        color: _consumptionColor,
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _mortalityChartCard() {
    final hasData = _weeklyPoints.any((p) => _femaleMortalityFor(p) + _maleMortalityFor(p) > 0);
    if (_weeklyPoints.isEmpty || !hasData) {
      return _emptyChartCard();
    }
    final maxY = _weeklyPoints
        .map((p) => (_femaleMortalityFor(p) + _maleMortalityFor(p)).toDouble())
        .reduce((a, b) => a > b ? a : b);
    return DailyReportCard(
      accentColor: _mortalityMaleColor,
      children: [
        Row(
          children: [
            _legendDot(_mortalityFemaleColor, 'Femelles'),
            const SizedBox(width: 14),
            _legendDot(_mortalityMaleColor, 'Mâles'),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY <= 0 ? 1 : maxY * 1.25,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final p = _weeklyPoints[group.x.toInt()];
                    return BarTooltipItem(
                      'S${p.ageWeeks}\nFemelles : ${_femaleMortalityFor(p)}\nMâles : ${_maleMortalityFor(p)}',
                      const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(sideTitles: _weekAxisTitles().sideTitles),
              ),
              barGroups: [
                for (int i = 0; i < _weeklyPoints.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: (_femaleMortalityFor(_weeklyPoints[i]) + _maleMortalityFor(_weeklyPoints[i])).toDouble(),
                        width: 10,
                        borderRadius: BorderRadius.circular(3),
                        rodStackItems: [
                          BarChartRodStackItem(
                            0,
                            _femaleMortalityFor(_weeklyPoints[i]).toDouble(),
                            _mortalityFemaleColor,
                          ),
                          BarChartRodStackItem(
                            _femaleMortalityFor(_weeklyPoints[i]).toDouble(),
                            (_femaleMortalityFor(_weeklyPoints[i]) + _maleMortalityFor(_weeklyPoints[i])).toDouble(),
                            _mortalityMaleColor,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayCard(FarmDailyReport r) {
    final date = DateTime.tryParse(r.date);
    final dateStr = date != null ? DateFormat('EEEE dd/MM/yyyy', 'fr_FR').format(date) : r.date;
    final currentTotal = r.endCounts.fold<int>(0, (a, c) => a + c.femaleCount + c.maleCount) +
        r.clinicEnd.femaleCount + r.clinicEnd.maleCount;
    final mortalityToday = r.mortality.totalFemale + r.mortality.totalMale;
    return DailyReportCard(
      accentColor: mortalityToday > 0 ? DailyReportColors.yellow500 : DailyReportColors.green600,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          children: [
            Expanded(child: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            DailyReportStatusBadge(
              label: r.statusLabel.toUpperCase(),
              color: r.status == 'valide'
                  ? DailyReportColors.green600
                  : r.status == 'a_corriger'
                      ? Colors.red
                      : DailyReportColors.yellow600,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dayMetric(
                icon: Icons.groups_rounded,
                value: '$currentTotal',
                sub: mortalityToday > 0 ? '-$mortalityToday' : '±0',
                subColor: mortalityToday > 0 ? Colors.red.shade600 : Colors.grey.shade400,
              ),
            ),
            Expanded(
              child: _dayMetric(
                icon: Icons.grain_rounded,
                value: '${r.aliment.stockAfterKg.toStringAsFixed(0)} kg',
                sub: r.aliment.totalConsumedKg > 0 ? '-${r.aliment.totalConsumedKg.toStringAsFixed(1)} kg' : '±0',
                subColor: r.aliment.totalConsumedKg > 0 ? DailyReportColors.yellow600 : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dayMetric({required IconData icon, required String value, required String sub, required Color subColor}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            Text(sub, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: subColor)),
          ],
        ),
      ],
    );
  }
}
