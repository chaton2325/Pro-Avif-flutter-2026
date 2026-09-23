import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/cumul.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

const _pageSize = 20;

/// Historique des ajouts à la valeur de DÉPART du cumul de mortalité, pour une ferme + un
/// lot — page séparée et paginée, même pattern que les autres historiques de cumul. Un ajout
/// n'écrase jamais rien : journal d'additions successives (voir POST /cumuls/mortality/add
/// côté backend). Le cumul ACTUEL (incrémenté par les rapports validés) ne se trouve pas ici
/// — voir l'onglet "Cumuls" de Suivi Bâtiment.
class LotMortalityCumulHistoryScreen extends StatefulWidget {
  final String farmName;
  final String lotNumber;

  const LotMortalityCumulHistoryScreen({super.key, required this.farmName, required this.lotNumber});

  @override
  State<LotMortalityCumulHistoryScreen> createState() => _LotMortalityCumulHistoryScreenState();
}

class _LotMortalityCumulHistoryScreenState extends State<LotMortalityCumulHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<LotMortalityCumulHistoryEntry> _entries = [];
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
    final result = await _mongoService.getLotMortalityCumulHistory(widget.farmName, widget.lotNumber, skip: 0, limit: _pageSize);
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
    final result = await _mongoService.getLotMortalityCumulHistory(
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
      appBar: dailyReportAppBar(widget.farmName, subtitle: 'Historique cumul mortalité — Lot ${widget.lotNumber}'),
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

  Widget _entryCard(LotMortalityCumulHistoryEntry h) {
    final dateStr = DateFormat('dd/MM/yyyy à HH:mm').format(h.createdAt);
    return DailyReportCard(
      accentColor: Colors.red.shade600,
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.add_circle_outline_rounded, size: 17, color: Colors.red.shade600),
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
          'F +${h.femaleCount} · M +${h.maleCount}',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: Colors.red.shade600),
        ),
      ],
    );
  }
}
