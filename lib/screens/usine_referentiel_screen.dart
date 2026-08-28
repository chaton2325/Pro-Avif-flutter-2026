import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/formula.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';

const List<String> _rawMaterialCategories = [
  'Énergie',
  'Protéine',
  'Minéral',
  'Additif',
  'Autre',
];

/// Brouillon d'une ligne de formule pendant l'édition : la source peut être une matière
/// première OU un autre aliment déjà produit (ex. SUPER PLUS) — [isAliment] distingue les
/// deux, ce qu'un simple MapEntry ne pouvait pas porter proprement.
class _FormulaLineDraft {
  String? sourceId;
  bool isAliment;
  final TextEditingController controller;
  _FormulaLineDraft({
    this.sourceId,
    this.isAliment = false,
    required this.controller,
  });
}

/// Référentiel matières premières + formules d'une usine précise (Partie 1).
/// Chaque usine a son propre référentiel : deux usines peuvent avoir des matières et
/// des formules totalement différentes.
class UsineReferentielScreen extends StatefulWidget {
  final Usine usine;
  const UsineReferentielScreen({super.key, required this.usine});

  @override
  State<UsineReferentielScreen> createState() => _UsineReferentielScreenState();
}

class _UsineReferentielScreenState extends State<UsineReferentielScreen>
    with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  late TabController _tabController;

  List<RawMaterial> _materials = [];
  List<Formula> _formulas = [];
  bool _isLoading = true;
  String? _error;

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
      final materials = await _mongoService.getRawMaterials(widget.usine.id!);
      final formulas = await _mongoService.getFormulas(widget.usine.id!);
      if (!mounted) return;
      setState(() {
        _materials = materials;
        _formulas = formulas;
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

  // ------------------------------------------------------- Matières premières

  void _showMaterialDialog({RawMaterial? material}) {
    final nameController = TextEditingController(text: material?.name ?? '');
    final unitController = TextEditingController(text: material?.unit ?? 'kg');
    final thresholdController = TextEditingController(
      text: formatQty(material?.lowStockThreshold ?? 0),
    );
    final supplierController = TextEditingController();
    String? category = material?.category ?? _rawMaterialCategories.first;
    String managementMode = material?.managementMode ?? 'global';
    bool isActive = material?.isActive ?? true;
    List<String> suppliers = List.from(material?.usualSuppliers ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            material == null
                ? 'Nouvelle matière première'
                : 'Modifier la matière',
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
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      prefixIcon: Icon(Icons.grass_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: unitController,
                          decoration: const InputDecoration(labelText: 'Unité'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Catégorie',
                          ),
                          value: category,
                          items: _rawMaterialCategories
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (v) => setDialogState(() => category = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Mode de gestion',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Global (CUMP)'),
                        selected: managementMode == 'global',
                        selectedColor: Colors.orange.shade100,
                        onSelected: (_) =>
                            setDialogState(() => managementMode = 'global'),
                      ),
                      ChoiceChip(
                        label: const Text('Par lot'),
                        selected: managementMode == 'par_lot',
                        selectedColor: Colors.orange.shade100,
                        onSelected: (_) =>
                            setDialogState(() => managementMode = 'par_lot'),
                      ),
                    ],
                  ),
                  if (material != null &&
                      managementMode != material.managementMode &&
                      material.currentStock > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        managementMode == 'par_lot'
                            ? 'Le stock actuel (${formatQty(material.currentStock)} ${material.unit}) sera migré vers un lot unique à l\'enregistrement.'
                            : 'Les lots actifs seront clôturés et fusionnés en un stock global avec un CUMP recalculé à l\'enregistrement.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade800,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: thresholdController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                    ],
                    decoration: const InputDecoration(
                      labelText: "Seuil d'alerte stock bas",
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fournisseurs habituels',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: supplierController,
                          decoration: const InputDecoration(
                            hintText: 'Nom du fournisseur',
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.add_circle,
                          color: Colors.orange,
                          size: 30,
                        ),
                        onPressed: () {
                          final s = supplierController.text.trim();
                          if (s.isNotEmpty && !suppliers.contains(s)) {
                            setDialogState(() {
                              suppliers.add(s);
                              supplierController.clear();
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: suppliers
                        .map(
                          (s) => Chip(
                            label: Text(s),
                            onDeleted: () =>
                                setDialogState(() => suppliers.remove(s)),
                          ),
                        )
                        .toList(),
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
                final newMaterial = RawMaterial(
                  id: material?.id,
                  usineId: widget.usine.id!,
                  name: nameController.text.trim(),
                  unit: unitController.text.trim().isEmpty
                      ? 'kg'
                      : unitController.text.trim(),
                  category: category,
                  managementMode: managementMode,
                  lowStockThreshold:
                      double.tryParse(thresholdController.text) ?? 0,
                  usualSuppliers: suppliers,
                  isActive: isActive,
                );
                await runBlocking(context, () async {
                  if (material == null) {
                    await _mongoService.addRawMaterial(newMaterial);
                  } else {
                    await _mongoService.updateRawMaterial(newMaterial);
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

  void _confirmDeleteMaterial(RawMaterial m) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Supprimer cette matière ?',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Cela supprime "${m.name}" du référentiel. L\'historique déjà enregistré (réceptions, lots, ajustements) reste consultable mais ne pointera plus vers une matière existante. Préférez la désactiver si elle n\'est pas utilisée pour l\'instant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              await runBlocking(context, () async {
                await _mongoService.deleteRawMaterial(m.id!);
                await _refreshData();
              });
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }

  /// Un aliment supprimé casserait les références historiques (production, stock,
  /// livraisons) qui pointent vers lui — désactiver le retire des usages futurs
  /// (production, livraison) tout en gardant l'historique consultable.
  Future<void> _setFormulaActive(Formula f, bool isActive) async {
    final err = await runBlocking(
      context,
      () => _mongoService.updateFormula(
        Formula(
          id: f.id,
          usineId: f.usineId,
          name: f.name,
          lines: f.lines,
          isActive: isActive,
          lowStockThreshold: f.lowStockThreshold,
          canBeIngredient: f.canBeIngredient,
          isManagedInKg: f.isManagedInKg,
        ),
      ),
    );
    if (err != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await _refreshData();
  }

  void _toggleFormulaActive(Formula f) {
    if (!f.isActive) {
      _setFormulaActive(f, true);
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Désactiver cet aliment ?',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          '"${f.name}" ne sera plus utilisable en production ni en livraison, mais reste consultable dans l\'historique. Réactivable à tout moment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuler', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(context);
              _setFormulaActive(f, false);
            },
            child: const Text('Désactiver'),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialsTab() {
    if (_materials.isEmpty)
      return const Center(
        child: Text(
          'Aucune matière première. Ajoutez-en une avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 148,
      ),
      itemCount: _materials.length,
      itemBuilder: (context, index) {
        final m = _materials[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
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
                    radius: 15,
                    backgroundColor: (m.isActive ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.1),
                    child: Icon(
                      Icons.grass_rounded,
                      size: 16,
                      color: m.isActive ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        m.name,
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                m.category ?? 'Sans catégorie',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
              Text(
                '${m.isParLot ? "Par lot" : "Global"} · seuil ${formatQty(m.lowStockThreshold)} ${m.unit}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (m.isActive ? Colors.green : Colors.grey.shade400)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      m.isActive ? 'ACTIF' : 'INACTIF',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: m.isActive
                            ? Colors.green.shade800
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showMaterialDialog(material: m),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.edit_rounded,
                        color: Colors.blue,
                        size: 18,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _confirmDeleteMaterial(m),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------- Formules

  void _showFormulaDialog({Formula? formula}) {
    // Options combinées pour chaque ligne : matières premières achetées + autres aliments
    // explicitement marqués "utilisable comme ingrédient" (ex. SUPER PLUS) — jamais la
    // formule en cours d'édition elle-même, et jamais un aliment non coché (RL0 par
    // exemple, un produit fini) même si techniquement il existe.
    final ingredientFormulas = _formulas
        .where((f) => f.id != null && f.id != formula?.id && f.canBeIngredient)
        .toList();
    if (_materials.isEmpty && ingredientFormulas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Créez au moins une matière première avant une formule.',
          ),
        ),
      );
      return;
    }
    final nameController = TextEditingController(text: formula?.name ?? '');
    final thresholdController = TextEditingController(
      text: formatQty(formula?.lowStockThreshold ?? 0),
    );
    bool isActive = formula?.isActive ?? true;
    bool canBeIngredient = formula?.canBeIngredient ?? false;
    bool isManagedInKg = formula?.isManagedInKg ?? false;
    String? error;
    List<_FormulaLineDraft> lines = (formula?.lines ?? [])
        .map(
          (l) => _FormulaLineDraft(
            sourceId: l.sourceId,
            isAliment: l.isIngredientAliment,
            controller: TextEditingController(
              text: formatQty(l.quantityPerTon),
            ),
          ),
        )
        .toList();
    final totalOptions = _materials.length + ingredientFormulas.length;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double total = 0;
          for (final l in lines) {
            total += double.tryParse(l.controller.text) ?? 0;
          }
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              formula == null ? 'Nouvelle formule' : 'Modifier la formule',
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
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nom (ex : RL0, RL2...)',
                        prefixIcon: Icon(Icons.science_outlined),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Gérer en kilogrammes (pas en tonnes)'),
                      subtitle: const Text(
                        'Pour un aliment simple, ex. coquille écrasée obtenue à partir de coquille (1 kg → 1 kg). Sinon, la composition se définit en kg par tonne produite.',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: isManagedInKg,
                      activeColor: Colors.orange,
                      onChanged: (v) => setDialogState(() => isManagedInKg = v),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isManagedInKg
                          ? 'Composition (kg par kg produit)'
                          : 'Composition (kg par tonne produite)',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...List.generate(lines.length, (i) {
                      final entry = lines[i];
                      final usedIds = lines.map((l) => l.sourceId).toSet();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value:
                                    _materials.any(
                                          (m) => m.id == entry.sourceId,
                                        ) ||
                                        ingredientFormulas.any(
                                          (f) => f.id == entry.sourceId,
                                        )
                                    ? entry.sourceId
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Matière ou aliment',
                                  isDense: true,
                                ),
                                items: [
                                  ..._materials
                                      .where(
                                        (m) =>
                                            m.id == entry.sourceId ||
                                            !usedIds.contains(m.id),
                                      )
                                      .map(
                                        (m) => DropdownMenuItem(
                                          value: m.id,
                                          child: Text(
                                            m.name,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                  ...ingredientFormulas
                                      .where(
                                        (f) =>
                                            f.id == entry.sourceId ||
                                            !usedIds.contains(f.id),
                                      )
                                      .map(
                                        (f) => DropdownMenuItem(
                                          value: f.id,
                                          child: Text(
                                            '🏭 ${f.name} (aliment produit)',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                ],
                                onChanged: (v) => setDialogState(() {
                                  final isAliment = ingredientFormulas.any(
                                    (f) => f.id == v,
                                  );
                                  lines[i] = _FormulaLineDraft(
                                    sourceId: v,
                                    isAliment: isAliment,
                                    controller: entry.controller,
                                  );
                                }),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: entry.controller,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d*$'),
                                  ),
                                ],
                                decoration: InputDecoration(
                                  labelText: isManagedInKg ? 'kg/kg' : 'kg/t',
                                  isDense: true,
                                ),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setDialogState(() => lines.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: totalOptions > lines.length
                          ? () => setDialogState(() {
                              final usedIds = lines
                                  .map((l) => l.sourceId)
                                  .toSet();
                              final availableMaterials = _materials
                                  .where((m) => !usedIds.contains(m.id))
                                  .toList();
                              if (availableMaterials.isNotEmpty) {
                                lines.add(
                                  _FormulaLineDraft(
                                    sourceId: availableMaterials.first.id,
                                    isAliment: false,
                                    controller: TextEditingController(
                                      text: '0',
                                    ),
                                  ),
                                );
                                return;
                              }
                              final availableAliments = ingredientFormulas
                                  .where((f) => !usedIds.contains(f.id))
                                  .toList();
                              if (availableAliments.isNotEmpty) {
                                lines.add(
                                  _FormulaLineDraft(
                                    sourceId: availableAliments.first.id,
                                    isAliment: true,
                                    controller: TextEditingController(
                                      text: '0',
                                    ),
                                  ),
                                );
                              }
                            })
                          : null,
                      icon: const Icon(Icons.add, color: Colors.orange),
                      label: const Text(
                        'Ajouter une ligne',
                        style: TextStyle(color: Colors.orange),
                      ),
                    ),
                    const Divider(),
                    Builder(
                      builder: (context) {
                        final reference = isManagedInKg ? 1.0 : 1000.0;
                        final tolerance = reference * 0.05;
                        final isOff = (total - reference).abs() > tolerance;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  isManagedInKg
                                      ? 'Total / kg produit'
                                      : 'Total / tonne',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${formatQty(total)} kg',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: isOff
                                        ? Colors.orange.shade800
                                        : Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                            if (isOff)
                              Text(
                                isManagedInKg
                                    ? 'Le total s\'écarte de 1 kg/kg : vérifiez qu\'il ne manque pas de composant.'
                                    : 'Le total s\'écarte de 1000 kg/t : vérifiez qu\'il ne manque pas de composant.',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.orange,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: thresholdController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*$'),
                        ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Seuil de stock bas (kg d\'aliment produit)',
                        prefixIcon: Icon(Icons.warning_amber_rounded),
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
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Utilisable comme ingrédient'),
                      subtitle: const Text(
                        'Apparaîtra dans le choix des matières d\'un autre aliment (ex. SUPER PLUS)',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: canBeIngredient,
                      activeColor: Colors.orange,
                      onChanged: (v) =>
                          setDialogState(() => canBeIngredient = v),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
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
                  if (nameController.text.trim().isEmpty || lines.isEmpty)
                    return;
                  final newFormula = Formula(
                    id: formula?.id,
                    usineId: widget.usine.id!,
                    name: nameController.text.trim(),
                    lines: lines
                        .map(
                          (l) => FormulaLine(
                            rawMaterialId: l.isAliment ? null : l.sourceId,
                            ingredientFormulaId: l.isAliment
                                ? l.sourceId
                                : null,
                            quantityPerTon:
                                double.tryParse(l.controller.text) ?? 0,
                          ),
                        )
                        .toList(),
                    isActive: isActive,
                    lowStockThreshold:
                        double.tryParse(thresholdController.text) ?? 0,
                    canBeIngredient: canBeIngredient,
                    isManagedInKg: isManagedInKg,
                  );
                  final err = await runBlocking(
                    context,
                    () => formula == null
                        ? _mongoService.addFormula(newFormula)
                        : _mongoService.updateFormula(newFormula),
                  );
                  if (err != null) {
                    setDialogState(() => error = err);
                    return;
                  }
                  await _refreshData();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFormulasTab() {
    if (_formulas.isEmpty)
      return const Center(
        child: Text(
          'Aucune formule. Créez-en une avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 160,
      ),
      itemCount: _formulas.length,
      itemBuilder: (context, index) {
        final f = _formulas[index];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.deepPurple.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.2)),
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
                    radius: 15,
                    backgroundColor: Colors.deepPurple.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.science_rounded,
                      size: 16,
                      color: Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        f.name,
                        maxLines: 1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (f.canBeIngredient || f.isManagedInKg)
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    if (f.canBeIngredient)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'INGRÉDIENT',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.deepPurple.shade700,
                          ),
                        ),
                      ),
                    if (f.isManagedInKg)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'GÉRÉ EN KG',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                f.lines.any((l) => l.isIngredientAliment)
                    ? '${f.lines.length} ligne(s) · ${formatQty(f.totalPerTon)} ${f.isManagedInKg ? "kg/kg" : "kg/t"} · utilise un aliment produit'
                    : '${f.lines.length} matière(s) · ${formatQty(f.totalPerTon)} ${f.isManagedInKg ? "kg/kg" : "kg/t"}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: (f.isActive ? Colors.green : Colors.grey.shade400)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      f.isActive ? 'ACTIF' : 'INACTIF',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: f.isActive
                            ? Colors.green.shade800
                            : Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _showFormulaDialog(formula: f),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.edit_rounded,
                        color: Colors.blue,
                        size: 18,
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => _toggleFormulaActive(f),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        f.isActive
                            ? Icons.block_rounded
                            : Icons.check_circle_outline_rounded,
                        color: f.isActive ? Colors.redAccent : Colors.green,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.usine.name.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            fontSize: 15,
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
            Tab(text: 'Matières premières'),
            Tab(text: 'Formules'),
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
              children: [_buildMaterialsTab(), _buildFormulasTab()],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        onPressed: () => _tabController.index == 0
            ? _showMaterialDialog()
            : _showFormulaDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
