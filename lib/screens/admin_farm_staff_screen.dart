import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../models/farm_staff.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

enum _StaffSort { alpha, recent }

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
  _StaffSort _sortMode = _StaffSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<FarmStaff> get _visible {
    var list = _staff;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((s) => s.name.toLowerCase().contains(q)).toList();
    } else {
      list = List.of(list);
    }
    if (_sortMode == _StaffSort.alpha) {
      list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFarms() async {
    final farms = List.of(await _mongoService.getFarms())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ajouter une personne'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
        ),
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

  void _confirmDelete(FarmStaff s) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retirer cette personne ?'),
        content: Text('${s.name} ne sera plus proposé dans le formulaire "Personnel".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
            onPressed: () async {
              await _mongoService.deleteFarmStaff(s.id!);
              if (!context.mounted) return;
              Navigator.pop(context);
              _selectFarm(_selectedFarm!);
            },
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
  }

  static const _avatarColors = [
    DailyReportColors.green700,
    DailyReportColors.green600,
    DailyReportColors.green900,
    DailyReportColors.yellow600,
  ];

  Color _avatarColor(String name) => _avatarColors[name.codeUnitAt(0) % _avatarColors.length];

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Personnel par ferme'),
      floatingActionButton: _selectedFarm == null
          ? null
          : FloatingActionButton(
              backgroundColor: DailyReportColors.green700,
              onPressed: _showAddDialog,
              child: const Icon(Icons.person_add_alt_1_rounded, color: Colors.white),
            ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              gradient: dailyReportHeaderGradient,
              borderRadius: BorderRadius.only(bottomLeft: Radius.circular(22), bottomRight: Radius.circular(22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('FERME', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                const SizedBox(height: 6),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<Farm>(
                      value: _selectedFarm,
                      isExpanded: true,
                      icon: const Icon(Icons.expand_more_rounded, color: DailyReportColors.green700),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        prefixIcon: Icon(Icons.home_work_rounded, color: DailyReportColors.green700, size: 20),
                      ),
                      style: const TextStyle(color: DailyReportColors.green900, fontWeight: FontWeight.w700, fontSize: 14),
                      items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
                      onChanged: (f) => f != null ? _selectFarm(f) : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: DailySearchSortBar<_StaffSort>(
              controller: _searchController,
              hintText: 'Rechercher une personne…',
              onSearchChanged: (v) => setState(() => _searchQuery = v),
              sortValue: _sortMode,
              onSortChanged: (v) => setState(() => _sortMode = v),
              sortOptions: const [
                DailySortOption(_StaffSort.alpha, 'Alphabétique (A→Z)'),
                DailySortOption(_StaffSort.recent, "Ordre d'ajout"),
              ],
            ),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Icon(Icons.groups_rounded, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text(
                    '${_staff.length} ${_staff.length > 1 ? "personnes" : "personne"}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
                : _visible.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_search_rounded, size: 40, color: Colors.grey.shade400),
                            const SizedBox(height: 10),
                            Text(
                              _staff.isEmpty ? 'Aucun personnel pour cette ferme.' : 'Aucun résultat.',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        itemCount: _visible.length,
                        itemBuilder: (context, i) {
                          final s = _visible[i];
                          final color = _avatarColor(s.name);
                          return DailyReportCard(
                            accentColor: color,
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: color.withValues(alpha: 0.15),
                                    child: Text(_initials(s.name), style: TextStyle(color: color, fontWeight: FontWeight.w800)),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(
                                                color: s.isActive ? DailyReportColors.green600 : Colors.grey.shade400,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              s.isActive ? 'Actif' : 'Inactif',
                                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    onPressed: () => _confirmDelete(s),
                                  ),
                                ],
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
