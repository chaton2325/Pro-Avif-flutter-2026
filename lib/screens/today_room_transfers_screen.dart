import 'package:flutter/material.dart';
import '../models/farm_daily_report.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/blocking_loader.dart';
import '../widgets/daily_report_widgets.dart';

const _pageSize = 20;

/// Transferts déjà enregistrés pour le rapport du jour d'une ferme — page dédiée et
/// paginée, séparée de l'écran de saisie (AdminRoomTransferEditScreen) pour ne pas mélanger
/// "consulter/annuler l'existant" et "saisir un nouveau mouvement". Chaque transfert reste
/// annulable tant que le rapport est modifiable : confirmation puis appel serveur immédiat,
/// protégé du double-tap par [runBlocking].
class TodayRoomTransfersScreen extends StatefulWidget {
  final String reportId;
  final String farmName;
  final List<RoomTransferEntry> transfers;

  const TodayRoomTransfersScreen({
    super.key,
    required this.reportId,
    required this.farmName,
    required this.transfers,
  });

  @override
  State<TodayRoomTransfersScreen> createState() => _TodayRoomTransfersScreenState();
}

class _TodayRoomTransfersScreenState extends State<TodayRoomTransfersScreen> {
  final MongoService _mongoService = MongoService();
  late List<RoomTransferEntry> _transfers;
  int _visibleCount = _pageSize;

  @override
  void initState() {
    super.initState();
    _transfers = List.of(widget.transfers);
  }

  Future<void> _cancel(int i) async {
    final t = _transfers[i];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Annuler ce transfert ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Text(
          '${t.fromRoom} → ${t.toRoom} · ${t.femaleCount} F · ${t.maleCount} M\n\n'
          "Les effectifs seront recalculés sans ce mouvement.",
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final newTransfers = List.of(_transfers)..removeAt(i);
    final result = await runBlocking(
      context,
      () => _mongoService.patchDailyReport(widget.reportId, transfers: newTransfers),
    );
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    setState(() {
      _transfers = result.report != null ? List.of(result.report!.transfers) : newTransfers;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transfert annulé.')));
  }

  @override
  Widget build(BuildContext context) {
    final visible = _transfers.take(_visibleCount).toList();
    final hasMore = _visibleCount < _transfers.length;
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farmName, subtitle: 'Transferts déjà enregistrés — aujourd\'hui'),
      body: _transfers.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 10),
                  Text('Aucun transfert enregistré aujourd\'hui.', style: TextStyle(color: Colors.grey.shade500)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: visible.length + (hasMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == visible.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _visibleCount += _pageSize),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DailyReportColors.green700,
                          side: const BorderSide(color: DailyReportColors.green600),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text('Charger plus (${_transfers.length - visible.length} restants)'),
                      ),
                    ),
                  );
                }
                return _entryCard(i, visible[i]);
              },
            ),
    );
  }

  Widget _entryCard(int i, RoomTransferEntry t) {
    return DailyReportCard(
      accentColor: DailyReportColors.green600,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded, size: 16, color: DailyReportColors.green700),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${t.fromRoom} → ${t.toRoom}',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton.icon(
              onPressed: () => _cancel(i),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade700,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Annuler', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text('${t.femaleCount} F · ${t.maleCount} M', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ],
    );
  }
}
