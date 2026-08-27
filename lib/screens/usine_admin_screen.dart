import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/usine.dart';
import '../models/usine_user.dart';
import '../models/poste.dart';
import '../models/poste_assignment.dart';
import '../models/usine_stats.dart';
import '../services/mongo_service.dart';
import '../widgets/blocking_loader.dart';
import 'usine_referentiel_screen.dart';
import 'usine_appro_screen.dart';
import 'usine_daily_report_screen.dart';
import 'usine_production_screen.dart';
import 'usine_simulation_screen.dart';
import 'usine_stock_livraison_screen.dart';
import 'usine_stats_screen.dart';

/// Administration transverse du module Usine Aliment (Partie 0) :
/// - Usines (comme les fermes, on peut en créer plusieurs)
/// - Utilisateurs usine : comptes propres à ce module, distincts des utilisateurs
///   du module Rapport Journalier (ceux-là restent rattachés à une ferme).
/// - Postes : nommés librement par l'admin ("Magasinier de l'usine", "Caissier"...),
///   chacun avec un jeu de permissions qui pilote l'accès aux écrans et le masquage
///   des coûts, plutôt qu'une liste de rôles figée dans le code.
/// - Affectations : un utilisateur usine peut cumuler plusieurs postes, chacun sur une
///   usine précise (pas de portée "toutes les usines" — l'utilisateur ne voit que
///   l'interface de son/ses usine(s) affectée(s)).
const Map<String, String> _adminJournalTypeLabels = {
  'referentiel': 'Référentiel',
  'approvisionnement': 'Approvisionnement',
  'prix_cump': 'Prix / CUMP',
  'production': 'Production',
  'livraisons': 'Livraisons',
  'logistique': 'Logistique',
  'administration': 'Administration',
};

class UsineAdminScreen extends StatefulWidget {
  const UsineAdminScreen({super.key});

  @override
  State<UsineAdminScreen> createState() => _UsineAdminScreenState();
}

