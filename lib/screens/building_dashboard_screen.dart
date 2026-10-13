import 'package:flutter/material.dart';
import '../models/building_tracking.dart';
import '../models/cumul.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/current_lot_dialog.dart';
import '../widgets/daily_report_widgets.dart';
import 'building_tracking_day_by_day_screen.dart';
import 'farm_feed_cumul_history_screen.dart';
import 'lot_egg_cumul_history_screen.dart';
import 'lot_mortality_cumul_history_screen.dart';
import 'building_tracking_detail_screen.dart';
import 'room_transfer_history_screen.dart';

// Mêmes seuils que la liste de Suivi bâtiment (voir building_tracking_screen.dart).
final _mortalityFemaleColor = Colors.red.shade400;
const _mortalityWarning = 2.0;
const _mortalityCritical = 5.0;
const _stockDaysWarning = 7.0;
const _stockDaysCritical = 3.0;

String _kg(double v) => '${v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1)} kg';

/// Tableau de bord d'un bâtiment : toutes les informations de suivi d'une ferme sur une seule
/// page mobile (effectif, mortalité, aliment, œufs, détail par salle), avec accès aux
/// graphiques, au jour par jour et aux transferts. Lecture seule, hors le lot en cours que
/// l'admin peut corriger depuis l'en-tête.
class BuildingDashboardScreen extends StatefulWidget {
  final BuildingTrackingItem item;

  const BuildingDashboardScreen({super.key, required this.item});

  @override
  State<BuildingDashboardScreen> createState() => _BuildingDashboardScreenState();
}

