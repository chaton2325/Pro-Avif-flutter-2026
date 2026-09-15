import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/delivery.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

/// Réception d'aliments côté ferme : les fermes reçoivent l'aliment produit par l'usine
/// (module Usine Aliment, voir routers/deliveries.py) — cet écran laisse le rédacteur
/// confirmer ce qui est physiquement arrivé, une livraison à la fois.
class FeedReceptionScreen extends StatefulWidget {
  final String farmName;

  const FeedReceptionScreen({super.key, required this.farmName});

  @override
  State<FeedReceptionScreen> createState() => _FeedReceptionScreenState();
}

class _FeedReceptionScreenState extends State<FeedReceptionScreen> {
  final MongoService _mongoService = MongoService();
  List<Delivery> _pending = [];
  List<Delivery> _history = [];
  bool _isLoading = true;
  bool _showHistory = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final pending = await _mongoService.getFarmPendingDeliveries(widget.farmName);
    final history = await _mongoService.getFarmAckHistory(widget.farmName);
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _history = history;
      _isLoading = false;
    });
  }

  void _openAckDialog(Delivery delivery) {
    final quantityController = TextEditingController(text: delivery.quantity.toString());
    final noteController = TextEditingController();
    String? error;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Réception — ${delivery.formulaName}'),
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
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Remarque (facultatif)'),
              ),
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
                _load();
              },
              child: const Text('Confirmer la réception'),
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
        title: const Text("Réception d'aliments"),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _toggleButton('En attente (${_pending.length})', !_showHistory,
                            () => setState(() => _showHistory = false)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _toggleButton('Historique', _showHistory, () => setState(() => _showHistory = true)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (!_showHistory)
                    if (_pending.isEmpty)
                      _emptyState("Aucune livraison en attente de réception.")
                    else
                      for (final d in _pending) _pendingCard(d)
                  else if (_history.isEmpty)
                    _emptyState('Aucune réception confirmée pour le moment.')
                  else
                    for (final d in _history) _historyCard(d),
                ],
              ),
            ),
    );
  }

  Widget _toggleButton(String label, bool active, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        backgroundColor: active ? DailyReportColors.green700 : Colors.white,
        foregroundColor: active ? Colors.white : DailyReportColors.green700,
        side: const BorderSide(color: DailyReportColors.green700),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }

  Widget _emptyState(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text(message, style: TextStyle(color: Colors.grey.shade500))),
      );

  Widget _pendingCard(Delivery d) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: DailyReportColors.yellow500),
      ),
      child: ListTile(
        title: Text('${d.formulaName} · ${d.quantity} kg', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${DateFormat('dd/MM/yyyy').format(d.createdAt)}'
          '${d.driverName != null ? " · ${d.driverName}" : ""}'
          '${d.vehicle != null ? " (${d.vehicle})" : ""}',
        ),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.yellow500, foregroundColor: Colors.black87),
          onPressed: () => _openAckDialog(d),
          child: const Text('Confirmer'),
        ),
      ),
    );
  }

  Widget _historyCard(Delivery d) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
      child: ListTile(
        leading: const Icon(Icons.check_circle, color: DailyReportColors.green600),
        title: Text('${d.formulaName} · ${d.farmReceivedQuantity ?? d.quantity} kg', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          d.farmReceivedAt != null ? DateFormat('dd/MM/yyyy à HH:mm').format(d.farmReceivedAt!) : '',
        ),
      ),
    );
  }
}
