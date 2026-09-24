import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../models/farm_feed_stock.dart';
import '../models/formula.dart';
import '../models/lot_egg_stock.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'inventory_history_screen.dart';

const _kEggFields = ['oac', 'po', 'dj', 'cas', 'sal'];
const _kEggFieldLabels = {'oac': 'OAC', 'po': 'PO', 'dj': 'DJ', 'cas': 'CAS', 'sal': 'SAL'};

/// Inventaire : corrige le stock ACTUEL d'aliment ou d'œufs d'une ferme pour qu'il colle à un
/// comptage physique — deux onglets (Aliment / Œufs), même écran pour l'admin (isAdmin: true,
/// applique directement) et le rédacteur (isAdmin: false, soumet une DEMANDE que l'admin doit
/// valider avant qu'elle n'ait le moindre effet sur le stock).
class InventoryScreen extends StatefulWidget {
  final Farm farm;
  final bool isAdmin;

  const InventoryScreen({super.key, required this.farm, this.isAdmin = false});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  late final TabController _tabController;

  bool _loading = true;
  List<Formula> _formulas = [];
  final Map<String, TextEditingController> _feedControllers = {};
  final Map<String, Map<String, TextEditingController>> _eggControllers = {};
  final _noteController = TextEditingController();
  bool _saving = false;
  String? _message;
  bool _success = false;

  // Référence "stock actuel" figée au chargement (jamais modifiée par la saisie, contrairement
  // aux controllers) — affichée à côté de chaque champ pour que la personne qui compte
  // physiquement voie ce que le système croit savoir, avant d'entrer son propre comptage.
  final Map<String, double> _currentFeedByFormula = {};
  final Map<String, Map<String, int>> _currentEggByRoom = {};

  double get _totalFeedKg => _formulas.fold<double>(
        0,
        (a, f) => a + (double.tryParse((_feedControllers[f.id]?.text ?? '0').replaceAll(',', '.')) ?? 0),
      );

  double get _currentTotalFeedKg => _currentFeedByFormula.values.fold<double>(0, (a, v) => a + v);

