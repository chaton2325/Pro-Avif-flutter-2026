import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'daily_report_form_screen.dart';
import 'daily_report_notifications_screen.dart';
import 'daily_report_summary_screen.dart';
import 'current_headcount_screen.dart';
import 'farm_feed_stock_view_screen.dart';
import 'feed_reception_screen.dart';

/// Accueil du rapport du jour (maquette écran 02) : statut, motif de renvoi éventuel, bouton
/// principal adaptatif — point d'entrée du parcours rédacteur.
class DailyReportHomeScreen extends StatefulWidget {
  final User user;

  const DailyReportHomeScreen({super.key, required this.user});

  @override
  State<DailyReportHomeScreen> createState() => _DailyReportHomeScreenState();
}

class _DailyReportHomeScreenState extends State<DailyReportHomeScreen> {
  final MongoService _mongoService = MongoService();
  Farm? _farm;
  FarmDailyReport? _report;
  bool _isLoading = true;
  String? _error;

  String get _todayStr => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    if (widget.user.farmId == null) {
      setState(() {
        _isLoading = false;
        _error = "Aucune ferme n'est assignée à ce compte.";
      });
      return;
    }
    final farm = await _mongoService.getFarmById(widget.user.farmId!);
    if (farm == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Ferme introuvable.';
      });
      return;
    }
    final report = await _mongoService.getOrCreateTodayReport(
      farmId: farm.id!,
      date: _todayStr,
    );
    if (!mounted) return;
    setState(() {
      _farm = farm;
      _report = report;
      _isLoading = false;
      if (report == null) _error = 'Impossible de charger le rapport du jour.';
    });
  }

  void _openReport() {
    final report = _report;
    if (report == null) return;
    if (report.isEditable) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DailyReportFormScreen(user: widget.user, report: report),
        ),
      ).then((_) => _load());
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DailyReportSummaryScreen(
            user: widget.user,
            report: report,
            readOnly: true,
          ),
        ),
      );
    }
  }

  Color _statusColor(String status) => switch (status) {
    'valide' => DailyReportColors.green700,
    'a_corriger' => DailyReportColors.yellow600,
    'en_attente_validation' => DailyReportColors.yellow600,
    _ => Colors.grey.shade600,
  };

  IconData _statusIcon(String status) => switch (status) {
    'valide' => Icons.check_circle_rounded,
    'a_corriger' => Icons.error_outline_rounded,
    'en_attente_validation' => Icons.hourglass_top_rounded,
    _ => Icons.edit_note_rounded,
  };

  String _primaryLabel(String status) => switch (status) {
    'a_corriger' => 'Corriger le rapport',
    'en_attente_validation' => 'Voir le récapitulatif',
    'valide' => 'Voir le rapport',
    _ => 'Commencer / continuer',
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        'Rapport Journalier',
        subtitle: _farm?.name,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DailyReportNotificationsScreen(user: widget.user)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _HeroStatusCard(
                        farm: _farm!,
                        report: _report!,
                        statusColor: _statusColor(_report!.status),
                        statusIcon: _statusIcon(_report!.status),
                      ),
                      if (_report!.status == 'a_corriger' && _report!.rejectionReason != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: DailyReportColors.yellow100,
                            borderRadius: BorderRadius.circular(14),
                            border: Border(left: BorderSide(color: DailyReportColors.yellow500, width: 4)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.priority_high_rounded, color: DailyReportColors.yellow600, size: 20),
                              const SizedBox(width: 10),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                                    children: [
                                      const TextSpan(
                                        text: 'Motif du validateur : ',
                                        style: TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      TextSpan(text: '« ${_report!.rejectionReason} »'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 22),
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
                            onTap: _openReport,
                            child: Center(
                              child: Text(
                                _primaryLabel(_report!.status),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 15),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      DailyReportMenuTile(
                        icon: Icons.local_shipping_outlined,
                        color: DailyReportColors.yellow600,
                        title: "Réception d'aliments",
                        subtitle: "Livraisons de l'usine à confirmer",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FeedReceptionScreen(farmName: _farm!.name),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DailyReportMenuTile(
                        icon: Icons.inventory_2_outlined,
                        color: DailyReportColors.yellow500,
                        title: 'Stock aliments',
                        subtitle: 'Ce qui reste, par aliment',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FarmFeedStockViewScreen(farmName: _farm!.name),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DailyReportMenuTile(
                        icon: Icons.groups_outlined,
                        color: DailyReportColors.green600,
                        title: 'Effectifs en cours',
                        subtitle: 'Effectif actuel, par salle',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CurrentHeadcountScreen(farmName: _farm!.name),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _HeroStatusCard extends StatelessWidget {
  final Farm farm;
  final FarmDailyReport report;
  final Color statusColor;
  final IconData statusIcon;

  const _HeroStatusCard({
    required this.farm,
    required this.report,
    required this.statusColor,
    required this.statusIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: dailyReportHeaderGradient,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: DailyReportColors.green900.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_work_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${farm.name} · Lot ${report.lotNumber ?? "—"}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${DateFormat('dd/MM/yyyy').format(DateTime.parse(report.date))}'
            '${report.ageDays != null ? " · ${report.ageDays} j / ${report.ageWeeks} sem" : ""}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.78), fontSize: 12.5),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 14, color: statusColor),
                const SizedBox(width: 6),
                Text(
                  report.statusLabel.toUpperCase(),
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w800, fontSize: 11.5, letterSpacing: 0.3),
                ),
              ],
            ),
          ),
          if (report.submittedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Soumis le ${DateFormat('dd/MM à HH:mm').format(report.submittedAt!)}',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }
}
