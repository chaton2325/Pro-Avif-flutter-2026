import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/lot_egg_stock.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'current_egg_stock_screen.dart';
import 'lot_egg_stock_history_screen.dart';

enum _EsSort { alpha, status }

class _FarmEggStockStatus {
  final Farm farm;
  final String? lotNumber;
  final LotEggStock? eggStock;
  _FarmEggStockStatus({required this.farm, this.lotNumber, this.eggStock});
}

int _totalPo(LotEggStock s) => s.po;

/// Stock d'œufs de départ d'un lot, GLOBAL au bâtiment (réservé à l'admin) : une seule saisie
/// par bâtiment, sans détail par salle — une pondeuse peut déjà être en ponte avant que ce lot
/// ne soit suivi ici. Les rapports journaliers en partent pour le stock d'œufs du bâtiment ;
/// les cumuls, eux, restent par salle (voir routers/lot_egg_stocks.py + daily_reports.py).
///
/// Liste des fermes avec leur statut (stock défini ou non pour le lot en cours) — tapoter une
/// ferme ouvre l'écran de saisie dédié (AdminLotEggStockEditScreen).
class AdminLotEggStocksScreen extends StatefulWidget {
  const AdminLotEggStocksScreen({super.key});

  @override
  State<AdminLotEggStocksScreen> createState() => _AdminLotEggStocksScreenState();
}

class _AdminLotEggStocksScreenState extends State<AdminLotEggStocksScreen> {
  final MongoService _mongoService = MongoService();
  List<_FarmEggStockStatus> _statuses = [];
  bool _loading = true;
  _EsSort _sortMode = _EsSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<_FarmEggStockStatus> get _visible {
    var list = _statuses;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((s) => s.farm.name.toLowerCase().contains(q)).toList();
    } else {
      list = List.of(list);
    }
    list.sort((a, b) => _sortMode == _EsSort.alpha
        ? a.farm.name.toLowerCase().compareTo(b.farm.name.toLowerCase())
        : (a.eggStock != null ? 1 : 0).compareTo(b.eggStock != null ? 1 : 0));
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
      final lotNumber = await _mongoService.getCurrentLotForFarm(farm.name);
      LotEggStock? eggStock;
      if (lotNumber != null) {
        eggStock = await _mongoService.getLotEggStock(farm.name, lotNumber);
      }
      return _FarmEggStockStatus(farm: farm, lotNumber: lotNumber, eggStock: eggStock);
    }));
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _loading = false;
    });
  }

  Future<void> _openFarm(_FarmEggStockStatus s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminLotEggStockEditScreen(farm: s.farm, initialLotNumber: s.lotNumber),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final defined = _statuses.where((s) => s.eggStock != null).length;
    final toDefine = _statuses.length - defined;

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar("Stock d'œufs de départ"),
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
                          label: 'Définis',
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
                  DailySearchSortBar<_EsSort>(
                    controller: _searchController,
                    hintText: 'Rechercher un bâtiment…',
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    sortValue: _sortMode,
                    onSortChanged: (v) => setState(() => _sortMode = v),
                    sortOptions: const [
                      DailySortOption(_EsSort.alpha, 'Alphabétique (A→Z)'),
                      DailySortOption(_EsSort.status, 'À définir en premier'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else
                    DailyReportFarmGrid(children: [for (final s in _visible) _farmCard(s)]),
                ],
              ),
            ),
    );
  }

  Widget _farmCard(_FarmEggStockStatus s) {
    final defined = s.eggStock != null;
    final color = defined ? DailyReportColors.green600 : DailyReportColors.yellow500;
    return DailyReportFarmGridCard(
      title: s.farm.name,
      accentColor: color,
      subtitle: [
        s.lotNumber != null ? 'Lot ${s.lotNumber}' : 'Aucun lot en cours',
        if (defined) 'PO ${_totalPo(s.eggStock!)}',
      ].join(' · '),
      badge: DailyReportStatusBadge(
        label: defined ? 'DÉFINI' : 'À DÉFINIR',
        color: color,
        icon: defined ? Icons.check_rounded : Icons.priority_high_rounded,
      ),
      trailingActions: [
        IconButton(
          icon: const Icon(Icons.visibility_outlined, color: DailyReportColors.green700, size: 18),
          tooltip: 'Voir le stock actuel',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => CurrentEggStockScreen(farmName: s.farm.name)),
          ),
        ),
      ],
      onTap: () => _openFarm(s),
    );
  }
}

