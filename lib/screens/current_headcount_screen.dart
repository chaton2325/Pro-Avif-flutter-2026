import 'package:flutter/material.dart';
import '../models/current_headcount.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

/// Effectif ACTUEL par salle, pour le rédacteur de sa propre ferme (bouton "Effectifs en
/// cours" de son tableau de bord) — jamais l'effectif de départ. Reprend endCounts du
/// dernier rapport journalier connu (routers/daily_reports.py), lecture seule.
class CurrentHeadcountScreen extends StatefulWidget {
  final String farmName;

  const CurrentHeadcountScreen({super.key, required this.farmName});

  @override
  State<CurrentHeadcountScreen> createState() => _CurrentHeadcountScreenState();
}

class _CurrentHeadcountScreenState extends State<CurrentHeadcountScreen> {
  final MongoService _mongoService = MongoService();
  CurrentHeadcount? _headcount;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final headcount = await _mongoService.getCurrentHeadcount(widget.farmName);
    if (!mounted) return;
    setState(() {
      _headcount = headcount;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = _headcount;
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Effectifs en cours', subtitle: widget.farmName),
      body: _isLoading || h == null
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!h.hasReports)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: DailyReportColors.yellow100, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        "Aucun rapport journalier encore soumis pour ce lot — effectif de départ affiché.",
                        style: TextStyle(color: DailyReportColors.yellow600, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: DailyReportStatTile(
                          value: '${h.totalFemale}',
                          label: 'Femelles',
                          color: DailyReportColors.green700,
                          icon: Icons.female_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DailyReportStatTile(
                          value: '${h.totalMale}',
                          label: 'Mâles',
                          color: DailyReportColors.green600,
                          icon: Icons.male_rounded,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Center(
                    child: Text(
                      [
                        if (h.lotNumber != null) 'Lot ${h.lotNumber}',
                        if (h.ageDays != null) 'Âge ${h.ageDays} j (semaine ${h.ageWeeks})',
                      ].join(' · '),
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const DailyReportSectionLabel('Par salle', icon: Icons.meeting_room_rounded),
                  for (final r in h.rooms) _roomCard(r.roomName, r.femaleCount, r.maleCount),
                  if (h.clinicCurrent.femaleCount > 0 || h.clinicCurrent.maleCount > 0)
                    _roomCard('Clinique', h.clinicCurrent.femaleCount, h.clinicCurrent.maleCount, icon: Icons.local_hospital_rounded),
                ],
              ),
            ),
    );
  }

  Widget _roomCard(String label, int female, int male, {IconData icon = Icons.meeting_room_outlined}) {
    return DailyReportCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: DailyReportColors.green700),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            Text('$female F · $male M', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
          ],
        ),
      ],
    );
  }
}
