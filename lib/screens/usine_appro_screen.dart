import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/reception.dart';
import '../models/stock_loss.dart';
import '../models/cost_adjustment.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';
import 'usine_lots_history_screen.dart';

/// Une ligne du fil d'historique (réception valorisée, perte ou ajustement CUMP fondus
/// dans une seule chronologie) — c'était le trou signalé : aucune trace consultable des
/// mouvements passés une fois la file d'attente de valorisation vidée.
class _HistoryEntry {
  final DateTime date;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool isPending;
  final String type; // 'attente' | 'reception' | 'perte' | 'ajustement'
  final String? performedBy;
  // Objet source, pour le détail complet en modal au clic — un seul des trois est renseigné,
  // selon [type].
  final Reception? reception;
  final StockLoss? loss;
  final CostAdjustment? adjustment;
  _HistoryEntry({
    required this.date,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.type,
    this.isPending = false,
    this.performedBy,
    this.reception,
    this.loss,
    this.adjustment,
  });
}

const Map<String, String> _historyTypeLabels = {
  'attente': 'En attente',
  'reception': 'Réceptions',
  'perte': 'Pertes / écarts',
  'ajustement': 'Ajustements CUMP',
};

/// Parcours 01 — Approvisionnement (maquette écrans 1-13), condensé en un seul écran
/// hub + une poignée de dialogs plutôt qu'une quinzaine d'écrans séparés.
/// Cloisonné par poste : sans [permissions] (chemin admin/test), tout est visible ; avec
/// [permissions] (utilisateur usine connecté), seuls les coûts/actions autorisés
/// apparaissent — ex. un magasinier (manageReception) ne voit jamais de F/kg ni de FCFA.
class UsineApproScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineApproScreen({super.key, required this.usine, this.permissions});

  @override
  State<UsineApproScreen> createState() => _UsineApproScreenState();
}

