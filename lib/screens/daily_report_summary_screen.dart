import 'package:flutter/material.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

/// Récapitulatif & envoi (maquette écran 07) : tout ce qui est affiché ici vient du serveur
/// (calculs jamais retapés) ; "Envoyer au validateur" déclenche la soumission (avec les
/// règles anti-erreur du cahier des charges appliquées côté backend).
class DailyReportSummaryScreen extends StatefulWidget {
  final User user;
  final FarmDailyReport report;
  final bool readOnly;

  const DailyReportSummaryScreen({
    super.key,
    required this.user,
    required this.report,
    this.readOnly = false,
  });

  @override
  State<DailyReportSummaryScreen> createState() => _DailyReportSummaryScreenState();
}

class _DailyReportSummaryScreenState extends State<DailyReportSummaryScreen> {
  final MongoService _mongoService = MongoService();
  late FarmDailyReport _report;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await _mongoService.submitDailyReport(_report.id);
    if (!mounted) return;
    if (result.error != null) {
      setState(() {
        _submitting = false;
        _error = result.error;
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context)
      ..pop()
      ..pop();
  }

  @override
  Widget build(BuildContext context) {
    final totalFemaleProd = _report.production.fold<int>(0, (a, p) => a + p.po);
    final totalFemaleEnd = _report.endCounts.fold<int>(0, (a, r) => a + r.femaleCount) + _report.clinicEnd.femaleCount;

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Récapitulatif'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _statBox('$totalFemaleProd', 'Prod. totale')),
              const SizedBox(width: 8),
              Expanded(child: _statBox('$totalFemaleEnd', 'Eff. restant F')),
              const SizedBox(width: 8),
              Expanded(
                child: _statBox(
                  _report.aliment.securityStockDays != null
                      ? '${_report.aliment.securityStockDays!.round()} j'
                      : '—',
                  'Sécurité aliment',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _card([
            _row('Mortalité du jour · cumul F/M',
                '${_report.mortality.totalFemale + _report.mortality.totalMale} · '
                    '${_report.mortality.cumulativeFemale}/${_report.mortality.cumulativeMale}'),
            const Divider(),
            _row('Eau consommée', '${_report.waterLiters ?? 0} L'),
            const Divider(),
            _row('Stock aliment', '${_report.aliment.stockAfterKg} kg'),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              "Ce récapitulatif part chez le validateur — rien n'est diffusé avant sa validation.",
              style: TextStyle(fontSize: 12.5, color: Colors.black87),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          ],
          const SizedBox(height: 20),
          if (!widget.readOnly)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: DailyReportColors.green700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Envoyer au validateur', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statBox(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _card(List<Widget> children) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.grey.shade200)),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(children: children)),
      );

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5))),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ],
        ),
      );
}
