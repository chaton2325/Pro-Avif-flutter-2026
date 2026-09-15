import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/delivery.dart';
import '../models/usine.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

enum _ReceptionFilter { all, pendingUsine, pendingFarm, received, cancelled }
enum _ReceptionSort { alpha, dateDesc }

const _pageSize = 30;

/// Vue admin des réceptions d'aliments, toutes fermes confondues (contrairement à
/// FeedReceptionScreen qui est scopée à UNE ferme, pour un rédacteur) — reprend
/// GET /deliveries?usineId= (routers/deliveries.py), qui contient déjà tout l'historique
/// usine + ferme sur un seul document par livraison.
class AdminFeedReceptionsScreen extends StatefulWidget {
  const AdminFeedReceptionsScreen({super.key});

  @override
  State<AdminFeedReceptionsScreen> createState() => _AdminFeedReceptionsScreenState();
}

class _AdminFeedReceptionsScreenState extends State<AdminFeedReceptionsScreen> {
  final MongoService _mongoService = MongoService();
  List<Usine> _usines = [];
  Usine? _selectedUsine;
  List<Delivery> _deliveries = [];
  bool _loading = true;
  bool _loadingMore = false;
  int _totalCount = 0;
  _ReceptionFilter _filter = _ReceptionFilter.pendingFarm;
  _ReceptionSort _sortMode = _ReceptionSort.alpha;
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final usines = await _mongoService.getUsines();
    if (!mounted) return;
    setState(() => _usines = usines);
    if (usines.isNotEmpty) {
      await _selectUsine(usines.first);
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _selectUsine(Usine usine) async {
    setState(() {
      _selectedUsine = usine;
      _loading = true;
    });
    final result = await _mongoService.getDeliveries(usineId: usine.id!, skip: 0, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _deliveries = result.data;
      _totalCount = result.totalCount;
      _loading = false;
    });
  }

  bool get _hasMore => _deliveries.length < _totalCount;

  Future<void> _loadMore() async {
    if (_selectedUsine == null || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final result = await _mongoService.getDeliveries(
      usineId: _selectedUsine!.id!,
      skip: _deliveries.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _deliveries = [..._deliveries, ...result.data];
      _totalCount = result.totalCount;
      _loadingMore = false;
    });
  }

