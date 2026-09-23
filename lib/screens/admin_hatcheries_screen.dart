import 'package:flutter/material.dart';
import '../models/hatchery.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

/// Référentiel couvoirs (admin uniquement) : vers où les œufs à couver (OAC) sont expédiés —
/// le rédacteur/admin choisit dedans à l'expédition, jamais de texte libre.
class AdminHatcheriesScreen extends StatefulWidget {
  const AdminHatcheriesScreen({super.key});

  @override
  State<AdminHatcheriesScreen> createState() => _AdminHatcheriesScreenState();
}

class _AdminHatcheriesScreenState extends State<AdminHatcheriesScreen> {
  final MongoService _mongoService = MongoService();
  List<Hatchery> _hatcheries = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<Hatchery> get _visible {
    var list = _hatcheries;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((h) => h.name.toLowerCase().contains(q)).toList();
    }
    return List.of(list)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
    final hatcheries = await _mongoService.getHatcheries();
    if (!mounted) return;
    setState(() {
      _hatcheries = hatcheries;
      _loading = false;
    });
  }

  void _showEditDialog({Hatchery? existing}) {
    final nameController = TextEditingController(text: existing?.name ?? '');
    bool isActive = existing?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? 'Nouveau couvoir' : 'Modifier le couvoir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nom du couvoir', border: OutlineInputBorder()),
              ),
              if (existing != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Actif'),
                  value: isActive,
                  activeThumbColor: DailyReportColors.green700,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                if (existing == null) {
                  await _mongoService.createHatchery(Hatchery(name: name));
                } else {
                  await _mongoService.updateHatchery(existing.id!, Hatchery(id: existing.id, name: name, isActive: isActive));
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

  Future<void> _delete(Hatchery h) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer ce couvoir ?'),
        content: Text('« ${h.name} » sera définitivement supprimé du référentiel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final error = await _mongoService.deleteHatchery(h.id!);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Couvoirs', subtitle: "Vers où sont expédiés les œufs à couver"),
      floatingActionButton: FloatingActionButton(
        backgroundColor: DailyReportColors.green700,
        onPressed: () => _showEditDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un couvoir…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Expanded(
                  child: _visible.isEmpty
                      ? Center(child: Text('Aucun couvoir trouvé.', style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _visible.length,
                          itemBuilder: (context, i) {
                            final h = _visible[i];
                            return DailyReportCard(
                              accentColor: h.isActive ? DailyReportColors.green600 : Colors.grey.shade400,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              children: [
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Container(
                                    width: 38,
                                    height: 38,
                                    decoration: BoxDecoration(
                                      color: DailyReportColors.purple600.withValues(alpha: 0.14),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Center(child: Text('🐣', style: TextStyle(fontSize: 17))),
                                  ),
                                  title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  subtitle: h.isActive ? null : Text('Inactif', style: TextStyle(color: Colors.grey.shade500)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18, color: DailyReportColors.green700),
                                        onPressed: () => _showEditDialog(existing: h),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                        onPressed: () => _delete(h),
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
}