class _UsineAdminScreenState extends State<UsineAdminScreen>
    with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  late TabController _tabController;

  List<Usine> _usines = [];
  List<Poste> _postes = [];
  List<PosteAssignment> _assignments = [];
  List<UsineUser> _usineUsers = [];
  bool _isLoading = true;
  String? _error;

  // Aperçu (toutes usines) : statistiques + graphique de chaque usine, pour que l'admin
  // n'ait pas besoin d'entrer dans chaque usine une à une pour se faire une idée globale.
  Map<String, DashboardStats> _usineDashboards = {};
  bool _dashboardsLoading = true;

  // Journal (toutes usines) : tous les filtres possibles — usine, catégorie, action,
  // utilisateur, période — pour un logiciel de gestion où il doit être possible de
  // retrouver n'importe quelle écriture, pas seulement de tout parcourir en scrollant.
  static const int _journalPageSize = 20;
  AuditLogPagedResult? _journalPage;
  bool _journalLoading = true;
  String? _journalType;
  String? _journalAction;
  String? _journalUsineId; // null = toutes les usines
  DateTimeRange? _journalDateRange; // null = toute période
  final TextEditingController _journalUserController = TextEditingController();
  int _journalPageIndex = 0;

  // Aperçu : filtre par usine (null = toutes, cartes résumées) ; une usine précise charge
  // en plus budgets & tendances (pertes) pour cette usine, sans les demander pour toutes
  // les usines à chaque rafraîchissement.
  String? _apercuUsineId;
  BudgetsStats? _apercuBudgets;
  TrendsStats? _apercuTrends;
  bool _apercuDetailLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    // Le bouton + n'a de sens que sur les onglets de gestion (pas Aperçu / Journal, qui ne
    // sont que de la lecture) : il faut donc reconstruire le Scaffold au changement d'onglet.
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _refreshData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _journalUserController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final usines = await _mongoService.getUsines();
      final postes = await _mongoService.getPostes();
      final assignments = await _mongoService.getPosteAssignments();
      final usineUsers = await _mongoService.getUsineUsers();
      if (!mounted) return;
      setState(() {
        _usines = usines;
        _postes = postes;
        _assignments = assignments;
        _usineUsers = usineUsers;
        _isLoading = false;
      });
      await Future.wait([_loadDashboards(), _loadJournalPage()]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur de chargement : $e";
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDashboards() async {
    setState(() => _dashboardsLoading = true);
    final entries = await Future.wait(
      _usines.where((u) => u.id != null).map((u) async {
        final stats = await _mongoService.getUsineDashboard(u.id!);
        return MapEntry(u.id!, stats);
      }),
    );
    if (!mounted) return;
    setState(() {
      _usineDashboards = {
        for (final e in entries)
          if (e.value != null) e.key: e.value!,
      };
      _dashboardsLoading = false;
    });
  }

  Future<void> _loadJournalPage() async {
    setState(() => _journalLoading = true);
    final page = await _mongoService.getUsineJournal(
      usineId: _journalUsineId,
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

  void _applyJournalUsine(String? usineId) {
    setState(() {
      _journalUsineId = usineId;
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

  Future<void> _applyApercuUsine(String? usineId) async {
    setState(() {
      _apercuUsineId = usineId;
      _apercuBudgets = null;
      _apercuTrends = null;
    });
    if (usineId == null) return;
    setState(() => _apercuDetailLoading = true);
    final results = await Future.wait([
      _mongoService.getBudgets(usineId),
      _mongoService.getTrends(usineId),
    ]);
    if (!mounted) return;
    setState(() {
      _apercuBudgets = results[0] as BudgetsStats?;
      _apercuTrends = results[1] as TrendsStats?;
      _apercuDetailLoading = false;
    });
  }

  String _usineNameFor(String? usineId) {
    if (usineId == null) return '—';
    return _usines
            .cast<Usine?>()
            .firstWhere((u) => u?.id == usineId, orElse: () => null)
            ?.name ??
        'Usine supprimée';
  }

  // ----------------------------------------------------------------- Aperçu

  Widget _buildMiniBarChart(List<MonthlyPoint> points, Color color) {
    if (points.isEmpty || points.every((p) => p.value == 0)) {
      return const SizedBox(
        height: 90,
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
      height: 120,
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
                    width: 14,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _statMini(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.orange, size: 16),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }

  /// Vue d'ensemble : statistiques + graphique de production de CHAQUE usine, sans avoir à
  /// entrer dans chacune une par une — le tableau de bord de l'admin, pas celui d'une usine.
  Widget _budgetStatusChip(String status) {
    final (label, color) = switch (status) {
      'depasse' => ('DÉPASSÉ', Colors.red),
      'sans_budget' => ('SANS BUDGET', Colors.grey),
      _ => ('OK', Colors.green),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  /// Détail budgets & tendances d'UNE usine (chargé à la demande, pas pour toutes les
  /// usines à chaque fois) : ce que l'onglet Budgets d'une usine montre déjà, condensé ici
  /// pour que l'admin n'ait pas besoin d'y entrer pour ces mêmes chiffres.
  Widget _buildApercuDrilldown() {
    if (_apercuDetailLoading) {
      return const Padding(
        padding: EdgeInsets.only(top: 20),
        child: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }
    final budgets = _apercuBudgets;
    final trends = _apercuTrends;
    final valueFmt = NumberFormat.compact(locale: 'fr_FR');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        _sectionLabel('BUDGETS DU MOIS'),
        const SizedBox(height: 10),
        if (budgets == null || budgets.categories.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Aucun budget configuré pour cette usine.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade100),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _statMini(
                      Icons.account_balance_outlined,
                      valueFmt.format(budgets.totalBudget),
                      'Budget total',
                    ),
                    const SizedBox(width: 8),
                    _statMini(
                      Icons.shopping_cart_outlined,
                      valueFmt.format(budgets.totalRealized),
                      'Réalisé',
                    ),
                    const SizedBox(width: 8),
                    _statMini(
                      budgets.variancePercent > 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      '${budgets.variancePercent.toStringAsFixed(0)}%',
                      'Écart',
                    ),
                  ],
                ),
                const Divider(height: 24),
                for (final c in budgets.categories)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.category,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        _budgetStatusChip(c.status),
                        const SizedBox(width: 8),
                        Text(
                          '${valueFmt.format(c.realizedFcfa)} / ${valueFmt.format(c.budgetFcfa)}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        _sectionLabel('PERTES / AVARIES (6 MOIS)'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
          ),
          child: _buildMiniBarChart(
            trends?.lossesTrend ?? [],
            Colors.amber.shade700,
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.grey.shade500,
        fontWeight: FontWeight.w800,
        fontSize: 11,
        letterSpacing: .5,
      ),
    );
  }

  Widget _buildApercuTab() {
    if (_dashboardsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orange),
      );
    }
    if (_usines.isEmpty) {
      return const Center(
        child: Text(
          'Aucune usine configurée.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    final valueFmt = NumberFormat.compact(locale: 'fr_FR');
    final visibleUsines = _apercuUsineId == null
        ? _usines
        : _usines.where((u) => u.id == _apercuUsineId).toList();
    return RefreshIndicator(
      onRefresh: _loadDashboards,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          DropdownButtonFormField<String?>(
            isExpanded: true,
            value: _apercuUsineId,
            decoration: const InputDecoration(
              labelText: 'Usine',
              isDense: true,
              prefixIcon: Icon(Icons.factory_outlined, size: 18),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Toutes les usines'),
              ),
              ..._usines
                  .where((u) => u.id != null)
                  .map(
                    (u) => DropdownMenuItem(value: u.id, child: Text(u.name)),
                  ),
            ],
            onChanged: _applyApercuUsine,
          ),
          const SizedBox(height: 16),
          for (final usine in visibleUsines) ...[
            Builder(
              builder: (context) {
                final d = usine.id != null ? _usineDashboards[usine.id!] : null;
                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
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
                          CircleAvatar(
                            backgroundColor:
                                (usine.isActive ? Colors.orange : Colors.grey)
                                    .withValues(alpha: 0.1),
                            child: Icon(
                              Icons.factory_rounded,
                              color: usine.isActive
                                  ? Colors.orange
                                  : Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              usine.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (d == null)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Aucune donnée pour cette usine.',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _statMini(
                              Icons.trending_up_rounded,
                              '${d.productionThisMonthKg.toStringAsFixed(0)} kg',
                              'Production',
                            ),
                            const SizedBox(width: 8),
                            _statMini(
                              Icons.payments_outlined,
                              '${d.avgCostPerKg.toStringAsFixed(0)} F',
                              'Coût moyen /kg',
                            ),
                            const SizedBox(width: 8),
                            _statMini(
                              Icons.account_balance_wallet_outlined,
                              valueFmt.format(d.stockValueFcfa),
                              'Valeur stock',
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _buildMiniBarChart(d.monthlyProduction, Colors.orange),
                      ],
                      if (_apercuUsineId == usine.id) _buildApercuDrilldown(),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- Journal

  static const Map<String, String> _collectionLabels = {
    'raw_materials': 'Matières premières',
    'formulas': 'Formules',
    'receptions': 'Réceptions',
    'raw_material_batches': 'Lots matières premières',
    'cost_adjustments': 'Ajustements CUMP',
    'stock_losses': 'Pertes / avaries',
    'production_batches': 'Production',
    'inventory_sessions': 'Inventaires',
    'feed_stock_batches': 'Stock aliment produit',
    'deliveries': 'Livraisons',
    'usines': 'Usines',
    'usine_users': 'Utilisateurs usine',
    'postes': 'Postes',
    'poste_assignments': 'Affectations',
    'drivers': 'Chauffeurs',
    'vehicles': 'Véhicules',
  };

  static const Map<String, (String, Color, IconData)> _actionMeta = {
    'CREATE': ('Création', Colors.green, Icons.add_circle_outline),
    'UPDATE': ('Modification', Colors.blue, Icons.edit_outlined),
    'DELETE': ('Suppression', Colors.red, Icons.delete_outline),
  };

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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

  /// Détail d'une entrée du journal, ouvert au clic — la ligne de liste ne donne qu'un
  /// résumé compact, tout le reste (usine, catégorie technique, horodatage précis) apparaît
  /// ici plutôt que d'alourdir chaque ligne.
  void _showJournalDetailDialog(AuditLogEntry e) {
    final meta =
        _actionMeta[e.action] ?? (e.action, Colors.grey, Icons.circle_outlined);
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
              _detailRow('Usine', _usineNameFor(e.usineId)),
              _detailRow('Utilisateur', e.userName),
              _detailRow(
                'Catégorie',
                _collectionLabels[e.collection] ?? e.collection,
              ),
              _detailRow(
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

  /// Historique de TOUTES les usines confondues par défaut — filtrable par usine,
  /// catégorie, action, utilisateur et période : un logiciel de gestion doit pouvoir
  /// retrouver n'importe quelle écriture, pas seulement la parcourir en scrollant.
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
                    child: DropdownButtonFormField<String?>(
                      isExpanded: true,
                      value: _journalUsineId,
                      decoration: const InputDecoration(
                        labelText: 'Usine',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Toutes les usines'),
                        ),
                        ..._usines
                            .where((u) => u.id != null)
                            .map(
                              (u) => DropdownMenuItem(
                                value: u.id,
                                child: Text(u.name),
                              ),
                            ),
                      ],
                      onChanged: _applyJournalUsine,
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
              const SizedBox(height: 8),
              TextField(
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
                    for (final entry in _adminJournalTypeLabels.entries) ...[
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
                    for (final entry in _actionMeta.entries) ...[
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
                        _actionMeta[e.action] ??
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
                                text: '${_usineNameFor(e.usineId)} · ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12.5,
                                  color: Colors.orange,
                                ),
                              ),
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

  // ---------------------------------------------------------------- Usines

  void _showUsineDialog({Usine? usine}) {
    final nameController = TextEditingController(text: usine?.name ?? '');
    final addressController = TextEditingController(text: usine?.address ?? '');
    bool isActive = usine?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            usine == null ? 'Nouvelle usine' : 'Modifier l\'usine',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Nom de l'usine",
                    prefixIcon: Icon(Icons.factory_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Adresse (optionnel)',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: isActive,
                  activeColor: Colors.orange,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final newUsine = Usine(
                  id: usine?.id,
                  name: nameController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                  isActive: isActive,
                );
                if (usine == null) {
                  await _mongoService.addUsine(newUsine);
                } else {
                  await _mongoService.updateUsine(newUsine);
                }
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsinesTab() {
    if (_usines.isEmpty)
      return const Center(
        child: Text(
          'Aucune usine. Ajoutez-en une avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _usines.length,
      itemBuilder: (context, index) {
        final usine = _usines[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            onTap: () => _showUsineActionsSheet(usine),
            leading: CircleAvatar(
              backgroundColor: (usine.isActive ? Colors.orange : Colors.grey)
                  .withValues(alpha: 0.1),
              child: Icon(
                Icons.factory_rounded,
                color: usine.isActive ? Colors.orange : Colors.grey,
              ),
            ),
            title: Text(
              usine.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              usine.address ?? (usine.isActive ? 'Active' : 'Inactive'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        );
      },
    );
  }

  /// Un seul point d'entrée, clairement libellé, pour naviguer vers les écrans propres à
  /// une usine — plutôt que de disperser ces raccourcis en icônes cryptiques dans chaque
  /// écran (ce qui rendait la barre du haut du référentiel illisible).
  void _showUsineActionsSheet(Usine usine) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.factory_rounded,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    usine.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: Colors.indigo,
              ),
              title: const Text('Référentiel'),
              subtitle: const Text(
                'Matières premières & formules',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineReferentielScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.teal,
              ),
              title: const Text('Approvisionnement'),
              subtitle: const Text(
                'Réceptions, lots, pertes, inventaire',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineApproScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.precision_manufacturing_outlined,
                color: Colors.deepPurple,
              ),
              title: const Text('Production'),
              subtitle: const Text(
                'Fabrication & coût de revient',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineProductionScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.teal,
              ),
              title: const Text('Stock & livraison'),
              subtitle: const Text(
                'Stock d\'aliment produit, livraisons',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineStockLivraisonScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.calculate_outlined,
                color: Colors.orange,
              ),
              title: const Text('Simulation'),
              subtitle: const Text(
                'Ce qu\'on peut produire, plan optimisé',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineSimulationScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.bar_chart_rounded,
                color: Colors.blueGrey,
              ),
              title: const Text('Statistiques'),
              subtitle: const Text(
                'Consommation, traçabilité, budgets',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineStatsScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.summarize_outlined,
                color: Colors.brown,
              ),
              title: const Text('Rapport de production'),
              subtitle: const Text(
                'Matière, production, livraison — format WhatsApp',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineDailyReportScreen(usine: usine),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.blue),
              title: const Text('Modifier l\'usine'),
              onTap: () {
                Navigator.pop(context);
                _showUsineDialog(usine: usine);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: const Text('Supprimer l\'usine'),
              onTap: () async {
                Navigator.pop(context);
                await _mongoService.deleteUsine(usine.id!);
                _refreshData();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Postes

  void _showPosteDialog({Poste? poste}) {
    final nameController = TextEditingController(text: poste?.name ?? '');
    PostePermissions perms = poste?.permissions ?? const PostePermissions();
    bool isActive = poste?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            poste == null ? 'Nouveau poste' : 'Modifier le poste',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modèles rapides',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: posteTemplates
                        .map(
                          (t) => ActionChip(
                            label: Text(
                              t.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: Colors.orange.shade50,
                            side: BorderSide(color: Colors.orange.shade200),
                            onPressed: () => setDialogState(() {
                              nameController.text = t.name;
                              perms = t.permissions;
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText:
                          'Nom du poste (ex : Magasinier de l\'usine, Caissier)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Actif'),
                    value: isActive,
                    activeColor: Colors.orange,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                  const Divider(),
                  const Text(
                    'Permissions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  ...PostePermissions.labels.map(
                    (entry) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: Colors.orange,
                      title: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 13),
                      ),
                      value: perms[entry.key],
                      onChanged: (v) => setDialogState(
                        () => perms = perms.copyWith(entry.key, v ?? false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final newPoste = Poste(
                  id: poste?.id,
                  name: nameController.text.trim(),
                  permissions: perms,
                  isActive: isActive,
                );
                await runBlocking(context, () async {
                  if (poste == null) {
                    await _mongoService.addPoste(newPoste);
                  } else {
                    await _mongoService.updatePoste(newPoste);
                  }
                  await _refreshData();
                });
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostesTab() {
    if (_postes.isEmpty)
      return const Center(
        child: Text(
          'Aucun poste. Créez-en un avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _postes.length,
      itemBuilder: (context, index) {
        final poste = _postes[index];
        final activeCount = PostePermissions.labels
            .where((e) => poste.permissions[e.key])
            .length;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.indigo.withValues(alpha: 0.1),
              child: const Icon(Icons.badge_rounded, color: Colors.indigo),
            ),
            title: Text(
              poste.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '$activeCount permission(s) active(s)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.edit_rounded,
                    color: Colors.blue,
                    size: 20,
                  ),
                  onPressed: () => _showPosteDialog(poste: poste),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: () async {
                    await runBlocking(context, () async {
                      await _mongoService.deletePoste(poste.id!);
                      await _refreshData();
                    });
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------- Utilisateurs usine

  void _showUsineUserDialog({UsineUser? usineUser}) {
    final nameController = TextEditingController(text: usineUser?.name ?? '');
    final passwordController = TextEditingController();
    bool isActive = usineUser?.isActive ?? true;
    String? selectedPosteId = _postes.isNotEmpty ? _postes.first.id : null;
    String? selectedUsineId = _usines.isNotEmpty ? _usines.first.id : null;
    // Affectations existantes (édition uniquement) : gérées en direct dans ce même dialog,
    // pour que le crayon suffise — plus besoin d'un écran séparé pour poste/usine.
    List<PosteAssignment> currentAssignments = usineUser == null
        ? []
        : _assignments.where((a) => a.userId == usineUser.id).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            usineUser == null
                ? 'Nouvel utilisateur usine'
                : 'Modifier ${usineUser.name}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: usineUser == null
                          ? 'Mot de passe'
                          : 'Nouveau mot de passe (laisser vide si inchangé)',
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Actif'),
                    value: isActive,
                    activeColor: Colors.orange,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Postes & usines',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (usineUser != null) ...[
                    if (currentAssignments.isEmpty)
                      const Text(
                        'Aucune affectation pour le moment.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    else
                      ...currentAssignments.map((a) {
                        final posteName =
                            _postes
                                .cast<Poste?>()
                                .firstWhere(
                                  (p) => p?.id == a.posteId,
                                  orElse: () => null,
                                )
                                ?.name ??
                            '?';
                        final usineName =
                            _usines
                                .cast<Usine?>()
                                .firstWhere(
                                  (us) => us?.id == a.usineId,
                                  orElse: () => null,
                                )
                                ?.name ??
                            '?';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '$posteName · $usineName',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            onPressed: () async {
                              final updated = await runBlocking(context, () async {
                                await _mongoService.deletePosteAssignment(
                                  a.id!,
                                );
                                return _mongoService.getPosteAssignments(
                                  userId: usineUser.id,
                                );
                              });
                              setDialogState(
                                () => currentAssignments = updated,
                              );
                              await _refreshData();
                            },
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                  ],
                  if (_postes.isEmpty || _usines.isEmpty)
                    Text(
                      _postes.isEmpty
                          ? 'Créez d\'abord un poste (onglet Postes).'
                          : 'Créez d\'abord une usine (onglet Usines).',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Poste'),
                          value: selectedPosteId,
                          items: _postes
                              .where((p) => p.id != null)
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    p.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedPosteId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Usine'),
                          value: selectedUsineId,
                          items: _usines
                              .where((u) => u.id != null)
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u.id,
                                  child: Text(
                                    u.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedUsineId = v),
                        ),
                        if (usineUser != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.orange,
                            ),
                            label: const Text(
                              'Ajouter cette affectation',
                              style: TextStyle(color: Colors.orange),
                            ),
                            onPressed: () async {
                              if (selectedPosteId == null ||
                                  selectedUsineId == null)
                                return;
                              final updated = await runBlocking(context, () async {
                                await _mongoService.addPosteAssignment(
                                  PosteAssignment(
                                    userId: usineUser.id!,
                                    posteId: selectedPosteId!,
                                    usineId: selectedUsineId!,
                                  ),
                                );
                                return _mongoService.getPosteAssignments(
                                  userId: usineUser.id,
                                );
                              });
                              setDialogState(
                                () => currentAssignments = updated,
                              );
                              await _refreshData();
                            },
                          ),
                        ],
                      ],
                    ),
                  if (usineUser == null &&
                      (_postes.isNotEmpty && _usines.isNotEmpty))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Cette affectation sera créée avec l\'utilisateur.',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                if (usineUser == null && passwordController.text.isEmpty)
                  return;
                final newUser = UsineUser(
                  id: usineUser?.id,
                  name: nameController.text.trim(),
                  password: passwordController.text.isEmpty
                      ? usineUser!.password
                      : passwordController.text,
                  isActive: isActive,
                );
                await runBlocking(context, () async {
                  if (usineUser == null) {
                    final created = await _mongoService.addUsineUser(newUser);
                    if (created?.id != null &&
                        selectedPosteId != null &&
                        selectedUsineId != null) {
                      await _mongoService.addPosteAssignment(
                        PosteAssignment(
                          userId: created!.id!,
                          posteId: selectedPosteId!,
                          usineId: selectedUsineId!,
                        ),
                      );
                    }
                  } else {
                    await _mongoService.updateUsineUser(newUser);
                  }
                  await _refreshData();
                });
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsineUsersTab() {
    if (_usineUsers.isEmpty)
      return const Center(
        child: Text(
          'Aucun utilisateur usine. Ajoutez-en un avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _usineUsers.length,
      itemBuilder: (context, index) {
        final u = _usineUsers[index];
        final userAssignments = _assignments
            .where((a) => a.userId == u.id)
            .toList();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
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
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: (u.isActive ? Colors.purple : Colors.grey)
                      .withValues(alpha: 0.1),
                  child: Icon(
                    Icons.person_rounded,
                    color: u.isActive ? Colors.purple : Colors.grey,
                  ),
                ),
                title: Text(
                  u.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  u.isActive ? 'Actif' : 'Inactif',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.edit_rounded,
                        color: Colors.blue,
                        size: 20,
                      ),
                      onPressed: () => _showUsineUserDialog(usineUser: u),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () async {
                        await runBlocking(context, () async {
                          await _mongoService.deleteUsineUser(u.id!);
                          await _refreshData();
                        });
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: userAssignments.isEmpty
                    ? GestureDetector(
                        onTap: () => _showUsineUserDialog(usineUser: u),
                        child: const Text(
                          '⚠ Aucune usine ni poste affecté — toucher pour affecter',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: userAssignments.map((a) {
                          final posteName =
                              _postes
                                  .cast<Poste?>()
                                  .firstWhere(
                                    (p) => p?.id == a.posteId,
                                    orElse: () => null,
                                  )
                                  ?.name ??
                              '?';
                          final usineName =
                              _usines
                                  .cast<Usine?>()
                                  .firstWhere(
                                    (us) => us?.id == a.usineId,
                                    orElse: () => null,
                                  )
                                  ?.name ??
                              '?';
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Colors.teal.shade50,
                            label: Text(
                              '$posteName · $usineName',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onDeleted: () async {
                              await runBlocking(context, () async {
                                await _mongoService.deletePosteAssignment(
                                  a.id!,
                                );
                                await _refreshData();
                              });
                            },
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------- Affectations

  void _showAssignmentDialog({String? presetUserId}) {
    if (_usineUsers.isEmpty || _postes.isEmpty || _usines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Il faut au moins un utilisateur usine, un poste et une usine.',
          ),
        ),
      );
      return;
    }
    String? selectedUserId = presetUserId ?? _usineUsers.first.id;
    String? selectedPosteId = _postes.first.id;
    String? selectedUsineId = _usines.first.id;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Affecter un poste',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Utilisateur usine',
                  ),
                  value: selectedUserId,
                  items: _usineUsers
                      .where((u) => u.id != null)
                      .map(
                        (u) =>
                            DropdownMenuItem(value: u.id, child: Text(u.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedUserId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Poste'),
                  value: selectedPosteId,
                  items: _postes
                      .where((p) => p.id != null)
                      .map(
                        (p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedPosteId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Usine'),
                  value: selectedUsineId,
                  items: _usines
                      .where((u) => u.id != null)
                      .map(
                        (u) =>
                            DropdownMenuItem(value: u.id, child: Text(u.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedUsineId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedUserId == null ||
                    selectedPosteId == null ||
                    selectedUsineId == null)
                  return;
                await runBlocking(context, () async {
                  await _mongoService.addPosteAssignment(
                    PosteAssignment(
                      userId: selectedUserId!,
                      posteId: selectedPosteId!,
                      usineId: selectedUsineId!,
                    ),
                  );
                  await _refreshData();
                });
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Affecter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsTab() {
    if (_assignments.isEmpty)
      return const Center(
        child: Text(
          'Aucune affectation. Ajoutez-en une avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _assignments.length,
      itemBuilder: (context, index) {
        final a = _assignments[index];
        final userName =
            _usineUsers
                .cast<UsineUser?>()
                .firstWhere((u) => u?.id == a.userId, orElse: () => null)
                ?.name ??
            a.userId;
        final posteName =
            _postes
                .cast<Poste?>()
                .firstWhere((p) => p?.id == a.posteId, orElse: () => null)
                ?.name ??
            a.posteId;
        final usineName =
            _usines
                .cast<Usine?>()
                .firstWhere((u) => u?.id == a.usineId, orElse: () => null)
                ?.name ??
            a.usineId;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.teal.withValues(alpha: 0.1),
              child: const Icon(
                Icons.assignment_ind_rounded,
                color: Colors.teal,
              ),
            ),
            title: Text(
              userName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '$posteName · $usineName',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              onPressed: () async {
                await runBlocking(context, () async {
                  await _mongoService.deletePosteAssignment(a.id!);
                  await _refreshData();
                });
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'USINE ALIMENT — ADMIN',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _refreshData,
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
            Tab(text: 'Journal'),
            Tab(text: 'Usines'),
            Tab(text: 'Postes'),
            Tab(text: 'Utilisateurs'),
            Tab(text: 'Affectations'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildApercuTab(),
                _buildJournalTab(),
                _buildUsinesTab(),
                _buildPostesTab(),
                _buildUsineUsersTab(),
                _buildAssignmentsTab(),
              ],
            ),
      floatingActionButton: _tabController.index < 2
          ? null
          : FloatingActionButton(
              backgroundColor: Colors.orange,
              onPressed: () {
                if (_tabController.index == 2)
                  _showUsineDialog();
                else if (_tabController.index == 3)
                  _showPosteDialog();
                else if (_tabController.index == 4)
                  _showUsineUserDialog();
                else
                  _showAssignmentDialog();
              },
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }
}