/// Écran de saisie du stock d'œufs de départ pour une ferme + un lot précis (OAC, PO, DJ,
/// CAS, SAL par salle).
class AdminLotEggStockEditScreen extends StatefulWidget {
  final Farm farm;
  final String? initialLotNumber;

  const AdminLotEggStockEditScreen({super.key, required this.farm, this.initialLotNumber});

  @override
  State<AdminLotEggStockEditScreen> createState() => _AdminLotEggStockEditScreenState();
}

const _newLotSentinel = '__new_lot__';
const _kEggFields = ['oac', 'po', 'dj', 'cas', 'sal'];
const _kEggFieldLabels = {'oac': 'OAC', 'po': 'PO', 'dj': 'DJ', 'cas': 'CAS', 'sal': 'SAL'};

class _AdminLotEggStockEditScreenState extends State<AdminLotEggStockEditScreen> {
  final MongoService _mongoService = MongoService();
  List<String> _lotNumbers = [];
  String? _selectedLot;
  bool _loadingLots = true;
  // field -> controller (stock global du bâtiment, pas de détail par salle)
  final Map<String, TextEditingController> _controllers = {};
  bool _saving = false;
  String? _message;
  bool _success = false;
  LotEggStock? _existingEggStock;

  int _valueOf(String field) => int.tryParse(_controllers[field]!.text) ?? 0;

  @override
  void initState() {
    super.initState();
    _selectedLot = widget.initialLotNumber;
    for (final f in _kEggFields) {
      _controllers[f] = TextEditingController(text: '0')..addListener(_onChanged);
    }
    _loadLots();
  }

