import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../models/cumul.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'farm_feed_cumul_history_screen.dart';
import 'lot_egg_cumul_history_screen.dart';

/// Cumuls de départ (aliments et œufs) — réservé à l'admin. Notion DISTINCTE du stock de
/// départ / stock actuel (AdminFarmFeedStocksScreen / AdminLotEggStocksScreen) : un compteur
/// manuel qui ne bouge jamais avec la consommation ou la ponte du rapport journalier — une
/// ferme peut avoir un stock d'OAC de 10 en salle 1 et un cumul de 100 sur cette même salle,
/// deux notions indépendantes. Chaque saisie ADDITIONNE au cumul déjà existant (jamais un
/// remplacement) — voir POST /cumuls/feed/add et POST /cumuls/eggs/add côté backend.
class AdminCumulsScreen extends StatefulWidget {
  const AdminCumulsScreen({super.key});

  @override
  State<AdminCumulsScreen> createState() => _AdminCumulsScreenState();
}

class _AdminCumulsScreenState extends State<AdminCumulsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        'Cumuls de départ',
        subtitle: 'Aliments et œufs — indépendant du stock actuel',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Aliments'),
            Tab(text: 'Œufs'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _FeedCumulTab(),
          _EggCumulTab(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Aliments
// ---------------------------------------------------------------------------

class _FarmFeedCumulStatus {
  final Farm farm;
  final FarmFeedCumul? cumul;
  _FarmFeedCumulStatus({required this.farm, this.cumul});
}

class _FeedCumulTab extends StatefulWidget {
  const _FeedCumulTab();

  @override
  State<_FeedCumulTab> createState() => _FeedCumulTabState();
}

class _FeedCumulTabState extends State<_FeedCumulTab> {
  final MongoService _mongoService = MongoService();
  List<_FarmFeedCumulStatus> _statuses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final farms = List.of(await _mongoService.getFarms())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final statuses = await Future.wait(farms.map((farm) async {
      final cumul = await _mongoService.getFarmFeedCumul(farm.name);
      return _FarmFeedCumulStatus(farm: farm, cumul: cumul);
    }));
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _loading = false;
    });
  }

  Future<void> _addCumul(_FarmFeedCumulStatus s) async {
    final controller = TextEditingController();
    final qty = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Ajouter au cumul — ${s.farm.name}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Cumul actuel : ${s.cumul?.totalKg ?? 0} kg\nCe montant s\'ajoutera au cumul déjà existant.',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Quantité à ajouter (kg)', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.purple600, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, double.tryParse(controller.text.replaceAll(',', '.'))),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (qty == null || qty <= 0 || !mounted) return;
    final result = await _mongoService.addFarmFeedCumul(s.farm.name, qty);
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _statuses.fold<double>(0, (a, s) => a + (s.cumul?.totalKg ?? 0));
    return _loading
        ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DailyReportStatTile(
                  value: '${total.toStringAsFixed(total == total.roundToDouble() ? 0 : 2)} kg',
                  label: 'Cumul total — toutes fermes',
                  color: DailyReportColors.purple600,
                  icon: Icons.stacked_line_chart_rounded,
                ),
                const SizedBox(height: 18),
                const DailyReportSectionLabel('Par ferme'),
                if (_statuses.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                  )
                else
                  for (final s in _statuses) _farmCard(s),
              ],
            ),
          );
  }

  Widget _farmCard(_FarmFeedCumulStatus s) {
    return DailyReportCard(
      accentColor: DailyReportColors.purple600,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.farm.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  const SizedBox(height: 4),
                  Text(
                    'Cumul : ${s.cumul?.totalKg ?? 0} kg',
                    style: const TextStyle(color: DailyReportColors.purple600, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.history_rounded, color: Colors.grey, size: 20),
              tooltip: 'Historique',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => FarmFeedCumulHistoryScreen(farmName: s.farm.name)),
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _addCumul(s),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('Ajouter'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DailyReportColors.purple600,
                side: const BorderSide(color: DailyReportColors.purple600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Œufs
// ---------------------------------------------------------------------------

class _EggCumulTab extends StatefulWidget {
  const _EggCumulTab();

  @override
  State<_EggCumulTab> createState() => _EggCumulTabState();
}

class _EggCumulTabState extends State<_EggCumulTab> {
  final MongoService _mongoService = MongoService();
  List<Farm> _farms = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final farms = List.of(await _mongoService.getFarms())
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _farms = farms;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _loading
        ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const DailyReportSectionLabel('Par ferme'),
                if (_farms.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 30),
                    child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                  )
                else
                  for (final f in _farms) _farmCard(f),
              ],
            ),
          );
  }

  Widget _farmCard(Farm f) {
    return DailyReportCard(
      accentColor: DailyReportColors.purple600,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        InkWell(
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminEggCumulEditScreen(farm: f)));
            _load();
          },
          child: Row(
            children: [
              Expanded(
                child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ],
    );
  }
}

