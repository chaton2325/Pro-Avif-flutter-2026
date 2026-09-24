import 'package:flutter/material.dart';
import '../models/current_egg_stock.dart';
import '../models/egg_shipment.dart';
import '../models/hatchery.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'egg_shipment_history_screen.dart';

/// Expédition d'œufs vers un couvoir, pour une ferme donnée — accessible au rédacteur (sa propre
/// ferme) comme à l'admin (n'importe quelle ferme, choisie en amont). Une même expédition peut
/// mélanger plusieurs catégories (OAC/PO/DJ/CAS/SAL, ex. 50 OAC + 30 PO en une livraison).
/// Créée "en attente de validation" : ne diminue le STOCK actuel des catégories choisies (voir
/// CurrentEggStock.stockFor) qu'une fois VALIDÉE par l'admin (voir EggShipmentHistoryScreen) —
/// jamais le cumul de production, qui ne fait qu'accumuler.
class EggShipmentScreen extends StatefulWidget {
  final String farmName;
  final bool isAdmin;

  const EggShipmentScreen({super.key, required this.farmName, this.isAdmin = false});

  @override
  State<EggShipmentScreen> createState() => _EggShipmentScreenState();
}

class _EggShipmentScreenState extends State<EggShipmentScreen> {
  final MongoService _mongoService = MongoService();
  CurrentEggStock? _stock;
  List<Hatchery> _hatcheries = [];
  bool _loading = true;
  Hatchery? _selectedHatchery;
  final Map<String, TextEditingController> _controllers = {
    for (final t in eggTypes) t: TextEditingController(),
  };
  bool _saving = false;
  String? _message;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final stock = await _mongoService.getCurrentEggStock(widget.farmName);
    final hatcheries = await _mongoService.getHatcheries(activeOnly: true);
    if (!mounted) return;
    setState(() {
      _stock = stock;
      _hatcheries = hatcheries;
      _selectedHatchery = hatcheries.isNotEmpty ? hatcheries.first : null;
      _loading = false;
    });
  }

  Map<String, int> get _enteredCounts => {
    for (final t in eggTypes) t: int.tryParse(_controllers[t]!.text) ?? 0,
  }..removeWhere((_, count) => count <= 0);

  Future<void> _submit() async {
    if (_selectedHatchery == null) {
      setState(() {
        _message = 'Choisissez un couvoir.';
        _success = false;
      });
      return;
    }
    final counts = _enteredCounts;
    if (counts.isEmpty) {
      setState(() {
        _message = 'Saisissez une quantité pour au moins une catégorie.';
        _success = false;
      });
      return;
    }
    final shortfalls = [
      for (final entry in counts.entries)
        if (entry.value > (_stock?.stockFor(entry.key) ?? 0)) entry.key,
    ];
    if (shortfalls.isNotEmpty) {
      final detail = shortfalls
          .map((t) => '${eggTypeLabels[t]} (${_stock?.stockFor(t) ?? 0} disponible(s))')
          .join(', ');
      setState(() {
        _message = 'Stock insuffisant : $detail.';
        _success = false;
      });
      return;
    }
    final summary = counts.entries.map((e) => '${e.value} ${eggTypeLabels[e.key]}').join(' + ');

    // Dialog de confirmation avant envoi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmer l\'expédition ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Expédier $summary vers ${_selectedHatchery!.name} (${widget.farmName})',
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DailyReportColors.yellow100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: DailyReportColors.yellow600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cette expédition sera "en attente de validation". '
                      'Le stock ne diminuera qu\'après validation par l\'admin.',
                      style: TextStyle(fontSize: 12, color: DailyReportColors.yellow600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer l\'expédition'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _message = null;
    });
    final result = await _mongoService.createEggShipment(
      farmName: widget.farmName,
      hatcheryId: _selectedHatchery!.id!,
      hatcheryName: _selectedHatchery!.name,
      counts: counts,
    );
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _saving = false;
        _success = false;
        _message = result.error;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _saving = false;
      _success = true;
      _message = 'Expédition envoyée : $summary vers ${_selectedHatchery!.name}, en attente de validation par l\'admin.';
      for (final c in _controllers.values) {
        c.clear();
      }
    });
    await _load();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farmName, subtitle: 'Expédition d\'œufs'),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const DailyReportSectionLabel('Stock disponible', icon: Icons.egg_rounded),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final t in eggTypes)
                      _chip('${eggTypeLabels[t]} en stock', '${_stock?.stockFor(t) ?? 0}'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Le cumul de production n'est jamais diminué par une expédition. Une expédition "
                  "envoyée reste \"en attente\" et ne fait baisser le stock qu'une fois validée par l'admin.",
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EggShipmentHistoryScreen(farmName: widget.farmName, isAdmin: widget.isAdmin),
                    ),
                  ),
                  icon: const Icon(Icons.history_rounded, size: 18),
                  label: const Text("Voir l'historique des expéditions"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DailyReportColors.purple600,
                    side: const BorderSide(color: DailyReportColors.purple600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    minimumSize: const Size(double.infinity, 42),
                  ),
                ),
                const SizedBox(height: 18),
                const DailyReportSectionLabel('Nouvelle expédition', icon: Icons.local_shipping_rounded),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 10),
                  child: Text(
                    "Une même expédition peut mélanger plusieurs catégories — remplissez la ou les quantités concernées.",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                  ),
                ),
                DailyReportCard(
                  children: [
                    if (_hatcheries.isEmpty)
                      Text(
                        "Aucun couvoir actif dans le référentiel — contactez l'admin pour en créer un.",
                        style: TextStyle(color: Colors.grey.shade500),
                      )
                    else
                      DropdownButtonFormField<Hatchery>(
                        initialValue: _selectedHatchery,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Couvoir', border: OutlineInputBorder()),
                        items: [for (final h in _hatcheries) DropdownMenuItem(value: h, child: Text(h.name))],
                        onChanged: (v) => setState(() => _selectedHatchery = v),
                      ),
                    const SizedBox(height: 12),
                    for (final t in eggTypes) ...[
                      TextField(
                        controller: _controllers[t],
                        keyboardType: TextInputType.number,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'Quantité ${eggTypeLabels[t]}',
                          helperText: '${_stock?.stockFor(t) ?? 0} disponible(s)',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
                if (_message != null)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
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
                      onTap: (_saving || _hatcheries.isEmpty) ? null : _submit,
                      child: Center(
                        child: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Expédier', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
