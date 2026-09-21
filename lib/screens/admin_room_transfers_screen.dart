import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/farm_daily_report.dart';
import '../models/lot_headcount.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/blocking_loader.dart';
import '../widgets/daily_report_widgets.dart';
import 'today_room_transfers_screen.dart';

/// Déplacement de sujets d'une salle à une autre du même bâtiment — réservé à l'admin
/// (jamais le rédacteur), agit sur le rapport journalier du jour de la ferme choisie.
///
/// Liste des fermes — tapoter une ferme ouvre l'écran de saisie dédié
/// (AdminRoomTransferEditScreen).
class AdminRoomTransfersScreen extends StatefulWidget {
  const AdminRoomTransfersScreen({super.key});

  @override
  State<AdminRoomTransfersScreen> createState() => _AdminRoomTransfersScreenState();
}

class _AdminRoomTransfersScreenState extends State<AdminRoomTransfersScreen> {
  final MongoService _mongoService = MongoService();
  List<Farm> _farms = [];
  bool _loading = true;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<Farm> get _visible {
    var list = _farms;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((f) => f.name.toLowerCase().contains(q)).toList();
    }
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
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Transferts de sujets'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: DailyReportColors.green100, borderRadius: BorderRadius.circular(10)),
                    child: const Text(
                      "Déplacer des sujets d'une salle à une autre du même bâtiment, pour le rapport du jour.",
                      style: TextStyle(color: DailyReportColors.green900, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  DailySearchSortBar<int>(
                    controller: _searchController,
                    hintText: 'Rechercher un bâtiment…',
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    sortValue: 0,
                    onSortChanged: (_) {},
                    sortOptions: const [DailySortOption(0, 'Alphabétique (A→Z)')],
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else
                    for (final f in _visible) _farmCard(f),
                ],
              ),
            ),
    );
  }

  Widget _farmCard(Farm f) {
    return DailyReportCard(
      accentColor: DailyReportColors.green600,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AdminRoomTransferEditScreen(farm: f)),
          ),
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

/// Écran de saisie des transferts pour une ferme, sur le rapport journalier du jour — un
/// champ (F/M) par salle de départ/arrivée, avec la même règle anti-erreur que le serveur
/// (mortalité + sorties ne peut pas dépasser l'effectif de début d'une salle).
class AdminRoomTransferEditScreen extends StatefulWidget {
  final Farm farm;

  const AdminRoomTransferEditScreen({super.key, required this.farm});

  @override
  State<AdminRoomTransferEditScreen> createState() => _AdminRoomTransferEditScreenState();
}

