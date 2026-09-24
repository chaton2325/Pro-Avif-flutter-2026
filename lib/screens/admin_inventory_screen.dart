import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'inventory_screen.dart';
import 'inventory_history_screen.dart';

/// Point d'entrée admin de l'inventaire (aliment + œufs) : l'admin choisit d'abord la ferme
/// (le rédacteur, lui, arrive directement sur InventoryScreen avec sa propre ferme déjà
/// fixée), ou consulte/valide toutes les demandes toutes fermes confondues — même principe
/// que AdminEggShipmentsScreen.
class AdminInventoryScreen extends StatefulWidget {
  const AdminInventoryScreen({super.key});

  @override
  State<AdminInventoryScreen> createState() => _AdminInventoryScreenState();
}

class _AdminInventoryScreenState extends State<AdminInventoryScreen> {
  final MongoService _mongoService = MongoService();
  List<Farm> _farms = [];
  bool _loading = true;
  int _pendingCount = 0;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<Farm> get _visible {
    var list = _farms;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((f) => f.name.toLowerCase().contains(q)).toList();
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
    final farms = await _mongoService.getFarms();
    final pending = await _mongoService.getPendingInventoryRequestsCount();
    if (!mounted) return;
    setState(() {
      _farms = farms;
      _pendingCount = pending;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Inventaire', subtitle: 'Choisir une ferme'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Badge(
                    isLabelVisible: _pendingCount > 0,
                    label: Text('$_pendingCount'),
                    backgroundColor: Colors.red.shade600,
                    alignment: const Alignment(1.05, -1.2),
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const InventoryHistoryScreen(isAdmin: true)),
                        );
                        _load();
                      },
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('Toutes les demandes — toutes fermes'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DailyReportColors.purple600,
                        side: const BorderSide(color: DailyReportColors.purple600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        minimumSize: const Size(double.infinity, 44),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un bâtiment…',
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
                      ? Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500)))
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            DailyReportFarmGrid(
                              children: [
                                for (final f in _visible)
                                  DailyReportFarmGridCard(
                                    title: f.name,
                                    accentColor: DailyReportColors.purple600,
                                    onTap: () async {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(builder: (_) => InventoryScreen(farm: f, isAdmin: true)),
                                      );
                                      _load();
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                ),
              ],
            ),
    );
  }
}
