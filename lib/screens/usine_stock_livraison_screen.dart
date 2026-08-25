import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/formula.dart';
import '../models/farm.dart';
import '../models/feed_stock.dart';
import '../models/delivery.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';

/// Parcours 04 — Stock & livraison (maquette écrans 22-24), en un écran à 2 onglets :
/// stock d'aliment produit décomposé par lot (RLx-xxxx) et historique des livraisons.
/// La « nouvelle livraison » (écran 23) est une action en contexte (pas d'écran dédié),
/// avec attribution automatique du lot d'aliment (FIFO) et rappel automatique du lot de
/// sujets du bâtiment — jamais de choix manuel de lot.
class UsineStockLivraisonScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineStockLivraisonScreen({
    super.key,
    required this.usine,
    this.permissions,
  });

  @override
  State<UsineStockLivraisonScreen> createState() =>
      _UsineStockLivraisonScreenState();
}

class _UsineStockLivraisonScreenState extends State<UsineStockLivraisonScreen>
    with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );
  static const int _pageSize = 20;

  List<FeedStockSummary> _stock = [];
  List<Formula> _formulas = [];
  List<Farm> _farms = [];
  DeliveryPagedResult? _deliveryPage;
  bool _isLoading = true;
  bool _isLoadingHistory = true;
  String? _historyFormulaFilter; // null = toutes les références
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _mongoService.getFeedStock(widget.usine.id!),
      _mongoService.getFormulas(widget.usine.id!),
      _mongoService.getFarms(),
    ]);
    if (!mounted) return;
    setState(() {
      _stock = results[0] as List<FeedStockSummary>;
      _formulas = results[1] as List<Formula>;
      _farms = results[2] as List<Farm>;
      _isLoading = false;
    });
    await _loadHistoryPage();
  }

  Future<void> _loadHistoryPage() async {
    setState(() => _isLoadingHistory = true);
    final page = await _mongoService.getDeliveries(
      usineId: widget.usine.id!,
      formulaId: _historyFormulaFilter,
      skip: _currentPage * _pageSize,
      limit: _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _deliveryPage = page;
      _isLoadingHistory = false;
    });
  }

  void _applyHistoryFilter(String? formulaId) {
    setState(() {
      _historyFormulaFilter = formulaId;
      _currentPage = 0;
    });
    _loadHistoryPage();
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    _loadHistoryPage();
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'rupture':
        return Colors.grey.shade600;
      case 'bas':
        return Colors.orange.shade800;
      default:
        return Colors.green.shade700;
    }
  }

  List<MapEntry<String, double>> _previewFifo(
    List<FeedStockBatch> batches,
    double qty,
  ) {
    double remaining = qty;
    final result = <MapEntry<String, double>>[];
    for (final b in batches) {
      if (remaining <= 0) break;
      final take = remaining < b.remainingQuantity
          ? remaining
          : b.remainingQuantity;
      if (take <= 0) continue;
      result.add(MapEntry(b.lotNumber, take));
      remaining -= take;
    }
    return result;
  }

  void _showDeliveryDialog() {
    if (_stock.isEmpty || _farms.isEmpty) {
      _snack(
        _farms.isEmpty
            ? "Aucune ferme enregistrée dans l'application."
            : 'Aucune formule / référence configurée.',
      );
      return;
    }
    Farm? selectedFarm;
    String? selectedRoom;
    String? currentLotSujets;
    bool lotLoading = false;
    String? selectedFormulaId = _stock
        .firstWhere((s) => s.totalStock > 0, orElse: () => _stock.first)
        .formulaId;
    final quantityController = TextEditingController();
    final driverController = TextEditingController();
    final vehicleController = TextEditingController();
    String? error;
    bool isBusy = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final stockEntry = _stock
              .where((s) => s.formulaId == selectedFormulaId)
              .toList();
          final available = stockEntry.isNotEmpty
              ? stockEntry.first.totalStock
              : 0.0;
          final batches = stockEntry.isNotEmpty
              ? stockEntry.first.batches
              : <FeedStockBatch>[];
          final qty = double.tryParse(quantityController.text) ?? 0;
          final preview = _previewFifo(batches, qty);
          final remainAfter = (available - qty).clamp(0, double.infinity);

          Future<void> fetchLot() async {
            if (selectedFarm == null || selectedRoom == null) return;
            setDialogState(() => lotLoading = true);
            final lot = await _mongoService.getCurrentLotForRoom(
              selectedFarm!.name,
              selectedRoom!,
            );
            setDialogState(() {
              currentLotSujets = lot;
              lotLoading = false;
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Nouvelle livraison',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<Farm>(
                      isExpanded: true,
                      value: selectedFarm,
                      decoration: const InputDecoration(labelText: 'Ferme'),
                      items: _farms
                          .map(
                            (f) => DropdownMenuItem(
                              value: f,
                              child: Text(
                                f.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        setDialogState(() {
                          selectedFarm = v;
                          selectedRoom = null;
                          currentLotSujets = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedRoom,
                      decoration: const InputDecoration(
                        labelText: 'Bâtiment destinataire',
                      ),
                      items: (selectedFarm?.rooms ?? [])
                          .map(
                            (r) => DropdownMenuItem(
                              value: r,
                              child: Text(r, overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: selectedFarm == null
                          ? null
                          : (v) {
                              setDialogState(() => selectedRoom = v);
                              fetchLot();
                            },
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Lot de sujets en cours',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const Spacer(),
                          if (lotLoading)
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.orange,
                              ),
                            )
                          else
                            Text(
                              currentLotSujets ??
                                  (selectedRoom == null
                                      ? '—'
                                      : 'Aucun lot actif'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color:
                                    currentLotSujets == null &&
                                        selectedRoom != null
                                    ? Colors.orange.shade800
                                    : Colors.black87,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedFormulaId,
                      decoration: const InputDecoration(labelText: 'Aliment'),
                      items: _stock
                          .map(
                            (s) => DropdownMenuItem(
                              value: s.formulaId,
                              child: Text(
                                '${s.formulaName} · ${s.totalStock.toStringAsFixed(0)} kg dispo',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedFormulaId = v),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Stock disponible',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const Spacer(),
                          Text(
                            '${available.toStringAsFixed(0)} kg',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: quantityController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Quantité à livrer (kg)',
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: driverController,
                      decoration: const InputDecoration(labelText: 'Chauffeur'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: vehicleController,
                      decoration: const InputDecoration(labelText: 'Véhicule'),
                    ),
                    if (preview.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          border: Border.all(color: Colors.green.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Lot(s) d'aliment attribué(s) (AUTO)",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: preview
                                  .map(
                                    (p) => Chip(
                                      visualDensity: VisualDensity.compact,
                                      label: Text(
                                        '${p.key} · ${p.value.toStringAsFixed(0)} kg',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Text(
                            'Stock restant après livraison',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const Spacer(),
                          Text(
                            '${remainAfter.toStringAsFixed(0)} kg',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (isBusy)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: Colors.orange,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.pop(context),
                child: const Text(
                  'Annuler',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: isBusy
                    ? null
                    : () async {
                        if (selectedFarm == null || selectedRoom == null) {
                          setDialogState(
                            () =>
                                error = 'Choisissez le bâtiment destinataire.',
                          );
                          return;
                        }
                        if (selectedFormulaId == null) {
                          setDialogState(
                            () => error = "Choisissez l'aliment à livrer.",
                          );
                          return;
                        }
                        if (qty <= 0) {
                          setDialogState(() => error = 'Quantité invalide.');
                          return;
                        }
                        if (qty > available) {
                          setDialogState(
                            () => error =
                                'La quantité dépasse le stock disponible.',
                          );
                          return;
                        }
                        setDialogState(() {
                          isBusy = true;
                          error = null;
                        });
                        final result = await _mongoService.createDelivery(
                          usineId: widget.usine.id!,
                          formulaId: selectedFormulaId!,
                          farmName: selectedFarm!.name,
                          roomName: selectedRoom!,
                          quantity: qty,
                          driverName: driverController.text.trim().isEmpty
                              ? null
                              : driverController.text.trim(),
                          vehicle: vehicleController.text.trim().isEmpty
                              ? null
                              : vehicleController.text.trim(),
                        );
                        if (result.error != null) {
                          setDialogState(() {
                            error = result.error;
                            isBusy = false;
                          });
                          return;
                        }
                        await _refreshAll();
                        if (!context.mounted) return;
                        Navigator.pop(context);
                        _snack(
                          'Livraison confirmée : ${qty.toStringAsFixed(0)} kg vers $selectedRoom.',
                        );
                      },
                child: const Text('Confirmer la livraison'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStockTab() {
    if (_stock.isEmpty) {
      return const Center(
        child: Text(
          'Aucune référence produite pour cette usine.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refreshAll,
      color: Colors.orange,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          if (_perms.manageDelivery)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: ListTile(
                onTap: _showDeliveryDialog,
                leading: CircleAvatar(
                  backgroundColor: Colors.teal.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.local_shipping_outlined,
                    color: Colors.teal,
                  ),
                ),
                title: const Text(
                  'Nouvelle livraison',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Bâtiment, lot de sujets et lot d\'aliment automatiques',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            ),
          ..._stock.map(
            (s) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: s.status == 'ok'
                      ? Colors.grey.shade100
                      : Colors.transparent,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        s.formulaName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (s.status != 'ok')
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _statusColor(
                              s.status,
                            ).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            s.status == 'rupture' ? 'RUPTURE' : 'BAS',
                            style: TextStyle(
                              color: _statusColor(s.status),
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '${s.totalStock.toStringAsFixed(0)} kg',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: s.lowStockThreshold > 0
                          ? (s.totalStock / (s.lowStockThreshold * 3)).clamp(
                              0,
                              1,
                            )
                          : (s.totalStock > 0 ? 1 : 0),
                      minHeight: 6,
                      backgroundColor: Colors.grey.shade100,
                      color: _statusColor(s.status == 'ok' ? 'ok' : s.status),
                    ),
                  ),
                  if (s.batches.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: s.batches
                          .map(
                            (b) => Chip(
                              visualDensity: VisualDensity.compact,
                              label: Text(
                                '${b.lotNumber} · ${b.remainingQuantity.toStringAsFixed(0)} kg',
                                style: const TextStyle(fontSize: 11),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Détail d'une livraison + action d'annulation : la quantité prélevée revient sur les
  /// lots d'aliment d'où elle venait (jamais un simple retrait de l'historique — la
  /// livraison reste visible, marquée « annulée » avec son motif).
  void _showDeliveryDetailDialog(Delivery d) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${d.farmName} — ${d.roomName}',
          style: const TextStyle(
            color: Colors.orange,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (d.isCancelled)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Annulée${d.cancelledAt != null ? " le ${DateFormat('dd/MM/yyyy').format(d.cancelledAt!)}" : ""}'
                      '${d.cancelledBy != null ? " par ${d.cancelledBy}" : ""} : ${d.cancelReason ?? ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade800,
                      ),
                    ),
                  ),
                _detailRow(
                  'Date',
                  DateFormat('dd/MM/yyyy · HH:mm').format(d.createdAt),
                ),
                _detailRow(
                  'Aliment',
                  '${d.formulaName} · ${d.quantity.toStringAsFixed(0)} kg',
                ),
                _detailRow('Lot(s) d\'aliment', d.lotsLabel),
                if (d.lotNumberSujets != null)
                  _detailRow('Lot de sujets', d.lotNumberSujets!),
                if (d.driverName != null)
                  _detailRow('Chauffeur', d.driverName!),
                if (d.vehicle != null) _detailRow('Véhicule', d.vehicle!),
                if (_perms.seeCosts)
                  _detailRow('Coût', '${d.totalCost.toStringAsFixed(0)} F'),
                if (d.performedBy != null)
                  _detailRow('Enregistrée par', d.performedBy!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer', style: TextStyle(color: Colors.grey)),
          ),
          if (!d.isCancelled && _perms.manageDelivery)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showCancelDeliveryDialog(d);
              },
              child: const Text(
                'Annuler la livraison',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCancelDeliveryDialog(Delivery d) {
    final reasonController = TextEditingController();
    String? error;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Annuler la livraison',
            style: TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${d.quantity.toStringAsFixed(0)} kg de ${d.formulaName} reviendront en stock (lots ${d.lotsLabel}).',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: reasonController,
                decoration: InputDecoration(
                  labelText: 'Motif',
                  errorText: error,
                ),
                autofocus: true,
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Retour', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () async {
                if (reasonController.text.trim().isEmpty) {
                  setDialogState(() => error = 'Motif requis');
                  return;
                }
                final err = await _mongoService.cancelDelivery(
                  d.id,
                  reasonController.text.trim(),
                );
                if (err != null) {
                  setDialogState(() => error = err);
                  return;
                }
                await _refreshAll();
                if (!context.mounted) return;
                Navigator.pop(context);
                _snack('Livraison annulée, stock reversé.');
              },
              child: const Text('Confirmer l\'annulation'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab() {
    final page = _deliveryPage;
    final totalPages = page == null || page.totalCount == 0
        ? 1
        : (page.totalCount / _pageSize).ceil();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: DropdownButtonFormField<String?>(
            isExpanded: true,
            value: _historyFormulaFilter,
            decoration: const InputDecoration(
              labelText: 'Référence',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Toutes les références'),
              ),
              ..._formulas
                  .where((f) => f.id != null)
                  .map(
                    (f) => DropdownMenuItem(value: f.id, child: Text(f.name)),
                  ),
            ],
            onChanged: _applyHistoryFilter,
          ),
        ),
        Expanded(
          child: _isLoadingHistory
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.orange),
                )
              : (page == null || page.data.isEmpty)
              ? const Center(
                  child: Text(
                    'Aucune livraison pour ce filtre.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  itemCount: page.data.length,
                  itemBuilder: (context, index) {
                    final d = page.data[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade100),
                      ),
                      child: ListTile(
                        onTap: () => _showDeliveryDetailDialog(d),
                        leading: CircleAvatar(
                          backgroundColor:
                              (d.isCancelled ? Colors.grey : Colors.teal)
                                  .withValues(alpha: 0.1),
                          child: Icon(
                            d.isCancelled
                                ? Icons.undo_rounded
                                : Icons.local_shipping_outlined,
                            color: d.isCancelled ? Colors.grey : Colors.teal,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '${DateFormat('dd/MM/yyyy').format(d.createdAt)} · ${d.farmName} — ${d.roomName}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: d.isCancelled ? Colors.grey : Colors.black,
                            decoration: d.isCancelled
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        subtitle: Text(
                          d.isCancelled
                              ? 'Annulée : ${d.cancelReason ?? ""}'
                              : '${d.lotNumberSujets != null ? "Lot ${d.lotNumberSujets} (sujets) · " : ""}'
                                    '${[d.driverName, d.vehicle].where((e) => e != null && e.isNotEmpty).join(' — ')}'
                                    '${d.driverName != null ? " · " : ""}aliment ${d.lotsLabel}'
                                    '${_perms.seeCosts ? " · ${d.totalCost.toStringAsFixed(0)} F" : ""}',
                          style: TextStyle(
                            color: d.isCancelled
                                ? Colors.red.shade300
                                : Colors.grey.shade600,
                            fontSize: 11.5,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${d.quantity.toStringAsFixed(0)} kg',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: d.isCancelled
                                    ? Colors.grey
                                    : Colors.black,
                                decoration: d.isCancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (d.isCancelled)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'ANNULÉE',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (page != null && totalPages > 1)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _currentPage > 0
                      ? () => _goToPage(_currentPage - 1)
                      : null,
                ),
                Text(
                  'Page ${_currentPage + 1} / $totalPages · ${page.totalCount} livraison(s)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _currentPage < totalPages - 1
                      ? () => _goToPage(_currentPage + 1)
                      : null,
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'STOCK & LIVRAISON',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
            fontSize: 13,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _refreshAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(text: 'Stock'),
            Tab(text: 'Livraisons'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : TabBarView(
              controller: _tabController,
              children: [_buildStockTab(), _buildHistoryTab()],
            ),
    );
  }
}
