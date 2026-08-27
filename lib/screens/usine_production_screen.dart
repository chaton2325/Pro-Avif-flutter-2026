import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/formula.dart';
import '../models/production_batch.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';
import 'usine_simulation_screen.dart';

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
      if (line.rawMaterialId == null) continue;
      final m = _materialById(line.rawMaterialId!);
      if (m != null &&
          m.lowStockThreshold > 0 &&
          m.currentStock < m.lowStockThreshold)
        return true;
    }
    return false;
  }

  // ------------------------------------------------------- Nouvelle fabrication (wizard)

  static const List<String> _wizardStepLabels = ['Quantité', 'Lancement'];

  void _showLaunchWizard(Formula formula) {
    final quantityController = TextEditingController();
    int step = 0; // 0 = saisie quantité, 1 = vérification stock puis lancement
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
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                ],
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
          } else {
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
                            '${formatQty(l.needed)} / ${formatQty(l.available)} ${l.unit}',
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
                            'Chevauchement de lots : ${l.batchPreview.map((b) => '${b['lotNumber']} (${formatQty(b['quantity'] as num)})').join(' + ')}',
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
              if (checkResult!.canLaunch && checkResult!.lines.isNotEmpty)
                Builder(
                  builder: (context) {
                    // Écran 15, annotation B : anticipation basée sur la matière la plus
                    // contrainte — combien de fabrications identiques restent possibles.
                    final counts = checkResult!.lines
                        .where((l) => l.needed > 0)
                        .map((l) => (l.available / l.needed).floor());
                    if (counts.isEmpty) return const SizedBox.shrink();
                    final minCount = counts.reduce((a, b) => a < b ? a : b);
                    if (minCount > 20) return const SizedBox.shrink();
                    final limiting = checkResult!.lines.firstWhere(
                      (l) =>
                          l.needed > 0 &&
                          (l.available / l.needed).floor() == minCount,
                    );
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Au rythme actuel, le stock de ${limiting.materialName} permet encore ~$minCount fabrication(s) de cette taille avant rupture.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    );
                  },
                ),
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
                      value: (step + 1) / 2,
                      minHeight: 5,
                      color: Colors.orange,
                      backgroundColor: Colors.orange.shade50,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Étape ${step + 1}/2 · ${_wizardStepLabels[step]}',
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
                        final result = await runBlocking(
                          context,
                          () => _mongoService.checkProduction(
                            widget.usine.id!,
                            formula.id!,
                            qty,
                          ),
                        );
                        setDialogState(() {
                          checkResult = result;
                          isBusy = false;
                          step = 1;
                        });
                      },
                child: const Text('Vérifier le stock'),
              ),
            ];
          } else {
            actions = [
              TextButton(
                onPressed: isBusy ? null : () => setDialogState(() => step = 0),
                child: const Text(
                  'Retour',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: (isBusy || !checkResult!.canLaunch)
                    ? null
                    : () async {
                        setDialogState(() {
                          isBusy = true;
                          error = null;
                        });
                        final qty = double.parse(quantityController.text);
                        // La quantité produite est provisoirement = la cible : la pesée de
                        // sortie réelle, souvent connue plus tard, se corrige à la clôture
                        // (écran 17) — le stock, lui, est bien consommé maintenant.
                        final result = await runBlocking(
                          context,
                          () => _mongoService.launchProduction(
                            usineId: widget.usine.id!,
                            formulaId: formula.id!,
                            quantityTarget: qty,
                            actualQuantityProduced: qty,
                          ),
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
                        _showCloseDialog(result.batch!, justLaunched: true);
                      },
                child: const Text('Lancer la fabrication'),
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

  /// Écran 17 — clôture : le stock est déjà consommé (lancement), il ne reste qu'à
  /// corriger la quantité réellement produite (pesée de sortie, souvent connue plus tard)
  /// avant de rester en brouillon ou d'envoyer au comptable. Jamais de F/kg ni de FCFA ici
  /// — cet écran reste celui de la production (annotation B).
  void _showCloseDialog(ProductionBatch batch, {bool justLaunched = false}) {
    final actualController = TextEditingController(
      text: formatQty(batch.actualQuantityProduced),
    );
    String? error;
    bool isBusy = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (justLaunched)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Fabrication lancée, stock déjà prélevé. Si la pesée de sortie n\'est pas encore connue, enregistrez en brouillon et revenez-y plus tard depuis l\'onglet Fabrication.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey),
                      ),
                    ),
                  TextField(
                    controller: actualController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Quantité produite (pesée de sortie, kg)',
                      errorText: error,
                    ),
                    autofocus: !justLaunched,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Matières consommées',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ...batch.consumption.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(child: Text(c.materialName)),
                          Text(
                            '${formatQty(c.quantityConsumed)} kg',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
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
          ),
          actions: [
            TextButton(
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
                      final err = await runBlocking(
                        context,
                        () => _mongoService.closeProduction(
                          batch.id!,
                          actualQuantityProduced: actual,
                          sendToAccountant: false,
                        ),
                      );
                      if (err != null) {
                        setDialogState(() {
                          error = err;
                          isBusy = false;
                        });
                        return;
                      }
                      await _refreshData();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      _snack(
                        'Enregistré en brouillon — à finaliser plus tard.',
                      );
                    },
              child: const Text(
                'Brouillon',
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
                      final err = await runBlocking(
                        context,
                        () => _mongoService.closeProduction(
                          batch.id!,
                          actualQuantityProduced: actual,
                          sendToAccountant: true,
                        ),
                      );
                      if (err != null) {
                        setDialogState(() {
                          error = err;
                          isBusy = false;
                        });
                        return;
                      }
                      await _refreshData();
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      _snack('Lot ${batch.lotNumber} envoyé au comptable.');
                    },
              child: const Text('Envoyer au comptable'),
            ),
          ],
        ),
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
    // Écran 17 : brouillons en attente de clôture — lancés (stock déjà prélevé) mais pas
    // encore envoyés au comptable, soit fraîchement créés, soit renvoyés par la
    // comptabilité (écran 19). Visible même sans validateCost, sinon la production n'a
    // jamais connaissance des lots à finaliser ou des renvois.
    final drafts = _batches.where((b) => b.isDraft).toList();
    return Column(
      children: [
        if (drafts.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: drafts.any((b) => b.isRejected)
                  ? Colors.red.shade50
                  : Colors.grey.shade100,
              border: drafts.any((b) => b.isRejected)
                  ? Border.all(color: Colors.red.shade200)
                  : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.hourglass_top_rounded,
                      color: drafts.any((b) => b.isRejected)
                          ? Colors.red.shade400
                          : Colors.grey.shade600,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${drafts.length} brouillon(s) à clôturer',
                      style: TextStyle(
                        color: drafts.any((b) => b.isRejected)
                            ? Colors.red.shade800
                            : Colors.grey.shade800,
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                ...drafts.map(
                  (b) => InkWell(
                    onTap: () => _showCloseDialog(b),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        b.isRejected
                            ? '${b.lotNumber} — renvoyé : ${b.rejectionReason}'
                            : '${b.lotNumber} — ${formatQty(b.actualQuantityProduced)} kg (à confirmer)',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: b.isRejected
                              ? Colors.brown
                              : Colors.grey.shade700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: _formulas.isEmpty ? 2 : _formulas.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade100),
                  ),
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UsineSimulationScreen(
                          usine: widget.usine,
                          permissions: widget.permissions,
                        ),
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: Colors.orange.withValues(alpha: 0.1),
                      child: const Icon(
                        Icons.calculate_outlined,
                        color: Colors.orange,
                      ),
                    ),
                    title: const Text(
                      'Simulateur & optimisation',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                    subtitle: const Text(
                      'Ce qu\'on peut produire, plan optimisé multi-formules',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                    ),
                  ),
                );
              }
              if (_formulas.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      'Aucune formule active. Créez-en une dans le référentiel.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              final f = _formulas[index - 1];
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
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------- Validation comptable

  void _showRejectDialog(ProductionBatch batch) {
    final reasonController = TextEditingController();
    String? error;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            '${batch.lotNumber} — Renvoyer',
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: reasonController,
            decoration: InputDecoration(
              labelText: 'Motif du renvoi',
              errorText: error,
            ),
            autofocus: true,
            maxLines: 2,
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Motif requis');
                  return;
                }
                final err = await runBlocking(
                  context,
                  () => _mongoService.rejectProduction(
                    batch.id!,
                    reasonController.text.trim(),
                  ),
                );
                if (err != null) {
                  setDialogState(() => error = err);
                  return;
                }
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
                _snack('Lot ${batch.lotNumber} renvoyé en production.');
              },
              child: const Text('Renvoyer en production'),
            ),
          ],
        ),
      ),
    );
  }

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
                                '${c.materialName} · ${formatQty(c.quantityConsumed)} kg × ${c.unitCost.toStringAsFixed(2)} F',
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
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^-?\d*\.?\d*$'),
                        ),
                      ],
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
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _showRejectDialog(batch);
                },
                child: const Text(
                  'Renvoyer',
                  style: TextStyle(color: Colors.redAccent),
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
                  final err = await runBlocking(
                    context,
                    () => _mongoService.validateProduction(
                      batch.id!,
                      adjustment: adjustment,
                      adjustmentReason: reasonController.text.trim().isEmpty
                          ? null
                          : reasonController.text.trim(),
                    ),
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
                  'Formule ${batch.formulaName} · cible ${formatQty(batch.quantityTarget)} kg · produit ${formatQty(batch.actualQuantityProduced)} kg',
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
                            '${c.materialName} · ${formatQty(c.quantityConsumed)} kg × ${c.unitCost.toStringAsFixed(2)} F',
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
      if (_historyFilter == 'a_valider') return b.status == 'a_valider';
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
                        onTap: () {
                          if (b.isValidated) {
                            _showBatchDetailDialog(b);
                          } else if (b.isDraft) {
                            _showCloseDialog(b);
                          } else {
                            _showValidateDialog(b);
                          }
                        },
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
                          b.isRejected && !b.isValidated
                              ? 'Renvoyé : ${b.rejectionReason}'
                              : '${formatQty(b.actualQuantityProduced)} kg · ${b.costPerUnit.toStringAsFixed(2)} F/kg',
                          style: TextStyle(
                            color: b.isRejected && !b.isValidated
                                ? Colors.redAccent
                                : Colors.grey.shade600,
                            fontSize: 12,
                            fontWeight: b.isRejected && !b.isValidated
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Chip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: b.isValidated
                              ? Colors.green.shade100
                              : (b.isRejected
                                    ? Colors.red.shade100
                                    : (b.isDraft
                                          ? Colors.grey.shade200
                                          : Colors.amber.shade100)),
                          label: Text(
                            b.isValidated
                                ? 'VALIDÉ'
                                : (b.isRejected
                                      ? 'RENVOYÉ'
                                      : (b.isDraft
                                            ? 'BROUILLON'
                                            : 'À VALIDER')),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: b.isValidated
                                  ? Colors.green.shade800
                                  : (b.isRejected
                                        ? Colors.red.shade800
                                        : (b.isDraft
                                              ? Colors.grey.shade700
                                              : Colors.brown)),
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
