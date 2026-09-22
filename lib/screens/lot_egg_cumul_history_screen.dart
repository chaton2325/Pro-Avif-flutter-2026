import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/cumul.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

const _pageSize = 20;

/// Historique des ajouts au cumul d'œufs de départ, pour une ferme + un lot — page séparée et
/// paginée. Un ajout n'écrase jamais rien : journal d'additions successives, par salle (voir
/// POST /cumuls/eggs/add côté backend).
class LotEggCumulHistoryScreen extends StatefulWidget {
  final String farmName;
  final String lotNumber;

  const LotEggCumulHistoryScreen({super.key, required this.farmName, required this.lotNumber});

  @override
  State<LotEggCumulHistoryScreen> createState() => _LotEggCumulHistoryScreenState();
}

class _LotEggCumulHistoryScreenState extends State<LotEggCumulHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<LotEggCumulHistoryEntry> _entries = [];
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
    final result = await _mongoService.getLotEggCumulHistory(widget.farmName, widget.lotNumber, skip: 0, limit: _pageSize);
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
    final result = await _mongoService.getLotEggCumulHistory(
      widget.farmName,
      widget.lotNumber,
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
      appBar: dailyReportAppBar(widget.farmName, subtitle: 'Historique du cumul œufs — Lot ${widget.lotNumber}'),
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
                                Icon(Icons.history_rounded, size: 40, color: Colors.grey.shade400),
                                const SizedBox(height: 10),
                                Text('Aucun ajout enregistré', style: TextStyle(color: Colors.grey.shade500)),
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
                                      child: Text('Charger plus (${_totalCount - _entries.length} restantes)'),
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

  Widget _entryCard(LotEggCumulHistoryEntry h) {
    final dateStr = DateFormat('dd/MM/yyyy à HH:mm').format(h.createdAt);
    return DailyReportCard(
      accentColor: DailyReportColors.purple600,
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.add_circle_outline_rounded, size: 17, color: DailyReportColors.purple600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ajouté le $dateStr${h.performedBy != null ? ' par ${h.performedBy}' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 25),
          child: Text('Salle ${h.roomName}', style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5)),
        ),
        const SizedBox(height: 10),
        Text(
          'OAC +${h.oac} · PO +${h.po} · DJ +${h.dj} · CAS +${h.cas} · SAL +${h.sal}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: DailyReportColors.purple600),
        ),
      ],
    );
  }
}