class _UsineApproScreenState extends State<UsineApproScreen>
    with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  List<RawMaterial> _materials = [];
  List<Reception> _pendingReceptions = [];
  List<_HistoryEntry> _history = [];
  bool _isLoading = true;
  String? _error;

  // Historique : filtre par type, par utilisateur, tri par date, pagination par 30.
  String _historyTypeFilter = 'tous';
  String _historyUserFilter = 'tous';
  bool _historySortDescending = true;
  int _historyPage = 0;
  static const int _historyPageSize = 30;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final materials = await _mongoService.getRawMaterials(widget.usine.id!);
      final pending = await _mongoService.getReceptions(
        usineId: widget.usine.id,
        status: 'en_attente',
      );
      final valorized = await _mongoService.getReceptions(
        usineId: widget.usine.id,
        status: 'valorisee',
      );
      final losses = await _mongoService.getStockLosses(
        usineId: widget.usine.id,
      );
      final adjustments = await _mongoService.getCostAdjustments(
        usineId: widget.usine.id,
      );
      if (!mounted) return;

      String materialName(String id) =>
          materials
              .cast<RawMaterial?>()
              .firstWhere((m) => m?.id == id, orElse: () => null)
              ?.name ??
          '?';
      String materialUnit(String id) =>
          materials
              .cast<RawMaterial?>()
              .firstWhere((m) => m?.id == id, orElse: () => null)
              ?.unit ??
          'kg';

      // Coûts (prix, CUMP) masqués de l'historique pour un poste sans seeCosts —
      // même règle que partout ailleurs côté magasinier/production dans la maquette.
      final showCosts = _perms.seeCosts;
      final history = <_HistoryEntry>[
        ...pending.map(
          (r) => _HistoryEntry(
            date: r.createdAt ?? DateTime.now(),
            icon: Icons.hourglass_top_rounded,
            color: Colors.amber.shade800,
            title: 'Réception en attente — ${materialName(r.rawMaterialId)}',
            subtitle:
                '${r.lotNumber} · ${formatQty(r.quantity)} ${materialUnit(r.rawMaterialId)}${r.supplier != null ? " · ${r.supplier}" : ""}',
            isPending: true,
            type: 'attente',
            performedBy: r.createdBy,
            reception: r,
          ),
        ),
        ...valorized.map(
          (r) => _HistoryEntry(
            date: r.valorizedAt ?? r.createdAt ?? DateTime.now(),
            icon: Icons.check_circle_outline,
            color: Colors.green,
            title: 'Réception valorisée — ${materialName(r.rawMaterialId)}',
            subtitle: showCosts
                ? '${r.lotNumber} · ${formatQty(r.quantity)} ${materialUnit(r.rawMaterialId)} @ ${r.unitPrice?.toStringAsFixed(2) ?? "—"} F${r.supplier != null ? " · ${r.supplier}" : ""}'
                : '${r.lotNumber} · ${formatQty(r.quantity)} ${materialUnit(r.rawMaterialId)}${r.supplier != null ? " · ${r.supplier}" : ""}',
            type: 'reception',
            performedBy: r.valorizedBy ?? r.createdBy,
            reception: r,
          ),
        ),
        // Les écarts sourcés d'un inventaire vivent désormais uniquement dans l'onglet
        // Inventaire (détail complet par matière dans la session) — les montrer aussi
        // ici ferait doublon avec un résumé moins complet.
        ...losses.where((l) => l.source != 'inventaire').map((l) {
          final sourceLabel = l.source == 'cloture_lot'
              ? 'Clôture de lot'
              : 'Perte déclarée';
          final isGain = l.quantity < 0;
          return _HistoryEntry(
            date: l.createdAt ?? DateTime.now(),
            icon: isGain
                ? Icons.add_circle_outline
                : Icons.warning_amber_rounded,
            color: isGain ? Colors.green : Colors.orange,
            title: '$sourceLabel — ${materialName(l.rawMaterialId)}',
            subtitle:
                '${isGain ? "+" : "-"}${formatQty(l.quantity.abs())} ${materialUnit(l.rawMaterialId)} · ${l.reason}',
            type: 'perte',
            performedBy: l.performedBy,
            loss: l,
          );
        }),
        if (showCosts)
          ...adjustments.map(
            (a) => _HistoryEntry(
              date: a.createdAt ?? DateTime.now(),
              icon: Icons.tune_rounded,
              color: Colors.indigo,
              title: 'Ajustement CUMP — ${materialName(a.rawMaterialId)}',
              subtitle:
                  '${a.previousCost.toStringAsFixed(2)} → ${a.newCost.toStringAsFixed(2)} F/${materialUnit(a.rawMaterialId)} · ${a.reason}',
              type: 'ajustement',
              performedBy: a.performedBy,
              adjustment: a,
            ),
          ),
      ]..sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _materials = materials;
        _pendingReceptions = pending;
        _history = history;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur de chargement : $e";
        _isLoading = false;
      });
    }
  }

  RawMaterial? _materialById(String id) => _materials
      .cast<RawMaterial?>()
      .firstWhere((m) => m?.id == id, orElse: () => null);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --------------------------------------------------------- Nouvelle réception

  void _showNewReceptionDialog() {
    if (_materials.isEmpty) {
      _snack('Créez au moins une matière première dans le référentiel.');
      return;
    }
    String? selectedMaterialId = _materials.first.id;
    final supplierController = TextEditingController();
    final quantityController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Nouvelle réception',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Matière première',
                  ),
                  value: selectedMaterialId,
                  items: _materials
                      .where((m) => m.id != null)
                      .map(
                        (m) =>
                            DropdownMenuItem(value: m.id, child: Text(m.name)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedMaterialId = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: supplierController,
                  decoration: const InputDecoration(
                    labelText: 'Fournisseur (optionnel)',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: quantityController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Quantité reçue (kg)',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: noteController,
                  decoration: const InputDecoration(
                    labelText: 'Remarque (optionnel)',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sans prix : la comptabilité valorisera cette réception avant qu\'elle ne compte en stock. '
                    'Date et heure de réception enregistrées automatiquement.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
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
                final qty = double.tryParse(quantityController.text);
                if (selectedMaterialId == null || qty == null || qty <= 0)
                  return;
                await runBlocking(context, () async {
                  await _mongoService.addReception(
                    Reception(
                      usineId: widget.usine.id!,
                      rawMaterialId: selectedMaterialId!,
                      supplier: supplierController.text.trim().isEmpty
                          ? null
                          : supplierController.text.trim(),
                      quantity: qty,
                      note: noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim(),
                    ),
                  );
                  await _refreshData();
                });
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer la réception'),
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------- File d'attente / valorisation

  void _showPendingReceptionsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Réceptions en attente de prix',
          style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 420,
          child: _pendingReceptions.isEmpty
              ? const Text(
                  'Aucune réception en attente.',
                  style: TextStyle(color: Colors.grey),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _pendingReceptions.map((r) {
                      final material = _materialById(r.rawMaterialId);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          material?.name ?? r.rawMaterialId,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '${r.lotNumber} · ${r.supplier ?? "?"} · ${formatQty(r.quantity)} ${material?.unit ?? ""}',
                        ),
                        trailing: _perms.setPrice
                            ? TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _showValorizeDialog(r, material);
                                },
                                child: const Text('Valoriser'),
                              )
                            : const Text(
                                'En attente',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      );
                    }).toList(),
                  ),
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

  void _showValorizeDialog(Reception reception, RawMaterial? material) {
    final priceController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '${reception.lotNumber} — Prix d\'achat',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${material?.name ?? ""} · ${reception.supplier ?? "?"} · ${formatQty(reception.quantity)} ${material?.unit ?? ""}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  decoration: InputDecoration(
                    labelText:
                        'Prix d\'achat (par ${material?.unit ?? "unité"})',
                    errorText: errorText,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                if (material?.isParLot ?? false)
                  const Text(
                    'Matière « par lot » : un nouveau lot séparé sera créé avec ce coût.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  )
                else
                  const Text(
                    'Matière « globale » : le CUMP sera recalculé automatiquement.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Plus tard',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final p = double.tryParse(priceController.text);
                  if (p == null || p <= 0) {
                    setDialogState(() => errorText = 'Prix invalide');
                    return;
                  }
                  final err = await runBlocking(
                    context,
                    () => _mongoService.valorizeReception(reception.id!, p),
                  );
                  if (err != null) {
                    setDialogState(() => errorText = err);
                    return;
                  }
                  await _refreshData();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('Valider & intégrer au stock'),
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'APPROVISIONNEMENT — ${widget.usine.name.toUpperCase()}',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
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
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(text: 'Réceptions'),
            Tab(text: 'Historique'),
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
              children: [_buildStockTab(), _buildHistoryTab()],
            ),
      floatingActionButton: !_perms.manageReception
          ? null
          : AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) => _tabController.index == 0
                  ? FloatingActionButton.extended(
                      backgroundColor: Colors.orange,
                      onPressed: _showNewReceptionDialog,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'Réception',
                        style: TextStyle(color: Colors.white),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
    );
  }

  Widget _buildStockTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (_pendingReceptions.isNotEmpty)
            GestureDetector(
              onTap: _showPendingReceptionsDialog,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.hourglass_top_rounded,
                      color: Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${_pendingReceptions.length} réception(s) en attente de prix — toucher pour valoriser',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.brown,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if ((_perms.manageReception || _perms.seeCosts) &&
              _materials.isNotEmpty)
            Container(
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
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UsineLotsHistoryScreen(
                        usine: widget.usine,
                        permissions: widget.permissions,
                      ),
                    ),
                  );
                  // Un lot a pu être clôturé sur cet écran (stock/lots actifs changés) —
                  // sans ce rafraîchissement, l'inventaire réaffichait le lot fermé
                  // jusqu'à ce qu'on quitte/revienne sur l'écran manuellement.
                  if (!mounted) return;
                  _refreshData();
                },
                leading: CircleAvatar(
                  backgroundColor: Colors.indigo.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.indigo,
                  ),
                ),
                title: const Text(
                  'Historique des lots',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                subtitle: const Text(
                  'Tous les lots, paginé',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            ),
          if (_materials.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Aucune matière première. Créez-en depuis le référentiel de cette usine.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else if (_pendingReceptions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Aucune réception en attente. Le stock et l\'inventaire se consultent depuis "Stock & Inventaire".',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
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

  /// Détail d'une ligne d'historique au clic — la carte inline ne montre qu'un résumé
  /// (le comptage global s'est agrandi avec la fusion réception/perte/ajustement dans une
  /// seule chronologie), certains champs comme la remarque ou le détail complet de la
  /// valorisation n'y trouvaient plus leur place.
  void _showHistoryDetailDialog(_HistoryEntry h) {
    final rows = <Widget>[];
    if (h.reception != null) {
      final r = h.reception!;
      final material = _materialById(r.rawMaterialId);
      rows.addAll([
        _detailRow('Matière', material?.name ?? '?'),
        _detailRow('Lot', r.lotNumber),
        _detailRow(
          'Quantité',
          '${formatQty(r.quantity)} ${material?.unit ?? "kg"}',
        ),
        _detailRow('Fournisseur', r.supplier ?? '—'),
        if (r.createdAt != null)
          _detailRow(
            'Reçue le',
            DateFormat('dd/MM/yyyy · HH:mm').format(r.createdAt!),
          ),
        _detailRow('Enregistrée par', r.createdBy ?? '—'),
        if (r.isPending)
          _detailRow('Statut', 'En attente de valorisation')
        else ...[
          if (_perms.seeCosts) ...[
            _detailRow(
              'Prix unitaire',
              '${r.unitPrice?.toStringAsFixed(2) ?? "—"} F',
            ),
            _detailRow(
              'Montant total',
              '${(r.totalAmount ?? ((r.unitPrice ?? 0) * r.quantity)).toStringAsFixed(0)} F',
            ),
          ],
          if (r.valorizedAt != null)
            _detailRow(
              'Valorisée le',
              DateFormat('dd/MM/yyyy · HH:mm').format(r.valorizedAt!),
            ),
          _detailRow('Valorisée par', r.valorizedBy ?? '—'),
        ],
        if (r.note != null && r.note!.trim().isNotEmpty)
          _detailRow('Remarque', r.note!),
      ]);
    } else if (h.loss != null) {
      final l = h.loss!;
      final material = _materialById(l.rawMaterialId);
      final isGain = l.quantity < 0;
      final sourceLabel = switch (l.source) {
        'cloture_lot' => 'Clôture de lot',
        'inventaire' => 'Écart d\'inventaire',
        _ => 'Perte déclarée',
      };
      rows.addAll([
        _detailRow('Matière', material?.name ?? '?'),
        _detailRow('Type', sourceLabel),
        _detailRow(
          isGain ? 'Gain' : 'Perte',
          '${formatQty(l.quantity.abs())} ${material?.unit ?? "kg"}',
        ),
        _detailRow('Motif', l.reason),
        if (l.createdAt != null)
          _detailRow(
            'Date',
            DateFormat('dd/MM/yyyy · HH:mm').format(l.createdAt!),
          ),
        _detailRow('Enregistrée par', l.performedBy ?? '—'),
        if (l.note != null && l.note!.trim().isNotEmpty)
          _detailRow('Remarque', l.note!),
      ]);
    } else if (h.adjustment != null) {
      final a = h.adjustment!;
      final material = _materialById(a.rawMaterialId);
      rows.addAll([
        _detailRow('Matière', material?.name ?? '?'),
        _detailRow(
          'Ancien coût',
          '${a.previousCost.toStringAsFixed(2)} F/${material?.unit ?? "kg"}',
        ),
        _detailRow(
          'Nouveau coût',
          '${a.newCost.toStringAsFixed(2)} F/${material?.unit ?? "kg"}',
        ),
        _detailRow('Motif', a.reason),
        if (a.createdAt != null)
          _detailRow(
            'Date',
            DateFormat('dd/MM/yyyy · HH:mm').format(a.createdAt!),
          ),
        _detailRow('Enregistrée par', a.performedBy ?? '—'),
      ]);
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          h.title,
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: rows,
            ),
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

  List<_HistoryEntry> get _filteredSortedHistory {
    final list = _history.where((h) {
      if (_historyTypeFilter != 'tous' && h.type != _historyTypeFilter)
        return false;
      if (_historyUserFilter != 'tous' &&
          (h.performedBy ?? 'Inconnu') != _historyUserFilter)
        return false;
      return true;
    }).toList();
    list.sort(
      (a, b) => _historySortDescending
          ? b.date.compareTo(a.date)
          : a.date.compareTo(b.date),
    );
    return list;
  }

  Widget _buildHistoryTab() {
    if (_history.isEmpty) {
      return const Center(
        child: Text(
          'Aucun mouvement pour le moment.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final availableTypes = _history.map((h) => h.type).toSet().toList();
    final availableUsers =
        _history.map((h) => h.performedBy ?? 'Inconnu').toSet().toList()
          ..sort();
    final filtered = _filteredSortedHistory;
    final totalPages = filtered.isEmpty
        ? 1
        : (filtered.length / _historyPageSize).ceil();
    final page = _historyPage.clamp(0, totalPages - 1);
    final pageItems = filtered
        .skip(page * _historyPageSize)
        .take(_historyPageSize)
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Tous'),
                      selected: _historyTypeFilter == 'tous',
                      onSelected: (_) => setState(() {
                        _historyTypeFilter = 'tous';
                        _historyPage = 0;
                      }),
                    ),
                    ...availableTypes.map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(_historyTypeLabels[t] ?? t),
                          selected: _historyTypeFilter == t,
                          onSelected: (_) => setState(() {
                            _historyTypeFilter = t;
                            _historyPage = 0;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _historyUserFilter,
                      decoration: const InputDecoration(
                        labelText: 'Utilisateur',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'tous',
                          child: Text('Tous les utilisateurs'),
                        ),
                        ...availableUsers.map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(u, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() {
                        _historyUserFilter = v ?? 'tous';
                        _historyPage = 0;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _historySortDescending
                        ? 'Plus récent d\'abord'
                        : 'Plus ancien d\'abord',
                    icon: Icon(
                      _historySortDescending
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: Colors.orange,
                    ),
                    onPressed: () => setState(() {
                      _historySortDescending = !_historySortDescending;
                      _historyPage = 0;
                    }),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: pageItems.isEmpty
              ? const Center(
                  child: Text(
                    'Aucun mouvement pour ce filtre.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refreshData,
                  color: Colors.orange,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: pageItems.length,
                    itemBuilder: (context, index) {
                      final h = pageItems[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          onTap: () => _showHistoryDetailDialog(h),
                          leading: CircleAvatar(
                            backgroundColor: h.color.withValues(alpha: 0.12),
                            child: Icon(h.icon, color: h.color, size: 20),
                          ),
                          title: Text(
                            h.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                h.subtitle,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                              if (h.performedBy != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'par ${h.performedBy}',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 10.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: h.performedBy != null,
                          trailing: h.isPending
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade100,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    'EN ATTENTE',
                                    style: TextStyle(
                                      color: Colors.amber.shade900,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                )
                              : Text(
                                  DateFormat('dd/MM/yy').format(h.date),
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        if (totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: page > 0
                      ? () => setState(() => _historyPage = page - 1)
                      : null,
                ),
                Text(
                  'Page ${page + 1} / $totalPages · ${filtered.length} mouvement(s)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: page < totalPages - 1
                      ? () => setState(() => _historyPage = page + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