  Future<void> _loadLots() async {
    final lots = List.of(await _mongoService.getLots())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final numbers = <String>{
      ...lots.map((l) => l.number),
      if (widget.initialLotNumber != null) widget.initialLotNumber!,
    }.toList();
    if (!mounted) return;
    setState(() {
      _lotNumbers = numbers;
      _loadingLots = false;
    });
    if (_selectedLot != null) _loadExisting();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _resetControllers() {
    for (final f in _kEggFields) {
      _controllers[f]!.text = '0';
    }
  }

  Future<void> _onLotSelected(String? lot) async {
    if (lot == _newLotSentinel) {
      await _createNewLot();
      return;
    }
    setState(() {
      _selectedLot = lot;
      _resetControllers();
      _message = null;
      _existingEggStock = null;
    });
    await _loadExisting();
  }

  Future<void> _createNewLot() async {
    final controller = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nouveau numéro de lot'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Numéro de lot (ex : LOT 24)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (number == null || number.isEmpty) return;
    setState(() {
      if (!_lotNumbers.contains(number)) _lotNumbers = [number, ..._lotNumbers];
      _selectedLot = number;
      _resetControllers();
      _existingEggStock = null;
      _message = 'Nouveau lot — saisissez le stock d\'œufs de départ.';
    });
  }

  Future<void> _loadExisting() async {
    if (_selectedLot == null || _selectedLot!.trim().isEmpty) return;
    final existing = await _mongoService.getLotEggStock(widget.farm.name, _selectedLot!.trim());
    if (!mounted) return;
    if (existing == null) {
      setState(() {
        _existingEggStock = null;
        _message = "Aucun stock déjà enregistré pour ce lot — c'est une première saisie.";
      });
      return;
    }
    setState(() {
      _existingEggStock = existing;
      _controllers['oac']!.text = existing.oac.toString();
      _controllers['po']!.text = existing.po.toString();
      _controllers['dj']!.text = existing.dj.toString();
      _controllers['cas']!.text = existing.cas.toString();
      _controllers['sal']!.text = existing.sal.toString();
      _message = 'Valeurs existantes chargées — modification possible.';
    });
  }

  /// Une resaisie écrase la valeur courante (l'historique la conserve côté backend, voir
  /// PUT /lot-egg-stocks) : on le fait savoir explicitement avant d'enregistrer plutôt que de
  /// remplacer silencieusement un stock déjà en place.
  Future<bool> _confirmOverwriteIfNeeded() async {
    final existing = _existingEggStock;
    if (existing == null) return true;
    final dateStr = existing.updatedAt != null ? DateFormat('dd/MM/yyyy à HH:mm').format(existing.updatedAt!) : null;
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
          'Un stock d\'œufs de départ est déjà enregistré pour ${widget.farm.name} / ${_selectedLot!.trim()}'
          '${dateStr != null ? ' (saisi le $dateStr${existing.performedBy != null ? ' par ${existing.performedBy}' : ''})' : ''}.\n\n'
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
    if (_selectedLot == null || _selectedLot!.trim().isEmpty) {
      setState(() {
        _message = 'Choisissez un numéro de lot.';
        _success = false;
      });
      return;
    }
    if (!await _confirmOverwriteIfNeeded()) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final eggStock = LotEggStock(
      farmName: widget.farm.name,
      lotNumber: _selectedLot!.trim(),
      oac: _valueOf('oac'),
      po: _valueOf('po'),
      dj: _valueOf('dj'),
      cas: _valueOf('cas'),
      sal: _valueOf('sal'),
    );
    final result = await _mongoService.upsertLotEggStock(eggStock);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = result.error == null;
      _message = result.error ?? 'Enregistré : PO ${_valueOf('po')}';
      if (result.eggStock != null) _existingEggStock = result.eggStock;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farm.name, subtitle: "Stock d'œufs de départ"),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DailyReportCard(children: [
            _loadingLots
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: DailyReportColors.green700)),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: _selectedLot,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Numéro de lot', border: OutlineInputBorder()),
                    hint: const Text('Choisir un lot'),
                    items: [
                      ..._lotNumbers.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                      const DropdownMenuItem(
                        value: _newLotSentinel,
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline, size: 17, color: DailyReportColors.green700),
                            SizedBox(width: 6),
                            Text('Nouveau numéro de lot…', style: TextStyle(color: DailyReportColors.green700, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: _onLotSelected,
                  ),
          ]),
          if (_existingEggStock != null) ...[
            const SizedBox(height: 12),
            _existingEggStockCard(_existingEggStock!),
            _historyButton(),
          ],
          const SizedBox(height: 4),
          const DailyReportSectionLabel('Nouvelle saisie — stock du bâtiment', icon: Icons.edit_note_rounded),
          DailyReportCard(
            children: [
              Row(
                children: [
                  const Icon(Icons.warehouse_outlined, size: 18, color: DailyReportColors.green700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(widget.farm.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                "Stock global du bâtiment — pas de détail par salle.",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final f in _kEggFields)
                    SizedBox(width: 90, child: _numberField(_kEggFieldLabels[f]!, _controllers[f]!)),
                ],
              ),
            ],
          ),
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

  /// Détail du stock déjà en base pour ce lot — affiché avant toute saisie : ce que l'admin
  /// s'apprête à écraser doit être visible avant qu'il ne le fasse.
  Widget _existingEggStockCard(LotEggStock existing) {
    final dateStr = existing.updatedAt != null ? DateFormat('dd/MM/yyyy à HH:mm').format(existing.updatedAt!) : null;
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
        Text(
          'OAC ${existing.oac} · PO ${existing.po} · DJ ${existing.dj} · CAS ${existing.cas} · SAL ${existing.sal}',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DailyReportColors.green700),
        ),
      ],
    );
  }

  Widget _historyButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LotEggStockHistoryScreen(farmName: widget.farm.name, lotNumber: _selectedLot!.trim()),
          ),
        ),
        icon: const Icon(Icons.history_rounded, size: 18),
        label: const Text("Voir l'historique du stock d'œufs de départ"),
        style: OutlinedButton.styleFrom(
          foregroundColor: DailyReportColors.green700,
          side: const BorderSide(color: DailyReportColors.green600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(double.infinity, 42),
        ),
      ),
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
    );
  }
}
