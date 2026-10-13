import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/current_lot_dialog.dart';
import '../widgets/daily_report_widgets.dart';

/// Fenêtre « Bâtiments » (Paramètres admin) : bâtiment en production ou non, et lot en cours.
/// Un bâtiment n'est pas en production par défaut : son rapport ne demande alors que l'eau.
class AdminFarmsSettingsScreen extends StatefulWidget {
  const AdminFarmsSettingsScreen({super.key});

  @override
  State<AdminFarmsSettingsScreen> createState() => _AdminFarmsSettingsScreenState();
}

class _AdminFarmsSettingsScreenState extends State<AdminFarmsSettingsScreen> {
  final MongoService _mongoService = MongoService();
  List<Farm> _farms = [];
  bool _loading = true;
  final Set<String> _saving = {};
  Map<String, String?> _lots = {}; // farmName -> lot en cours
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    final farms = await _mongoService.getFarms();
    if (!mounted) return;
    farms.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final lots = await Future.wait(farms.map((f) => _mongoService.getCurrentLotForFarm(f.name)));
    if (!mounted) return;
    setState(() {
      _lots = {for (var i = 0; i < farms.length; i++) farms[i].name: lots[i]};
      _farms = farms;
      _loading = false;
    });
  }

  Future<void> _toggle(Farm farm, bool value) async {
    final id = farm.id;
    if (id == null) return;
    setState(() => _saving.add(id));
    final ok = await _mongoService.setFarmProduction(id, value);
    if (!mounted) return;
    setState(() {
      _saving.remove(id);
      if (ok) {
        final i = _farms.indexWhere((f) => f.id == id);
        if (i != -1) {
          _farms[i] = Farm(id: id, name: farm.name, rooms: farm.rooms, isProduction: value);
        }
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Échec de la mise à jour du bâtiment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    // Tri à l'affichage (insensible à la casse et aux espaces de bord) : « bandjoun » et
    // « Bandjoun Semto » restent voisins.
    String key(Farm f) => f.name.trim().toLowerCase();
    final visibleFarms = _farms.where((f) => q.isEmpty || key(f).contains(q)).toList()
      ..sort((a, b) => key(a).compareTo(key(b)));
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Bâtiments', subtitle: 'Production et lot en cours'),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
        Text(
          'En production : le rapport journalier affiche la production (œufs) et l\'eau. '
          'Sinon : l\'eau seulement.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Rechercher un bâtiment',
            prefixIcon: const Icon(Icons.search),
            isDense: true,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_farms.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Aucun bâtiment.'))
        else if (visibleFarms.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Aucun bâtiment ne correspond.'))
        else
          for (final f in visibleFarms)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(f.isProduction ? 'En production' : 'Hors production'),
                    value: f.isProduction,
                    onChanged: (f.id == null || _saving.contains(f.id)) ? null : (v) => _toggle(f, v),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Lot en cours : ${_lots[f.name] ?? "non défini"}',
                            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: f.id == null
                              ? null
                              : () async {
                                  final changed = await showCurrentLotDialog(
                                    context,
                                    farmId: f.id!,
                                    farmName: f.name,
                                    currentLot: _lots[f.name],
                                  );
                                  if (changed && mounted) _loadFarms();
                                },
                          child: const Text('Modifier le lot'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
