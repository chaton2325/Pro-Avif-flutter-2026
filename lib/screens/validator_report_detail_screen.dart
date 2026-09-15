import 'package:flutter/material.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

const List<String> kRejectReasonChips = [
  'Chiffre incohérent',
  'Stock à vérifier',
  'Photo manquante',
];

/// Détail & validation (maquette écran 10) : données du rédacteur en lecture seule, un
/// renvoi impose un motif (chip ou "Autre" + texte), jamais de refus sans justification.
class ValidatorReportDetailScreen extends StatefulWidget {
  final User user;
  final FarmDailyReport report;

  const ValidatorReportDetailScreen({super.key, required this.user, required this.report});

  @override
  State<ValidatorReportDetailScreen> createState() => _ValidatorReportDetailScreenState();
}

class _ValidatorReportDetailScreenState extends State<ValidatorReportDetailScreen> {
  final MongoService _mongoService = MongoService();
  late FarmDailyReport _report;
  String? _selectedReason;
  final _customReasonController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  bool get _canAct => _report.status == 'en_attente_validation';

  Future<void> _validate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _mongoService.validateDailyReport(_report.id);
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    Navigator.pop(context);
  }

  Future<void> _reject() async {
    final reason = _selectedReason == 'Autre…' ? _customReasonController.text.trim() : _selectedReason;
    if (reason == null || reason.isEmpty) {
      setState(() => _error = 'Choisissez ou saisissez un motif.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _mongoService.rejectDailyReport(_report.id, reason);
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _busy = false;
        _error = result.error;
      });
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: Text('${_report.farmName} — Lot ${_report.lotNumber ?? "—"}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card([
            _row(
              'Mortalité · Production · Eau',
              '${_report.mortality.totalFemale + _report.mortality.totalMale} · '
                  '${_report.production.fold<int>(0, (a, p) => a + p.po)} · ${_report.waterLiters ?? 0} L',
            ),
            const Divider(),
            _row(
              'Stock aliment · Sécurité',
              '${_report.aliment.stockAfterKg} kg · '
                  '${_report.aliment.securityStockDays != null ? "${_report.aliment.securityStockDays!.round()} j" : "—"}',
            ),
          ]),
          const SizedBox(height: 16),
          if (_report.observation != null && _report.observation!.isNotEmpty) ...[
            _card([_row('Observation', _report.observation!)]),
            const SizedBox(height: 16),
          ],
          if (_canAct) ...[
            Text('RENVOYER — MOTIF', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [...kRejectReasonChips, 'Autre…'].map((reason) {
                final selected = _selectedReason == reason;
                return ChoiceChip(
                  label: Text(reason),
                  selected: selected,
                  selectedColor: DailyReportColors.yellow500,
                  labelStyle: TextStyle(fontSize: 12, color: selected ? Colors.black87 : Colors.black54),
                  onSelected: (_) => setState(() => _selectedReason = reason),
                );
              }).toList(),
            ),
            if (_selectedReason == 'Autre…') ...[
              const SizedBox(height: 8),
              TextField(
                controller: _customReasonController,
                decoration: const InputDecoration(hintText: 'Précisez le motif', border: OutlineInputBorder()),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DailyReportColors.yellow600,
                      side: const BorderSide(color: DailyReportColors.yellow500),
                    ),
                    onPressed: _busy ? null : _reject,
                    child: const Text('Renvoyer'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
                    onPressed: _busy ? null : _validate,
                    child: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Valider'),
                  ),
                ),
              ],
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
              child: Text('Statut : ${_report.statusLabel}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(children: children)),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );
}
