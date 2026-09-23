import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'egg_shipment_screen.dart';
import 'egg_shipment_history_screen.dart';

/// Point d'entrée admin du module expéditions d'œufs : l'admin choisit d'abord la ferme (le
/// rédacteur, lui, arrive directement sur EggShipmentScreen avec sa propre ferme déjà fixée),
/// ou consulte/valide toutes les expéditions toutes fermes confondues.
class AdminEggShipmentsScreen extends StatefulWidget {
  const AdminEggShipmentsScreen({super.key});

  @override
  State<AdminEggShipmentsScreen> createState() => _AdminEggShipmentsScreenState();
}

class _AdminEggShipmentsScreenState extends State<AdminEggShipmentsScreen> {
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
    final pending = await _mongoService.getPendingEggShipmentsCount();
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
      appBar: dailyReportAppBar('Expéditions d\'œufs', subtitle: 'Choisir une ferme'),
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
                          MaterialPageRoute(builder: (_) => const EggShipmentHistoryScreen(isAdmin: true)),
                        );
                        _load();
                      },
                      icon: const Icon(Icons.history_rounded, size: 18),
                      label: const Text('Toutes les expéditions — toutes fermes'),
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
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => EggShipmentScreen(farmName: f.name, isAdmin: true)),
                                    ),
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
