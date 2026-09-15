import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/delivery.dart';
import '../models/usine.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

enum _ReceptionFilter { all, pendingUsine, pendingFarm, received, cancelled }

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
  _ReceptionFilter _filter = _ReceptionFilter.pendingFarm;

  @override
  void initState() {
    super.initState();
    _init();
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
    final result = await _mongoService.getDeliveries(usineId: usine.id!, limit: 300);
    if (!mounted) return;
    setState(() {
      _deliveries = result.data;
      _loading = false;
    });
  }

  List<Delivery> get _filtered {
    switch (_filter) {
      case _ReceptionFilter.pendingUsine:
        return _deliveries.where((d) => d.status == 'en_attente').toList();
      case _ReceptionFilter.pendingFarm:
        return _deliveries.where((d) => d.isAwaitingFarmAck).toList();
      case _ReceptionFilter.received:
        return _deliveries.where((d) => d.farmReceivedAt != null).toList();
      case _ReceptionFilter.cancelled:
        return _deliveries.where((d) => d.isCancelled).toList();
      case _ReceptionFilter.all:
        return _deliveries;
    }
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
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Réceptions — toutes fermes'),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                                children: const [
                                  Padding(
                                    padding: EdgeInsets.symmetric(vertical: 60),
                                    child: Center(child: Text('Rien ici.')),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _filtered.length,
                                itemBuilder: (context, i) => _row(_filtered[i]),
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
      label: Text(label, style: const TextStyle(fontSize: 11.5)),
      selected: selected,
      selectedColor: DailyReportColors.green600,
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.black87),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _row(Delivery d) {
    final awaitingFarm = d.isAwaitingFarmAck;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: awaitingFarm ? DailyReportColors.yellow500 : Colors.grey.shade200),
      ),
      child: ListTile(
        title: Text('${d.farmName} — ${d.formulaName}', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${d.quantity} kg expédiés'
          '${d.farmReceivedQuantity != null ? " · ${d.farmReceivedQuantity} kg reçus" : ""}'
          '\n${DateFormat('dd/MM/yyyy').format(d.createdAt)}'
          '${d.isCancelled ? " · ANNULÉE" : ""}',
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
    );
  }
}
