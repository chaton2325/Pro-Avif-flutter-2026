import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/production_batch.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';

/// Validation comptable du coût de revient d'un lot d'aliment — écran dédié (pas une
/// modale) : la décision est irréversible (le stock est réellement prélevé, le coût figé
/// définitivement) et mérite plus de place qu'une popup, plus une confirmation explicite
/// avant d'agir et un accusé de succès après.
class ValidateProductionScreen extends StatefulWidget {
  final ProductionBatch batch;
  final VoidCallback onReject;

  const ValidateProductionScreen({super.key, required this.batch, required this.onReject});

  @override
  State<ValidateProductionScreen> createState() => _ValidateProductionScreenState();
}

class _ValidateProductionScreenState extends State<ValidateProductionScreen> {
  final MongoService _mongoService = MongoService();
  final _adjustmentController = TextEditingController(text: '0');
  final _reasonController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _adjustmentController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double get _adjustment => double.tryParse(_adjustmentController.text) ?? 0;
  double get _previewTotal => widget.batch.totalCost + _adjustment;
  double get _previewPerUnit =>
      widget.batch.actualQuantityProduced > 0 ? _previewTotal / widget.batch.actualQuantityProduced : 0;

  Future<void> _confirmAndValidate() async {
    if (_adjustment != 0 && _reasonController.text.trim().isEmpty) {
      setState(() => _error = 'Motif requis pour un ajustement non nul');
      return;
    }
    setState(() => _error = null);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(child: Text('Confirmer la validation ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ],
        ),
        content: Text(
          'Le coût de revient du lot ${widget.batch.lotNumber} sera figé définitivement à '
          '${formatQty(_previewPerUnit)} F/kg'
          '${_adjustment != 0 ? ' (ajustement ${_adjustment > 0 ? '+' : ''}${formatQty(_adjustment)} FCFA)' : ''}.\n\n'
          'Cette action est irréversible : le stock réellement consommé est prélevé à ce moment-là.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    final err = await runBlocking(
      context,
      () => _mongoService.validateProduction(
        widget.batch.id!,
        adjustment: _adjustment,
        adjustmentReason: _reasonController.text.trim().isEmpty ? null : _reasonController.text.trim(),
      ),
    );
    if (err != null) {
      if (!mounted) return;
      setState(() => _error = err);
      return;
    }
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
            const SizedBox(width: 10),
            const Expanded(child: Text('Coût validé', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ],
        ),
        content: Text(
          'Lot ${widget.batch.lotNumber} : coût de revient figé à ${formatQty(_previewPerUnit)} F/kg.\n'
          'Le stock réellement consommé a été prélevé.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  void _openReject() {
    Navigator.pop(context);
    widget.onReject();
  }

  @override
  Widget build(BuildContext context) {
    final batch = widget.batch;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text('${batch.lotNumber} — Validation'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${batch.formulaName} · ${formatQty(batch.actualQuantityProduced)} kg produits',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                ),
                const SizedBox(height: 12),
                for (final c in batch.consumption)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${c.materialName} · ${formatQty(c.quantityConsumed)} kg × ${formatQty(c.unitCost)} F'),
                        ),
                        Text(formatQty(c.lineCost), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                const Padding(
                  padding: EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(
                    'Coûts estimés au lancement — le stock n\'est réellement prélevé et le coût '
                    'figé qu\'en validant ci-dessous ; ils peuvent différer légèrement si le stock a '
                    'changé depuis.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _adjustmentController,
                  keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^-?\d*\.?\d*$'))],
                  decoration: InputDecoration(
                    labelText: 'Ajustement (charges indirectes, FCFA)',
                    border: const OutlineInputBorder(),
                    errorText: _error,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _reasonController,
                  decoration: const InputDecoration(labelText: 'Motif (si ajustement non nul)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Coût de revient définitif', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        '${formatQty(_previewPerUnit)} F/kg',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: _previewPerUnit <= 0 ? Colors.red : Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _openReject,
                  child: const Text('Renvoyer', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _confirmAndValidate,
                  child: const Text('Valider le coût', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
