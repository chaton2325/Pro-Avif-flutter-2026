import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/lot_headcount.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'lot_headcount_history_screen.dart';

enum _HcSort { alpha, status }

class _FarmHeadcountStatus {
  final Farm farm;
  final String? lotNumber;
  final LotHeadcount? headcount;
  _FarmHeadcountStatus({required this.farm, this.lotNumber, this.headcount});
}

/// Effectifs de départ d'un lot (réservé à l'admin — "l'admin peut tout faire") : saisis
/// une seule fois à la mise en place du lot, le rapport journalier reprend ensuite tout seul
/// l'effectif restant de la veille (voir routers/headcounts.py côté backend).
///
/// Liste des fermes avec leur statut (effectifs définis ou non pour le lot en cours) —
/// tapoter une ferme ouvre l'écran de saisie dédié (AdminLotHeadcountEditScreen).
class AdminLotHeadcountsScreen extends StatefulWidget {
  const AdminLotHeadcountsScreen({super.key});

  @override
  State<AdminLotHeadcountsScreen> createState() => _AdminLotHeadcountsScreenState();
}

class _AdminLotHeadcountsScreenState extends State<AdminLotHeadcountsScreen> {
  final MongoService _mongoService = MongoService();
  List<_FarmHeadcountStatus> _statuses = [];
  bool _loading = true;
  _HcSort _sortMode = _HcSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  List<_FarmHeadcountStatus> get _visible {
    var list = _statuses;
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((s) => s.farm.name.toLowerCase().contains(q)).toList();
    } else {
      list = List.of(list);
    }
    list.sort((a, b) => _sortMode == _HcSort.alpha
        ? a.farm.name.toLowerCase().compareTo(b.farm.name.toLowerCase())
        : (a.headcount != null ? 1 : 0).compareTo(b.headcount != null ? 1 : 0));
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
    final statuses = await Future.wait(farms.map((farm) async {
      final lotNumber = await _mongoService.getCurrentLotForFarm(farm.name);
      LotHeadcount? headcount;
      if (lotNumber != null) {
        headcount = await _mongoService.getLotHeadcount(farm.name, lotNumber);
      }
      return _FarmHeadcountStatus(farm: farm, lotNumber: lotNumber, headcount: headcount);
    }));
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _loading = false;
    });
  }

  Future<void> _openFarm(_FarmHeadcountStatus s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminLotHeadcountEditScreen(farm: s.farm, initialLotNumber: s.lotNumber),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final defined = _statuses.where((s) => s.headcount != null).length;
    final toDefine = _statuses.length - defined;

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Effectifs de départ'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$defined',
                          label: 'Effectifs définis',
                          color: DailyReportColors.green700,
                          icon: Icons.check_circle_outline,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DailyReportStatTile(
                          value: '$toDefine',
                          label: 'À définir',
                          color: DailyReportColors.yellow600,
                          icon: Icons.hourglass_top_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const DailyReportSectionLabel('Par ferme'),
                  DailySearchSortBar<_HcSort>(
                    controller: _searchController,
                    hintText: 'Rechercher un bâtiment…',
                    onSearchChanged: (v) => setState(() => _searchQuery = v),
                    sortValue: _sortMode,
                    onSortChanged: (v) => setState(() => _sortMode = v),
                    sortOptions: const [
                      DailySortOption(_HcSort.alpha, 'Alphabétique (A→Z)'),
                      DailySortOption(_HcSort.status, 'À définir en premier'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text('Aucun bâtiment trouvé.', style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else
                    for (final s in _visible) _farmCard(s),
                ],
              ),
            ),
    );
  }

  Widget _farmCard(_FarmHeadcountStatus s) {
    final defined = s.headcount != null;
    final color = defined ? DailyReportColors.green600 : DailyReportColors.yellow500;
    return DailyReportCard(
      accentColor: color,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      children: [
        InkWell(
          onTap: () => _openFarm(s),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.farm.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(
                      s.lotNumber != null ? 'Lot ${s.lotNumber}' : 'Aucun lot en cours',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                    ),
                    if (defined) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${s.headcount!.totalFemale} F · ${s.headcount!.totalMale} M',
                        style: const TextStyle(color: DailyReportColors.green700, fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              DailyReportStatusBadge(
                label: defined ? 'DÉFINIS' : 'À DÉFINIR',
                color: color,
                icon: defined ? Icons.check_rounded : Icons.priority_high_rounded,
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ],
    );
  }
}

/// Écran de saisie des effectifs de départ pour une ferme + un lot précis, avec totaux
/// recalculés en direct pendant la saisie (au lieu de n'apparaître qu'après enregistrement).
class AdminLotHeadcountEditScreen extends StatefulWidget {
  final Farm farm;
  final String? initialLotNumber;

  const AdminLotHeadcountEditScreen({super.key, required this.farm, this.initialLotNumber});

  @override
  State<AdminLotHeadcountEditScreen> createState() => _AdminLotHeadcountEditScreenState();
}

const _newLotSentinel = '__new_lot__';

class _AdminLotHeadcountEditScreenState extends State<AdminLotHeadcountEditScreen> {
  final MongoService _mongoService = MongoService();
  List<String> _lotNumbers = [];
  String? _selectedLot;
  bool _loadingLots = true;
  final _clinicFemaleController = TextEditingController(text: '0');
  final _clinicMaleController = TextEditingController(text: '0');
  final Map<String, TextEditingController> _femaleControllers = {};
  final Map<String, TextEditingController> _maleControllers = {};
  bool _saving = false;
  String? _message;
  bool _success = false;
  LotHeadcount? _existingHeadcount;

  int get _totalFemale =>
      widget.farm.rooms.fold<int>(0, (a, r) => a + (int.tryParse(_femaleControllers[r]?.text ?? '0') ?? 0)) +
      (int.tryParse(_clinicFemaleController.text) ?? 0);
  int get _totalMale =>
      widget.farm.rooms.fold<int>(0, (a, r) => a + (int.tryParse(_maleControllers[r]?.text ?? '0') ?? 0)) +
      (int.tryParse(_clinicMaleController.text) ?? 0);

  @override
  void initState() {
    super.initState();
    _selectedLot = widget.initialLotNumber;
    for (final room in widget.farm.rooms) {
      _femaleControllers[room] = TextEditingController(text: '0')..addListener(_onChanged);
      _maleControllers[room] = TextEditingController(text: '0')..addListener(_onChanged);
    }
    _clinicFemaleController.addListener(_onChanged);
    _clinicMaleController.addListener(_onChanged);
    _loadLots();
  }

  Future<void> _loadLots() async {
    final lots = List.of(await _mongoService.getLots())
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final numbers = <String>{
      ...lots.map((l) => l.number),
      if (widget.initialLotNumber != null) widget.initialLotNumber!,
    }.toList();
    if (!mounted) return;
    setState(() {
      _lotNumbers = numbers;
      _loadingLots = false;
    });
    if (_selectedLot != null) _loadExisting();
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _clinicFemaleController.dispose();
    _clinicMaleController.dispose();
    for (final c in _femaleControllers.values) {
      c.dispose();
    }
    for (final c in _maleControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onLotSelected(String? lot) async {
    if (lot == _newLotSentinel) {
      await _createNewLot();
      return;
    }
    setState(() {
      _selectedLot = lot;
      for (final room in widget.farm.rooms) {
        _femaleControllers[room]!.text = '0';
        _maleControllers[room]!.text = '0';
      }
      _clinicFemaleController.text = '0';
      _clinicMaleController.text = '0';
      _message = null;
      _existingHeadcount = null;
    });
    await _loadExisting();
  }

  /// Une ferme sans pesée encore faite (nouveau lot mis en place) n'a pas de "lot en cours"
  /// détectable — et le lot n'existe pas forcément déjà dans le référentiel global des lots.
  /// Sans ceci, l'admin n'a aucun moyen de créer les effectifs de départ d'un tout nouveau
  /// lot : le menu ne proposerait que des numéros d'autres fermes.
  Future<void> _createNewLot() async {
    final controller = TextEditingController();
    final number = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Nouveau numéro de lot'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Numéro de lot (ex : LOT 24)', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (number == null || number.isEmpty) return;
    setState(() {
      if (!_lotNumbers.contains(number)) _lotNumbers = [number, ..._lotNumbers];
      _selectedLot = number;
      for (final room in widget.farm.rooms) {
        _femaleControllers[room]!.text = '0';
        _maleControllers[room]!.text = '0';
      }
      _clinicFemaleController.text = '0';
      _clinicMaleController.text = '0';
      _existingHeadcount = null;
      _message = "Nouveau lot — saisissez les effectifs de départ.";
    });
  }

  Future<void> _loadExisting() async {
    if (_selectedLot == null || _selectedLot!.trim().isEmpty) return;
    final existing = await _mongoService.getLotHeadcount(widget.farm.name, _selectedLot!.trim());
    if (!mounted) return;
    if (existing == null) {
      setState(() {
        _existingHeadcount = null;
        _message = "Aucun effectif déjà enregistré pour ce lot — c'est une première saisie.";
      });
      return;
    }
    setState(() {
      _existingHeadcount = existing;
      for (final r in existing.rooms) {
        _femaleControllers[r.roomName]?.text = r.femaleCount.toString();
        _maleControllers[r.roomName]?.text = r.maleCount.toString();
      }
      _clinicFemaleController.text = existing.clinicFemaleCount.toString();
      _clinicMaleController.text = existing.clinicMaleCount.toString();
      _message = 'Valeurs existantes chargées — modification possible.';
    });
  }

  /// Une resaisie écrase la valeur courante (l'historique la conserve côté backend, voir
  /// PUT /lot-headcounts) : on le fait savoir explicitement avant d'enregistrer plutôt que de
  /// remplacer silencieusement un effectif déjà en place.
  Future<bool> _confirmOverwriteIfNeeded() async {
    final existing = _existingHeadcount;
    if (existing == null) return true;
    final dateStr = existing.updatedAt != null
        ? DateFormat('dd/MM/yyyy à HH:mm').format(existing.updatedAt!)
        : null;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text('Remplacer l\'effectif existant ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ],
        ),
        content: Text(
          'Un effectif est déjà enregistré pour ${widget.farm.name} / ${_selectedLot!.trim()}'
          '${dateStr != null ? ' (saisi le $dateStr${existing.performedBy != null ? ' par ${existing.performedBy}' : ''})' : ''} '
          ': ${existing.totalFemale} F / ${existing.totalMale} M.\n\n'
          'Enregistrer va le remplacer par cette nouvelle saisie. L\'ancienne valeur restera consultable dans l\'historique.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ANNULER')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('REMPLACER'),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  Future<void> _save() async {
    if (_selectedLot == null || _selectedLot!.trim().isEmpty) {
      setState(() {
        _message = 'Choisissez un numéro de lot.';
        _success = false;
      });
      return;
    }
    if (!await _confirmOverwriteIfNeeded()) return;
    if (!mounted) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final headcount = LotHeadcount(
      farmName: widget.farm.name,
      lotNumber: _selectedLot!.trim(),
      rooms: widget.farm.rooms
          .map((r) => RoomHeadcount(
                roomName: r,
                femaleCount: int.tryParse(_femaleControllers[r]!.text) ?? 0,
                maleCount: int.tryParse(_maleControllers[r]!.text) ?? 0,
              ))
          .toList(),
      clinicFemaleCount: int.tryParse(_clinicFemaleController.text) ?? 0,
      clinicMaleCount: int.tryParse(_clinicMaleController.text) ?? 0,
    );
    final result = await _mongoService.upsertLotHeadcount(headcount);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = result.error == null;
      _message = result.error ?? 'Enregistré : ${result.headcount!.totalFemale} F / ${result.headcount!.totalMale} M';
      if (result.headcount != null) _existingHeadcount = result.headcount;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farm.name, subtitle: 'Effectifs de départ'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DailyReportCard(children: [
            _loadingLots
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: DailyReportColors.green700)),
                  )
                : DropdownButtonFormField<String>(
                    value: _selectedLot,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Numéro de lot', border: OutlineInputBorder()),
                    hint: const Text('Choisir un lot'),
                    items: [
                      ..._lotNumbers.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                      const DropdownMenuItem(
                        value: _newLotSentinel,
                        child: Row(
                          children: [
                            Icon(Icons.add_circle_outline, size: 17, color: DailyReportColors.green700),
                            SizedBox(width: 6),
                            Text('Nouveau numéro de lot…', style: TextStyle(color: DailyReportColors.green700, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ],
                    onChanged: _onLotSelected,
                  ),
          ]),
          if (_existingHeadcount != null) ...[
            const SizedBox(height: 12),
            _existingHeadcountCard(_existingHeadcount!),
            _historyButton(),
          ],
          const SizedBox(height: 4),
          const DailyReportSectionLabel('Nouvelle saisie', icon: Icons.edit_note_rounded),
          Row(
            children: [
              Expanded(
                child: DailyReportStatTile(
                  value: '$_totalFemale',
                  label: 'Total femelles',
                  color: DailyReportColors.green700,
                  icon: Icons.female_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DailyReportStatTile(
                  value: '$_totalMale',
                  label: 'Total mâles',
                  color: DailyReportColors.green600,
                  icon: Icons.male_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const DailyReportSectionLabel('Par salle', icon: Icons.meeting_room_rounded),
          for (final room in widget.farm.rooms) _roomCard(room),
          DailyReportCard(
            accentColor: DailyReportColors.yellow500,
            children: [
              Row(
                children: [
                  const Icon(Icons.local_hospital_rounded, size: 18, color: DailyReportColors.yellow600),
                  const SizedBox(width: 8),
                  const Text('Clinique', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _numberField('Femelles', _clinicFemaleController)),
                  const SizedBox(width: 10),
                  Expanded(child: _numberField('Mâles', _clinicMaleController)),
                ],
              ),
            ],
          ),
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
              gradient: const LinearGradient(colors: [DailyReportColors.green700, DailyReportColors.green600]),
              boxShadow: [
                BoxShadow(color: DailyReportColors.green700.withValues(alpha: 0.32), blurRadius: 12, offset: const Offset(0, 5)),
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
                      : const Text('Enregistrer', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Détail de l'effectif déjà en base pour ce lot — affiché avant toute saisie (jamais
  /// deviné à partir des champs pré-remplis) : ce que l'admin s'apprête à écraser doit être
  /// visible avant qu'il ne le fasse.
  Widget _existingHeadcountCard(LotHeadcount existing) {
    final dateStr = existing.updatedAt != null
        ? DateFormat('dd/MM/yyyy à HH:mm').format(existing.updatedAt!)
        : null;
    return DailyReportCard(
      accentColor: DailyReportColors.green700,
      margin: const EdgeInsets.only(bottom: 4),
      children: [
        Row(
          children: [
            const Icon(Icons.fact_check_rounded, size: 18, color: DailyReportColors.green700),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Effectif actuellement enregistré', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
            ),
          ],
        ),
        if (dateStr != null || existing.performedBy != null) ...[
          const SizedBox(height: 2),
          Text(
            'Saisi le ${dateStr ?? '—'}${existing.performedBy != null ? ' par ${existing.performedBy}' : ''}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
          ),
        ],
        const SizedBox(height: 10),
        for (final r in existing.rooms)
          if (r.femaleCount > 0 || r.maleCount > 0) _existingRow(r.roomName, r.femaleCount, r.maleCount),
        if (existing.clinicFemaleCount > 0 || existing.clinicMaleCount > 0)
          _existingRow('Clinique', existing.clinicFemaleCount, existing.clinicMaleCount),
        const Divider(height: 18),
        Row(
          children: [
            const Expanded(child: Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
            Text(
              '${existing.totalFemale} F · ${existing.totalMale} M',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DailyReportColors.green700),
            ),
          ],
        ),
      ],
    );
  }

  /// Un simple bouton vers la page dédiée (paginée) de l'historique — jamais chargé ici, ni
  /// même son total : cette fenêtre ne montre que l'effectif actuellement enregistré.
  Widget _historyButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LotHeadcountHistoryScreen(farmName: widget.farm.name, lotNumber: _selectedLot!.trim()),
          ),
        ),
        icon: const Icon(Icons.history_rounded, size: 18),
        label: const Text("Voir l'historique des effectifs de départ"),
        style: OutlinedButton.styleFrom(
          foregroundColor: DailyReportColors.green700,
          side: const BorderSide(color: DailyReportColors.green600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          minimumSize: const Size(double.infinity, 42),
        ),
      ),
    );
  }

  Widget _existingRow(String label, int female, int male) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('$female F · $male M', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _roomCard(String room) {
    return DailyReportCard(
      children: [
        Row(
          children: [
            const Icon(Icons.meeting_room_outlined, size: 18, color: DailyReportColors.green700),
            const SizedBox(width: 8),
            Text(room, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _numberField('Femelles', _femaleControllers[room]!)),
            const SizedBox(width: 10),
            Expanded(child: _numberField('Mâles', _maleControllers[room]!)),
          ],
        ),
      ],
    );
  }

  Widget _numberField(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, isDense: true, border: const OutlineInputBorder()),
    );
  }
}
