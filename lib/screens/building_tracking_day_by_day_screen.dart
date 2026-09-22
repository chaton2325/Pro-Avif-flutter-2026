import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_daily_report.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

const _pageSize = 20;

/// Historique jour par jour du suivi bâtiment — page dédiée et paginée, séparée du résumé
/// et des graphiques (BuildingTrackingDetailScreen) pour ne pas surcharger un seul écran.
/// Chaque jour affiche aussi qui a soumis/validé/rejeté le rapport et à quelle heure — pas
/// seulement les chiffres, pour tracer les actions de tous les intervenants (rédacteur,
/// validateur), pas juste de l'admin qui consulte.
class BuildingTrackingDayByDayScreen extends StatefulWidget {
  final String farmId;
  final String farmName;
  final String? lotNumber;

  const BuildingTrackingDayByDayScreen({
    super.key,
    required this.farmId,
    required this.farmName,
    this.lotNumber,
  });

  @override
  State<BuildingTrackingDayByDayScreen> createState() => _BuildingTrackingDayByDayScreenState();
}

class _BuildingTrackingDayByDayScreenState extends State<BuildingTrackingDayByDayScreen> {
  final MongoService _mongoService = MongoService();
  List<FarmDailyReport> _reports = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  int _totalCount = 0;

  bool get _hasMore => _reports.length < _totalCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final history = await _mongoService.getBuildingTrackingHistory(
      widget.farmId,
      lotNumber: widget.lotNumber,
      skip: 0,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _reports = history.data;
      _totalCount = history.totalCount;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final result = await _mongoService.getBuildingTrackingHistory(
      widget.farmId,
      lotNumber: widget.lotNumber,
      skip: _reports.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _reports = [..._reports, ...result.data];
      _totalCount = result.totalCount;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farmName, subtitle: 'Jour par jour ($_totalCount)'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: _reports.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.event_note_rounded, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text('Aucun rapport pour ce lot.', style: TextStyle(color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _reports.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _reports.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                              child: _loadingMore
                                  ? const CircularProgressIndicator(color: DailyReportColors.green700)
                                  : OutlinedButton(
                                      onPressed: _loadMore,
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: DailyReportColors.green700,
                                        side: const BorderSide(color: DailyReportColors.green600),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      child: Text('Charger plus (${_totalCount - _reports.length} restants)'),
                                    ),
                            ),
                          );
                        }
                        return _dayCard(_reports[i]);
                      },
                    ),
            ),
    );
  }

  Widget _dayCard(FarmDailyReport r) {
    final date = DateTime.tryParse(r.date);
    final dateStr = date != null ? DateFormat('EEEE dd/MM/yyyy', 'fr_FR').format(date) : r.date;
    final currentTotal = r.endCounts.fold<int>(0, (a, c) => a + c.femaleCount + c.maleCount) +
        r.clinicEnd.femaleCount + r.clinicEnd.maleCount;
    final mortalityToday = r.mortality.totalFemale + r.mortality.totalMale;
    return DailyReportCard(
      accentColor: mortalityToday > 0 ? DailyReportColors.yellow500 : DailyReportColors.green600,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          children: [
            Expanded(child: Text(dateStr, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            DailyReportStatusBadge(
              label: r.statusLabel.toUpperCase(),
              color: r.status == 'valide'
                  ? DailyReportColors.green600
                  : r.status == 'a_corriger'
                      ? Colors.red
                      : DailyReportColors.yellow600,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _dayMetric(
                icon: Icons.groups_rounded,
                value: '$currentTotal',
                sub: mortalityToday > 0 ? '-$mortalityToday' : '±0',
                subColor: mortalityToday > 0 ? Colors.red.shade600 : Colors.grey.shade400,
              ),
            ),
            Expanded(
              child: _dayMetric(
                icon: Icons.grain_rounded,
                value: '${r.aliment.stockAfterKg.toStringAsFixed(0)} kg',
                sub: r.aliment.totalConsumedKg > 0 ? '-${r.aliment.totalConsumedKg.toStringAsFixed(1)} kg' : '±0',
                subColor: r.aliment.totalConsumedKg > 0 ? DailyReportColors.yellow600 : Colors.grey.shade400,
              ),
            ),
          ],
        ),
        if (r.transfers.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final t in r.transfers)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, size: 14, color: DailyReportColors.green700),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      '${t.fromRoom} → ${t.toRoom} · ${t.femaleCount} F · ${t.maleCount} M',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DailyReportColors.green700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
        if (r.submittedBy != null || r.validatedBy != null || r.rejectedBy != null) ...[
          const Divider(height: 18),
          if (r.submittedBy != null) _actionLine(Icons.send_rounded, 'Soumis', r.submittedBy!, r.submittedAt),
          if (r.validatedBy != null) _actionLine(Icons.verified_rounded, 'Validé', r.validatedBy!, r.validatedAt),
          if (r.rejectedBy != null) _actionLine(Icons.undo_rounded, 'Renvoyé', r.rejectedBy!, r.rejectedAt),
        ],
      ],
    );
  }

  Widget _actionLine(IconData icon, String label, String by, DateTime? at) {
    final timeStr = at != null ? DateFormat('dd/MM HH:mm').format(at) : '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$label par $by${timeStr.isNotEmpty ? " · $timeStr" : ""}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dayMetric({required IconData icon, required String value, required String sub, required Color subColor}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            Text(sub, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: subColor)),
          ],
        ),
      ],
    );
  }
}