class _AdminRoomTransferEditScreenState extends State<AdminRoomTransferEditScreen> {
  final MongoService _mongoService = MongoService();
  FarmDailyReport? _report;
  // Transferts déjà persistés côté serveur — consultables/annulables uniquement depuis
  // TodayRoomTransfersScreen (page séparée), jamais modifiables ici.
  List<RoomTransferEntry> _existingTransfers = [];
  // Brouillon des nouveaux mouvements en cours de saisie sur CET écran — pas encore envoyé
  // au serveur tant que "Enregistrer" n'a pas été appuyé.
  late List<RoomTransferEntry> _transfers;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  String get _todayStr => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final report = await _mongoService.getOrCreateTodayReport(farmId: widget.farm.id!, date: _todayStr);
    if (!mounted) return;
    setState(() {
      _report = report;
      _existingTransfers = report != null ? List.of(report.transfers) : [];
      _transfers = [];
      _loading = false;
    });
  }

  Future<void> _openExistingTransfers() async {
    final report = _report;
    if (report == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TodayRoomTransfersScreen(
          reportId: report.id,
          farmName: widget.farm.name,
          transfers: _existingTransfers,
        ),
      ),
    );
    if (!mounted) return;
    _load();
  }

  String? _validateTransfers() {
    final report = _report;
    if (report == null) return null;
    final all = [..._existingTransfers, ..._transfers];
    for (final t in _transfers) {
      if (t.fromRoom == t.toRoom) {
        return 'Un transfert ne peut pas partir et arriver dans la même salle (${t.fromRoom}).';
      }
    }
    for (final start in report.startCounts) {
      final mort = report.mortality.byRoom.firstWhere(
        (m) => m.roomName == start.roomName,
        orElse: () => RoomHeadcount(roomName: start.roomName),
      );
      final outFemale = all.where((t) => t.fromRoom == start.roomName).fold<int>(0, (a, t) => a + t.femaleCount);
      final outMale = all.where((t) => t.fromRoom == start.roomName).fold<int>(0, (a, t) => a + t.maleCount);
      if (mort.femaleCount + outFemale > start.femaleCount) {
        return 'Mortalité + transferts sortants femelles > effectif début dans ${start.roomName}.';
      }
      if (mort.maleCount + outMale > start.maleCount) {
        return 'Mortalité + transferts sortants mâles > effectif début dans ${start.roomName}.';
      }
    }
    return null;
  }

  Future<void> _save() async {
    final validationError = _validateTransfers();
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final combined = [..._existingTransfers, ..._transfers];
    final result = await runBlocking(
      context,
      () => _mongoService.patchDailyReport(_report!.id, transfers: combined),
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _saving = false;
        _error = result.error;
      });
      return;
    }
    setState(() {
      _saving = false;
      _report = result.report;
      _existingTransfers = result.report != null ? List.of(result.report!.transfers) : combined;
      _transfers = [];
    });
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: DailyReportColors.green700),
            const SizedBox(width: 10),
            const Expanded(child: Text('Transferts enregistrés', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ],
        ),
        content: Text(
          'Les effectifs de ${widget.farm.name} ont été mis à jour pour le rapport du $_todayStr.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        widget.farm.name,
        subtitle: 'Transferts — rapport du jour',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rafraîchir',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : report == null
              ? Center(child: Text('Impossible de charger le rapport du jour.', style: TextStyle(color: Colors.grey.shade500)))
              : !report.isEditable
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          "Le rapport du jour de cette ferme est déjà ${report.statusLabel.toLowerCase()} — "
                          "impossible d'ajouter un transfert tant qu'il n'est pas repassé modifiable.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        const DailyReportSectionLabel('Effectif actuel par salle', icon: Icons.meeting_room_rounded),
                        for (final r in report.endCounts.isNotEmpty ? report.endCounts : report.startCounts)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Expanded(child: Text(r.roomName, style: const TextStyle(fontSize: 13))),
                                Text('${r.femaleCount} F · ${r.maleCount} M', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              ],
                            ),
                          ),
                        const SizedBox(height: 18),
                        if (_existingTransfers.isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: _openExistingTransfers,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: DailyReportColors.green700,
                                side: const BorderSide(color: DailyReportColors.green600),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              icon: const Icon(Icons.history_rounded, size: 18),
                              label: Text('Voir les transferts déjà enregistrés (${_existingTransfers.length})'),
                            ),
                          ),
                        const SizedBox(height: 18),
                        const DailyReportSectionLabel('Nouveau transfert', icon: Icons.swap_horiz_rounded),
                        if (_transfers.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text('Aucun sujet déplacé pour le moment.', style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5)),
                          ),
                        for (var i = 0; i < _transfers.length; i++) _transferRow(i, report),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: report.startCounts.length < 2
                                ? null
                                : () => setState(() {
                                    final rooms = report.startCounts.map((r) => r.roomName).toList();
                                    _transfers.add(RoomTransferEntry(fromRoom: rooms[0], toRoom: rooms[1]));
                                  }),
                            icon: const Icon(Icons.add_circle_outline, size: 18),
                            label: const Text('Ajouter un transfert'),
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
                          ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: DailyReportColors.green700,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: _saving ? null : _save,
                            child: const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _transferRow(int i, FarmDailyReport report) {
    final t = _transfers[i];
    final rooms = report.startCounts.map((r) => r.roomName).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: rooms.contains(t.fromRoom) ? t.fromRoom : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'De', isDense: true, border: OutlineInputBorder()),
                  items: rooms.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _transfers[i] = RoomTransferEntry(
                        fromRoom: v!,
                        toRoom: t.toRoom,
                        femaleCount: t.femaleCount,
                        maleCount: t.maleCount,
                      )),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: rooms.contains(t.toRoom) ? t.toRoom : null,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Vers', isDense: true, border: OutlineInputBorder()),
                  items: rooms.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (v) => setState(() => _transfers[i] = RoomTransferEntry(
                        fromRoom: t.fromRoom,
                        toRoom: v!,
                        femaleCount: t.femaleCount,
                        maleCount: t.maleCount,
                      )),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
                onPressed: () => setState(() => _transfers.removeAt(i)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _intField(
                  'Femelles',
                  t.femaleCount,
                  (v) => setState(() => _transfers[i] = RoomTransferEntry(
                        fromRoom: t.fromRoom,
                        toRoom: t.toRoom,
                        femaleCount: v,
                        maleCount: t.maleCount,
                      )),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _intField(
                  'Mâles',
                  t.maleCount,
                  (v) => setState(() => _transfers[i] = RoomTransferEntry(
                        fromRoom: t.fromRoom,
                        toRoom: t.toRoom,
                        femaleCount: t.femaleCount,
                        maleCount: v,
                      )),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
      onChanged: (v) => onChanged(int.tryParse(v) ?? 0),
    );
  }
}
