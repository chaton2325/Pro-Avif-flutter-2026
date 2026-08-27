import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/raw_material_batch.dart';
import '../models/inventory_session.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';

/// Inventaire des matières premières, dans une page dédiée avec pagination côté serveur
/// (50 par page) — séparée de l'historique des mouvements (réceptions, pertes,
/// ajustements) de l'écran Appro, comme l'historique des lots l'est déjà.
class UsineInventoryScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineInventoryScreen({super.key, required this.usine, this.permissions});

  @override
  State<UsineInventoryScreen> createState() => _UsineInventoryScreenState();
}

class _UsineInventoryScreenState extends State<UsineInventoryScreen> {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;
  static const int _pageSize = 50;

  List<RawMaterial> _materials = [];
  List<RawMaterialBatch> _activeBatches = [];
  List<InventorySession> _sessions = [];
  int _totalCount = 0;
  int _page = 0;
  bool _isLoadingData = true;
  bool _isLoadingSessions = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadSessionsPage();
  }

  Future<void> _loadData() async {
    final results = await Future.wait([
      _mongoService.getRawMaterials(widget.usine.id!),
      _mongoService.getRawMaterialBatches(
        usineId: widget.usine.id,
        status: 'actif',
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _materials = results[0] as List<RawMaterial>;
      _activeBatches = results[1] as List<RawMaterialBatch>;
      _isLoadingData = false;
    });
  }

  Future<void> _loadSessionsPage() async {
    setState(() => _isLoadingSessions = true);
    final page = await _mongoService.getInventorySessions(
      widget.usine.id!,
      scope: 'matieres',
      limit: _pageSize,
      skip: _page * _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _sessions = page.items;
      _totalCount = page.totalCount;
      _isLoadingSessions = false;
    });
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _loadSessionsPage();
  }

  List<RawMaterialBatch> _batchesFor(String materialId) =>
      _activeBatches.where((b) => b.rawMaterialId == materialId).toList();

  Widget _countRow({
    required String label,
    required double systemQty,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            'Sys: ${formatQty(systemQty)}',
            style: const TextStyle(color: Colors.grey, fontSize: 11),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
              ],
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
  }

  /// Une matière « globale » compte en un seul champ (son stock agrégé). Une matière
  /// « par lot » avec des lots actifs compte lot par lot (plusieurs réceptions
  /// coexistent souvent avec des quantités restantes différentes) — un seul champ
  /// agrégé imputerait sinon systématiquement tout l'écart au lot le plus ancien.
  void _showInventoryDialog() {
    final materialControllers = {
      for (final m in _materials)
        if (!m.isParLot || _batchesFor(m.id!).isEmpty)
          m.id!: TextEditingController(text: formatQty(m.currentStock)),
    };
    final batchControllers = {
      for (final m in _materials.where((m) => m.isParLot))
        for (final b in _batchesFor(m.id!))
          b.id!: TextEditingController(text: formatQty(b.remainingQuantity)),
    };
    final commentController = TextEditingController();
    int step = 0; // 0 = saisie, 1 = écarts
    List<({RawMaterial material, RawMaterialBatch? batch, double variance})>
    variances = [];

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
                    ? _materials.expand((m) {
                        final batches = m.isParLot
                            ? _batchesFor(m.id!)
                            : const <RawMaterialBatch>[];
                        if (batches.isEmpty) {
                          return [
                            _countRow(
                              label: m.name,
                              systemQty: m.currentStock,
                              controller: materialControllers[m.id]!,
                            ),
                          ];
                        }
                        return [
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              m.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          ...batches.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(left: 12),
                              child: _countRow(
                                label: 'Lot ${b.lotNumber}',
                                systemQty: b.remainingQuantity,
                                controller: batchControllers[b.id]!,
                              ),
                            ),
                          ),
                        ];
                      }).toList()
                    : [
                        ...variances.map((entry) {
                          final m = entry.material;
                          final b = entry.batch;
                          final systemQty =
                              b?.remainingQuantity ?? m.currentStock;
                          final v = entry.variance;
                          // "OK" seulement si l'écart est un résidu de calcul flottant
                          // (ex. 0.0000001) invisible à l'affichage — jamais un vrai
                          // écart saisi par l'utilisateur (ex. 0.9), qui reste affiché
                          // avec sa valeur exacte, pas arrondie à l'entier.
                          final ok = isNegligibleVariance(v);
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              b != null ? '${m.name} — Lot ${b.lotNumber}' : m.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${formatQty(systemQty)} → ${formatQty(systemQty - v)} ${m.unit}',
                            ),
                            trailing: Text(
                              ok
                                  ? 'OK'
                                  : (v > 0
                                        ? '− ${formatQty(v.abs())}'
                                        : '+ ${formatQty(v.abs())}'),
                              style: TextStyle(
                                color: ok ? Colors.green : Colors.orange.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        }),
                        if (variances.every((e) => isNegligibleVariance(e.variance)))
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
                      final list =
                          <
                            ({
                              RawMaterial material,
                              RawMaterialBatch? batch,
                              double variance,
                            })
                          >[];
                      for (final m in _materials) {
                        final batches = m.isParLot
                            ? _batchesFor(m.id!)
                            : const <RawMaterialBatch>[];
                        if (batches.isEmpty) {
                          final counted =
                              double.tryParse(
                                materialControllers[m.id]!.text,
                              ) ??
                              m.currentStock;
                          list.add((
                            material: m,
                            batch: null,
                            variance: m.currentStock - counted,
                          ));
                        } else {
                          for (final b in batches) {
                            final counted =
                                double.tryParse(
                                  batchControllers[b.id]!.text,
                                ) ??
                                b.remainingQuantity;
                            list.add((
                              material: m,
                              batch: b,
                              variance: b.remainingQuantity - counted,
                            ));
                          }
                        }
                      }
                      variances = list;
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
                      final counts = <InventoryCountEntry>[
                        for (final entry in variances)
                          (
                            rawMaterialId: entry.material.id!,
                            countedQuantity:
                                (entry.batch?.remainingQuantity ??
                                    entry.material.currentStock) -
                                entry.variance,
                            batchId: entry.batch?.id,
                          ),
                      ];
                      await runBlocking(context, () async {
                        await _mongoService.applyInventory(
                          widget.usine.id!,
                          counts,
                          comment: commentController.text.trim().isEmpty
                              ? null
                              : commentController.text.trim(),
                        );
                        await _loadData();
                        _page = 0;
                        await _loadSessionsPage();
                      });
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

  void _showSessionDetail(InventorySession s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          s.createdAt != null
              ? DateFormat('dd/MM/yyyy HH:mm').format(s.createdAt!)
              : 'Inventaire',
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
                if (s.comment != null && s.comment!.isNotEmpty) ...[
                  Text(
                    s.comment!,
                    style: const TextStyle(
                      fontStyle: FontStyle.italic,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                if (s.performedBy != null)
                  Text(
                    'Réalisé par ${s.performedBy}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                const Divider(height: 20),
                if (s.details.isEmpty)
                  const Text(
                    'Détail non disponible pour cet inventaire (réalisé avant l\'ajout de cette fonctionnalité).',
                    style: TextStyle(color: Colors.grey),
                  )
                else
                  ...s.details.map((d) {
                    final ok = isNegligibleVariance(d.variance);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.lotNumber != null
                                  ? '${d.name} — Lot ${d.lotNumber}'
                                  : d.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            '${formatQty(d.systemQuantity)} → ${formatQty(d.countedQuantity)} ${d.unit}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ok
                                ? 'OK'
                                : (d.variance > 0
                                      ? '− ${formatQty(d.variance.abs())}'
                                      : '+ ${formatQty(d.variance.abs())}'),
                            style: TextStyle(
                              color: ok
                                  ? Colors.green
                                  : Colors.orange.shade800,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
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

  @override
  Widget build(BuildContext context) {
    final totalPages = _totalCount == 0 ? 1 : (_totalCount / _pageSize).ceil();
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'INVENTAIRE — MATIÈRES',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: .5, fontSize: 13),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_perms.manageReception && _materials.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
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
                  onTap: _isLoadingData ? null : _showInventoryDialog,
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
            ),
          Expanded(
            child: _isLoadingSessions
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.orange),
                  )
                : _sessions.isEmpty
                ? const Center(
                    child: Text(
                      'Aucun inventaire réalisé pour le moment.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadSessionsPage,
                    color: Colors.orange,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _sessions.length,
                      itemBuilder: (context, index) {
                        final s = _sessions[index];
                        final ok = s.varianceCount == 0;
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
                            onTap: () => _showSessionDetail(s),
                            leading: CircleAvatar(
                              backgroundColor: (ok ? Colors.green : Colors.orange)
                                  .withValues(alpha: 0.12),
                              child: Icon(
                                Icons.fact_check_outlined,
                                color: ok ? Colors.green : Colors.orange,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              ok
                                  ? 'Inventaire — aucun écart'
                                  : 'Inventaire — ${s.varianceCount} écart(s)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${s.materialsCount} matière(s) contrôlée(s)${s.comment != null && s.comment!.isNotEmpty ? " · ${s.comment}" : ""}'
                              '\n${s.createdAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(s.createdAt!) : ""}${s.performedBy != null ? " · ${s.performedBy}" : ""}',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                            isThreeLine: true,
                            trailing: const Icon(
                              Icons.chevron_right,
                              color: Colors.grey,
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
                    onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
                  ),
                  Text(
                    'Page ${_page + 1} / $totalPages · $_totalCount inventaire(s)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _page < totalPages - 1
                        ? () => _goToPage(_page + 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
