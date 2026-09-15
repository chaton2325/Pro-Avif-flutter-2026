import 'package:flutter/material.dart';
import '../models/treatment_reference.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

/// Référentiel vaccins/médicaments (admin uniquement) : le rédacteur choisit dedans dans le
/// formulaire "Traitements", jamais de texte libre (cahier des charges section 5).
class AdminTreatmentReferencesScreen extends StatefulWidget {
  const AdminTreatmentReferencesScreen({super.key});

  @override
  State<AdminTreatmentReferencesScreen> createState() => _AdminTreatmentReferencesScreenState();
}

class _AdminTreatmentReferencesScreenState extends State<AdminTreatmentReferencesScreen> {
  final MongoService _mongoService = MongoService();
  List<TreatmentReference> _references = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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
    final unitController = TextEditingController(text: existing?.unit ?? 'doses');

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
                  DropdownMenuItem(value: 'medicament', child: Text('Médicament')),
                ],
                onChanged: (v) => setDialogState(() => type = v!),
                decoration: const InputDecoration(labelText: 'Type'),
              ),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom')),
              TextField(controller: unitController, decoration: const InputDecoration(labelText: 'Unité (ex. doses, ml)')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                if (existing == null) {
                  await _mongoService.createTreatmentReference(TreatmentReference(
                    type: type,
                    name: nameController.text.trim(),
                    unit: unitController.text.trim().isEmpty ? 'doses' : unitController.text.trim(),
                  ));
                } else {
                  await _mongoService.updateTreatmentReference(TreatmentReference(
                    id: existing.id,
                    type: type,
                    name: nameController.text.trim(),
                    unit: unitController.text.trim(),
                    isActive: existing.isActive,
                  ));
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
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Vaccins & médicaments'),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: DailyReportColors.green700,
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _references.length,
              itemBuilder: (context, i) {
                final ref = _references[i];
                return Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                  child: ListTile(
                    leading: Text(ref.type == 'vaccin' ? '💉' : '💊', style: const TextStyle(fontSize: 20)),
                    title: Text(ref.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(ref.unit),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _showEditDialog(existing: ref)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () async {
                            await _mongoService.deleteTreatmentReference(ref.id!);
                            _load();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
