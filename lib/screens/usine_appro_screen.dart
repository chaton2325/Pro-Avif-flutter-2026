import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/reception.dart';
import '../models/raw_material_batch.dart';
import '../models/stock_loss.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';
import 'usine_inventory_screen.dart';
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
  _HistoryEntry({
    required this.date,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.type,
    this.isPending = false,
    this.performedBy,
  });
}

const Map<String, String> _historyTypeLabels = {
  'attente': 'En attente',
  'reception': 'Réceptions',
  'perte': 'Pertes / écarts',
  'ajustement': 'Ajustements CUMP',
};

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
            ),
          ),
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

  /// Écran 05, annotation C : valorisation totale du stock de matières premières,
  /// recalculée à chaque mouvement — un indicateur uniquement comptable/admin.
  double get _totalStockValueFcfa {
    double total = 0;
    for (final m in _materials) {
      if (m.isParLot) {
        total += _batchesFor(
          m.id ?? '',
        ).fold(0.0, (sum, b) => sum + b.remainingQuantity * b.unitCost);
      } else {
        total += m.currentStock * (m.weightedCost ?? 0);
      }
    }
    return total;
  }

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
    DateTime receivedAt = DateTime.now();

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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Date de réception',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(DateFormat('dd/MM/yyyy').format(receivedAt)),
                  trailing: const Icon(Icons.edit_calendar_outlined),
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: receivedAt,
                      firstDate: DateTime(now.year - 5),
                      lastDate: now,
                      builder: (context, child) => Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Colors.orange,
                          ),
                        ),
                        child: child!,
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() => receivedAt = picked);
                    }
                  },
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sans prix : la comptabilité valorisera cette réception avant qu\'elle ne compte en stock. '
                    'Ne changez la date que pour un lot déjà en stock avant l\'usage de l\'application.',
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
                      createdAt: receivedAt,
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
                            '${b.receivedAt != null ? DateFormat('dd/MM/yyyy').format(b.receivedAt!) : ""} · ${formatQty(b.remainingQuantity)}/${formatQty(b.receivedQuantity)} ${material.unit}'
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

  /// Écran 07 — fiche matière première, réservée à la comptabilité (seeCosts) : stock/CUMP/
  /// couverture en jours puis l'historique complet (réceptions + ajustements CUMP) d'UNE
  /// matière gérée en CUMP global. Les matières « par lot » ouvrent la liste des lots
  /// (écran 08, _showLotsDialog) à la place — jamais cette fiche.
  void _showMaterialFicheDialog(RawMaterial material) async {
    final fiche = await _mongoService.getMaterialFiche(material.id!);
    if (!mounted) return;
    if (fiche == null) {
      _snack('Erreur de chargement de la fiche.');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          fiche.materialName,
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _ficheStat(
                      formatQty(fiche.currentStock),
                      'Stock ${fiche.unit}',
                    ),
                    _ficheStat(
                      fiche.weightedCost != null
                          ? fiche.weightedCost!.toStringAsFixed(1)
                          : '—',
                      'CUMP F/${fiche.unit}',
                    ),
                    _ficheStat(
                      fiche.coverageDays != null
                          ? '${fiche.coverageDays!.toStringAsFixed(0)} j'
                          : '—',
                      'Couverture',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Historique — réceptions & ajustements',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                if (fiche.history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Aucun mouvement enregistré.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  ...fiche.history.map(
                    (h) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        '${DateFormat('dd/MM/yyyy').format(h.date)} · ${h.label}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      subtitle: Text(
                        h.detail,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: h.type == 'reception_attente'
                          ? const Icon(
                              Icons.circle,
                              size: 10,
                              color: Colors.amber,
                            )
                          : (h.amountFcfa != null
                                ? Text(
                                    h.amountFcfa!.toStringAsFixed(0),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null),
                    ),
                  ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    "Le coût pondéré lisse les variations de prix d'un fournisseur à l'autre ; les ajustements manuels apparaissent dans la même chronologie.",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
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

  Widget _ficheStat(String value, String label) {
    return Expanded(
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
    );
  }

  void _showCloseLotDialog(RawMaterialBatch batch, RawMaterial material) {
    final countedController = TextEditingController(
      text: formatQty(batch.remainingQuantity),
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
          // "Aucun écart" seulement si c'est un résidu de calcul flottant invisible à
          // l'affichage — jamais un écart réellement saisi, même petit (0.9 reste 0.9,
          // pas arrondi à 1).
          final varianceOk = isNegligibleVariance(variance);
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
                  'Restant théorique : ${formatQty(batch.remainingQuantity)} ${material.unit}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: countedController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Quantité comptée (pesée finale)',
                    errorText: errorText,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  varianceOk
                      ? 'Aucun écart'
                      : (variance > 0
                            ? 'Perte constatée : ${formatQty(variance)} ${material.unit}'
                            : 'Gain constaté : ${formatQty(-variance)} ${material.unit}'),
                  style: TextStyle(
                    color: varianceOk
                        ? Colors.grey
                        : (variance > 0
                              ? Colors.orange.shade800
                              : Colors.green.shade700),
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
                  final err = await runBlocking(
                    context,
                    () => _mongoService.closeRawMaterialBatch(
                      batch.id!,
                      c,
                      reason,
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
                'Stock actuel : ${formatQty(material.currentStock)} ${material.unit}',
                style: const TextStyle(color: Colors.grey),
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
                final err = await runBlocking(
                  context,
                  () => _mongoService.declareStockLoss(
                    StockLoss(
                      usineId: widget.usine.id!,
                      rawMaterialId: material.id!,
                      quantity: qty,
                      reason: reason,
                      note: noteController.text.trim().isEmpty
                          ? null
                          : noteController.text.trim(),
                    ),
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

  void _showMissingCostDialog(List<RawMaterial> materials) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Matières sans coût de référence',
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tant qu\'aucun coût n\'est défini, le premier CUMP se calculera à partir de zéro dès la prochaine réception. Définissez un coût de référence pour chacune avant de réceptionner :',
                style: TextStyle(fontSize: 12.5, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              ...materials.map(
                (m) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    m.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  trailing: TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAdjustCostDialog(m);
                    },
                    child: const Text('Définir'),
                  ),
                ),
              ),
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
            material.weightedCost == null
                ? 'Définir le coût — ${material.name}'
                : 'Ajuster le CUMP — ${material.name}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                material.weightedCost == null
                    ? 'Aucun coût de référence défini pour l\'instant.'
                    : 'Coût actuel : ${material.weightedCost!.toStringAsFixed(2)} F/${material.unit}',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
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
                final err = await runBlocking(
                  context,
                  () => _mongoService.adjustRawMaterialCost(
                    material.id!,
                    cost,
                    reasonController.text.trim(),
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
              child: const Text('Valider l\'ajustement'),
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
    // Matières « globales » sans aucun coût de référence : la comptabilité doit le
    // définir *avant* la première réception, sinon le premier CUMP se recalcule sur une
    // base à 0 (voir la formule pondérée). On le dit activement, pas juste en silence
    // dans un menu — c'est un système de gestion, ça doit être explicite.
    final materialsWithoutCost = _materials
        .where((m) => !m.isParLot && m.weightedCost == null)
        .toList();

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (_perms.seeCosts && _materials.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.account_balance_wallet_outlined,
                    color: Colors.grey,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Valeur totale du stock de matières premières : ${NumberFormat('#,###', 'fr_FR').format(_totalStockValueFcfa)} FCFA',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
          if (_perms.adjustCost && materialsWithoutCost.isNotEmpty)
            GestureDetector(
              onTap: () => _showMissingCostDialog(materialsWithoutCost),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.priority_high_rounded,
                      color: Colors.red.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${materialsWithoutCost.length} matière(s) sans CUMP défini — veuillez ajuster le coût avant la prochaine réception',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.red.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UsineInventoryScreen(
                        usine: widget.usine,
                        permissions: widget.permissions,
                      ),
                    ),
                  );
                  if (!mounted) return;
                  _refreshData();
                },
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    color: Colors.orange,
                  ),
                ),
                title: const Text(
                  'Inventaire',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                subtitle: const Text(
                  'Comptage physique et historique, paginé',
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
                // Écran 01, annotation A : une matière « par lot » ouvre la liste des lots
                // (écran 08) ; une matière en CUMP global ouvre sa fiche comptable (écran 07,
                // annotation A de l'écran 05) — jamais accessible à qui n'a pas seeCosts.
                onTap: m.isParLot
                    ? ((_perms.manageReception || _perms.seeCosts)
                          ? () => _showLotsDialog(m)
                          : null)
                    : (_perms.seeCosts
                          ? () => _showMaterialFicheDialog(m)
                          : null),
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
                      ? '${formatQty(m.currentStock)} ${m.unit} · $batchCount lot(s) actif(s)'
                      : _perms.seeCosts
                      ? '${formatQty(m.currentStock)} ${m.unit} · CUMP ${m.weightedCost?.toStringAsFixed(2) ?? "—"} F/${m.unit}'
                      : '${formatQty(m.currentStock)} ${m.unit}',
                  style: TextStyle(
                    color: isLow
                        ? Colors.orange.shade800
                        : Colors.grey.shade600,
                    fontSize: 12,
                    fontWeight: isLow ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing:
                    ((m.isParLot &&
                            (_perms.manageReception || _perms.seeCosts)) ||
                        (!m.isParLot &&
                            (_perms.manageReception ||
                                _perms.adjustCost ||
                                _perms.seeCosts)))
                    ? PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, color: Colors.grey),
                        onSelected: (value) {
                          if (value == 'lots') _showLotsDialog(m);
                          if (value == 'fiche') _showMaterialFicheDialog(m);
                          if (value == 'perte') _showDeclareLossDialog(m);
                          if (value == 'ajuster') _showAdjustCostDialog(m);
                        },
                        itemBuilder: (context) => [
                          if (m.isParLot &&
                              (_perms.manageReception || _perms.seeCosts))
                            const PopupMenuItem(
                              value: 'lots',
                              child: Text('Voir les lots'),
                            ),
                          if (!m.isParLot && _perms.seeCosts)
                            const PopupMenuItem(
                              value: 'fiche',
                              child: Text('Voir la fiche'),
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
