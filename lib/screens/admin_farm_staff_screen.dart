import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../models/farm_staff.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

/// Personnel affecté à un bâtiment (admin uniquement) : le rédacteur ne fait que choisir un
/// statut chaque jour dans cette liste (cahier des charges section 5, "jamais retapé").
class AdminFarmStaffScreen extends StatefulWidget {
  const AdminFarmStaffScreen({super.key});

  @override
  State<AdminFarmStaffScreen> createState() => _AdminFarmStaffScreenState();
}

class _AdminFarmStaffScreenState extends State<AdminFarmStaffScreen> {
  final MongoService _mongoService = MongoService();
  List<Farm> _farms = [];
  Farm? _selectedFarm;
  List<FarmStaff> _staff = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    final farms = await _mongoService.getFarms();
    if (!mounted) return;
    setState(() {
      _farms = farms;
      _loading = false;
    });
    if (farms.isNotEmpty) _selectFarm(farms.first);
  }

  Future<void> _selectFarm(Farm farm) async {
    setState(() {
      _selectedFarm = farm;
      _loading = true;
    });
    final staff = await _mongoService.getFarmStaff(farm.id!);
    if (!mounted) return;
    setState(() {
      _staff = staff;
      _loading = false;
    });
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ajouter une personne'),
        content: TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nom')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () async {
              if (nameController.text.trim().isEmpty || _selectedFarm == null) return;
              await _mongoService.createFarmStaff(
                FarmStaff(farmId: _selectedFarm!.id!, name: nameController.text.trim()),
              );
              if (!context.mounted) return;
              Navigator.pop(context);
              _selectFarm(_selectedFarm!);
            },
            child: const Text('Ajouter'),
          ),
        ],
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
        title: const Text('Personnel par ferme'),
      ),
      floatingActionButton: _selectedFarm == null
          ? null
          : FloatingActionButton(
              backgroundColor: DailyReportColors.green700,
              onPressed: _showAddDialog,
              child: const Icon(Icons.add, color: Colors.white),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<Farm>(
              value: _selectedFarm,
              decoration: const InputDecoration(labelText: 'Ferme', border: OutlineInputBorder()),
              items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
              onChanged: (f) => f != null ? _selectFarm(f) : null,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _staff.length,
                    itemBuilder: (context, i) {
                      final s = _staff[i];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.grey.shade200)),
                        child: ListTile(
                          title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                            onPressed: () async {
                              await _mongoService.deleteFarmStaff(s.id!);
                              _selectFarm(_selectedFarm!);
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
