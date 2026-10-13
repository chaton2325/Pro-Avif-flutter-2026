import 'package:flutter/material.dart';
import '../models/farm_daily_report.dart';
import '../services/daily_report_pdf_service.dart';
import '../utils/daily_report_colors.dart';

/// Bouton « Exporter en PDF » d'un rapport journalier. Ne s'affiche que pour un rapport VALIDÉ
/// (règle métier : on n'exporte qu'un rapport validé par le validateur).
class DailyReportPdfButton extends StatefulWidget {
  final FarmDailyReport report;

  /// Version compacte (icône seule) pour une carte de liste.
  final bool compact;

  const DailyReportPdfButton({super.key, required this.report, this.compact = false});

  @override
  State<DailyReportPdfButton> createState() => _DailyReportPdfButtonState();
}

class _DailyReportPdfButtonState extends State<DailyReportPdfButton> {
  bool _busy = false;

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await DailyReportPdfService.exportAndShare(widget.report);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de générer le PDF du rapport.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!DailyReportPdfService.canExport(widget.report)) return const SizedBox.shrink();
    if (widget.compact) {
      return IconButton(
        tooltip: 'Exporter en PDF',
        visualDensity: VisualDensity.compact,
        onPressed: _busy ? null : _export,
        icon: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf_rounded, color: DailyReportColors.green700),
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: DailyReportColors.green700,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        onPressed: _busy ? null : _export,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.picture_as_pdf_rounded),
        label: Text(
          _busy ? 'Génération du PDF…' : 'Exporter le rapport en PDF',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