  List<Delivery> get _filtered {
    Iterable<Delivery> result = switch (_filter) {
      _ReceptionFilter.pendingUsine => _deliveries.where((d) => d.status == 'en_attente'),
      _ReceptionFilter.pendingFarm => _deliveries.where((d) => d.isAwaitingFarmAck),
      _ReceptionFilter.received => _deliveries.where((d) => d.farmReceivedAt != null),
      _ReceptionFilter.cancelled => _deliveries.where((d) => d.isCancelled),
      _ReceptionFilter.all => _deliveries,
    };
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      result = result.where((d) => d.farmName.toLowerCase().contains(q) || d.formulaName.toLowerCase().contains(q));
    }
    final list = result.toList();
    list.sort((a, b) => _sortMode == _ReceptionSort.alpha
        ? a.farmName.toLowerCase().compareTo(b.farmName.toLowerCase())
        : b.createdAt.compareTo(a.createdAt));
    return list;
  }

  void _openAckDialog(Delivery delivery) {
    final quantityController = TextEditingController(text: delivery.quantity.toString());
    final noteController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${delivery.farmName} — ${delivery.formulaName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Quantité expédiée : ${delivery.quantity} kg', style: TextStyle(color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(
                controller: quantityController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantité réellement reçue (kg)'),
              ),
              TextField(controller: noteController, decoration: const InputDecoration(labelText: 'Remarque')),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
              onPressed: () async {
                final qty = double.tryParse(quantityController.text.replaceAll(',', '.'));
                final result = await _mongoService.acknowledgeDeliveryReceipt(
                  delivery.id,
                  receivedQuantity: qty,
                  note: noteController.text.trim().isEmpty ? null : noteController.text.trim(),
                );
                if (result.error != null) {
                  setDialogState(() => error = result.error);
                  return;
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                if (_selectedUsine != null) _selectUsine(_selectedUsine!);
              },
              child: const Text('Confirmer au nom de la ferme'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Réceptions — toutes fermes'),
      body: Column(
        children: [
          if (_usines.length > 1)
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<Usine>(
                value: _selectedUsine,
                decoration: const InputDecoration(labelText: 'Usine', border: OutlineInputBorder()),
                items: _usines.map((u) => DropdownMenuItem(value: u, child: Text(u.name))).toList(),
                onChanged: (u) => u != null ? _selectUsine(u) : null,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: DailySearchSortBar<_ReceptionSort>(
              controller: _searchController,
              hintText: 'Rechercher une ferme, un aliment…',
              onSearchChanged: (v) => setState(() => _searchQuery = v),
              sortValue: _sortMode,
              onSortChanged: (v) => setState(() => _sortMode = v),
              sortOptions: const [
                DailySortOption(_ReceptionSort.alpha, 'Ferme (A→Z)'),
                DailySortOption(_ReceptionSort.dateDesc, 'Plus récent'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 6,
              children: [
                _filterChip('En attente ferme', _ReceptionFilter.pendingFarm),
                _filterChip('En attente usine', _ReceptionFilter.pendingUsine),
                _filterChip('Reçues', _ReceptionFilter.received),
                _filterChip('Annulées', _ReceptionFilter.cancelled),
                _filterChip('Tout', _ReceptionFilter.all),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
                : _usines.isEmpty
                    ? const Center(child: Text('Aucune usine configurée.'))
                    : RefreshIndicator(
                        onRefresh: () => _selectUsine(_selectedUsine!),
                        child: _filtered.isEmpty
                            ? ListView(
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 60),
                                    child: Center(child: Text('Rien ici.')),
                                  ),
                                  if (_hasMore)
                                    Center(
                                      child: _loadingMore
                                          ? const CircularProgressIndicator(color: DailyReportColors.green700)
                                          : OutlinedButton(
                                              onPressed: _loadMore,
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: DailyReportColors.green700,
                                                side: const BorderSide(color: DailyReportColors.green600),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              ),
                                              child: Text('Charger plus (${_totalCount - _deliveries.length} restantes)'),
                                            ),
                                    ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _filtered.length + (_hasMore ? 1 : 0),
                                itemBuilder: (context, i) {
                                  if (i == _filtered.length) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Center(
                                        child: _loadingMore
                                            ? const CircularProgressIndicator(color: DailyReportColors.green700)
                                            : OutlinedButton(
                                                onPressed: _loadMore,
                                                style: OutlinedButton.styleFrom(
                                                  foregroundColor: DailyReportColors.green700,
                                                  side: const BorderSide(color: DailyReportColors.green600),
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                                ),
                                                child: Text('Charger plus (${_totalCount - _deliveries.length} restantes)'),
                                              ),
                                      ),
                                    );
                                  }
                                  return _row(_filtered[i]);
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _ReceptionFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      selected: selected,
      backgroundColor: Colors.white,
      selectedColor: DailyReportColors.green700,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999), side: BorderSide(color: selected ? DailyReportColors.green700 : Colors.grey.shade300)),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey.shade700),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _row(Delivery d) {
    final awaitingFarm = d.isAwaitingFarmAck;
    final accent = d.isCancelled
        ? Colors.grey.shade400
        : awaitingFarm
            ? DailyReportColors.yellow500
            : DailyReportColors.green600;
    return DailyReportCard(
      accentColor: accent,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.15), shape: BoxShape.circle),
            child: Icon(
              d.isCancelled ? Icons.cancel_outlined : (awaitingFarm ? Icons.local_shipping_outlined : Icons.check_circle_outline),
              color: accent,
              size: 19,
            ),
          ),
          title: Text('${d.farmName} — ${d.formulaName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
          subtitle: Text(
            '${d.quantity} kg expédiés'
            '${d.farmReceivedQuantity != null ? " · ${d.farmReceivedQuantity} kg reçus" : ""}'
            '\n${DateFormat('dd/MM/yyyy').format(d.createdAt)}'
            '${d.isCancelled ? " · ANNULÉE" : ""}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
          ),
          isThreeLine: true,
          trailing: awaitingFarm
              ? ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.yellow500, foregroundColor: Colors.black87),
                  onPressed: () => _openAckDialog(d),
                  child: const Text('Confirmer'),
                )
              : d.farmReceivedAt != null
                  ? const Icon(Icons.check_circle, color: DailyReportColors.green600)
                  : null,
        ),
      ],
    );
  }
}
