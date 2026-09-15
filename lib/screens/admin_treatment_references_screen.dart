import 'package:flutter/material.dart';
import '../models/treatment_reference.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

enum _TypeFilter { all, vaccin, medicament }

enum _RefSort { alpha, type }

/// Référentiel vaccins/médicaments (admin uniquement) : le rédacteur choisit dedans dans le
/// formulaire "Traitements", jamais de texte libre (cahier des charges section 5).
class AdminTreatmentReferencesScreen extends StatefulWidget {
  const AdminTreatmentReferencesScreen({super.key});

  @override
  State<AdminTreatmentReferencesScreen> createState() =>
      _AdminTreatmentReferencesScreenState();
}

class _AdminTreatmentReferencesScreenState
    extends State<AdminTreatmentReferencesScreen> {
  final MongoService _mongoService = MongoService();
  List<TreatmentReference> _references = [];
  bool _loading = true;
  _TypeFilter _typeFilter = _TypeFilter.all;
  _RefSort _sortMode = _RefSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<TreatmentReference> get _visible {
    Iterable<TreatmentReference> result = _references;
    if (_typeFilter != _TypeFilter.all) {
      final wanted = _typeFilter == _TypeFilter.vaccin
          ? 'vaccin'
          : 'medicament';
      result = result.where((r) => r.type == wanted);
    }
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      result = result.where((r) => r.name.toLowerCase().contains(q));
    }
    final list = result.toList();
    list.sort(
      (a, b) => _sortMode == _RefSort.alpha
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : a.type.compareTo(b.type) != 0
          ? a.type.compareTo(b.type)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
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
    final refs = await _mongoService.getTreatmentReferences();
    if (!mounted) return;
    setState(() {
      _references = refs;
      _loading = false;
    });
  }

  void _showEditDialog({TreatmentReference? existing}) {
    String type = existing?.type ?? 'vaccin';
    final nameController = TextEditingController(text: existing?.name ?? '');
    final unitController = TextEditingController(
      text: existing?.unit ?? 'doses',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'Nouvelle référence' : 'Modifier'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: type,
                items: const [
                  DropdownMenuItem(value: 'vaccin', child: Text('Vaccin')),
                  DropdownMenuItem(
                    value: 'medicament',
                    child: Text('Médicament'),
                  ),
                ],
                onChanged: (v) => setDialogState(() => type = v!),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Nom'),
              ),
              TextField(
                controller: unitController,
                decoration: const InputDecoration(
                  labelText: 'Unité (ex. doses, ml)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: DailyReportColors.green700,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                if (existing == null) {
                  await _mongoService.createTreatmentReference(
                    TreatmentReference(
                      type: type,
                      name: nameController.text.trim(),
                      unit: unitController.text.trim().isEmpty
                          ? 'doses'
                          : unitController.text.trim(),
                    ),
                  );
                } else {
                  await _mongoService.updateTreatmentReference(
                    TreatmentReference(
                      id: existing.id,
                      type: type,
                      name: nameController.text.trim(),
                      unit: unitController.text.trim(),
                      isActive: existing.isActive,
                    ),
                  );
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                _load();
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Vaccins & médicaments'),
      floatingActionButton: FloatingActionButton(
        backgroundColor: DailyReportColors.green700,
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: DailyReportColors.green700,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: DailySearchSortBar<_RefSort>(
                    controller: _searchController,
                    hintText: 'Rechercher un vaccin, un médicament…',
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    sortValue: _sortMode,
                    onSortChanged: (v) => setState(() => _sortMode = v),
                    sortOptions: const [
                      DailySortOption(_RefSort.alpha, 'Alphabétique (A→Z)'),
                      DailySortOption(_RefSort.type, 'Type puis nom'),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _typeChip('Tous', _TypeFilter.all),
                      const SizedBox(width: 6),
                      _typeChip('💉 Vaccins', _TypeFilter.vaccin),
                      const SizedBox(width: 6),
                      _typeChip('💊 Médicaments', _TypeFilter.medicament),
                    ],
                  ),
                ),
                Expanded(
                  child: _visible.isEmpty
                      ? Center(
                          child: Text(
                            'Aucune référence trouvée.',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _visible.length,
                          itemBuilder: (context, i) {
                            final ref = _visible[i];
                            final isVaccin = ref.type == 'vaccin';
                            final color = isVaccin
                                ? DailyReportColors.green700
                                : DailyReportColors.yellow600;
                            return DailyReportCard(
                              accentColor: color,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 6,
                              ),
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(
                                        isVaccin ? '💉' : '💊',
                                        style: const TextStyle(fontSize: 17),
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    ref.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    ref.unit,
                                    style: TextStyle(
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          Icons.edit,
                                          size: 18,
                                          color: DailyReportColors.green700,
                                        ),
                                        onPressed: () =>
                                            _showEditDialog(existing: ref),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_outline,
                                          size: 18,
                                          color: Colors.red,
                                        ),
                                        onPressed: () async {
                                          await _mongoService
                                              .deleteTreatmentReference(
                                                ref.id!,
                                              );
                                          _load();
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _typeChip(String label, _TypeFilter value) {
    final selected = _typeFilter == value;
    return ChoiceChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
      selected: selected,
      backgroundColor: Colors.white,
      selectedColor: DailyReportColors.green700,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? DailyReportColors.green700 : Colors.grey.shade300,
        ),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : Colors.grey.shade700,
      ),
      onSelected: (_) => setState(() => _typeFilter = value),
    );
  }
}