class _BuildingDashboardScreenState extends State<BuildingDashboardScreen> {
  final MongoService _mongoService = MongoService();
  late BuildingTrackingItem _item;
  // Cumuls du lot (saisis + rapports) : source distincte du suivi, chargée à part.
  BuildingCumulItem? _cumul;
  // Lots du bâtiment (en cours + passés) et lot choisi dans le sélecteur de la section « Par lot ».
  List<BuildingLotSummary> _lots = [];
  String? _selectedLot;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadCumul();
    _loadLots();
  }

  Future<void> _loadLots() async {
    final lots = await _mongoService.getBuildingLots(_item.farmId);
    if (!mounted) return;
    setState(() {
      _lots = lots;
      if (!lots.any((l) => l.lotNumber == _selectedLot)) {
        _selectedLot = lots.isEmpty ? null : lots.first.lotNumber;
      }
    });
  }

  Future<void> _loadCumul() async {
    final items = await _mongoService.getBuildingCumuls();
    if (!mounted) return;
    final found = items.where((c) => c.farmId == _item.farmId);
    setState(() => _cumul = found.isEmpty ? null : found.first);
  }

  Future<void> _reload() async {
    setState(() => _refreshing = true);
    _loadCumul();
    _loadLots();
    final items = await _mongoService.getBuildingTracking();
    if (!mounted) return;
    final fresh = items.where((i) => i.farmId == _item.farmId);
    setState(() {
      if (fresh.isNotEmpty) _item = fresh.first;
      _refreshing = false;
    });
  }

  bool get _alert =>
      _item.hasReports &&
      (_item.mortalityRatePercent >= _mortalityCritical ||
          (_item.securityStockDays != null && _item.securityStockDays! < _stockDaysCritical));

  Color get _mortalityColor => _item.mortalityRatePercent >= _mortalityCritical
      ? Colors.red.shade600
      : _item.mortalityRatePercent >= _mortalityWarning
          ? DailyReportColors.yellow600
          : DailyReportColors.green600;

  Color get _stockColor {
    final d = _item.securityStockDays;
    if (d == null) return Colors.grey.shade500;
    if (d < _stockDaysCritical) return Colors.red.shade600;
    if (d < _stockDaysWarning) return DailyReportColors.yellow600;
    return DailyReportColors.green600;
  }

  bool get _hasEggs =>
      _item.cumulativeOac > 0 ||
      _item.currentStockOac > 0 ||
      _item.cumulativePo > 0 ||
      _item.cumulativeDj > 0 ||
      _item.cumulativeCas > 0 ||
      _item.cumulativeSal > 0 ||
      _item.currentEggRooms.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final item = _item;
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(item.farmName, subtitle: 'Tableau de bord du bâtiment'),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
          children: [
            _hero(item),
            if (_refreshing) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
            const SizedBox(height: 14),
            _kpiGrid(item),
            const SizedBox(height: 18),
            _sectionTitle('Effectif par salle', Icons.groups_rounded),
            _headcountSection(item),
            const SizedBox(height: 18),
            _sectionTitle('Aliment', Icons.grain_rounded),
            _feedSection(item),
            if (_hasEggs) ...[
              const SizedBox(height: 18),
              _sectionTitle('Œufs', Icons.egg_rounded),
              _eggsSection(item),
            ],
            if (_cumul != null) ...[
              const SizedBox(height: 18),
              _sectionTitle('Cumuls du lot', Icons.stacked_line_chart_rounded),
              _cumulSection(_cumul!),
            ],
            if (_lots.isNotEmpty) ...[
              const SizedBox(height: 18),
              _sectionTitle('Par lot', Icons.layers_rounded),
              _lotsSection(),
            ],
            const SizedBox(height: 18),
            _sectionTitle('Aller plus loin', Icons.open_in_new_rounded),
            _actionTile(
              icon: Icons.show_chart_rounded,
              color: DailyReportColors.green700,
              title: 'Graphiques par semaine',
              subtitle: 'Consommation et mortalité, par salle',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => BuildingTrackingDetailScreen(item: item)),
              ),
            ),
            _actionTile(
              icon: Icons.event_note_rounded,
              color: DailyReportColors.blue600,
              title: 'Jour par jour',
              subtitle: 'Qui a fait quoi, et quand',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BuildingTrackingDayByDayScreen(
                    farmId: item.farmId,
                    farmName: item.farmName,
                    lotNumber: item.lotNumber,
                  ),
                ),
              ),
            ),
            _actionTile(
              icon: Icons.swap_horiz_rounded,
              color: DailyReportColors.purple600,
              title: 'Transferts de sujets',
              subtitle: 'Historique des mouvements entre salles',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => RoomTransferHistoryScreen(
                    farmId: item.farmId,
                    farmName: item.farmName,
                    lotNumber: item.lotNumber,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- En-tête ----
  Widget _hero(BuildingTrackingItem item) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: dailyReportHeaderGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: DailyReportColors.green900.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_work_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.farmName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              if (_alert)
                const DailyReportStatusBadge(label: 'ALERTE', color: Colors.red, icon: Icons.priority_high_rounded, solid: true),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _heroChip(Icons.layers_rounded, 'Lot ${item.lotNumber ?? "non défini"}'),
              if (item.ageDays != null) _heroChip(Icons.cake_rounded, '${item.ageDays} j · S${item.ageWeeks}'),
              _heroChip(
                Icons.event_available_rounded,
                item.lastReportDate != null ? 'Dernier rapport ${item.lastReportDate}' : 'Aucun rapport validé',
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Modifier le lot'),
            onPressed: () async {
              final changed = await showCurrentLotDialog(
                context,
                farmId: item.farmId,
                farmName: item.farmName,
                currentLot: item.lotNumber,
              );
              if (changed && mounted) _reload();
            },
          ),
        ],
      ),
    );
  }

  Widget _heroChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: Colors.white),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ---- Indicateurs ----
  Widget _kpiGrid(BuildingTrackingItem item) {
    final tiles = [
      _kpi(
        icon: Icons.groups_rounded,
        color: DailyReportColors.green700,
        value: '${item.currentTotal}',
        label: 'Effectif actuel',
        sub: 'sur ${item.initialTotal} au départ',
      ),
      _kpi(
        icon: Icons.trending_down_rounded,
        color: _mortalityColor,
        value: '${item.mortalityRatePercent.toStringAsFixed(1)}%',
        label: 'Mortalité cumulée',
        sub: '${item.cumulativeMortalityTotal} sujets',
      ),
      _kpi(
        icon: Icons.grain_rounded,
        color: DailyReportColors.yellow600,
        value: _kg(item.currentFeedStockKg),
        label: 'Stock aliment',
        sub: 'sur ${_kg(item.initialFeedStockKg)} au départ',
      ),
      _kpi(
        icon: Icons.hourglass_bottom_rounded,
        color: _stockColor,
        value: item.securityStockDays != null ? '${item.securityStockDays!.toStringAsFixed(1)} j' : '—',
        label: 'Autonomie',
        sub: 'consommé : ${_kg(item.cumulativeConsumedKg)}',
      ),
      if (_hasEggs) ...[
        _kpi(
          icon: Icons.egg_alt_rounded,
          color: DailyReportColors.purple600,
          value: item.layingRatePercent != null ? '${item.layingRatePercent!.toStringAsFixed(1)}%' : '—',
          label: 'Taux de ponte',
          sub: 'PO / femelles',
        ),
        _kpi(
          icon: Icons.scale_rounded,
          color: DailyReportColors.blue600,
          value: item.feedConversionRatio != null ? item.feedConversionRatio!.toStringAsFixed(2) : '—',
          label: 'Indice de conso.',
          sub: 'kg d\'aliment / œuf',
        ),
      ],
    ];
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, child: t)],
        );
      },
    );
  }

  Widget _kpi({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          Text(sub, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // ---- Sections ----
  Widget _sectionTitle(String text, IconData icon) => DailyReportSectionLabel(text, icon: icon);

  Widget _panel(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _empty(String text) => _panel([
        Center(child: Text(text, style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5))),
      ]);

  Widget _headcountSection(BuildingTrackingItem item) {
    final rows = <({String name, int f, int m})>[
      for (final r in item.currentRooms) (name: r.roomName, f: r.femaleCount, m: r.maleCount),
      if (item.currentClinic.femaleCount > 0 || item.currentClinic.maleCount > 0)
        (name: 'Clinique', f: item.currentClinic.femaleCount, m: item.currentClinic.maleCount),
    ];
    if (rows.isEmpty) return _empty('Aucun effectif enregistré.');
    final total = rows.fold<int>(0, (a, r) => a + r.f + r.m);
    return _panel([
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const Divider(height: 18),
        Row(
          children: [
            Expanded(child: Text(rows[i].name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
            Text('${rows[i].f + rows[i].m}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ],
        ),
        const SizedBox(height: 6),
        _bar(total > 0 ? (rows[i].f + rows[i].m) / total : 0, DailyReportColors.green600),
        const SizedBox(height: 4),
        Text('${rows[i].f} femelles · ${rows[i].m} mâles',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    ]);
  }

  Widget _feedSection(BuildingTrackingItem item) {
    final consumedFraction = item.initialFeedStockKg > 0 ? item.feedConsumedPercent / 100 : 0.0;
    return _panel([
      Row(
        children: [
          Expanded(
            child: Text('Stock restant', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w700)),
          ),
          Text('${_kg(item.currentFeedStockKg)} / ${_kg(item.initialFeedStockKg)}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
        ],
      ),
      const SizedBox(height: 6),
      _bar(1 - consumedFraction, _stockColor),
      if (item.currentFeedRooms.isNotEmpty) ...[
        const Divider(height: 22),
        const Text('Consommation cumulée par salle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 8),
        for (final r in item.currentFeedRooms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.formulaName != null ? '${r.roomName} · ${r.formulaName}' : r.roomName,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
                Text(_kg(r.femaleKg + r.maleKg), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
              ],
            ),
          ),
      ],
    ]);
  }

  Widget _eggsSection(BuildingTrackingItem item) {
    final stocks = [
      ('OAC', item.currentStockOac),
      ('PO', item.currentStockPo),
      ('DJ + CAS', item.currentStockDj + item.currentStockCas),
      ('SAL', item.currentStockSal),
    ];
    return _panel([
      Text(
        item.hasReports ? 'Stock disponible' : 'Stock disponible (stock de départ)',
        style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          for (final s in stocks)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: DailyReportColors.purple100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text('${s.$2}',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16, color: DailyReportColors.purple600)),
                    const SizedBox(height: 2),
                    Text(s.$1, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
        ],
      ),
      if (item.currentEggRooms.isNotEmpty) ...[
        const Divider(height: 24),
        const Text('Production cumulée par salle', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(height: 8),
        for (final r in item.currentEggRooms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(r.roomName, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
                Text(
                  'OAC ${r.oac} · PO ${r.po} · DJ ${r.dj} · CAS ${r.cas} · SAL ${r.sal}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
      ],
    ]);
  }

  // ---- Par lot : sélecteur + synthèse du lot choisi ----
  Widget _lotsSection() {
    final lot = _lots.firstWhere((l) => l.lotNumber == _selectedLot, orElse: () => _lots.first);
    final mortalityColor = lot.mortalityRatePercent >= _mortalityCritical
        ? Colors.red.shade600
        : lot.mortalityRatePercent >= _mortalityWarning
            ? DailyReportColors.yellow600
            : DailyReportColors.green600;
    final total = lot.cumulativeMortalityTotal;
    final femaleShare = total > 0 ? lot.cumulativeMortalityFemale / total : 0.0;
    final period = lot.firstReportDate == null
        ? 'Aucun rapport validé'
        : lot.firstReportDate == lot.lastReportDate
            ? 'Le ${lot.firstReportDate}'
            : 'Du ${lot.firstReportDate} au ${lot.lastReportDate}';
    final plural = lot.reportCount > 1 ? 's' : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _lots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final l = _lots[i];
              final selected = l.lotNumber == lot.lotNumber;
              return ChoiceChip(
                label: Text(l.isCurrent ? '${l.lotNumber} · en cours' : l.lotNumber),
                selected: selected,
                onSelected: (_) => setState(() => _selectedLot = l.lotNumber),
                selectedColor: DailyReportColors.green600,
                backgroundColor: Colors.white,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        _panel([
          Row(
            children: [
              Expanded(
                child: Text('Lot ${lot.lotNumber}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
              ),
              DailyReportStatusBadge(
                label: lot.isCurrent ? 'EN COURS' : 'TERMINÉ',
                color: lot.isCurrent ? DailyReportColors.green700 : Colors.grey,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$period · ${lot.reportCount} rapport$plural validé$plural',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          const Divider(height: 22),
          _lotFigure('Effectif', '${lot.initialTotal} → ${lot.currentTotal}', Icons.groups_rounded, DailyReportColors.green700),
          _lotFigure(
            'Mortalité',
            '${lot.mortalityRatePercent.toStringAsFixed(1)}% · ${lot.cumulativeMortalityTotal} sujets',
            Icons.trending_down_rounded,
            mortalityColor,
          ),
          if (total > 0) ...[
            const SizedBox(height: 4),
            _bar(femaleShare, _mortalityFemaleColor),
            const SizedBox(height: 4),
            Text(
              'F ${lot.cumulativeMortalityFemale} · M ${lot.cumulativeMortalityMale}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 4),
          ],
          _lotFigure('Aliment consommé', _kg(lot.cumulativeConsumedKg), Icons.grain_rounded, DailyReportColors.yellow600),
          _lotFigure(
            'Œufs cumulés',
            'PO ${lot.cumulativePo} · OAC ${lot.cumulativeOac} · DJ+CAS ${lot.cumulativeDj + lot.cumulativeCas} · SAL ${lot.cumulativeSal}',
            Icons.egg_rounded,
            DailyReportColors.purple600,
          ),
          if (lot.feedConversionRatio != null)
            _lotFigure(
              'Indice de conso.',
              '${lot.feedConversionRatio!.toStringAsFixed(2)} kg/œuf',
              Icons.scale_rounded,
              DailyReportColors.blue600,
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _historyButton(
                'Courbes du lot',
                DailyReportColors.green700,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BuildingTrackingDetailScreen(
                      item: lot.toTrackingItem(farmId: _item.farmId, farmName: _item.farmName),
                    ),
                  ),
                ),
              ),
              _historyButton(
                'Jour par jour',
                DailyReportColors.blue600,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BuildingTrackingDayByDayScreen(
                      farmId: _item.farmId,
                      farmName: _item.farmName,
                      lotNumber: lot.lotNumber,
                    ),
                  ),
                ),
              ),
              _historyButton(
                'Cumul aliment',
                DailyReportColors.purple600,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FarmFeedCumulHistoryScreen(farmName: _item.farmName, lotNumber: lot.lotNumber),
                  ),
                ),
              ),
              _historyButton(
                'Cumul œufs',
                DailyReportColors.purple600,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LotEggCumulHistoryScreen(farmName: _item.farmName, lotNumber: lot.lotNumber),
                  ),
                ),
              ),
              _historyButton(
                'Cumul mortalité',
                Colors.red.shade600,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LotMortalityCumulHistoryScreen(farmName: _item.farmName, lotNumber: lot.lotNumber),
                  ),
                ),
              ),
            ],
          ),
        ]),
      ],
    );
  }

  Widget _lotFigure(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cumulSection(BuildingCumulItem c) {
    final feedKg = c.feedRooms.fold<double>(0, (a, r) => a + r.femaleKg + r.maleKg);
    final eggRooms = c.rooms.where((r) => r.oac + r.po + r.dj + r.cas + r.sal > 0).toList();
    final mortalityRooms = c.mortalityRooms.where((r) => r.femaleCount > 0 || r.maleCount > 0).toList();
    final lot = c.lotNumber;
    Widget header(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(text, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: color)),
              ),
            ],
          ),
        );
    Widget line(String left, String right) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(child: Text(left, style: const TextStyle(fontSize: 12.5))),
              Text(right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        );
    Widget none(String t) => Text(t, style: TextStyle(color: Colors.grey.shade400, fontSize: 11.5));

    return _panel([
      header(Icons.grain_rounded, DailyReportColors.purple600, 'Consommation cumulée : ${_kg(feedKg)}'),
      if (c.feedRooms.isEmpty)
        none("Aucune consommation cumulée pour l'instant.")
      else
        for (final r in c.feedRooms)
          if (r.femaleKg > 0 || r.maleKg > 0)
            line(
              r.formulaName != null ? '${r.roomName} · ${r.formulaName}' : r.roomName,
              'F ${_kg(r.femaleKg)} · M ${_kg(r.maleKg)}',
            ),
      const Divider(height: 24),
      header(Icons.egg_rounded, DailyReportColors.purple600, 'Cumul œufs (manuel)'),
      if (eggRooms.isEmpty)
        none('Aucun cumul œufs enregistré.')
      else
        for (final r in eggRooms)
          line(r.roomName, 'OAC ${r.oac} · PO ${r.po} · DJ ${r.dj} · CAS ${r.cas} · SAL ${r.sal}'),
      const Divider(height: 24),
      header(
        Icons.dangerous_outlined,
        Colors.red.shade600,
        'Mortalité cumulée : F ${c.cumulativeMortalityFemale} · M ${c.cumulativeMortalityMale}',
      ),
      if (mortalityRooms.isEmpty)
        none("Aucune mortalité cumulée pour l'instant.")
      else
        for (final r in mortalityRooms) line(r.roomName, 'F ${r.femaleCount} · M ${r.maleCount}'),
      if (lot != null) ...[
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _historyButton(
              'Historique aliment',
              DailyReportColors.purple600,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FarmFeedCumulHistoryScreen(farmName: c.farmName, lotNumber: lot)),
              ),
            ),
            _historyButton(
              'Historique œufs',
              DailyReportColors.purple600,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LotEggCumulHistoryScreen(farmName: c.farmName, lotNumber: lot)),
              ),
            ),
            _historyButton(
              'Historique mortalité',
              Colors.red.shade600,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LotMortalityCumulHistoryScreen(farmName: c.farmName, lotNumber: lot)),
              ),
            ),
          ],
        ),
      ],
    ]);
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

  Widget _bar(double fraction, Color color) {
    final f = fraction.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Container(height: 8, color: Colors.grey.shade200),
            Container(height: 8, width: c.maxWidth * f, color: color),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                      Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
