import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/formula.dart';
import '../models/farm_feed_stock.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'farm_feed_stock_history_screen.dart';

enum _FsSort { alpha, status }

class _FarmFeedStockStatus {
  final Farm farm;
  final FarmFeedStock? feedStock;
  _FarmFeedStockStatus({required this.farm, this.feedStock});
}

/// Aliments de départ d'une ferme (réservé à l'admin) : le stock d'aliment déjà présent dans
/// le bâtiment, réparti par aliment (référentiel "formulas" du module Usine Aliment) — jamais
/// lié à un lot de sujets, contrairement à AdminLotHeadcountsScreen pour les effectifs (ce
/// stock ne redémarre pas à zéro à l'arrivée d'un nouveau lot).
///
/// Liste des fermes avec leur statut (stock défini ou non) — tapoter une ferme ouvre l'écran
/// de saisie dédié (AdminFarmFeedStockEditScreen).
class AdminFarmFeedStocksScreen extends StatefulWidget {
  const AdminFarmFeedStocksScreen({super.key});

  @override
  State<AdminFarmFeedStocksScreen> createState() => _AdminFarmFeedStocksScreenState();
}

class _AdminFarmFeedStocksScreenState extends State<AdminFarmFeedStocksScreen> {
  final MongoService _mongoService = MongoService();
  List<_FarmFeedStockStatus> _statuses = [];
  bool _loading = true;
  _FsSort _sortMode = _FsSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<_FarmFeedStockStatus> get _visible {
    var list = _statuses;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((s) => s.farm.name.toLowerCase().contains(q)).toList();
    } else {
      list = List.of(list);
    }
    list.sort((a, b) => _sortMode == _FsSort.alpha
        ? a.farm.name.toLowerCase().compareTo(b.farm.name.toLowerCase())
        : (a.feedStock != null ? 1 : 0).compareTo(b.feedStock != null ? 1 : 0));
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
    final farms = List.of(await _mongoService.getFarms())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final statuses = await Future.wait(farms.map((farm) async {
      final feedStock = await _mongoService.getFarmFeedStock(farm.name);
      return _FarmFeedStockStatus(farm: farm, feedStock: feedStock);
    }));
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _loading = false;
    });
  }

  Future<void> _openFarm(_FarmFeedStockStatus s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminFarmFeedStockEditScreen(farm: s.farm)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final defined = _statuses.where((s) => s.feedStock != null).length;
    final toDefine = _statuses.length - defined;

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Aliments de départ'),
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
                          value: '$defined',
                          label: 'Stocks définis',
                          color: DailyReportColors.green700,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$toDefine',
                          label: 'À définir',
                          color: DailyReportColors.yellow600,
                          icon: Icons.hourglass_top_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const DailyReportSectionLabel('Par ferme'),
                  DailySearchSortBar<_FsSort>(
                    controller: _searchController,
                    hintText: 'Rechercher un bâtiment…',
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    sortValue: _sortMode,
                    onSortChanged: (v) => setState(() => _sortMode = v),
                    sortOptions: const [
                      DailySortOption(_FsSort.alpha, 'Alphabétique (A→Z)'),
                      DailySortOption(_FsSort.status, 'À définir en premier'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else
                    for (final s in _visible) _farmCard(s),
                ],
              ),
            ),
    );
  }

  Widget _farmCard(_FarmFeedStockStatus s) {
    final defined = s.feedStock != null;
    final color = defined ? DailyReportColors.green600 : DailyReportColors.yellow500;
    return DailyReportCard(
      accentColor: color,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        InkWell(
          onTap: () => _openFarm(s),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.farm.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    if (defined) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${s.feedStock!.totalKg} kg',
                        style: const TextStyle(color: DailyReportColors.green700, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              DailyReportStatusBadge(
                label: defined ? 'DÉFINIS' : 'À DÉFINIR',
                color: color,
                icon: defined ? Icons.check_rounded : Icons.priority_high_rounded,
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ],
    );
  }
}

/// Écran de saisie des aliments de départ pour une ferme, un champ (kg) par aliment actif du
/// référentiel — total recalculé en direct pendant la saisie. Jamais de sélection de lot ici.
class AdminFarmFeedStockEditScreen extends StatefulWidget {
  final Farm farm;

  const AdminFarmFeedStockEditScreen({super.key, required this.farm});

  @override
  State<AdminFarmFeedStockEditScreen> createState() => _AdminFarmFeedStockEditScreenState();
}

class _AdminFarmFeedStockEditScreenState extends State<AdminFarmFeedStockEditScreen> {
  final MongoService _mongoService = MongoService();
  List<Formula> _formulas = [];
  bool _loading = true;
  final Map<String, TextEditingController> _quantityControllers = {};
  bool _saving = false;
  String? _message;
  bool _success = false;
  FarmFeedStock? _existingFeedStock;

  double get _totalKg => _formulas.fold<double>(
        0,
        (a, f) => a + (double.tryParse((_quantityControllers[f.id]?.text ?? '0').replaceAll(',', '.')) ?? 0),
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final formulas = List.of(await _mongoService.getAllFormulas())
      ..retainWhere((f) => f.isActive)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    for (final f in formulas) {
      _quantityControllers[f.id ?? f.name] = TextEditingController(text: '0')..addListener(_onChanged);
    }
    final existing = await _mongoService.getFarmFeedStock(widget.farm.name);
    if (!mounted) return;
    setState(() {
      _formulas = formulas;
      _loading = false;
      if (existing == null) {
        _message = "Aucun stock déjà enregistré pour cette ferme — c'est une première saisie.";
        return;
      }
      _existingFeedStock = existing;
      for (final q in existing.quantities) {
        _quantityControllers[q.formulaId]?.text = _formatQty(q.quantityKg);
      }
      _message = 'Valeurs existantes chargées — modification possible.';
    });
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in _quantityControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Une resaisie écrase la valeur courante (l'historique la conserve côté backend, voir
  /// PUT /farm-feed-stocks) : on le fait savoir explicitement avant d'enregistrer plutôt que
  /// de remplacer silencieusement un stock déjà en place.
  Future<bool> _confirmOverwriteIfNeeded() async {
    final existing = _existingFeedStock;
    if (existing == null) return true;
    final dateStr = existing.updatedAt != null
        ? DateFormat('dd/MM/yyyy à HH:mm').format(existing.updatedAt!)
        : null;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text('Remplacer le stock existant ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ],
        ),
        content: Text(
          'Un stock d\'aliment de départ est déjà enregistré pour ${widget.farm.name}'
          '${dateStr != null ? ' (saisi le $dateStr${existing.performedBy != null ? ' par ${existing.performedBy}' : ''})' : ''} '
          ': ${existing.totalKg} kg.\n\n'
          'Enregistrer va le remplacer par cette nouvelle saisie. L\'ancienne valeur restera consultable dans l\'historique.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULER')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMPLACER'),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _save() async {
    if (!await _confirmOverwriteIfNeeded()) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final feedStock = FarmFeedStock(
      farmName: widget.farm.name,
      quantities: _formulas
          .map((f) => FeedStartingQuantity(
                formulaId: f.id ?? '',
                formulaName: f.name,
                quantityKg: double.tryParse((_quantityControllers[f.id]?.text ?? '0').replaceAll(',', '.')) ?? 0,
              ))
          .toList(),
    );
    final result = await _mongoService.upsertFarmFeedStock(feedStock);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = result.error == null;
      _message = result.error ?? 'Enregistré : ${result.feedStock!.totalKg} kg';
      if (result.feedStock != null) _existingFeedStock = result.feedStock;
    });
  }

  String _formatQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farm.name, subtitle: 'Aliments de départ'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_existingFeedStock != null) ...[
                  _existingFeedStockCard(_existingFeedStock!),
                  _historyButton(),
                  const SizedBox(height: 12),
                ],
                const DailyReportSectionLabel('Nouvelle saisie', icon: Icons.edit_note_rounded),
                DailyReportStatTile(
                  value: '${_totalKg.toStringAsFixed(_totalKg == _totalKg.roundToDouble() ? 0 : 2)} kg',
                  label: 'Total aliments',
                  color: DailyReportColors.green700,
                  icon: Icons.inventory_2_rounded,
                ),
                const SizedBox(height: 18),
                const DailyReportSectionLabel('Par aliment', icon: Icons.grain_rounded),
                if (_formulas.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text(
                        "Aucun aliment actif dans le référentiel Usine Aliment.",
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  )
                else
                  for (final f in _formulas) _formulaCard(f),
                if (_message != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4, bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _success ? DailyReportColors.green100 : DailyReportColors.yellow100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _message!,
                      style: TextStyle(color: _success ? DailyReportColors.green900 : DailyReportColors.yellow600, fontWeight: FontWeight.w600, fontSize: 12.5),
                    ),
                  ),
                Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(colors: [DailyReportColors.green700, DailyReportColors.green600]),
                    boxShadow: [
                      BoxShadow(color: DailyReportColors.green700.withValues(alpha: 0.32), blurRadius: 12, offset: const Offset(0, 5)),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _saving ? null : _save,
                      child: Center(
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// Détail du stock déjà en base pour cette ferme — affiché avant toute saisie : ce que
  /// l'admin s'apprête à écraser doit être visible avant qu'il ne le fasse.
  Widget _existingFeedStockCard(FarmFeedStock existing) {
    final dateStr = existing.updatedAt != null
        ? DateFormat('dd/MM/yyyy à HH:mm').format(existing.updatedAt!)
        : null;
    return DailyReportCard(
      accentColor: DailyReportColors.green700,
      margin: const EdgeInsets.only(bottom: 4),
      children: [
        Row(
          children: [
            const Icon(Icons.fact_check_rounded, size: 18, color: DailyReportColors.green700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Stock actuellement enregistré', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ],
        ),
        if (dateStr != null || existing.performedBy != null) ...[
          const SizedBox(height: 2),
          Text(
            'Saisi le ${dateStr ?? '—'}${existing.performedBy != null ? ' par ${existing.performedBy}' : ''}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 10),
        for (final q in existing.quantities)
          if (q.quantityKg > 0) _existingRow(q.formulaName, q.quantityKg),
        const Divider(height: 18),
        Row(
          children: [
            const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
            Text(
              '${existing.totalKg} kg',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DailyReportColors.green700),
            ),
          ],
        ),
      ],
    );
  }

  /// Un simple bouton vers la page dédiée (paginée) de l'historique — jamais chargé ici.
  Widget _historyButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => FarmFeedStockHistoryScreen(farmName: widget.farm.name)),
        ),
        icon: const Icon(Icons.history_rounded, size: 18),
        label: const Text("Voir l'historique des aliments de départ"),
        style: OutlinedButton.styleFrom(
          foregroundColor: DailyReportColors.green700,
          side: const BorderSide(color: DailyReportColors.green600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(double.infinity, 42),
        ),
      ),
    );
  }

  Widget _existingRow(String label, double quantityKg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('$quantityKg kg', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _formulaCard(Formula f) {
    return DailyReportCard(
      children: [
        Row(
          children: [
            const Icon(Icons.grain_rounded, size: 18, color: DailyReportColors.green700),
            const SizedBox(width: 8),
            Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _quantityControllers[f.id ?? f.name],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Quantité (kg)', isDense: true, border: OutlineInputBorder()),
        ),
      ],
    );
  }
}
