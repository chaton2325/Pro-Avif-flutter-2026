import 'package:flutter/material.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/formula.dart';
import '../services/mongo_service.dart';
import 'usine_appro_screen.dart';
import 'usine_production_screen.dart';

const List<String> _rawMaterialCategories = ['Énergie', 'Protéine', 'Minéral', 'Additif', 'Autre'];

/// Référentiel matières premières + formules d'une usine précise (Partie 1).
/// Chaque usine a son propre référentiel : deux usines peuvent avoir des matières et
/// des formules totalement différentes.
class UsineReferentielScreen extends StatefulWidget {
  final Usine usine;
  const UsineReferentielScreen({super.key, required this.usine});

  @override
  State<UsineReferentielScreen> createState() => _UsineReferentielScreenState();
}

class _UsineReferentielScreenState extends State<UsineReferentielScreen> with SingleTickerProviderStateMixin {
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
    final thresholdController = TextEditingController(text: (material?.lowStockThreshold ?? 0).toStringAsFixed(0));
    final supplierController = TextEditingController();
    String? category = material?.category ?? _rawMaterialCategories.first;
    String managementMode = material?.managementMode ?? 'global';
    bool isActive = material?.isActive ?? true;
    List<String> suppliers = List.from(material?.usualSuppliers ?? []);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(material == null ? 'Nouvelle matière première' : 'Modifier la matière',
              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom', prefixIcon: Icon(Icons.grass_outlined))),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: unitController, decoration: const InputDecoration(labelText: 'Unité'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Catégorie'),
                          value: category,
                          items: _rawMaterialCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                          onChanged: (v) => setDialogState(() => category = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Mode de gestion', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Global (CUMP)'),
                        selected: managementMode == 'global',
                        selectedColor: Colors.orange.shade100,
                        onSelected: (_) => setDialogState(() => managementMode = 'global'),
                      ),
                      ChoiceChip(
                        label: const Text('Par lot'),
                        selected: managementMode == 'par_lot',
                        selectedColor: Colors.orange.shade100,
                        onSelected: (_) => setDialogState(() => managementMode = 'par_lot'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: thresholdController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Seuil d'alerte stock bas"),
                  ),
                  const SizedBox(height: 16),
                  const Text('Fournisseurs habituels', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(child: TextField(controller: supplierController, decoration: const InputDecoration(hintText: 'Nom du fournisseur'))),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.orange, size: 30),
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
                    children: suppliers.map((s) => Chip(label: Text(s), onDeleted: () => setDialogState(() => suppliers.remove(s)))).toList(),
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
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final newMaterial = RawMaterial(
                  id: material?.id,
                  usineId: widget.usine.id!,
                  name: nameController.text.trim(),
                  unit: unitController.text.trim().isEmpty ? 'kg' : unitController.text.trim(),
                  category: category,
                  managementMode: managementMode,
                  lowStockThreshold: double.tryParse(thresholdController.text) ?? 0,
                  usualSuppliers: suppliers,
                  isActive: isActive,
                );
                if (material == null) {
                  await _mongoService.addRawMaterial(newMaterial);
                } else {
                  await _mongoService.updateRawMaterial(newMaterial);
                }
                await _refreshData();
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

  Widget _buildMaterialsTab() {
    if (_materials.isEmpty) return const Center(child: Text('Aucune matière première. Ajoutez-en une avec le bouton +.', style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _materials.length,
      itemBuilder: (context, index) {
        final m = _materials[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.green.withValues(alpha: 0.1), child: const Icon(Icons.grass_rounded, color: Colors.green)),
            title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text(
              '${m.category ?? "Sans catégorie"} · ${m.isParLot ? "Par lot" : "Global"} · seuil ${m.lowStockThreshold.toStringAsFixed(0)} ${m.unit}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20), onPressed: () => _showMaterialDialog(material: m)),
                IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20), onPressed: () async { await _mongoService.deleteRawMaterial(m.id!); _refreshData(); }),
              ],
            ),
          ),
        );
      },
    );
  }

  // -------------------------------------------------------------- Formules

  void _showFormulaDialog({Formula? formula}) {
    if (_materials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Créez au moins une matière première avant une formule.')));
      return;
    }
    final nameController = TextEditingController(text: formula?.name ?? '');
    bool isActive = formula?.isActive ?? true;
    List<MapEntry<String, TextEditingController>> lines = (formula?.lines ?? []).map((l) => MapEntry(l.rawMaterialId, TextEditingController(text: l.quantityPerTon.toStringAsFixed(0)))).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double total = 0;
          for (final l in lines) {
            total += double.tryParse(l.value.text) ?? 0;
          }
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(formula == null ? 'Nouvelle formule' : 'Modifier la formule',
                style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom (ex : RL0, RL2...)', prefixIcon: Icon(Icons.science_outlined))),
                    const SizedBox(height: 16),
                    const Text('Composition (kg par tonne produite)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    ...List.generate(lines.length, (i) {
                      final entry = lines[i];
                      final usedIds = lines.map((l) => l.key).toSet();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _materials.any((m) => m.id == entry.key) ? entry.key : null,
                                decoration: const InputDecoration(labelText: 'Matière', isDense: true),
                                items: _materials
                                    .where((m) => m.id == entry.key || !usedIds.contains(m.id))
                                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)))
                                    .toList(),
                                onChanged: (v) => setDialogState(() => lines[i] = MapEntry(v!, entry.value)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: TextField(
                                controller: entry.value,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(labelText: 'kg/t', isDense: true),
                                onChanged: (_) => setDialogState(() {}),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                              onPressed: () => setDialogState(() => lines.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    }),
                    TextButton.icon(
                      onPressed: _materials.length > lines.length
                          ? () => setDialogState(() => lines.add(MapEntry(_materials.firstWhere((m) => !lines.map((l) => l.key).contains(m.id)).id!, TextEditingController(text: '0'))))
                          : null,
                      icon: const Icon(Icons.add, color: Colors.orange),
                      label: const Text('Ajouter une matière', style: TextStyle(color: Colors.orange)),
                    ),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total / tonne', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(
                          '${total.toStringAsFixed(0)} kg',
                          style: TextStyle(fontWeight: FontWeight.w900, color: (total - 1000).abs() > 50 ? Colors.orange.shade800 : Colors.green.shade700),
                        ),
                      ],
                    ),
                    if ((total - 1000).abs() > 50)
                      const Text('Le total s\'écarte de 1000 kg/t : vérifiez qu\'il ne manque pas de composant.',
                          style: TextStyle(fontSize: 11, color: Colors.orange)),
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty || lines.isEmpty) return;
                  final newFormula = Formula(
                    id: formula?.id,
                    usineId: widget.usine.id!,
                    name: nameController.text.trim(),
                    lines: lines.map((l) => FormulaLine(rawMaterialId: l.key, quantityPerTon: double.tryParse(l.value.text) ?? 0)).toList(),
                    isActive: isActive,
                  );
                  if (formula == null) {
                    await _mongoService.addFormula(newFormula);
                  } else {
                    await _mongoService.updateFormula(newFormula);
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
    if (_formulas.isEmpty) return const Center(child: Text('Aucune formule. Créez-en une avec le bouton +.', style: TextStyle(color: Colors.grey)));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _formulas.length,
      itemBuilder: (context, index) {
        final f = _formulas[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.deepPurple.withValues(alpha: 0.1), child: const Icon(Icons.science_rounded, color: Colors.deepPurple)),
            title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w900)),
            subtitle: Text('${f.lines.length} matière(s) · ${f.totalPerTon.toStringAsFixed(0)} kg/t', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20), onPressed: () => _showFormulaDialog(formula: f)),
                IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20), onPressed: () async { await _mongoService.deleteFormula(f.id!); _refreshData(); }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.usine.name.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1, fontSize: 15)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.local_shipping_outlined, color: Colors.orange),
            tooltip: 'Approvisionnement',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UsineApproScreen(usine: widget.usine))),
          ),
          IconButton(
            icon: const Icon(Icons.precision_manufacturing_outlined, color: Colors.orange),
            tooltip: 'Production',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => UsineProductionScreen(usine: widget.usine))),
          ),
          IconButton(icon: const Icon(Icons.refresh, color: Colors.orange), onPressed: _refreshData),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [Tab(text: 'Matières premières'), Tab(text: 'Formules')],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center)))
              : TabBarView(controller: _tabController, children: [_buildMaterialsTab(), _buildFormulasTab()]),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        onPressed: () => _tabController.index == 0 ? _showMaterialDialog() : _showFormulaDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
