import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/egg_shipment.dart';
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

/// Historique des expéditions d'œufs vers un couvoir — page séparée et paginée.
/// farmName == null : toutes fermes confondues (vue admin globale, "Toutes les expéditions").
/// farmName renseigné : l'historique d'une seule ferme (rédacteur de sa propre ferme, ou admin
/// qui l'a choisie). isAdmin contrôle si les boutons Valider/Rejeter apparaissent sur les
/// expéditions en attente — le rédacteur ne fait que consulter, jamais valider.
/// validatorName : si renseigné, filtre sur les expéditions validées PAR cet utilisateur
/// (pour l'onglet "Mes validations" du validateur œufs).
/// initialFilter : filtre de statut initial sous forme de string (ex: 'valide', 'en_attente_validation', 'rejetee', ou null pour toutes).
class EggShipmentHistoryScreen extends StatefulWidget {
  final String? farmName;
  final bool isAdmin;
  final String? validatorName;
  final String? initialFilter;

  const EggShipmentHistoryScreen({
    super.key,
    this.farmName,
    this.isAdmin = false,
    this.validatorName,
    this.initialFilter,
  });

  @override
  State<EggShipmentHistoryScreen> createState() => _EggShipmentHistoryScreenState();
}

class _EggShipmentHistoryScreenState extends State<EggShipmentHistoryScreen> {
  final MongoService _mongoService = MongoService();
  List<EggShipment> _entries = [];
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
    final result = await _mongoService.getEggShipments(
      farmName: widget.farmName,
      status: _statusFor(_filter),
      validatedBy: widget.validatorName,
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
    final result = await _mongoService.getEggShipments(
      farmName: widget.farmName,
      status: _statusFor(_filter),
      validatedBy: widget.validatorName,
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

  Future<void> _validate(EggShipment s) async {
    // Un champ "coût de revient par œuf" PAR CATÉGORIE présente dans l'expédition — OAC/PO/
    // DJ/CAS/SAL n'ont pas la même valeur, jamais un prix unique appliqué à tout le mélange.
    final costControllers = {for (final e in s.categoryCounts) e.key: TextEditingController()};
    final indirectController = TextEditingController();
    final motifController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Valider cette expédition ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Valider ${s.summaryLabel} vers ${s.hatcheryName} (${s.farmName}) va diminuer le stock '
                'd\'œufs disponible de cette ferme. Cette action est définitive.',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              for (final e in s.categoryCounts) ...[
                TextField(
                  controller: costControllers[e.key],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Coût de revient par œuf ${eggTypeLabels[e.key]} (FCFA)',
                    border: const OutlineInputBorder(),
                    hintText: 'Ex: 25.50',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: indirectController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Charges indirectes TOTALES (FCFA)',
                  border: OutlineInputBorder(),
                  hintText: 'Ex: 5000 (transport, manutention...)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: motifController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Motif / Commentaire (optionnel)',
                  border: OutlineInputBorder(),
                  hintText: 'Ex: Client pressé, qualité validée, livraison urgente...',
                ),
              ),
            ],
          ),
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
    final costPerEgg = {
      for (final entry in costControllers.entries)
        entry.key: double.tryParse(entry.value.text) ?? 0,
    };
    final indirectCosts = double.tryParse(indirectController.text);
    final motif = motifController.text.trim().isEmpty ? null : motifController.text.trim();
    final result = await runBlocking(context, () => _mongoService.validateEggShipment(
      s.id!,
      costPerEgg: costPerEgg,
      indirectCosts: indirectCosts,
      motif: motif,
    ));
    if (!mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.error!)));
      return;
    }
    _load();
  }

  Future<void> _reject(EggShipment s) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rejeter cette expédition ?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${s.summaryLabel} vers ${s.hatcheryName} (${s.farmName}) — le stock ne sera pas impacté.',
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
    final result = await runBlocking(context, () => _mongoService.rejectEggShipment(s.id!, reason));
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
        subtitle: "Historique des expéditions d'œufs",
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                _filterChip('Toutes', _StatusFilter.all),
                const SizedBox(width: 6),
                _filterChip('En attente', _StatusFilter.pending),
                const SizedBox(width: 6),
                _filterChip('Validées', _StatusFilter.validated),
                const SizedBox(width: 6),
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
                                      Text('Aucune expédition trouvée', style: TextStyle(color: Colors.grey.shade500)),
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

  Color _statusColor(EggShipment s) {
    if (s.isValidated) return DailyReportColors.green700;
    if (s.isRejected) return Colors.red.shade600;
    return DailyReportColors.yellow600;
  }

  Widget _entryCard(EggShipment s) {
    final dateStr = DateFormat('dd/MM/yyyy à HH:mm').format(s.createdAt);
    final color = _statusColor(s);
    return DailyReportCard(
      accentColor: color,
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.local_shipping_rounded, size: 17, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Expédié le $dateStr${s.performedBy != null ? ' par ${s.performedBy}' : ''}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            DailyReportStatusBadge(label: s.statusLabel.toUpperCase(), color: color, solid: true),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 25),
          child: Text(
            [
              if (widget.farmName == null) s.farmName,
              'Vers ${s.hatcheryName}',
              if (s.lotNumber != null) 'Lot ${s.lotNumber}',
            ].join(' · '),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11.5),
          ),
        ),
        const SizedBox(height: 10),
        Text(s.summaryLabel, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: color)),
        if (s.isValidated) ...[
          const SizedBox(height: 4),
          Text(
            'Validée le ${DateFormat('dd/MM/yyyy à HH:mm').format(s.validatedAt!)}${s.validatedBy != null ? ' par ${s.validatedBy}' : ''}',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
          ),
          if (s.motif != null && s.motif!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Motif: ${s.motif}',
              style: TextStyle(color: Colors.blue.shade700, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
          if ((s.costPerEgg != null && s.costPerEgg!.isNotEmpty) || s.indirectCosts != null || s.totalCost != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: DailyReportColors.green100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (s.costPerEgg != null)
                    for (final e in s.costPerEgg!.entries)
                      Text(
                        'Coût/œuf ${eggTypeLabels[e.key] ?? e.key}: ${e.value.toStringAsFixed(0)} FCFA',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: DailyReportColors.green900),
                      ),
                  if (s.indirectCosts != null)
                    Text('Charges indirectes: ${s.indirectCosts!.toStringAsFixed(0)} FCFA', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12, color: DailyReportColors.green900)),
                  if (s.totalCost != null)
                    Text('Coût TOTAL: ${s.totalCost!.toStringAsFixed(0)} FCFA', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: DailyReportColors.green700)),
                ],
              ),
            ),
          ],
        ],
        if (s.isRejected) ...[
          const SizedBox(height: 4),
          Text(
            'Rejetée${s.rejectedAt != null ? ' le ${DateFormat('dd/MM/yyyy à HH:mm').format(s.rejectedAt!)}' : ''}'
            '${s.rejectedBy != null ? ' par ${s.rejectedBy}' : ''}'
            '${s.rejectionReason != null ? ' — ${s.rejectionReason}' : ''}',
            style: TextStyle(color: Colors.red.shade400, fontSize: 11),
          ),
        ],
        if (widget.isAdmin && s.isPending) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reject(s),
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
                  onPressed: () => _validate(s),
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
