import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/formula.dart';
import '../models/poste.dart';
import '../models/usine_stats.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';

const Map<String, String> _journalTypeLabels = {
  'referentiel': 'Référentiel',
  'approvisionnement': 'Approvisionnement',
  'prix_cump': 'Prix / CUMP',
  'production': 'Production',
  'livraisons': 'Livraisons',
  'logistique': 'Logistique',
  'administration': 'Administration',
};

const Map<String, (String, Color, IconData)> _journalActionMeta = {
  'CREATE': ('Création', Colors.green, Icons.add_circle_outline),
  'UPDATE': ('Modification', Colors.blue, Icons.edit_outlined),
  'DELETE': ('Suppression', Colors.red, Icons.delete_outline),
};

/// Parcours 05 — Statistiques & traçabilité (maquette écrans 31-36), condensé en un seul
/// écran à onglets (au lieu de 6 écrans séparés) : aperçu, consommation par bâtiment,
/// traçabilité par lot, journal d'activité, budgets & coûts, graphiques & tendances.
class UsineStatsScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineStatsScreen({super.key, required this.usine, this.permissions});

  @override
  State<UsineStatsScreen> createState() => _UsineStatsScreenState();
}

class _UsineStatsScreenState extends State<UsineStatsScreen>
    with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;
  late final TabController _tabController = TabController(
    length: 6,
    vsync: this,
  );
  static const int _journalPageSize = 20;

  bool _isLoading = true;
  DashboardStats? _dashboard;
  List<RoomConsumption> _consumption = [];
  List<RawMaterial> _materials = [];
  List<Formula> _formulas = [];
  BudgetsStats? _budgets;
  TrendsStats? _trends;
  String? _trendMaterialId;
  String? _trendFormulaId;

  TraceResult? _traceResult;
  bool _traceLoading = false;
  final _traceController = TextEditingController();

  AuditLogPagedResult? _journalPage;
  bool _journalLoading = true;
  String? _journalType;
  String? _journalAction;
  DateTimeRange? _journalDateRange;
  final TextEditingController _journalUserController = TextEditingController();
  int _journalPageIndex = 0;

  late Timer _clockTimer;
  String _currentTime = '';
  String _currentDateStr = '';

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
    _refreshAll();
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _tabController.dispose();
    _traceController.dispose();
    _journalUserController.dispose();
    super.dispose();
  }

  void _updateClock() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(now);
      _currentDateStr = DateFormat('dd/MM/yyyy').format(now);
    });
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _mongoService.getUsineDashboard(widget.usine.id!),
      _mongoService.getConsumptionByRoom(widget.usine.id!),
      _mongoService.getRawMaterials(widget.usine.id!),
      _mongoService.getFormulas(widget.usine.id!),
      _mongoService.getBudgets(widget.usine.id!),
    ]);
    if (!mounted) return;
    final materials = results[2] as List<RawMaterial>;
    setState(() {
      _dashboard = results[0] as DashboardStats?;
      _consumption = results[1] as List<RoomConsumption>;
      _materials = materials;
      _formulas = results[3] as List<Formula>;
      _budgets = results[4] as BudgetsStats?;
      _trendMaterialId ??= materials.isNotEmpty ? materials.first.id : null;
      _isLoading = false;
    });
    await _loadTrends();
    await _loadJournalPage();
  }

  Future<void> _loadTrends() async {
    final trends = await _mongoService.getTrends(
      widget.usine.id!,
      rawMaterialId: _trendMaterialId,
      formulaId: _trendFormulaId,
    );
    if (!mounted) return;
    setState(() => _trends = trends);
  }

  Future<void> _loadJournalPage() async {
    setState(() => _journalLoading = true);
    final page = await _mongoService.getUsineJournal(
      usineId: widget.usine.id!,
      type: _journalType,
      action: _journalAction,
      performedBy: _journalUserController.text.trim().isEmpty
          ? null
          : _journalUserController.text.trim(),
      dateFrom: _journalDateRange?.start,
      dateTo: _journalDateRange?.end,
      skip: _journalPageIndex * _journalPageSize,
      limit: _journalPageSize,
    );
    if (!mounted) return;
    setState(() {
      _journalPage = page;
      _journalLoading = false;
    });
  }

  void _applyJournalFilter(String? type) {
    setState(() {
      _journalType = type;
      _journalPageIndex = 0;
    });
    _loadJournalPage();
  }

  void _applyJournalAction(String? action) {
    setState(() {
      _journalAction = action;
      _journalPageIndex = 0;
    });
    _loadJournalPage();
  }

  void _applyJournalUser() {
    setState(() => _journalPageIndex = 0);
    _loadJournalPage();
  }

  Future<void> _pickJournalDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _journalDateRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.orange),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _journalDateRange = picked;
      _journalPageIndex = 0;
    });
    _loadJournalPage();
  }

  void _clearJournalDateRange() {
    setState(() {
      _journalDateRange = null;
      _journalPageIndex = 0;
    });
    _loadJournalPage();
  }

  Widget _journalDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showJournalDetailDialog(AuditLogEntry e) {
    final meta =
        _journalActionMeta[e.action] ??
        (e.action, Colors.grey, Icons.circle_outlined);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(meta.$3, color: meta.$2),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                meta.$1,
                style: TextStyle(color: meta.$2, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _journalDetailRow('Utilisateur', e.userName),
              _journalDetailRow(
                'Date',
                DateFormat('dd/MM/yyyy à HH:mm:ss').format(e.timestamp),
              ),
              const Divider(height: 24),
              Text(e.details, style: const TextStyle(fontSize: 13.5)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Future<void> _runTrace() async {
    final q = _traceController.text.trim();
    if (q.isEmpty) return;
    setState(() => _traceLoading = true);
    final result = await _mongoService.traceLot(q);
    if (!mounted) return;
    setState(() {
      _traceResult = result;
      _traceLoading = false;
    });
  }

  void _showBudgetDialog(String category, double currentAmount) {
    final controller = TextEditingController(
      text: currentAmount.toStringAsFixed(0),
    );
    final now = DateTime.now();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Budget $category',
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
          ],
          decoration: const InputDecoration(
            labelText: 'Montant mensuel (FCFA)',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text) ?? 0;
              final refreshed = await runBlocking(context, () async {
                await _mongoService.setBudget(
                  usineId: widget.usine.id!,
                  category: category,
                  month: now.month,
                  year: now.year,
                  amountFcfa: amount,
                );
                return _mongoService.getBudgets(widget.usine.id!);
              });
              if (!mounted) return;
              setState(() => _budgets = refreshed);
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }

  Widget _buildBarChart(List<MonthlyPoint> points, Color color) {
    if (points.isEmpty || points.every((p) => p.value == 0)) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: Text(
            'Pas encore de données.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      );
    }
    final maxY = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 140,
      child: BarChart(
        BarChartData(
          maxY: maxY <= 0 ? 1 : maxY * 1.25,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox();
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      points[i].label,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (int i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: points[i].value,
                    color: color,
                    width: 16,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Carte héros orange en tête du tableau de bord — même langage visuel que l'accueil
  /// principal de l'app (user_dashboard.dart) : nom + heure/date en direct, puis l'usine
  /// bien en évidence. Sans cette carte, l'écran n'était qu'un empilement de blocs plats.
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.orange.shade600,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bienvenue,',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    _mongoService.currentUsineUser?.name ?? 'Admin',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currentTime,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    _currentDateStr,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'USINE ALIMENT',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.usine.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statIconCard(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.orange, size: 26),
            const SizedBox(height: 10),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAccessCard(
    String emoji,
    String label,
    Color color,
    int tabIndex,
  ) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _tabController.animateTo(tabIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Text(emoji, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 13,
      color: Colors.grey,
      letterSpacing: 1.1,
    ),
  );

  Widget _buildOverviewTab() {
    final d = _dashboard;
    if (d == null) {
      return RefreshIndicator(
        onRefresh: _refreshAll,
        color: Colors.orange,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 60),
            const Center(
              child: Text(
                'Aucune donnée.',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }
    final valueFmt = NumberFormat.compact(locale: 'fr_FR');

    // Section "Accès rapide" : autant de cartes que d'onglets accessibles, réparties par
    // 2 sur chaque ligne plutôt qu'un simple menu de lignes empilées.
    final quickAccess = <Widget>[
      _quickAccessCard('📦', 'Consommation\npar bâtiment', Colors.teal, 1),
      _quickAccessCard('🔎', 'Traçabilité\npar lot', Colors.indigo, 2),
      _quickAccessCard('🕒', "Journal\nd'activité", Colors.blueGrey, 3),
      if (_perms.seeCosts)
        _quickAccessCard('💰', 'Budgets\n& coûts', Colors.green, 4),
      _quickAccessCard('📈', 'Graphiques\n& tendances', Colors.purple, 5),
    ];
    final quickAccessRows = <Widget>[];
    for (var i = 0; i < quickAccess.length; i += 2) {
      quickAccessRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              quickAccess[i],
              const SizedBox(width: 12),
              if (i + 1 < quickAccess.length)
                quickAccess[i + 1]
              else
                const Spacer(),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          _buildHeroCard(),
          const SizedBox(height: 24),
          _sectionLabel('CE MOIS-CI'),
          const SizedBox(height: 12),
          Row(
            children: [
              _statIconCard(
                Icons.trending_up_rounded,
                '${formatQty(d.productionThisMonthKg)} kg',
                'Production',
              ),
              if (_perms.seeCosts) ...[
                const SizedBox(width: 12),
                _statIconCard(
                  Icons.payments_outlined,
                  '${d.avgCostPerKg.toStringAsFixed(0)} F',
                  'Coût moyen /kg',
                ),
                const SizedBox(width: 12),
                _statIconCard(
                  Icons.account_balance_wallet_outlined,
                  valueFmt.format(d.stockValueFcfa),
                  'Valeur stock',
                ),
              ],
            ],
          ),
          const SizedBox(height: 28),
          _sectionLabel('PRODUCTION MENSUELLE'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.bar_chart_rounded,
                      color: Colors.orange.shade700,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'kg produits par mois',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildBarChart(d.monthlyProduction, Colors.orange),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _sectionLabel('ACCÈS RAPIDE'),
          const SizedBox(height: 12),
          ...quickAccessRows,
        ],
      ),
    );
  }

  Widget _buildRoomsTab() {
    if (_consumption.isEmpty) {
      return const Center(
        child: Text(
          'Aucune livraison ce mois-ci.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: _consumption
            .map(
              (r) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: ExpansionTile(
                  shape: const Border(),
                  title: Text(
                    r.roomName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                    ),
                  ),
                  subtitle: Text(
                    r.lotNumberSujets != null
                        ? 'Lot ${r.lotNumberSujets} (sujets) · ${r.farmName}'
                        : r.farmName,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11.5,
                    ),
                  ),
                  trailing: Text(
                    '${formatQty(r.totalKg)} kg',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  children: r.details
                      .map(
                        (det) => ListTile(
                          dense: true,
                          title: Text(
                            det.formulaName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                          subtitle: Text(
                            'lot(s) ${det.lotsLabel}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          trailing: Text(
                            '${formatQty(det.quantityKg)} kg',
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _buildTraceTab() {
    final result = _traceResult;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _traceController,
                decoration: const InputDecoration(
                  labelText: "Numéro de lot (n'importe lequel)",
                ),
                onSubmitted: (_) => _runTrace(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _traceLoading ? null : _runTrace,
              style: IconButton.styleFrom(backgroundColor: Colors.orange),
              icon: _traceLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.search, color: Colors.white),
            ),
          ],
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          if (result.matchType == 'introuvable')
            const Text(
              'Aucun lot trouvé avec ce numéro.',
              style: TextStyle(color: Colors.grey),
            )
          else ...[
            for (final fab in result.fabrications) ...[
              if (fab.materials.isNotEmpty) ...[
                const Text(
                  '🌽 Matières d\'origine',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                ...fab.materials.map(
                  (m) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${m.lotNumber} (${formatQty(m.quantity)} kg) · ${m.materialName}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                '🏭 Fabrication',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Lot ${fab.lotNumber} · ${fab.formulaName} · ${formatQty(fab.quantity)} kg'
                '${fab.validatedAt != null ? " · validé ${DateFormat('dd/MM').format(fab.validatedAt!)}" : ""}',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 16),
            ],
            if (result.deliveries.isNotEmpty) ...[
              const Text(
                '🚚 Livraison',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              ...result.deliveries.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${DateFormat('dd/MM').format(d.date)} · ${d.farmName} — ${d.roomName}'
                    '${d.lotNumberSujets != null ? " · Lot ${d.lotNumberSujets} (sujets)" : ""} · ${formatQty(d.quantity)} kg',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
            if (result.materialDeliveries.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '📦 Livraison matière (client)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 6),
              ...result.materialDeliveries.map(
                (d) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${DateFormat('dd/MM').format(d.date)} · ${d.materialName} → ${d.clientName} · ${formatQty(d.quantity)} kg',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ),
            ],
          ],
        ],
      ],
    );
  }

  Widget _buildJournalTab() {
    final page = _journalPage;
    final totalPages = page == null || page.totalCount == 0
        ? 1
        : (page.totalCount / _journalPageSize).ceil();
    final dateLabel = _journalDateRange == null
        ? 'Toute la période'
        : '${DateFormat('dd/MM/yy').format(_journalDateRange!.start)} - ${DateFormat('dd/MM/yy').format(_journalDateRange!.end)}';
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _journalUserController,
                      decoration: InputDecoration(
                        labelText: 'Rechercher un utilisateur',
                        isDense: true,
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward, size: 16),
                          onPressed: _applyJournalUser,
                        ),
                      ),
                      onSubmitted: (_) => _applyJournalUser(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _pickJournalDateRange,
                    icon: const Icon(Icons.date_range_outlined, size: 16),
                    label: Text(
                      dateLabel,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                  if (_journalDateRange != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: _clearJournalDateRange,
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Tous'),
                      selected: _journalType == null,
                      onSelected: (_) => _applyJournalFilter(null),
                    ),
                    const SizedBox(width: 8),
                    for (final entry in _journalTypeLabels.entries) ...[
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _journalType == entry.key,
                        onSelected: (_) => _applyJournalFilter(entry.key),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Toute action'),
                      selected: _journalAction == null,
                      onSelected: (_) => _applyJournalAction(null),
                      avatar: const Icon(Icons.all_inclusive, size: 14),
                    ),
                    const SizedBox(width: 8),
                    for (final entry in _journalActionMeta.entries) ...[
                      ChoiceChip(
                        label: Text(entry.value.$1),
                        selected: _journalAction == entry.key,
                        onSelected: (_) => _applyJournalAction(entry.key),
                        avatar: Icon(
                          entry.value.$3,
                          size: 14,
                          color: entry.value.$2,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _journalLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.orange),
                )
              : (page == null || page.data.isEmpty)
              ? const Center(
                  child: Text(
                    'Aucune activité pour ce filtre.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  itemCount: page.data.length,
                  itemBuilder: (context, index) {
                    final e = page.data[index];
                    final meta =
                        _journalActionMeta[e.action] ??
                        (e.action, Colors.grey, Icons.circle_outlined);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: ListTile(
                        dense: true,
                        onTap: () => _showJournalDetailDialog(e),
                        leading: CircleAvatar(
                          backgroundColor: meta.$2.withValues(alpha: 0.1),
                          radius: 16,
                          child: Icon(meta.$3, size: 16, color: meta.$2),
                        ),
                        title: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${e.userName} ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                              TextSpan(
                                text: '— ${e.details}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy, HH:mm').format(e.timestamp),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10.5,
                          ),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.grey,
                          size: 18,
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (page != null && totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _journalPageIndex > 0
                      ? () {
                          setState(() => _journalPageIndex--);
                          _loadJournalPage();
                        }
                      : null,
                ),
                Text(
                  'Page ${_journalPageIndex + 1} / $totalPages',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _journalPageIndex < totalPages - 1
                      ? () {
                          setState(() => _journalPageIndex++);
                          _loadJournalPage();
                        }
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBudgetsTab() {
    if (!_perms.seeCosts) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Réservé à la comptabilité / direction.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final b = _budgets;
    if (b == null)
      return const Center(
        child: Text('Aucune donnée.', style: TextStyle(color: Colors.grey)),
      );
    final valueFmt = NumberFormat.compact(locale: 'fr_FR');
    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Row(
            children: [
              _statIconCard(
                Icons.account_balance_wallet_outlined,
                valueFmt.format(b.totalBudget),
                'Budget matières',
              ),
              const SizedBox(width: 12),
              _statIconCard(
                Icons.payments_outlined,
                valueFmt.format(b.totalRealized),
                'Réalisé',
              ),
              const SizedBox(width: 12),
              _statIconCard(
                b.variancePercent >= 0
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                '${b.variancePercent >= 0 ? "+" : ""}${b.variancePercent.toStringAsFixed(1)}%',
                'Écart',
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Par catégorie',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          ...b.categories.map((c) {
            final color = c.status == 'depasse'
                ? Colors.red.shade400
                : (c.status == 'sans_budget'
                      ? Colors.grey.shade400
                      : Colors.green.shade600);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: InkWell(
                // Écran 35, annotation A : fixer/modifier un budget est un geste comptable
                // (adjustCost) — la simple lecture (seeCosts) ne suffit pas à l'éditer.
                onTap: _perms.adjustCost
                    ? () => _showBudgetDialog(c.category, c.budgetFcfa)
                    : null,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          c.category,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          c.status == 'sans_budget'
                              ? '${valueFmt.format(c.realizedFcfa)} (sans budget)'
                              : '${valueFmt.format(c.realizedFcfa)} / ${valueFmt.format(c.budgetFcfa)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: (c.percentUsed / 100).clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade100,
                        color: color,
                      ),
                    ),
                    if (c.status == 'depasse' && c.topMaterial != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Dépassement tiré par : ${c.topMaterial}',
                          style: TextStyle(fontSize: 11, color: color),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }),
          if (b.formulaCosts.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Coût de revient moyen par aliment',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(
                children: b.formulaCosts
                    .map(
                      (f) => ListTile(
                        dense: true,
                        title: Text(
                          f.formulaName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${f.avgCostPerUnit.toStringAsFixed(1)} F/kg',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                              ),
                            ),
                            if (f.trendPercent != null) ...[
                              const SizedBox(width: 6),
                              Icon(
                                f.trendPercent! >= 0
                                    ? Icons.arrow_upward
                                    : Icons.arrow_downward,
                                size: 13,
                                color: f.trendPercent! >= 0
                                    ? Colors.red.shade400
                                    : Colors.green.shade600,
                              ),
                              Text(
                                '${f.trendPercent!.abs().toStringAsFixed(1)}%',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: f.trendPercent! >= 0
                                      ? Colors.red.shade400
                                      : Colors.green.shade600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrendsTab() {
    final t = _trends;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      children: [
        if (_perms.seeCosts) ...[
          DropdownButtonFormField<String>(
            isExpanded: true,
            value: _trendMaterialId,
            decoration: const InputDecoration(
              labelText: 'CUMP — matière première',
              isDense: true,
            ),
            items: _materials
                .where((m) => m.id != null)
                .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                .toList(),
            onChanged: (v) {
              setState(() => _trendMaterialId = v);
              _loadTrends();
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: _buildBarChart(t?.cumpTrend ?? [], Colors.indigo),
          ),
          const SizedBox(height: 20),
        ],
        DropdownButtonFormField<String?>(
          isExpanded: true,
          value: _trendFormulaId,
          decoration: const InputDecoration(
            labelText: 'Production — filtrer par référence',
            isDense: true,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Toutes formules'),
            ),
            ..._formulas
                .where((f) => f.id != null)
                .map((f) => DropdownMenuItem(value: f.id, child: Text(f.name))),
          ],
          onChanged: (v) {
            setState(() => _trendFormulaId = v);
            _loadTrends();
          },
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: _buildBarChart(t?.productionTrend ?? [], Colors.orange),
        ),
        const SizedBox(height: 20),
        const Text(
          'Pertes & avaries (kg/mois)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: _buildBarChart(t?.lossesTrend ?? [], Colors.amber.shade700),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'STATISTIQUES',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
            fontSize: 13,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _refreshAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(text: 'Aperçu'),
            Tab(text: 'Bâtiments'),
            Tab(text: 'Traçabilité'),
            Tab(text: 'Journal'),
            Tab(text: 'Budgets'),
            Tab(text: 'Tendances'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildRoomsTab(),
                _buildTraceTab(),
                _buildJournalTab(),
                _buildBudgetsTab(),
                _buildTrendsTab(),
              ],
            ),
    );
  }
}
