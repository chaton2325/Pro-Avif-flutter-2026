import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/delivery.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

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
      appBar: dailyReportAppBar("Réception d'aliments"),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Expanded(
                          child: _toggleButton('En attente (${_pending.length})', !_showHistory,
                              () => setState(() => _showHistory = false)),
                        ),
                        Expanded(
                          child: _toggleButton('Historique', _showHistory, () => setState(() => _showHistory = true)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          gradient: active ? const LinearGradient(colors: [DailyReportColors.green700, DailyReportColors.green600]) : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: active ? Colors.white : Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _emptyState(String message) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 10),
              Text(message, style: TextStyle(color: Colors.grey.shade500)),
            ],
          ),
        ),
      );

  Widget _pendingCard(Delivery d) {
    return DailyReportCard(
      accentColor: DailyReportColors.yellow500,
      margin: const EdgeInsets.only(bottom: 12),
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: DailyReportColors.yellow100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.local_shipping_outlined, color: DailyReportColors.yellow600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${d.formulaName} · ${d.quantity} kg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('dd/MM/yyyy').format(d.createdAt)}'
                    '${d.driverName != null ? " · ${d.driverName}" : ""}'
                    '${d.vehicle != null ? " (${d.vehicle})" : ""}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DailyReportColors.yellow500,
              foregroundColor: Colors.black87,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => _openAckDialog(d),
            child: const Text('Confirmer la réception', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _historyCard(Delivery d) {
    return DailyReportCard(
      accentColor: DailyReportColors.green600,
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: DailyReportColors.green100, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.check_circle_rounded, color: DailyReportColors.green700),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${d.formulaName} · ${d.farmReceivedQuantity ?? d.quantity} kg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    d.farmReceivedAt != null ? DateFormat('dd/MM/yyyy à HH:mm').format(d.farmReceivedAt!) : '',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