const _newLotSentinel = '__new_lot__';
const _kEggFields = ['oac', 'po', 'dj', 'cas', 'sal'];
const _kEggFieldLabels = {'oac': 'OAC', 'po': 'PO', 'dj': 'DJ', 'cas': 'CAS', 'sal': 'SAL'};

/// Ajout au cumul d'œufs de départ pour une ferme + un lot, salle par salle : les champs
/// représentent le montant à AJOUTER (pas la valeur totale), remis à zéro après chaque envoi
/// réussi. Le cumul déjà enregistré par salle reste affiché au-dessus, jamais écrasé.
class AdminEggCumulEditScreen extends StatefulWidget {
  final Farm farm;

  const AdminEggCumulEditScreen({super.key, required this.farm});

  @override
  State<AdminEggCumulEditScreen> createState() => _AdminEggCumulEditScreenState();
}

class _AdminEggCumulEditScreenState extends State<AdminEggCumulEditScreen> {
  final MongoService _mongoService = MongoService();
  List<String> _lotNumbers = [];
  String? _selectedLot;
  bool _loadingLots = true;
  final Map<String, Map<String, TextEditingController>> _controllers = {};
  bool _saving = false;
  String? _message;
  bool _success = false;
  LotEggCumul? _existingCumul;

  @override
  void initState() {
    super.initState();
    for (final room in widget.farm.rooms) {
      _controllers[room] = {for (final f in _kEggFields) f: TextEditingController(text: '0')};
    }
    _loadLots();
  }

  Future<void> _loadLots() async {
    final lots = List.of(await _mongoService.getLots())..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final currentLot = await _mongoService.getCurrentLotForFarm(widget.farm.name);
    final numbers = <String>{...lots.map((l) => l.number), if (currentLot != null) currentLot}.toList();
    if (!mounted) return;
    setState(() {
      _lotNumbers = numbers;
      _selectedLot = currentLot;
      _loadingLots = false;
    });
    if (_selectedLot != null) _loadExisting();
  }

