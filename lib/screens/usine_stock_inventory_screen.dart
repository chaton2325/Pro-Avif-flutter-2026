import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/poste.dart';
import '../models/raw_material.dart';
import '../models/raw_material_batch.dart';
import '../models/stock_loss.dart';
import '../models/feed_stock.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';
import 'usine_inventory_screen.dart';
import 'usine_feed_inventory_screen.dart';
import 'usine_lots_history_screen.dart';

const List<String> _lossReasons = [
  'Avarie (humidité)',
  'Séchage / évaporation',
  'Casse / manutention',
  'Autre',
];

/// Un seul écran pour tout ce qui est "combien j'ai" et "je vérifie que c'est exact" —
/// stock et inventaire de matières premières ET d'aliments produits ensemble, plutôt que
/// dispersés entre Approvisionnement (matières) et Stock & Livraison (aliments).
/// Approvisionnement garde réceptions/pertes/historique ; Livraisons garde la création et
/// la validation des livraisons.
class UsineStockInventoryScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineStockInventoryScreen({
    super.key,
    required this.usine,
    this.permissions,
  });

  @override
  State<UsineStockInventoryScreen> createState() =>
      _UsineStockInventoryScreenState();
}

class _UsineStockInventoryScreenState extends State<UsineStockInventoryScreen>
    with TickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  late final TabController _inventoryTabController = TabController(
    length: 2,
    vsync: this,
  );
  late final TabController _stockTabController = TabController(
    length: 2,
    vsync: this,
  );

  List<RawMaterial> _materials = [];
  List<RawMaterialBatch> _activeBatches = [];
  List<FeedStockSummary> _feedStock = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _inventoryTabController.dispose();
    _stockTabController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _mongoService.getRawMaterials(widget.usine.id!),
      _mongoService.getRawMaterialBatches(
        usineId: widget.usine.id,
        status: 'actif',
      ),
      _mongoService.getFeedStock(widget.usine.id!),
    ]);
    if (!mounted) return;
    setState(() {
      _materials = results[0] as List<RawMaterial>;
      _activeBatches = results[1] as List<RawMaterialBatch>;
      _feedStock = results[2] as List<FeedStockSummary>;
      _isLoading = false;
    });
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<RawMaterialBatch> _batchesFor(String materialId) =>
      _activeBatches.where((b) => b.rawMaterialId == materialId).toList();

  /// Valorisation totale du stock de matières premières, recalculée à chaque mouvement —
  /// un indicateur uniquement comptable/admin.
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

  Color _statusColor(String status) {
    switch (status) {
      case 'rupture':
        return Colors.grey.shade600;
      case 'bas':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  // ------------------------------------------------------------------ Lots

  /// Page dédiée et paginée côté serveur plutôt qu'un modal chargeant tous les lots d'un
  /// coup — une matière très ancienne peut en accumuler des milliers.
  Future<void> _showLotsDialog(RawMaterial material) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UsineLotsHistoryScreen(
          usine: widget.usine,
          permissions: widget.permissions,
          initialMaterialId: material.id,
        ),
      ),
    );
    if (!mounted) return;
    _refreshData();
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

  // -------------------------------------------------------------------- Stock

  Widget _buildStockTab() {
    return Column(
      children: [
        TabBar(
          controller: _stockTabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(text: 'Matières premières'),
            Tab(text: 'Aliments'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _stockTabController,
            children: [_buildStockMaterialsTab(), _buildStockFeedTab()],
          ),
        ),
      ],
    );
  }

  Widget _buildStockMaterialsTab() {
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
          if (_materials.isNotEmpty)
            ..._materials.map((m) {
              final isLow =
                  m.currentStock < m.lowStockThreshold &&
                  m.lowStockThreshold > 0;
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
                  // (écran 08) ; une matière en CUMP global ouvre sa fiche comptable (écran
                  // 07) — jamais accessible à qui n'a pas seeCosts.
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
          if (_materials.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Aucune matière première pour cette usine.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStockFeedTab() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (_feedStock.isNotEmpty)
            ..._feedStock.map(
              (s) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: s.status == 'ok'
                        ? Colors.grey.shade100
                        : Colors.transparent,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          s.formulaName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (s.status != 'ok')
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor(
                                s.status,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              s.status == 'rupture' ? 'RUPTURE' : 'BAS',
                              style: TextStyle(
                                color: _statusColor(s.status),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        const Spacer(),
                        Text(
                          '${formatQty(s.totalStock)} kg',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        value: s.lowStockThreshold > 0
                            ? (s.totalStock / (s.lowStockThreshold * 3)).clamp(
                                0,
                                1,
                              )
                            : (s.totalStock > 0 ? 1 : 0),
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade100,
                        color: _statusColor(s.status == 'ok' ? 'ok' : s.status),
                      ),
                    ),
                    if (s.batches.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: s.batches
                            .map(
                              (b) => Chip(
                                visualDensity: VisualDensity.compact,
                                label: Text(
                                  '${b.lotNumber} · ${formatQty(b.remainingQuantity)} kg',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          if (_feedStock.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(
                child: Text(
                  'Aucun aliment produit pour cette usine.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- Inventaire

  Widget _buildInventoryTab() {
    return Column(
      children: [
        TabBar(
          controller: _inventoryTabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(text: 'Matières premières'),
            Tab(text: 'Aliments'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _inventoryTabController,
            children: [
              UsineInventoryScreen(
                usine: widget.usine,
                permissions: widget.permissions,
              ),
              UsineFeedInventoryScreen(
                usine: widget.usine,
                permissions: widget.permissions,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Séparation stricte des deux onglets par leur permission dédiée respective — sauf
  // pour un poste n'ayant ni l'une ni l'autre (ex. Logistique, entré ici via un autre
  // droit comme manageDelivery) : dans ce cas, comportement inchangé, les deux restent
  // visibles plutôt que de le laisser sans aucun onglet à afficher.
  bool get _showStockTab => _perms.viewStock || !_perms.manageInventory;
  bool get _showInventoryTab => _perms.manageInventory || !_perms.viewStock;

  @override
  Widget build(BuildContext context) {
    final showBoth = _showStockTab && _showInventoryTab;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'STOCK & INVENTAIRE',
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
            onPressed: _refreshData,
          ),
        ],
        bottom: showBoth
            ? TabBar(
                controller: _tabController,
                labelColor: Colors.orange,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.orange,
                tabs: const [
                  Tab(text: 'Stock'),
                  Tab(text: 'Inventaire'),
                ],
              )
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : showBoth
          ? TabBarView(
              controller: _tabController,
              children: [_buildStockTab(), _buildInventoryTab()],
            )
          : (_showStockTab ? _buildStockTab() : _buildInventoryTab()),
    );
  }
}
