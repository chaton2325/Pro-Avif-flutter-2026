import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../models/building_tracking.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'building_tracking_day_by_day_screen.dart';
import 'room_transfer_history_screen.dart';

// Mortalité = rouge (cohérent avec le reste de l'écran de suivi bâtiment), deux nuances
// pour distinguer femelles/mâles ; aliment = jaune (couleur déjà associée à ce domaine dans
// tout le module Rapport Journalier). Une seule teinte par série, jamais recolorée par valeur.
const _consumptionColor = DailyReportColors.yellow600;
final _mortalityFemaleColor = Colors.red.shade400;
final _mortalityMaleColor = Colors.red.shade800;

/// Détail du suivi bâtiment pour une ferme : le récapitulatif (effectif/stock actuels vs
/// départ) et les graphiques hebdomadaires. Le jour par jour et l'historique des transferts
/// sont sur des pages séparées et paginées (BuildingTrackingDayByDayScreen,
/// RoomTransferHistoryScreen) pour ne pas surcharger cet écran.
class BuildingTrackingDetailScreen extends StatefulWidget {
  final BuildingTrackingItem item;

  const BuildingTrackingDetailScreen({super.key, required this.item});

  @override
  State<BuildingTrackingDetailScreen> createState() => _BuildingTrackingDetailScreenState();
}

class _BuildingTrackingDetailScreenState extends State<BuildingTrackingDetailScreen> {
  final MongoService _mongoService = MongoService();
  List<WeeklyTrackingPoint> _weeklyPoints = [];
  bool _isLoading = true;
  // null = toutes les salles cumulées ; sinon filtre les deux graphiques sur une salle
  // précise (utile pour repérer où la mortalité ou la consommation se concentre).
  String? _selectedRoom;

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
    final weeklyPoints = await _mongoService.getBuildingTrackingWeeklyChart(
      widget.item.farmId,
      lotNumber: widget.item.lotNumber,
    );
    if (!mounted) return;
    setState(() {
      _weeklyPoints = weeklyPoints;
      _isLoading = false;
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
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RoomTransferHistoryScreen(
                          farmId: item.farmId,
                          farmName: item.farmName,
                          lotNumber: item.lotNumber,
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DailyReportColors.green700,
                      side: const BorderSide(color: DailyReportColors.green600),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                    label: const Text("Voir l'historique des transferts de sujets"),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BuildingTrackingDayByDayScreen(
                          farmId: item.farmId,
                          farmName: item.farmName,
                          lotNumber: item.lotNumber,
                        ),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DailyReportColors.green700,
                      side: const BorderSide(color: DailyReportColors.green600),
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.event_note_rounded, size: 18),
                    label: const Text('Voir jour par jour (qui a fait quoi, et quand)'),
                  ),
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
        if (item.currentRooms.isNotEmpty || item.currentClinic.femaleCount > 0 || item.currentClinic.maleCount > 0) ...[
          const Divider(height: 24),
          const Text('Effectif actuel par salle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          const SizedBox(height: 6),
          for (final r in item.currentRooms)
            if (r.femaleCount > 0 || r.maleCount > 0) _roomHeadcountRow(r.roomName, r.femaleCount, r.maleCount),
          if (item.currentClinic.femaleCount > 0 || item.currentClinic.maleCount > 0)
            _roomHeadcountRow('Clinique', item.currentClinic.femaleCount, item.currentClinic.maleCount),
        ],
      ],
    );
  }

  Widget _roomHeadcountRow(String label, int female, int male) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('$female F · $male M', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
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

  /// Axes communs aux deux courbes : repères de semaine en bas, valeurs masquées à gauche
  /// (le détail s'affiche au toucher d'un point).
  FlTitlesData _lineTitles() => FlTitlesData(
        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(sideTitles: _weekAxisTitles().sideTitles),
      );

  LineChartBarData _line(List<double> values, Color color) => LineChartBarData(
        spots: [for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
        isCurved: true,
        curveSmoothness: 0.25,
        preventCurveOverShooting: true,
        color: color,
        barWidth: 3,
        dotData: FlDotData(
          show: values.length <= 24,
          getDotPainter: (spot, percent, bar, index) =>
              FlDotCirclePainter(radius: 3, color: Colors.white, strokeWidth: 2, strokeColor: color),
        ),
        belowBarData: BarAreaData(show: true, color: color.withValues(alpha: 0.10)),
      );

  Widget _consumptionChartCard() {
    if (_weeklyPoints.isEmpty || _weeklyPoints.every((p) => _consumedFor(p) <= 0)) {
      return _emptyChartCard();
    }
    final values = _weeklyPoints.map(_consumedFor).toList();
    final maxY = values.reduce((a, b) => a > b ? a : b);
    return DailyReportCard(
      accentColor: _consumptionColor,
      children: [
        SizedBox(
          height: 190,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY <= 0 ? 1 : maxY * 1.25,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: _lineTitles(),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => [
                    for (final t in spots)
                      LineTooltipItem(
                        'S${_weeklyPoints[t.x.toInt()].ageWeeks} · ${t.y.toStringAsFixed(1)} kg',
                        const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                      ),
                  ],
                ),
              ),
              lineBarsData: [_line(values, _consumptionColor)],
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
    final female = _weeklyPoints.map((p) => _femaleMortalityFor(p).toDouble()).toList();
    final male = _weeklyPoints.map((p) => _maleMortalityFor(p).toDouble()).toList();
    final maxY = [...female, ...male].reduce((a, b) => a > b ? a : b);
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
          height: 190,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maxY <= 0 ? 1 : maxY * 1.25,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: _lineTitles(),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) {
                    final week = _weeklyPoints[spots.first.x.toInt()].ageWeeks;
                    return [
                      for (var i = 0; i < spots.length; i++)
                        LineTooltipItem(
                          i == 0 ? 'S$week\n' : '',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 11),
                          children: [
                            TextSpan(
                              text: '${spots[i].barIndex == 0 ? "Femelles" : "Mâles"} : ${spots[i].y.toInt()}',
                              style: TextStyle(
                                color: spots[i].barIndex == 0 ? Colors.red.shade200 : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                    ];
                  },
                ),
              ),
              lineBarsData: [
                _line(female, _mortalityFemaleColor),
                _line(male, _mortalityMaleColor),
              ],
            ),
          ),
        ),
      ],
    );
  }

}
