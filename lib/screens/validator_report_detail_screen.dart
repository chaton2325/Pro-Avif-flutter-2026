import 'package:flutter/material.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

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
      appBar: dailyReportAppBar('${_report.farmName} — Lot ${_report.lotNumber ?? "—"}'),
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
            const DailyReportSectionLabel('Renvoyer — motif', icon: Icons.reply_rounded),
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
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: DailyReportColors.yellow600,
                        side: const BorderSide(color: DailyReportColors.yellow500, width: 1.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _busy ? null : _reject,
                      child: const Text('Renvoyer', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [DailyReportColors.green700, DailyReportColors.green600]),
                      boxShadow: [
                        BoxShadow(color: DailyReportColors.green700.withValues(alpha: 0.32), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _busy ? null : _validate,
                        child: Center(
                          child: _busy
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Valider', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DailyReportColors.green100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: DailyReportColors.green700, size: 18),
                  const SizedBox(width: 10),
                  Text(
                    'Statut : ${_report.statusLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: DailyReportColors.green900),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => DailyReportCard(children: children);

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
