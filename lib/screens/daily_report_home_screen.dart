import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/farm_daily_report.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import 'daily_report_form_screen.dart';
import 'daily_report_notifications_screen.dart';
import 'daily_report_summary_screen.dart';
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

  Color _statusBg(String status) => switch (status) {
    'valide' => DailyReportColors.green100,
    'a_corriger' => DailyReportColors.yellow100,
    'en_attente_validation' => DailyReportColors.yellow100,
    _ => Colors.grey.shade100,
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
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Rapport Journalier'),
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
                      _InfoCard(farm: _farm!, report: _report!),
                      const SizedBox(height: 16),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(color: Colors.grey.shade200),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                                decoration: BoxDecoration(
                                  color: _statusBg(_report!.status),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  _report!.statusLabel.toUpperCase(),
                                  style: TextStyle(
                                    color: _statusColor(_report!.status),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              if (_report!.submittedAt != null) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'Soumis le ${DateFormat('dd/MM à HH:mm').format(_report!.submittedAt!)}',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (_report!.status == 'a_corriger' && _report!.rejectionReason != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: DailyReportColors.yellow100,
                            border: Border.all(color: DailyReportColors.yellow500),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.info_outline, color: DailyReportColors.yellow600, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                                    children: [
                                      const TextSpan(
                                        text: 'Motif du validateur : ',
                                        style: TextStyle(fontWeight: FontWeight.w700),
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
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _openReport,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DailyReportColors.green700,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(_primaryLabel(_report!.status), style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _NavCard(
                        icon: Icons.local_shipping_outlined,
                        title: 'Réception d\'aliments',
                        subtitle: 'Livraisons de l\'usine à confirmer',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FeedReceptionScreen(farmName: _farm!.name),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final Farm farm;
  final FarmDailyReport report;

  const _InfoCard({required this.farm, required this.report});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Bâtiment · Lot', '${farm.name} · ${report.lotNumber ?? "—"}'),
            const Divider(height: 20),
            _row(
              'Date · Âge',
              '${DateFormat('dd/MM/yyyy').format(DateTime.parse(report.date))}'
                  '${report.ageDays != null ? " · ${report.ageDays} j / ${report.ageWeeks} sem" : ""}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ],
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Icon(icon, color: DailyReportColors.green700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
