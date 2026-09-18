import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/delivery.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

/// Réception d'aliments côté ferme : les fermes reçoivent l'aliment produit par l'usine
/// (module Usine Aliment, voir routers/deliveries.py). Toutes les livraisons en attente
/// (parfois plusieurs aliments différents à la fois) se confirment en un seul geste : une
/// quantité modifiable par aliment, puis un message récapitulatif avant que ça n'entre dans
/// le stock du bâtiment (farm_feed_stocks, débité ensuite par la consommation quotidienne).
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
  final Map<String, TextEditingController> _quantityControllers = {};
  bool _isLoading = true;
  bool _confirming = false;
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
    for (final d in pending) {
      _quantityControllers.putIfAbsent(d.id, () => TextEditingController(text: d.quantity.toString()));
    }
    setState(() {
      _pending = pending;
      _history = history;
      _isLoading = false;
    });
  }

  @override
  void dispose() {
    for (final c in _quantityControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Confirme toutes les livraisons en attente d'un coup — une quantité (modifiable) par
  /// aliment — puis affiche un message récapitulatif avant que ça n'entre dans le stock.
  Future<void> _confirmAll() async {
    setState(() => _confirming = true);
    final confirmed = <(String formulaName, double quantity)>[];
    final errors = <String>[];
    for (final d in _pending) {
      final qty = double.tryParse((_quantityControllers[d.id]?.text ?? '').replaceAll(',', '.'));
      final result = await _mongoService.acknowledgeDeliveryReceipt(d.id, receivedQuantity: qty);
      if (result.error != null) {
        errors.add('${d.formulaName} : ${result.error}');
      } else {
        confirmed.add((d.formulaName, qty ?? d.quantity));
      }
    }
    if (!mounted) return;
    setState(() => _confirming = false);
    await _load();
    if (!mounted) return;
    await _showConfirmationSummary(confirmed, errors);
  }

  Future<void> _showConfirmationSummary(List<(String, double)> confirmed, List<String> errors) async {
    final total = confirmed.fold<double>(0, (a, c) => a + c.$2);
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              errors.isEmpty ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
              color: errors.isEmpty ? DailyReportColors.green700 : Colors.orange,
            ),
            const SizedBox(width: 10),
            const Expanded(child: Text('Réception confirmée', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (confirmed.isNotEmpty) ...[
              for (final c in confirmed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(c.$1, style: const TextStyle(fontSize: 13.5))),
                      Text('${c.$2} kg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                    ],
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  const Expanded(child: Text('Total ajouté au stock', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5))),
                  Text('$total kg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: DailyReportColors.green700)),
                ],
              ),
            ],
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('Échecs :', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade700, fontSize: 12.5)),
              for (final e in errors)
                Text(e, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
            ],
          ],
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
                    else ...[
                      for (final d in _pending) _pendingCard(d),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DailyReportColors.green700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: _confirming ? null : _confirmAll,
                          child: _confirming
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(
                                  _pending.length > 1
                                      ? 'Confirmer les ${_pending.length} réceptions'
                                      : 'Confirmer la réception',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                        ),
                      ),
                    ]
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
                  Text(d.formulaName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(
                    'Expédié : ${d.quantity} kg · ${DateFormat('dd/MM/yyyy').format(d.createdAt)}'
                    '${d.driverName != null ? " · ${d.driverName}" : ""}'
                    '${d.vehicle != null ? " (${d.vehicle})" : ""}',
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _quantityControllers[d.id],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Quantité réellement reçue (kg)',
            isDense: true,
            border: OutlineInputBorder(),
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