  int _currentEggTotal(String field) =>
      _currentEggByRoom.values.fold<int>(0, (a, room) => a + (room[field] ?? 0));

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final c in _feedControllers.values) {
      c.dispose();
    }
    for (final room in _eggControllers.values) {
      for (final c in room.values) {
        c.dispose();
      }
    }
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final formulas = List.of(await _mongoService.getAllFormulas())
      ..retainWhere((f) => f.isActive)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final feedStock = await _mongoService.getFarmFeedStock(widget.farm.name);
    for (final f in formulas) {
      final key = f.id ?? f.name;
      final current = feedStock?.quantities.where((q) => q.formulaId == f.id).firstOrNull;
      final currentQty = current?.quantityKg ?? 0;
      _currentFeedByFormula[key] = currentQty;
      _feedControllers[key] = TextEditingController(text: _formatQty(currentQty));
    }

    // Référence "œufs" : le cumul ACTUEL (voir CurrentEggStockScreen), pas le stock de départ
    // du lot (lot_egg_stocks) qui est figé depuis la mise en place — sinon la personne qui
    // compte physiquement comparerait son comptage à une valeur périmée depuis des jours.
    final currentEggStock = await _mongoService.getCurrentEggStock(widget.farm.name);
    for (final room in widget.farm.rooms) {
      final current = currentEggStock.rooms.where((r) => r.roomName == room).firstOrNull;
      _currentEggByRoom[room] = {
        'oac': current?.cumulativeOac ?? 0,
        'po': current?.cumulativePo ?? 0,
        'dj': current?.cumulativeDj ?? 0,
        'cas': current?.cumulativeCas ?? 0,
        'sal': current?.cumulativeSal ?? 0,
      };
      _eggControllers[room] = {
        for (final f in _kEggFields) f: TextEditingController(text: '${_currentEggByRoom[room]![f]}'),
      };
    }

    if (!mounted) return;
    setState(() {
      _formulas = formulas;
      _loading = false;
    });
  }

  String _formatQty(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  List<FeedStartingQuantity> get _feedPayload => _formulas
      .map((f) => FeedStartingQuantity(
            formulaId: f.id ?? '',
            formulaName: f.name,
            quantityKg: double.tryParse((_feedControllers[f.id]?.text ?? '0').replaceAll(',', '.')) ?? 0,
          ))
      .toList();

  List<RoomEggStock> get _eggPayload => widget.farm.rooms
      .map((room) => RoomEggStock(
            roomName: room,
            oac: int.tryParse(_eggControllers[room]!['oac']!.text) ?? 0,
            po: int.tryParse(_eggControllers[room]!['po']!.text) ?? 0,
            dj: int.tryParse(_eggControllers[room]!['dj']!.text) ?? 0,
            cas: int.tryParse(_eggControllers[room]!['cas']!.text) ?? 0,
            sal: int.tryParse(_eggControllers[room]!['sal']!.text) ?? 0,
          ))
      .toList();

  Future<void> _submit(String type) async {
    final isFeed = type == 'aliment';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          widget.isAdmin ? 'Appliquer cet inventaire ?' : 'Envoyer cette demande ?',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        content: Text(
          widget.isAdmin
              ? 'Le stock ${isFeed ? "d'aliment" : "d'œufs"} de ${widget.farm.name} sera remplacé '
                  'immédiatement par ce comptage. L\'ancienne valeur restera consultable dans l\'historique.'
              : 'Cette demande sera "en attente de validation" : le stock ne changera qu\'une fois '
                  'l\'admin passé — pas tout de suite.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.isAdmin ? 'Appliquer' : 'Envoyer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await _mongoService.createInventoryRequest(
      farmName: widget.farm.name,
      type: type,
      feedQuantities: isFeed ? _feedPayload : const [],
      eggRooms: isFeed ? const [] : _eggPayload,
      note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
      autoValidate: widget.isAdmin,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = result.error == null;
      _message = result.error ??
          (widget.isAdmin ? 'Inventaire appliqué.' : 'Demande envoyée, en attente de validation par l\'admin.');
      if (result.error == null) _noteController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        widget.farm.name,
        subtitle: 'Inventaire',
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Aliment'),
            Tab(text: 'Œufs'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Historique',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InventoryHistoryScreen(farmName: widget.farm.name, isAdmin: widget.isAdmin),
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : TabBarView(
              controller: _tabController,
              children: [
                _feedTab(),
                _eggTab(),
              ],
            ),
    );
  }

  Widget _infoBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: DailyReportColors.purple600.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: DailyReportColors.purple600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.isAdmin
                  ? 'Saisissez ce que vous avez compté : le stock est remplacé immédiatement.'
                  : 'Saisissez ce que vous avez compté : la demande sera envoyée à l\'admin, le stock ne change qu\'après sa validation.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteAndSubmit(String type) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        TextField(
          controller: _noteController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Motif / commentaire (optionnel)',
            border: OutlineInputBorder(),
            hintText: 'Ex : comptage mensuel, écart constaté hier...',
          ),
        ),
        if (_message != null)
          Container(
            margin: const EdgeInsets.only(top: 12),
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
        const SizedBox(height: 18),
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
              onTap: _saving ? null : () => _submit(type),
              child: Center(
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        widget.isAdmin ? 'Appliquer l\'inventaire' : 'Envoyer la demande',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _feedTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoBanner(),
        Row(
          children: [
            Expanded(
              child: DailyReportStatTile(
                value: '${_currentTotalFeedKg.toStringAsFixed(_currentTotalFeedKg == _currentTotalFeedKg.roundToDouble() ? 0 : 2)} kg',
                label: 'Stock actuel (système)',
                color: DailyReportColors.yellow600,
                icon: Icons.fact_check_outlined,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DailyReportStatTile(
                value: '${_totalFeedKg.toStringAsFixed(_totalFeedKg == _totalFeedKg.roundToDouble() ? 0 : 2)} kg',
                label: 'Total compté',
                color: DailyReportColors.green700,
                icon: Icons.inventory_2_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const DailyReportSectionLabel('Par aliment', icon: Icons.grain_rounded),
        if (_formulas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Text("Aucun aliment actif dans le référentiel Usine Aliment.", style: TextStyle(color: Colors.grey.shade500)),
            ),
          )
        else
          for (final f in _formulas)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DailyReportCard(
                margin: EdgeInsets.zero,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.grain_rounded, size: 18, color: DailyReportColors.green700),
                      const SizedBox(width: 8),
                      Expanded(child: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
                      Text(
                        'Actuel : ${_formatQty(_currentFeedByFormula[f.id ?? f.name] ?? 0)} kg',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _feedControllers[f.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Quantité comptée (kg)', isDense: true, border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
        _noteAndSubmit('aliment'),
      ],
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label  ', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            TextSpan(text: value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: DailyReportColors.green900)),
          ],
        ),
      ),
    );
  }

  Widget _eggTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _infoBanner(),
        const DailyReportSectionLabel('Stock actuel (système), toutes salles', icon: Icons.fact_check_outlined),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final f in _kEggFields) _chip('${_kEggFieldLabels[f]} actuel', '${_currentEggTotal(f)}'),
          ],
        ),
        const SizedBox(height: 18),
        const DailyReportSectionLabel('Par salle', icon: Icons.meeting_room_rounded),
        if (widget.farm.rooms.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('Aucune salle définie pour cette ferme.', style: TextStyle(color: Colors.grey.shade500))),
          )
        else
          for (final room in widget.farm.rooms)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DailyReportCard(
                margin: EdgeInsets.zero,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.meeting_room_outlined, size: 18, color: DailyReportColors.green700),
                      const SizedBox(width: 8),
                      Text(room, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Actuel — ${[
                      for (final f in _kEggFields) '${_kEggFieldLabels[f]} ${_currentEggByRoom[room]?[f] ?? 0}',
                    ].join(' · ')}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w600),
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
                            controller: _eggControllers[room]![f],
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(labelText: _kEggFieldLabels[f]!, isDense: true, border: const OutlineInputBorder()),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        _noteAndSubmit('oeufs'),
      ],
    );
  }
}
