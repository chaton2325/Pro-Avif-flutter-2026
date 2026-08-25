import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/reception.dart';
import '../models/raw_material_batch.dart';
import '../models/stock_loss.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';

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
  _HistoryEntry({
    required this.date,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.isPending = false,
  });
}

const List<String> _lossReasons = [
  'Avarie (humidité)',
  'Séchage / évaporation',
  'Casse / manutention',
  'Autre',
];

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
  List<RawMaterialBatch> _activeBatches = [];
  List<_HistoryEntry> _history = [];
  bool _isLoading = true;
  String? _error;

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
      final batches = await _mongoService.getRawMaterialBatches(
        usineId: widget.usine.id,
        status: 'actif',
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
      final inventorySessions = await _mongoService.getInventorySessions(
        widget.usine.id!,
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
                '${r.lotNumber} · ${r.quantity.toStringAsFixed(0)} ${materialUnit(r.rawMaterialId)}${r.supplier != null ? " · ${r.supplier}" : ""}',
            isPending: true,
          ),
        ),
        ...valorized.map(
          (r) => _HistoryEntry(
            date: r.valorizedAt ?? r.createdAt ?? DateTime.now(),
            icon: Icons.check_circle_outline,
            color: Colors.green,
            title: 'Réception valorisée — ${materialName(r.rawMaterialId)}',
            subtitle: showCosts
                ? '${r.lotNumber} · ${r.quantity.toStringAsFixed(0)} ${materialUnit(r.rawMaterialId)} @ ${r.unitPrice?.toStringAsFixed(2) ?? "—"} F${r.supplier != null ? " · ${r.supplier}" : ""}'
                : '${r.lotNumber} · ${r.quantity.toStringAsFixed(0)} ${materialUnit(r.rawMaterialId)}${r.supplier != null ? " · ${r.supplier}" : ""}',
          ),
        ),
        ...losses.map((l) {
          final sourceLabel = l.source == 'inventaire'
              ? 'Écart d\'inventaire'
              : (l.source == 'cloture_lot'
                    ? 'Clôture de lot'
                    : 'Perte déclarée');
          final isGain = l.quantity < 0;
          return _HistoryEntry(
            date: l.createdAt ?? DateTime.now(),
            icon: isGain
                ? Icons.add_circle_outline
                : Icons.warning_amber_rounded,
            color: isGain ? Colors.green : Colors.orange,
            title: '$sourceLabel — ${materialName(l.rawMaterialId)}',
            subtitle:
                '${isGain ? "+" : "-"}${l.quantity.abs().toStringAsFixed(0)} ${materialUnit(l.rawMaterialId)} · ${l.reason}',
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
            ),
          ),
        ...inventorySessions.map((s) {
          final materialsCount = s['materialsCount'] as int? ?? 0;
          final varianceCount = s['varianceCount'] as int? ?? 0;
          final createdAt =
              DateTime.tryParse(s['createdAt']?.toString() ?? '') ??
              DateTime.now();
          final comment = s['comment'] as String?;
          return _HistoryEntry(
            date: createdAt,
            icon: Icons.fact_check_outlined,
            color: varianceCount == 0 ? Colors.green : Colors.orange,
            title: varianceCount == 0
                ? 'Inventaire — aucun écart'
                : 'Inventaire — $varianceCount écart(s)',
            subtitle:
                '$materialsCount matière(s) contrôlée(s)${comment != null && comment.isNotEmpty ? " · $comment" : ""}',
          );
        }),
      ]..sort((a, b) => b.date.compareTo(a.date));

      setState(() {
        _materials = materials;
        _pendingReceptions = pending;
        _activeBatches = batches;
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

  List<RawMaterialBatch> _batchesFor(String materialId) =>
      _activeBatches.where((b) => b.rawMaterialId == materialId).toList();

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
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Quantité reçue',
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
                    'Sans prix : la comptabilité valorisera cette réception avant qu\'elle ne compte en stock.',
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
                          '${r.lotNumber} · ${r.supplier ?? "?"} · ${r.quantity.toStringAsFixed(0)} ${material?.unit ?? ""}',
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
                  '${material?.name ?? ""} · ${reception.supplier ?? "?"} · ${reception.quantity.toStringAsFixed(0)} ${material?.unit ?? ""}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
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
                  final err = await _mongoService.valorizeReception(
                    reception.id!,
                    p,
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

  // ------------------------------------------------------------------ Lots

  void _showLotsDialog(RawMaterial material) async {
    final allBatches = await _mongoService.getRawMaterialBatches(
      usineId: widget.usine.id,
      rawMaterialId: material.id,
    );
    allBatches.sort(
      (a, b) => (a.receivedAt ?? DateTime(2000)).compareTo(
        b.receivedAt ?? DateTime(2000),
      ),
    );
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Lots — ${material.name}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: allBatches.isEmpty
                ? const Text(
                    'Aucun lot pour cette matière.',
                    style: TextStyle(color: Colors.grey),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: allBatches.map((b) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            b.lotNumber,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${b.receivedAt != null ? DateFormat('dd/MM/yyyy').format(b.receivedAt!) : ""} · ${b.remainingQuantity.toStringAsFixed(0)}/${b.receivedQuantity.toStringAsFixed(0)} ${material.unit}'
                            '${_perms.seeCosts ? " · ${b.unitCost.toStringAsFixed(1)} F/${material.unit}" : ""}',
                          ),
                          trailing: b.isActive
                              ? TextButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    _showCloseLotDialog(b, material);
                                  },
                                  child: const Text('Clôturer'),
                                )
                              : const Text(
                                  'CLÔTURÉ',
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
      ),
    );
  }

  void _showCloseLotDialog(RawMaterialBatch batch, RawMaterial material) {
    final countedController = TextEditingController(
      text: batch.remainingQuantity.toStringAsFixed(0),
    );
    String reason = _lossReasons.first;
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final counted =
              double.tryParse(countedController.text) ??
              batch.remainingQuantity;
          final variance = batch.remainingQuantity - counted;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '${batch.lotNumber} — Clôture',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Restant théorique : ${batch.remainingQuantity.toStringAsFixed(0)} ${material.unit}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: countedController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Quantité comptée (pesée finale)',
                    errorText: errorText,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  variance == 0
                      ? 'Aucun écart'
                      : (variance > 0
                            ? 'Perte constatée : ${variance.toStringAsFixed(0)} ${material.unit}'
                            : 'Gain constaté : ${(-variance).toStringAsFixed(0)} ${material.unit}'),
                  style: TextStyle(
                    color: variance > 0
                        ? Colors.orange.shade800
                        : (variance < 0 ? Colors.green.shade700 : Colors.grey),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Motif'),
                  value: reason,
                  items: _lossReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => reason = v!),
                ),
              ],
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
                  final c = double.tryParse(countedController.text);
                  if (c == null || c < 0) {
                    setDialogState(() => errorText = 'Quantité invalide');
                    return;
                  }
                  final err = await _mongoService.closeRawMaterialBatch(
                    batch.id!,
                    c,
                    reason,
                  );
                  if (err != null) {
                    setDialogState(() => errorText = err);
                    return;
                  }
                  await _refreshData();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('Clôturer & enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------- Pertes

  void _showDeclareLossDialog(RawMaterial material) {
    final quantityController = TextEditingController();
    final noteController = TextEditingController();
    String reason = _lossReasons.first;
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Déclarer une perte — ${material.name}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Stock actuel : ${material.currentStock.toStringAsFixed(0)} ${material.unit}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Quantité perdue',
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Motif'),
                value: reason,
                items: _lossReasons
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) => setDialogState(() => reason = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Commentaire (optionnel)',
                ),
                maxLines: 2,
              ),
            ],
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
                if (qty == null || qty <= 0) {
                  setDialogState(() => errorText = 'Quantité invalide');
                  return;
                }
                final err = await _mongoService.declareStockLoss(
                  StockLoss(
                    usineId: widget.usine.id!,
                    rawMaterialId: material.id!,
                    quantity: qty,
                    reason: reason,
                    note: noteController.text.trim().isEmpty
                        ? null
                        : noteController.text.trim(),
                  ),
                );
                if (err != null) {
                  setDialogState(() => errorText = err);
                  return;
                }
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer la perte'),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------- Ajustement du CUMP

  void _showAdjustCostDialog(RawMaterial material) {
    final costController = TextEditingController();
    final reasonController = TextEditingController();
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Ajuster le CUMP — ${material.name}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Coût actuel : ${material.weightedCost?.toStringAsFixed(2) ?? "—"} F/${material.unit}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: costController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Nouveau coût (F/${material.unit})',
                  errorText: errorText,
                  helperText: 'Doit rester strictement positif',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motif (obligatoire)',
                ),
              ),
            ],
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
                final cost = double.tryParse(costController.text);
                if (cost == null || cost <= 0) {
                  setDialogState(() => errorText = 'Coût invalide');
                  return;
                }
                if (reasonController.text.trim().isEmpty) {
                  setDialogState(() => errorText = 'Motif requis');
                  return;
                }
                final err = await _mongoService.adjustRawMaterialCost(
                  material.id!,
                  cost,
                  reasonController.text.trim(),
                );
                if (err != null) {
                  setDialogState(() => errorText = err);
                  return;
                }
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Valider l\'ajustement'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Inventaire

  void _showInventoryDialog() {
    final controllers = {
      for (final m in _materials)
        m.id!: TextEditingController(text: m.currentStock.toStringAsFixed(0)),
    };
    final commentController = TextEditingController();
    int step = 0; // 0 = saisie, 1 = écarts
    List<MapEntry<RawMaterial, double>> variances = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            step == 0 ? 'Inventaire — Comptage' : 'Inventaire — Écarts',
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
                children: step == 0
                    ? _materials.map((m) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(child: Text(m.name)),
                              Text(
                                'Sys: ${m.currentStock.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  color: Colors.grey,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 90,
                                child: TextField(
                                  controller: controllers[m.id],
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.right,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList()
                    : [
                        ...variances.map((entry) {
                          final m = entry.key;
                          final v = entry.value;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              m.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${m.currentStock.toStringAsFixed(0)} → ${(m.currentStock - v).toStringAsFixed(0)} ${m.unit}',
                            ),
                            trailing: Text(
                              v == 0
                                  ? 'OK'
                                  : (v > 0
                                        ? '− ${v.toStringAsFixed(0)}'
                                        : '+ ${(-v).toStringAsFixed(0)}'),
                              style: TextStyle(
                                color: v == 0
                                    ? Colors.green
                                    : Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }),
                        if (variances.every((e) => e.value == 0))
                          const Text(
                            'Aucun écart.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: commentController,
                          decoration: const InputDecoration(
                            labelText: 'Commentaire général (optionnel)',
                          ),
                          maxLines: 2,
                        ),
                      ],
              ),
            ),
          ),
          actions: step == 0
              ? [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      variances = _materials.map((m) {
                        final counted =
                            double.tryParse(controllers[m.id]!.text) ??
                            m.currentStock;
                        return MapEntry(m, m.currentStock - counted);
                      }).toList();
                      setDialogState(() => step = 1);
                    },
                    child: const Text('Voir les écarts'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => setDialogState(() => step = 0),
                    child: const Text(
                      'Retour',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      final counts = {
                        for (final m in _materials)
                          m.id!:
                              double.tryParse(controllers[m.id]!.text) ??
                              m.currentStock,
                      };
                      await _mongoService.applyInventory(
                        widget.usine.id!,
                        counts,
                        comment: commentController.text.trim().isEmpty
                            ? null
                            : commentController.text.trim(),
                      );
                      await _refreshData();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                    },
                    child: const Text('Valider l\'inventaire'),
                  ),
                ],
        ),
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
            Tab(text: 'Stock'),
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
          if (_perms.manageReception && _materials.isNotEmpty)
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
                onTap: _showInventoryDialog,
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    color: Colors.orange,
                  ),
                ),
                title: const Text(
                  'Lancer un inventaire',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                subtitle: const Text(
                  'Comptage physique et recalage du stock',
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
            ),
          ..._materials.map((m) {
            final isLow =
                m.currentStock < m.lowStockThreshold && m.lowStockThreshold > 0;
            final batchCount = _batchesFor(m.id ?? '').length;
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
                onTap: (m.isParLot && _perms.manageReception)
                    ? () => _showLotsDialog(m)
                    : null,
                leading: CircleAvatar(
                  backgroundColor: (isLow ? Colors.orange : Colors.green)
                      .withValues(alpha: 0.1),
                  child: Icon(
                    Icons.grass_rounded,
                    color: isLow ? Colors.orange : Colors.green,
                  ),
                ),
                title: Text(
                  m.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  m.isParLot
                      ? '${m.currentStock.toStringAsFixed(0)} ${m.unit} · $batchCount lot(s) actif(s)'
                      : _perms.seeCosts
                      ? '${m.currentStock.toStringAsFixed(0)} ${m.unit} · CUMP ${m.weightedCost?.toStringAsFixed(2) ?? "—"} F/${m.unit}'
                      : '${m.currentStock.toStringAsFixed(0)} ${m.unit}',
                  style: TextStyle(
                    color: isLow
                        ? Colors.orange.shade800
                        : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: isLow ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing:
                    ((m.isParLot && _perms.manageReception) ||
                        (!m.isParLot &&
                            (_perms.manageReception || _perms.adjustCost)))
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                        onSelected: (value) {
                          if (value == 'lots') _showLotsDialog(m);
                          if (value == 'perte') _showDeclareLossDialog(m);
                          if (value == 'ajuster') _showAdjustCostDialog(m);
                        },
                        itemBuilder: (context) => [
                          if (m.isParLot && _perms.manageReception)
                            const PopupMenuItem(
                              value: 'lots',
                              child: Text('Voir les lots'),
                            ),
                          if (!m.isParLot && _perms.manageReception)
                            const PopupMenuItem(
                              value: 'perte',
                              child: Text('Déclarer une perte'),
                            ),
                          if (!m.isParLot && _perms.adjustCost)
                            const PopupMenuItem(
                              value: 'ajuster',
                              child: Text('Ajuster le CUMP'),
                            ),
                        ],
                      )
                    : null,
              ),
            );
          }),
        ],
      ),
    );
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
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: Colors.orange,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        itemCount: _history.length,
        itemBuilder: (context, index) {
          final h = _history[index];
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
              subtitle: Text(
                h.subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
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
    );
  }
}
