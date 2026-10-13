import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'admin_daily_report_users_screen.dart';
import 'admin_farm_staff_screen.dart';
import 'admin_hatcheries_screen.dart';
import 'admin_treatment_references_screen.dart';

/// Onglet « Paramètres » du hub admin du Rapport Journalier : référentiels rarement modifiés
/// (personnel, utilisateurs, couvoirs, traitements) + choix des bâtiments en production.
/// Un bâtiment n'est pas en production par défaut : son rapport ne demande alors que l'eau.
class AdminDailyReportSettingsTab extends StatefulWidget {
  const AdminDailyReportSettingsTab({super.key});

  @override
  State<AdminDailyReportSettingsTab> createState() => _AdminDailyReportSettingsTabState();
}

class _AdminDailyReportSettingsTabState extends State<AdminDailyReportSettingsTab> {
  final MongoService _mongoService = MongoService();
  List<Farm> _farms = [];
  bool _loading = true;
  final Set<String> _saving = {};
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
    setState(() {
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
    final items = [
      (
        icon: Icons.badge_rounded,
        color: DailyReportColors.green700,
        title: 'Personnel',
        subtitle: 'Créer, affecter, gérer par ferme',
        builder: (BuildContext c) => const AdminFarmStaffScreen(),
      ),
      (
        icon: Icons.admin_panel_settings_rounded,
        color: DailyReportColors.green900,
        title: 'Utilisateurs',
        subtitle: 'Comptes rédacteurs & validateurs, accès expéditions',
        builder: (BuildContext c) => const AdminDailyReportUsersScreen(),
      ),
      (
        icon: Icons.egg_rounded,
        color: DailyReportColors.blue600,
        title: 'Couvoirs',
        subtitle: 'Vers où sont expédiés les œufs à couver',
        builder: (BuildContext c) => const AdminHatcheriesScreen(),
      ),
      (
        icon: Icons.medical_services_rounded,
        color: DailyReportColors.blue600,
        title: 'Vaccins & médicaments',
        subtitle: 'Référentiel des traitements',
        builder: (BuildContext c) => const AdminTreatmentReferencesScreen(),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 12.0;
            final tileWidth = (constraints.maxWidth - spacing) / 2;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final e in items)
                  SizedBox(
                    width: tileWidth,
                    child: DailyReportSquareMenuTile(
                      icon: e.icon,
                      color: e.color,
                      title: e.title,
                      subtitle: e.subtitle,
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: e.builder)),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const Text(
          'Bâtiments en production',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: DailyReportColors.green900),
        ),
        const SizedBox(height: 4),
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
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (final f in visibleFarms)
                  SwitchListTile(
                    title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(f.isProduction ? 'En production' : 'Hors production'),
                    value: f.isProduction,
                    onChanged: (f.id == null || _saving.contains(f.id)) ? null : (v) => _toggle(f, v),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
