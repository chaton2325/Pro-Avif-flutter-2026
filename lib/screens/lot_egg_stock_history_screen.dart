import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/lot_egg_stock.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

const _pageSize = 20;

/// Historique des stocks d'œufs de départ écrasés par une resaisie, pour une ferme + un lot
/// donnés — page séparée (accessible via un simple bouton "Voir l'historique" depuis l'écran
/// de saisie) et paginée, même pattern que LotHeadcountHistoryScreen.
class LotEggStockHistoryScreen extends StatefulWidget {
  final String farmName;
  final String lotNumber;

  const LotEggStockHistoryScreen({super.key, required this.farmName, required this.lotNumber});

  @override
  State<LotEggStockHistoryScreen> createState() => _LotEggStockHistoryScreenState();
}

class _LotEggStockHistoryScreenState extends State<LotEggStockHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<LotEggStockHistoryEntry> _entries = [];
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
    final result = await _mongoService.getLotEggStockHistory(widget.farmName, widget.lotNumber, skip: 0, limit: _pageSize);
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
    final result = await _mongoService.getLotEggStockHistory(
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
      appBar: dailyReportAppBar(widget.farmName, subtitle: 'Historique — Lot ${widget.lotNumber}'),
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
                                Text('Aucune version antérieure', style: TextStyle(color: Colors.grey.shade500)),
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

  Widget _entryCard(LotEggStockHistoryEntry h) {
    final recordedStr = h.recordedAt != null ? DateFormat('dd/MM/yyyy à HH:mm').format(h.recordedAt!) : null;
    final replacedStr = DateFormat('dd/MM/yyyy à HH:mm').format(h.replacedAt);
    final totalPo = h.rooms.fold<int>(0, (a, r) => a + r.po);
    return DailyReportCard(
      accentColor: DailyReportColors.yellow500,
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.history_rounded, size: 17, color: DailyReportColors.yellow600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                recordedStr != null ? 'Saisi le $recordedStr${h.recordedBy != null ? ' par ${h.recordedBy}' : ''}' : 'Saisi le — inconnu',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 25),
          child: Text(
            'Remplacé le $replacedStr${h.replacedBy != null ? ' par ${h.replacedBy}' : ''}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
          ),
        ),
        const SizedBox(height: 10),
        for (final r in h.rooms)
          if (r.oac + r.po + r.dj + r.cas + r.sal > 0) _row(r),
        const Divider(height: 16),
        Row(
          children: [
            const Expanded(child: Text('Total PO', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13))),
            Text(
              '$totalPo',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: DailyReportColors.green700),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(RoomEggStock r) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(r.roomName, style: const TextStyle(fontSize: 12.5))),
          Text(
            'OAC ${r.oac} · PO ${r.po} · DJ ${r.dj} · CAS ${r.cas} · SAL ${r.sal}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
