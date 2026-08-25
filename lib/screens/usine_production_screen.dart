import 'package:flutter/material.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/formula.dart';
import '../models/production_batch.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';

/// Parcours 02 — Production & coût de revient (maquette écrans 14-19), condensé en un
/// écran à 2 onglets : lancement d'une fabrication (avec répartition FIFO automatique
/// entre lots quand une matière « par lot » chevauche 2 réceptions) et validation
/// comptable du coût de revient.
class UsineProductionScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineProductionScreen({
    super.key,
    required this.usine,
    this.permissions,
  });

  @override
  State<UsineProductionScreen> createState() => _UsineProductionScreenState();
}

class _UsineProductionScreenState extends State<UsineProductionScreen>
    with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  late TabController _tabController;
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;

  List<Formula> _formulas = [];
  List<RawMaterial> _materials = [];
  List<ProductionBatch> _batches = [];
  bool _isLoading = true;
  String? _error;
  String _historyFilter = 'tous'; // 'tous' | 'a_valider' | 'valide'

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
      final formulas = await _mongoService.getFormulas(widget.usine.id!);
      final materials = await _mongoService.getRawMaterials(widget.usine.id!);
      final batches = await _mongoService.getProductionBatches(
        usineId: widget.usine.id,
      );
      if (!mounted) return;
      setState(() {
        _formulas = formulas.where((f) => f.isActive).toList();
        _materials = materials;
        _batches = batches;
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

  /// Statut indicatif (pas un blocage) : LIMITE si une matière de la formule est déjà
  /// sous son seuil d'alerte — même logique que le stock bas de l'écran Approvisionnement.
  bool _isFormulaLimited(Formula f) {
    for (final line in f.lines) {
      final m = _materialById(line.rawMaterialId);
      if (m != null &&
          m.lowStockThreshold > 0 &&
          m.currentStock < m.lowStockThreshold)
        return true;
    }
    return false;
  }

  // ------------------------------------------------------- Nouvelle fabrication (wizard)

  static const List<String> _wizardStepLabels = [
    'Quantité',
    'Vérification',
    'Confirmation',
  ];

  void _showLaunchWizard(Formula formula) {
    final quantityController = TextEditingController();
    final actualController = TextEditingController();
    int step =
        0; // 0 = saisie quantité, 1 = vérification stock, 2 = confirmation sortie
    ProductionCheckResult? checkResult;
    String? error;
    bool isBusy = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          List<Widget> stepChildren;
          if (step == 0) {
            stepChildren = [
              TextField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantité à produire (kg)',
                ),
                autofocus: true,
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ];
          } else if (step == 1) {
            stepChildren = [
              const Text(
                'Matières nécessaires vs stock',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              ...checkResult!.lines.map((l) {
                final color = l.status == 'insuffisant'
                    ? Colors.red
                    : (l.status == 'limite' ? Colors.orange : Colors.green);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.materialName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Text(
                            '${l.needed.toStringAsFixed(0)} / ${l.available.toStringAsFixed(0)} ${l.unit}',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (l.batchPreview.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Chevauchement de lots : ${l.batchPreview.map((b) => '${b['lotNumber']} (${(b['quantity'] as num).toStringAsFixed(0)})').join(' + ')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.orange,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              if (!checkResult!.canLaunch)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'Stock insuffisant pour au moins une matière : impossible de lancer cette fabrication.',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ];
          } else {
            stepChildren = [
              TextField(
                controller: actualController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Quantité produite (pesée de sortie, kg)',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              const Text(
                'Les matières ci-dessus seront prélevées du stock à la confirmation.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
            ];
          }

          final content = SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (step + 1) / 3,
                      minHeight: 5,
                      color: Colors.orange,
                      backgroundColor: Colors.orange.shade50,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Étape ${step + 1}/3 · ${_wizardStepLabels[step]}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...stepChildren,
                  if (isBusy)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Center(
                        child: CircularProgressIndicator(color: Colors.orange),
                      ),
                    ),
                ],
              ),
            ),
          );

          List<Widget> actions;
          if (step == 0) {
            actions = [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.pop(context),
                child: const Text(
                  'Annuler',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        final qty = double.tryParse(quantityController.text);
                        if (qty == null || qty <= 0) {
                          setDialogState(() => error = 'Quantité invalide');
                          return;
                        }
                        setDialogState(() {
                          isBusy = true;
                          error = null;
                        });
                        final result = await _mongoService.checkProduction(
                          widget.usine.id!,
                          formula.id!,
                          qty,
                        );
                        actualController.text = qty.toStringAsFixed(0);
                        setDialogState(() {
                          checkResult = result;
                          isBusy = false;
                          step = 1;
                        });
                      },
                child: const Text('Vérifier le stock'),
              ),
            ];
          } else if (step == 1) {
            actions = [
              TextButton(
                onPressed: () => setDialogState(() => step = 0),
                child: const Text(
                  'Retour',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: checkResult!.canLaunch
                    ? () => setDialogState(() => step = 2)
                    : null,
                child: const Text('Continuer'),
              ),
            ];
          } else {
            actions = [
              TextButton(
                onPressed: isBusy ? null : () => setDialogState(() => step = 1),
                child: const Text(
                  'Retour',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        final actual = double.tryParse(actualController.text);
                        if (actual == null || actual <= 0) {
                          setDialogState(() => error = 'Quantité invalide');
                          return;
                        }
                        setDialogState(() {
                          isBusy = true;
                          error = null;
                        });
                        final qty = double.parse(quantityController.text);
                        final result = await _mongoService.launchProduction(
                          usineId: widget.usine.id!,
                          formulaId: formula.id!,
                          quantityTarget: qty,
                          actualQuantityProduced: actual,
                        );
                        if (result.error != null) {
                          setDialogState(() {
                            error = result.error;
                            isBusy = false;
                          });
                          return;
                        }
                        await _refreshData();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        _snack(
                          'Fabrication ${result.batch!.lotNumber} lancée, envoyée au comptable.',
                        );
                      },
                child: const Text('Lancer & envoyer au comptable'),
              ),
            ];
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              formula.name,
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: content,
            actions: actions,
          );
        },
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildLaunchTab() {
    if (!_perms.manageProduction) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            "Le lancement d'une fabrication est réservé au responsable de production.",
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_formulas.isEmpty)
      return const Center(
        child: Text(
          'Aucune formule active. Créez-en une dans le référentiel.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _formulas.length,
      itemBuilder: (context, index) {
        final f = _formulas[index];
        final isLimited = _isFormulaLimited(f);
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
            onTap: () => _showLaunchWizard(f),
            leading: CircleAvatar(
              backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
              child: const Icon(
                Icons.science_rounded,
                color: Colors.deepPurple,
              ),
            ),
            title: Text(
              f.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '${f.lines.length} matière(s) première(s)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: Chip(
              visualDensity: VisualDensity.compact,
              backgroundColor: isLimited
                  ? Colors.amber.shade100
                  : Colors.green.shade100,
              label: Text(
                isLimited ? 'LIMITE' : 'OK',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isLimited ? Colors.brown : Colors.green.shade800,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------- Validation comptable

  void _showValidateDialog(ProductionBatch batch) {
    final adjustmentController = TextEditingController(text: '0');
    final reasonController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final adjustment = double.tryParse(adjustmentController.text) ?? 0;
          final previewTotal = batch.totalCost + adjustment;
          final previewPerUnit = batch.actualQuantityProduced > 0
              ? previewTotal / batch.actualQuantityProduced
              : 0;
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '${batch.lotNumber} — Validation',
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
                    ...batch.consumption.map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${c.materialName} · ${c.quantityConsumed.toStringAsFixed(0)} kg × ${c.unitCost.toStringAsFixed(2)} F',
                              ),
                            ),
                            Text(
                              c.lineCost.toStringAsFixed(0),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(),
                    TextField(
                      controller: adjustmentController,
                      keyboardType: const TextInputType.numberWithOptions(
                        signed: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Ajustement (charges indirectes, FCFA)',
                        errorText: error,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonController,
                      decoration: const InputDecoration(
                        labelText: 'Motif (si ajustement non nul)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Coût de revient définitif',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${previewPerUnit.toStringAsFixed(2)} F/kg',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: previewPerUnit <= 0
                                ? Colors.red
                                : Colors.green.shade700,
                          ),
                        ),
                      ],
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
                  if (adjustment != 0 && reasonController.text.trim().isEmpty) {
                    setDialogState(
                      () => error = 'Motif requis pour un ajustement non nul',
                    );
                    return;
                  }
                  final err = await _mongoService.validateProduction(
                    batch.id!,
                    adjustment: adjustment,
                    adjustmentReason: reasonController.text.trim().isEmpty
                        ? null
                        : reasonController.text.trim(),
                  );
                  if (err != null) {
                    setDialogState(() => error = err);
                    return;
                  }
                  await _refreshData();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('Valider le coût'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Fiche détaillée en lecture seule d'un lot déjà validé — c'était le trou de
  /// l'historique : un lot validé était jusque-là inerte, impossible à consulter.
  void _showBatchDetailDialog(ProductionBatch batch) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${batch.lotNumber} — Historique',
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
                Text(
                  'Formule ${batch.formulaName} · cible ${batch.quantityTarget.toStringAsFixed(0)} kg · produit ${batch.actualQuantityProduced.toStringAsFixed(0)} kg',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                if (batch.createdAt != null)
                  Text(
                    'Lancé le ${batch.createdAt!.day.toString().padLeft(2, '0')}/${batch.createdAt!.month.toString().padLeft(2, '0')}/${batch.createdAt!.year}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                const Divider(),
                ...batch.consumption.map(
                  (c) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${c.materialName} · ${c.quantityConsumed.toStringAsFixed(0)} kg × ${c.unitCost.toStringAsFixed(2)} F',
                          ),
                        ),
                        Text(
                          c.lineCost.toStringAsFixed(0),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                if (batch.costAdjustment != 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Ajustement comptable : ${batch.costAdjustment > 0 ? '+' : ''}${batch.costAdjustment.toStringAsFixed(0)} FCFA${batch.adjustmentReason != null ? ' (${batch.adjustmentReason})' : ''}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Coût de revient validé',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${batch.costPerUnit.toStringAsFixed(2)} F/kg',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
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

  Widget _buildValidationTab() {
    if (!_perms.validateCost) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Le suivi des coûts de revient est réservé à la comptabilité.',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final filtered = _batches.where((b) {
      if (_historyFilter == 'a_valider') return !b.isValidated;
      if (_historyFilter == 'valide') return b.isValidated;
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Tous'),
                selected: _historyFilter == 'tous',
                onSelected: (_) => setState(() => _historyFilter = 'tous'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('À valider'),
                selected: _historyFilter == 'a_valider',
                onSelected: (_) => setState(() => _historyFilter = 'a_valider'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Validés'),
                selected: _historyFilter == 'valide',
                onSelected: (_) => setState(() => _historyFilter = 'valide'),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(
                  child: Text(
                    'Aucun lot dans cette catégorie.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final b = filtered[index];
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
                        onTap: () => b.isValidated
                            ? _showBatchDetailDialog(b)
                            : _showValidateDialog(b),
                        leading: CircleAvatar(
                          backgroundColor:
                              (b.isValidated ? Colors.green : Colors.amber)
                                  .withValues(alpha: 0.15),
                          child: Icon(
                            b.isValidated
                                ? Icons.check_circle_outline
                                : Icons.hourglass_top_rounded,
                            color: b.isValidated ? Colors.green : Colors.orange,
                          ),
                        ),
                        title: Text(
                          b.lotNumber,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          '${b.actualQuantityProduced.toStringAsFixed(0)} kg · ${b.costPerUnit.toStringAsFixed(2)} F/kg',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        trailing: Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: b.isValidated
                              ? Colors.green.shade100
                              : Colors.amber.shade100,
                          label: Text(
                            b.isValidated ? 'VALIDÉ' : 'À VALIDER',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: b.isValidated
                                  ? Colors.green.shade800
                                  : Colors.brown,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'PRODUCTION — ${widget.usine.name.toUpperCase()}',
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
            Tab(text: 'Fabrication'),
            Tab(text: 'Suivi & historique'),
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
              children: [_buildLaunchTab(), _buildValidationTab()],
            ),
    );
  }
}
