import 'package:flutter/material.dart';
import '../models/current_egg_stock.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

/// Stock d'œufs ACTUEL (cumuls OAC/PO/DJ/CAS/SAL), pour le rédacteur de sa propre ferme
/// (bouton "Stock œufs") comme pour l'admin (depuis l'écran de saisie du stock de départ) —
/// jamais le stock de départ seul. Reprend les cumuls du dernier rapport journalier connu
/// (routers/daily_reports.py), lecture seule.
class CurrentEggStockScreen extends StatefulWidget {
  final String farmName;

  const CurrentEggStockScreen({super.key, required this.farmName});

  @override
  State<CurrentEggStockScreen> createState() => _CurrentEggStockScreenState();
}

class _CurrentEggStockScreenState extends State<CurrentEggStockScreen> {
  final MongoService _mongoService = MongoService();
  CurrentEggStock? _stock;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await _mongoService.getCurrentEggStock(widget.farmName);
    if (!mounted) return;
    setState(() {
      _stock = stock;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _stock;
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Stock œufs', subtitle: widget.farmName),
      body: _isLoading || s == null
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!s.hasReports)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: DailyReportColors.yellow100, borderRadius: BorderRadius.circular(10)),
                      child: Text(
                        "Aucun rapport journalier encore validé pour ce lot — stock de départ affiché.",
                        style: TextStyle(color: DailyReportColors.yellow600, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                    ),
                  if (s.lotNumber != null)
                    Center(
                      child: Text(
                        'Lot ${s.lotNumber}',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                      ),
                    ),
                  const SizedBox(height: 12),
                  DailyReportStatTile(
                    value: '${s.currentStockOac}',
                    label: 'OAC disponibles pour expédition',
                    color: DailyReportColors.purple600,
                    icon: Icons.egg_rounded,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Seul l'OAC part vers un couvoir : ${s.totalOac} produits au total dont "
                    "${s.totalShippedOac} déjà expédié(s), il en reste ${s.currentStockOac}.",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                  ),
                  const SizedBox(height: 18),
                  const DailyReportSectionLabel('Stock des autres catégories', icon: Icons.egg_alt_rounded),
                  Text(
                    "Rien ne les décrémente jamais (pas d'expédition pour PO/DJ/CAS/SAL) : leur cumul de production EST leur stock actuel.",
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _totalTile('PO', s.totalPo, DailyReportColors.green600),
                      _totalTile('DJ', s.totalDj, DailyReportColors.yellow600),
                      _totalTile('CAS', s.totalCas, Colors.deepOrange),
                      _totalTile('SAL', s.totalSal, DailyReportColors.purple600),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const DailyReportSectionLabel('Stock par salle', icon: Icons.meeting_room_rounded),
                  if (s.rooms.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text('Aucune donnée.', style: TextStyle(color: Colors.grey.shade500))),
                    )
                  else
                    for (final r in s.rooms) _roomCard(r),
                ],
              ),
            ),
    );
  }

  Widget _totalTile(String label, int value, Color color) {
    return SizedBox(
      width: 96,
      child: DailyReportStatTile(value: '$value', label: label, color: color),
    );
  }

  Widget _roomCard(RoomEggStockCurrent r) {
    return DailyReportCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          children: [
            const Icon(Icons.meeting_room_outlined, size: 18, color: DailyReportColors.green700),
            const SizedBox(width: 10),
            Expanded(child: Text(r.roomName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            _roomMetric('OAC', r.cumulativeOac),
            _roomMetric('PO', r.cumulativePo),
            _roomMetric('DJ', r.cumulativeDj),
            _roomMetric('CAS', r.cumulativeCas),
            _roomMetric('SAL', r.cumulativeSal),
          ],
        ),
      ],
    );
  }

  Widget _roomMetric(String label, int value) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '$label ', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
          TextSpan(text: '$value', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
        ],
      ),
    );
  }
}
