import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/formula.dart';
import '../models/poste.dart';
import '../models/usine_stats.dart';
import '../services/mongo_service.dart';

const Map<String, String> _journalTypeLabels = {
  'receptions': 'Réceptions',
  'prix_cump': 'Prix / CUMP',
  'production': 'Production',
  'livraisons': 'Livraisons',
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
  int _journalPageIndex = 0;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _traceController.dispose();
    super.dispose();
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
          keyboardType: TextInputType.number,
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
              await _mongoService.setBudget(
                usineId: widget.usine.id!,
                category: category,
                month: now.month,
                year: now.year,
                amountFcfa: amount,
              );
              final refreshed = await _mongoService.getBudgets(
                widget.usine.id!,
              );
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

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
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

  Widget _menuRow(String emoji, String label, int tabIndex) {
    return ListTile(
      onTap: () => _tabController.animateTo(tabIndex),
      leading: Text(emoji, style: const TextStyle(fontSize: 18)),
      title: Text(
        label,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      trailing: const Text(
        'Ouvrir →',
        style: TextStyle(
          color: Colors.orange,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final d = _dashboard;
    if (d == null)
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
              _statCard(
                '${d.productionThisMonthKg.toStringAsFixed(0)} kg',
                'Production · mois',
              ),
              if (_perms.seeCosts)
                _statCard(
                  '${d.avgCostPerKg.toStringAsFixed(0)} F',
                  'Coût moyen /kg',
                ),
              if (_perms.seeCosts)
                _statCard(
                  valueFmt.format(d.stockValueFcfa),
                  'Valeur stock FCFA',
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Production mensuelle (kg)',
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
            child: _buildBarChart(d.monthlyProduction, Colors.orange),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              children: [
                _menuRow('📦', 'Consommation par bâtiment', 1),
                const Divider(height: 1),
                _menuRow('🔎', 'Traçabilité par lot', 2),
                const Divider(height: 1),
                _menuRow('🕒', "Journal d'activité", 3),
                if (_perms.seeCosts) ...[
                  const Divider(height: 1),
                  _menuRow('💰', 'Budgets & coûts', 4),
                ],
                const Divider(height: 1),
                _menuRow('📈', 'Graphiques & tendances', 5),
              ],
            ),
          ),
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
                    '${r.totalKg.toStringAsFixed(0)} kg',
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
                            '${det.quantityKg.toStringAsFixed(0)} kg',
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
                      '${m.lotNumber} (${m.quantity.toStringAsFixed(0)} kg) · ${m.materialName}',
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
                'Lot ${fab.lotNumber} · ${fab.formulaName} · ${fab.quantity.toStringAsFixed(0)} kg'
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
                    '${d.lotNumberSujets != null ? " · Lot ${d.lotNumberSujets} (sujets)" : ""} · ${d.quantity.toStringAsFixed(0)} kg',
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: SingleChildScrollView(
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
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          backgroundColor: Colors.orange.withValues(alpha: 0.1),
                          radius: 16,
                          child: const Icon(
                            Icons.history,
                            size: 16,
                            color: Colors.orange,
                          ),
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
                        ),
                        subtitle: Text(
                          DateFormat('dd/MM/yyyy, HH:mm').format(e.timestamp),
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10.5,
                          ),
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
              _statCard(valueFmt.format(b.totalBudget), 'Budget matières'),
              _statCard(valueFmt.format(b.totalRealized), 'Réalisé'),
              _statCard(
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
