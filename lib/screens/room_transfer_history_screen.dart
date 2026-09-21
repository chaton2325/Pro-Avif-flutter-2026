import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/building_tracking.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

const _pageSize = 20;

/// Historique des transferts de sujets entre salles, pour une ferme — page dédiée et
/// paginée (bouton "Charger plus"), même pattern que les autres historiques. Jamais stocké
/// à part : une simple extraction des rapports journaliers existants (champ transfers).
class RoomTransferHistoryScreen extends StatefulWidget {
  final String farmId;
  final String farmName;
  final String? lotNumber;

  const RoomTransferHistoryScreen({super.key, required this.farmId, required this.farmName, this.lotNumber});

  @override
  State<RoomTransferHistoryScreen> createState() => _RoomTransferHistoryScreenState();
}

class _RoomTransferHistoryScreenState extends State<RoomTransferHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<TransferHistoryEntry> _entries = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  int _totalCount = 0;

  bool get _hasMore => _entries.length < _totalCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await _mongoService.getTransfersHistory(widget.farmId, lotNumber: widget.lotNumber, skip: 0, limit: _pageSize);
    if (!mounted) return;
    setState(() {
      _entries = result.data;
      _totalCount = result.totalCount;
      _isLoading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final result = await _mongoService.getTransfersHistory(
      widget.farmId,
      lotNumber: widget.lotNumber,
      skip: _entries.length,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _entries = [..._entries, ...result.data];
      _totalCount = result.totalCount;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(widget.farmName, subtitle: 'Historique des transferts'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? ListView(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 60),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.swap_horiz_rounded, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text('Aucun transfert enregistré.', style: TextStyle(color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _entries.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _entries.length) {
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
                                      child: Text('Charger plus (${_totalCount - _entries.length} restants)'),
                                    ),
                            ),
                          );
                        }
                        return _entryCard(_entries[i]);
                      },
                    ),
            ),
    );
  }

  Widget _entryCard(TransferHistoryEntry t) {
    final date = DateTime.tryParse(t.date);
    final dateStr = date != null ? DateFormat('dd/MM/yyyy').format(date) : t.date;
    return DailyReportCard(
      accentColor: DailyReportColors.green600,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Flexible(child: Text(t.fromRoom, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5), overflow: TextOverflow.ellipsis)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: DailyReportColors.green700),
                  ),
                  Flexible(child: Text(t.toRoom, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            Text(dateStr, style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Text('${t.femaleCount} F · ${t.maleCount} M', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            if (t.performedBy != null) ...[
              const SizedBox(width: 8),
              Text('· ${t.performedBy}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
            ],
          ],
        ),
      ],
    );
  }
}
