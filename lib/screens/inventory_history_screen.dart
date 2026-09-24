import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/inventory_request.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import '../widgets/blocking_loader.dart';

const _pageSize = 20;

enum _StatusFilter { all, pending, validated, rejected }

String? _statusFor(_StatusFilter f) => switch (f) {
  _StatusFilter.pending => 'en_attente_validation',
  _StatusFilter.validated => 'valide',
  _StatusFilter.rejected => 'rejetee',
  _StatusFilter.all => null,
};

/// Historique des inventaires (aliment + œufs) — page séparée et paginée, « par site » :
/// farmName == null : toutes fermes confondues (vue admin globale) ; farmName renseigné :
/// l'historique d'une seule ferme (rédacteur de sa propre ferme, ou admin qui l'a choisie).
/// isAdmin contrôle si les boutons Valider/Rejeter apparaissent sur les demandes en attente —
/// le rédacteur ne fait que consulter, jamais valider (même principe que EggShipmentHistoryScreen).
class InventoryHistoryScreen extends StatefulWidget {
  final String? farmName;
  final bool isAdmin;
  final String? initialFilter;

  const InventoryHistoryScreen({super.key, this.farmName, this.isAdmin = false, this.initialFilter});

  @override
  State<InventoryHistoryScreen> createState() => _InventoryHistoryScreenState();
}

class _InventoryHistoryScreenState extends State<InventoryHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<InventoryRequest> _entries = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  int _totalCount = 0;
  _StatusFilter _filter = _StatusFilter.all;

  bool get _hasMore => _entries.length < _totalCount;

  @override
  void initState() {
    super.initState();
    _filter = _parseFilter(widget.initialFilter);
    _load();
  }

  _StatusFilter _parseFilter(String? filter) {
    switch (filter) {
      case 'en_attente_validation':
        return _StatusFilter.pending;
      case 'valide':
        return _StatusFilter.validated;
      case 'rejetee':
        return _StatusFilter.rejected;
      default:
        return _StatusFilter.all;
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await _mongoService.getInventoryRequests(
      farmName: widget.farmName,
      status: _statusFor(_filter),
      skip: 0,
      limit: _pageSize,
    );
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
    final result = await _mongoService.getInventoryRequests(
      farmName: widget.farmName,
      status: _statusFor(_filter),
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

  void _onFilterChanged(_StatusFilter f) {
    setState(() => _filter = f);
    _load();
  }

  Future<void> _validate(InventoryRequest r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Valider cet inventaire ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Text(
          '${r.typeLabel} — ${r.farmName} : ${r.summaryLabel}.\n\n'
          'Le stock sera remplacé par ce comptage. Cette action est définitive.',
          style: const TextStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Valider'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await runBlocking(context, () => _mongoService.validateInventoryRequest(r.id!));
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    _load();
  }

  Future<void> _reject(InventoryRequest r) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rejeter cet inventaire ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${r.typeLabel} — ${r.farmName} : ${r.summaryLabel} — le stock ne sera pas impacté.',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Motif du rejet', border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.yellow600, foregroundColor: Colors.white),
            onPressed: () {
              if (reasonController.text.trim().isEmpty) return;
              Navigator.pop(context, true);
            },
            child: const Text('Rejeter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) return;
    final result = await runBlocking(context, () => _mongoService.rejectInventoryRequest(r.id!, reason));
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        widget.farmName ?? 'Toutes les fermes',
        subtitle: "Historique des inventaires",
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _filterChip('Toutes', _StatusFilter.all),
                _filterChip('En attente', _StatusFilter.pending),
                _filterChip('Validées', _StatusFilter.validated),
                _filterChip('Rejetées', _StatusFilter.rejected),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
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
                                      Text('Aucun inventaire trouvé', style: TextStyle(color: Colors.grey.shade500)),
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
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, _StatusFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      selected: selected,
      backgroundColor: Colors.white,
      selectedColor: DailyReportColors.purple600,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? DailyReportColors.purple600 : Colors.grey.shade300),
      ),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey.shade700),
      onSelected: (_) => _onFilterChanged(value),
    );
  }

  Color _statusColor(InventoryRequest r) {
    if (r.isValidated) return DailyReportColors.green700;
    if (r.isRejected) return Colors.red.shade600;
    return DailyReportColors.yellow600;
  }

  Widget _entryCard(InventoryRequest r) {
    final dateStr = DateFormat('dd/MM/yyyy à HH:mm').format(r.createdAt);
    final color = _statusColor(r);
    return DailyReportCard(
      accentColor: color,
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(r.isFeed ? Icons.grain_rounded : Icons.egg_rounded, size: 17, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${r.typeLabel} — $dateStr${r.performedBy != null ? ' par ${r.performedBy}' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            DailyReportStatusBadge(label: r.statusLabel.toUpperCase(), color: color, solid: true),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 25),
          child: Text(
            [
              if (widget.farmName == null) r.farmName,
              if (r.lotNumber != null) 'Lot ${r.lotNumber}',
            ].join(' · '),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          r.summaryLabel.isEmpty ? '—' : r.summaryLabel,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: color),
        ),
        if (r.note != null && r.note!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Motif : ${r.note}', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5, fontStyle: FontStyle.italic)),
        ],
        if (r.isValidated) ...[
          const SizedBox(height: 4),
          Text(
            'Validé le ${DateFormat('dd/MM/yyyy à HH:mm').format(r.validatedAt!)}${r.validatedBy != null ? ' par ${r.validatedBy}' : ''}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
        ],
        if (r.isRejected) ...[
          const SizedBox(height: 4),
          Text(
            'Rejeté${r.rejectedAt != null ? ' le ${DateFormat('dd/MM/yyyy à HH:mm').format(r.rejectedAt!)}' : ''}'
            '${r.rejectedBy != null ? ' par ${r.rejectedBy}' : ''}'
            '${r.rejectionReason != null ? ' — ${r.rejectionReason}' : ''}',
            style: TextStyle(color: Colors.red.shade400, fontSize: 11),
          ),
        ],
        if (widget.isAdmin && r.isPending) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reject(r),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DailyReportColors.yellow600,
                    side: const BorderSide(color: DailyReportColors.yellow500),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Rejeter', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _validate(r),
                  style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
                  child: const Text('Valider', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