  @override
  void dispose() {
    for (final fields in _controllers.values) {
      for (final c in fields.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  void _resetControllers() {
    for (final room in widget.farm.rooms) {
      for (final f in _kEggFields) {
        _controllers[room]![f]!.text = '0';
      }
    }
  }

  Future<void> _onLotSelected(String? lot) async {
    if (lot == _newLotSentinel) {
      await _createNewLot();
      return;
    }
    setState(() {
      _selectedLot = lot;
      _resetControllers();
      _message = null;
      _existingCumul = null;
    });
    await _loadExisting();
  }

  Future<void> _createNewLot() async {
    final controller = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Numéro de lot'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Numéro de lot (ex : LOT 24)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.purple600, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Choisir'),
          ),
        ],
      ),
    );
    if (number == null || number.isEmpty) return;
    setState(() {
      if (!_lotNumbers.contains(number)) _lotNumbers = [number, ..._lotNumbers];
      _selectedLot = number;
      _resetControllers();
      _existingCumul = null;
      _message = null;
    });
    await _loadExisting();
  }

  Future<void> _loadExisting() async {
    if (_selectedLot == null || _selectedLot!.trim().isEmpty) return;
    final existing = await _mongoService.getLotEggCumul(widget.farm.name, _selectedLot!.trim());
    if (!mounted) return;
    setState(() {
      _existingCumul = existing;
      _message = existing == null ? "Aucun cumul enregistré pour ce lot — première saisie." : null;
    });
  }

  int _currentFor(String room, String field) {
    RoomEggCumul? r;
    for (final candidate in _existingCumul?.rooms ?? const <RoomEggCumul>[]) {
      if (candidate.roomName == room) {
        r = candidate;
        break;
      }
    }
    if (r == null) return 0;
    switch (field) {
      case 'oac':
        return r.oac;
      case 'po':
        return r.po;
      case 'dj':
        return r.dj;
      case 'cas':
        return r.cas;
      default:
        return r.sal;
    }
  }

  Future<void> _save() async {
    if (_selectedLot == null || _selectedLot!.trim().isEmpty) {
      setState(() {
        _message = 'Choisissez un numéro de lot.';
        _success = false;
      });
      return;
    }
    final entries = <MapEntry<String, Map<String, int>>>[];
    for (final room in widget.farm.rooms) {
      final deltas = {
        for (final f in _kEggFields) f: int.tryParse(_controllers[room]![f]!.text) ?? 0,
      };
      if (deltas.values.any((v) => v != 0)) entries.add(MapEntry(room, deltas));
    }
    if (entries.isEmpty) {
      setState(() {
        _message = 'Saisissez au moins une quantité à ajouter.';
        _success = false;
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    String? error;
    for (final e in entries) {
      final result = await _mongoService.addLotEggCumul(
        farmName: widget.farm.name,
        lotNumber: _selectedLot!.trim(),
        roomName: e.key,
        oac: e.value['oac']!,
        po: e.value['po']!,
        dj: e.value['dj']!,
        cas: e.value['cas']!,
        sal: e.value['sal']!,
      );
      if (result.error != null) {
        error = result.error;
        break;
      }
      _existingCumul = result.cumul;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = error == null;
      _message = error ?? 'Cumul mis à jour.';
      if (error == null) _resetControllers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farm.name, subtitle: "Cumul œufs de départ"),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DailyReportCard(children: [
            _loadingLots
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: DailyReportColors.purple600)),
                  )
                : DropdownButtonFormField<String>(
                    initialValue: _selectedLot,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Numéro de lot', border: OutlineInputBorder()),
                    hint: const Text('Choisir un lot'),
                    items: [
                      ..._lotNumbers.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                      const DropdownMenuItem(
                        value: _newLotSentinel,
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline, size: 17, color: DailyReportColors.purple600),
                            SizedBox(width: 6),
                            Text('Nouveau numéro de lot…', style: TextStyle(color: DailyReportColors.purple600, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: _onLotSelected,
                  ),
          ]),
          if (_selectedLot != null) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LotEggCumulHistoryScreen(farmName: widget.farm.name, lotNumber: _selectedLot!.trim()),
                ),
              ),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text("Voir l'historique du cumul"),
              style: OutlinedButton.styleFrom(
                foregroundColor: DailyReportColors.purple600,
                side: const BorderSide(color: DailyReportColors.purple600),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(double.infinity, 42),
              ),
            ),
          ],
          const SizedBox(height: 18),
          const DailyReportSectionLabel('Ajouter — par salle', icon: Icons.add_circle_outline_rounded),
          for (final room in widget.farm.rooms) _roomCard(room),
          if (_message != null)
            Container(
              margin: const EdgeInsets.only(top: 4, bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _success ? DailyReportColors.green100 : DailyReportColors.yellow100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _message!,
                style: TextStyle(color: _success ? DailyReportColors.green900 : DailyReportColors.yellow600, fontWeight: FontWeight.w600, fontSize: 12.5),
              ),
            ),
          Container(
            width: double.infinity,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [DailyReportColors.purple600, DailyReportColors.purple600.withValues(alpha: 0.75)]),
              boxShadow: [
                BoxShadow(color: DailyReportColors.purple600.withValues(alpha: 0.32), blurRadius: 12, offset: const Offset(0, 5)),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _saving ? null : _save,
                child: Center(
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Ajouter au cumul', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roomCard(String room) {
    return DailyReportCard(
      children: [
        Row(
          children: [
            const Icon(Icons.meeting_room_outlined, size: 18, color: DailyReportColors.purple600),
            const SizedBox(width: 8),
            Text(room, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Cumul actuel : ${_kEggFields.map((f) => '${_kEggFieldLabels[f]} ${_currentFor(room, f)}').join(' · ')}',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final f in _kEggFields)
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _controllers[room]![f],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: '+ ${_kEggFieldLabels[f]}', isDense: true, border: const OutlineInputBorder()),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
