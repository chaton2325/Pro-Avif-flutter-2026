import 'package:flutter/material.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_full_summary.dart';
import '../widgets/daily_report_widgets.dart';

/// Récapitulatif & envoi (maquette écran 07) : tout ce qui est affiché ici vient du serveur
/// (calculs jamais retapés) ; "Envoyer au validateur" déclenche la soumission (avec les
/// règles anti-erreur du cahier des charges appliquées côté backend).
///
/// Le contenu (effectifs, aliment, mortalité, transferts, production, traitements,
/// personnel, observation) vient de DailyReportFullSummary — partagé avec
/// ValidatorReportDetailScreen pour que le validateur voie exactement la même chose que le
/// rédacteur, jamais une version appauvrie.
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
  bool _isProduction = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _loadFarm();
  }

  Future<void> _loadFarm() async {
    final farm = await _mongoService.getFarmById(_report.farmId);
    if (!mounted || farm == null) return;
    setState(() => _isProduction = farm.isProduction);
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
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Récapitulatif', subtitle: _report.farmName),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DailyReportFullSummary(report: _report, isProduction: _isProduction),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: DailyReportColors.green100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.shield_outlined, color: DailyReportColors.green700, size: 18),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Ce récapitulatif part chez le validateur — rien n'est diffusé avant sa validation.",
                    style: TextStyle(fontSize: 12.5, color: DailyReportColors.green900),
                  ),
                ),
              ],
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
            Container(
              width: double.infinity,
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(colors: [DailyReportColors.green700, DailyReportColors.green600]),
                boxShadow: [
                  BoxShadow(color: DailyReportColors.green700.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6)),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _submitting ? null : _submit,
                  child: Center(
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Envoyer au validateur', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
