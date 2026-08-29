import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/formula.dart';
import '../models/farm.dart';
import '../models/feed_stock.dart';
import '../models/delivery.dart';
import '../models/delivery_resource.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';

/// Parcours 04 — Livraisons (le stock d'aliment produit se consulte désormais depuis
/// « Stock & Inventaire ») : création d'une livraison (attribution automatique du lot
/// d'aliment par FIFO et rappel automatique du lot de sujets du bâtiment — jamais de choix
/// manuel de lot) puis validation/annulation, le tout dans une seule vue sans onglets.
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

class _UsineStockLivraisonScreenState extends State<UsineStockLivraisonScreen> {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;
  static const int _pageSize = 20;

  List<FeedStockSummary> _stock = [];
  List<Formula> _formulas = [];
  List<Farm> _farms = [];
  List<DeliveryResource> _drivers = [];
  List<DeliveryResource> _vehicles = [];
  DeliveryPagedResult? _deliveryPage;
  bool _isLoading = true;
  bool _isLoadingHistory = true;
  String? _historyFormulaFilter; // null = toutes les références
  String _historySortBy = 'createdAt';
  String _historySortOrder = 'desc';
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    setState(() => _isLoading = true);
    final results = await Future.wait([
      _mongoService.getFeedStock(widget.usine.id!),
      _mongoService.getFormulas(widget.usine.id!),
      _mongoService.getFarms(),
      _mongoService.getDrivers(widget.usine.id!),
      _mongoService.getVehicles(widget.usine.id!),
    ]);
    if (!mounted) return;
    setState(() {
      _stock = results[0] as List<FeedStockSummary>;
      _formulas = results[1] as List<Formula>;
      _farms = (results[2] as List<Farm>)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _drivers = results[3] as List<DeliveryResource>;
      _vehicles = results[4] as List<DeliveryResource>;
      _isLoading = false;
    });
    await _loadHistoryPage();
  }

  Future<void> _loadHistoryPage() async {
    setState(() => _isLoadingHistory = true);
    final page = await _mongoService.getDeliveries(
      usineId: widget.usine.id!,
      formulaId: _historyFormulaFilter,
      sortBy: _historySortBy,
      sortOrder: _historySortOrder,
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

  // Encodé "champ_ordre" (ex. "driverName_asc") pour tenir dans un seul DropdownButton.
  static const Map<String, (String, String)> _historySortOptions = {
    'createdAt_desc': ('createdAt', 'desc'),
    'createdAt_asc': ('createdAt', 'asc'),
    'farmName_asc': ('farmName', 'asc'),
    'driverName_asc': ('driverName', 'asc'),
    'vehicle_asc': ('vehicle', 'asc'),
    'quantity_desc': ('quantity', 'desc'),
    'quantity_asc': ('quantity', 'asc'),
  };

  void _applyHistorySort(String? key) {
    if (key == null) return;
    final option = _historySortOptions[key];
    if (option == null) return;
    setState(() {
      _historySortBy = option.$1;
      _historySortOrder = option.$2;
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

  /// Sélecteur de ferme en feuille modale scrollable + recherche : contrairement à un
  /// DropdownButtonFormField classique (menu qui peut déborder l'écran et devenir
  /// inatteignable dès que la liste des fermes s'allonge), cette feuille reste toujours
  /// pleinement navigable — au clavier via la recherche, ou au doigt via le scroll.
  Future<Farm?> _pickFarm(BuildContext context) async {
    final searchController = TextEditingController();
    return showModalBottomSheet<Farm>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        List<Farm> filtered = List.of(_farms);
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                    child: Text(
                      'Choisir une ferme',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: searchController,
                      autofocus: false,
                      decoration: InputDecoration(
                        hintText: 'Rechercher une ferme...',
                        prefixIcon: const Icon(
                          Icons.search,
                          color: Colors.orange,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (query) {
                        final q = query.toLowerCase();
                        setSheetState(() {
                          filtered = _farms
                              .where((f) => f.name.toLowerCase().contains(q))
                              .toList();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Aucune ferme trouvée',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (_, i) {
                              final farm = filtered[i];
                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFFFF3E0),
                                  child: Icon(
                                    Icons.agriculture_rounded,
                                    color: Colors.orange,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  farm.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  '${farm.rooms.length} bâtiment${farm.rooms.length > 1 ? 's' : ''}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () => Navigator.pop(sheetContext, farm),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Gestion du référentiel chauffeurs/véhicules (logistique) : on ne saisit plus le nom
  /// d'un chauffeur ou d'un véhicule en texte libre à chaque livraison, on choisit dans une
  /// liste que la logistique tient à jour ici.
  void _showManageDriversVehiclesDialog() {
    bool showDrivers = true;
    final nameController = TextEditingController();
    bool isBusy = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final items = showDrivers ? _drivers : _vehicles;

          Future<void> reload() async {
            final results = await Future.wait([
              _mongoService.getDrivers(widget.usine.id!),
              _mongoService.getVehicles(widget.usine.id!),
            ]);
            if (!mounted) return;
            setState(() {
              _drivers = results[0];
              _vehicles = results[1];
            });
            setDialogState(() {});
          }

          Future<void> add() async {
            if (isBusy) return;
            final name = nameController.text.trim();
            if (name.isEmpty) return;
            setDialogState(() => isBusy = true);
            final error = await runBlocking(
              context,
              () => showDrivers
                  ? _mongoService.createDriver(widget.usine.id!, name)
                  : _mongoService.createVehicle(widget.usine.id!, name),
            );
            nameController.clear();
            if (error != null) _snack(error);
            await reload();
            setDialogState(() => isBusy = false);
          }

          Future<void> toggleActive(DeliveryResource item) async {
            if (isBusy) return;
            setDialogState(() => isBusy = true);
            final error = await runBlocking(
              context,
              () => showDrivers
                  ? _mongoService.updateDriver(
                      item.id,
                      item.usineId,
                      item.name,
                      !item.isActive,
                    )
                  : _mongoService.updateVehicle(
                      item.id,
                      item.usineId,
                      item.name,
                      !item.isActive,
                    ),
            );
            if (error != null) _snack(error);
            await reload();
            setDialogState(() => isBusy = false);
          }

          Future<void> remove(DeliveryResource item) async {
            if (isBusy) return;
            setDialogState(() => isBusy = true);
            final error = await runBlocking(
              context,
              () => showDrivers
                  ? _mongoService.deleteDriver(item.id)
                  : _mongoService.deleteVehicle(item.id),
            );
            if (error != null) _snack(error);
            await reload();
            setDialogState(() => isBusy = false);
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Chauffeurs & véhicules',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SizedBox(
              width: 420,
              height: 440,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Chauffeurs'),
                          selected: showDrivers,
                          selectedColor: Colors.orange.withValues(alpha: 0.15),
                          onSelected: (_) =>
                              setDialogState(() => showDrivers = true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          label: const Text('Véhicules'),
                          selected: !showDrivers,
                          selectedColor: Colors.orange.withValues(alpha: 0.15),
                          onSelected: (_) =>
                              setDialogState(() => showDrivers = false),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          decoration: InputDecoration(
                            labelText: showDrivers
                                ? 'Nom du chauffeur'
                                : 'Nom / plaque du véhicule',
                            isDense: true,
                          ),
                          onSubmitted: (_) => add(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: isBusy ? null : add,
                        icon: const Icon(Icons.add),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              showDrivers
                                  ? 'Aucun chauffeur configuré'
                                  : 'Aucun véhicule configuré',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (_, i) {
                              final item = items[i];
                              return ListTile(
                                dense: true,
                                title: Text(
                                  item.name,
                                  style: TextStyle(
                                    decoration: item.isActive
                                        ? null
                                        : TextDecoration.lineThrough,
                                    color: item.isActive
                                        ? Colors.black87
                                        : Colors.grey,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: item.isActive,
                                      activeTrackColor: Colors.orange,
                                      onChanged: (_) => toggleActive(item),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                        size: 20,
                                      ),
                                      onPressed: () => remove(item),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      ),
    );
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
    String? currentLotSujets;
    bool lotLoading = false;
    String? selectedFormulaId = _stock
        .firstWhere((s) => s.totalStock > 0, orElse: () => _stock.first)
        .formulaId;
    final quantityController = TextEditingController();
    String? selectedDriverName;
    String? selectedVehicleName;
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
            if (selectedFarm == null) return;
            setDialogState(() => lotLoading = true);
            final lot = await _mongoService.getCurrentLotForFarm(
              selectedFarm!.name,
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
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        final picked = await _pickFarm(context);
                        if (picked == null) return;
                        setDialogState(() {
                          selectedFarm = picked;
                          currentLotSujets = null;
                        });
                        fetchLot();
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Ferme',
                          suffixIcon: Icon(Icons.arrow_drop_down),
                        ),
                        child: Text(
                          selectedFarm?.name ?? 'Choisir une ferme',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selectedFarm == null
                                ? Colors.grey.shade600
                                : Colors.black87,
                          ),
                        ),
                      ),
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
                                  (selectedFarm == null
                                      ? '—'
                                      : 'Aucun lot actif'),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color:
                                    currentLotSujets == null &&
                                        selectedFarm != null
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
                                '${s.formulaName} · ${formatQty(s.totalStock)} kg dispo',
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
                            '${formatQty(available)} kg',
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*$'),
                        ),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Quantité à livrer (kg)',
                        errorText: qty > available
                            ? 'Dépasse le stock disponible (${formatQty(available)} kg)'
                            : null,
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedDriverName,
                      decoration: InputDecoration(
                        labelText: 'Chauffeur',
                        helperText: _drivers.where((d) => d.isActive).isEmpty
                            ? 'Aucun chauffeur configuré'
                            : null,
                      ),
                      items: _drivers
                          .where((d) => d.isActive)
                          .map(
                            (d) => DropdownMenuItem(
                              value: d.name,
                              child: Text(
                                d.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedDriverName = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: selectedVehicleName,
                      decoration: InputDecoration(
                        labelText: 'Véhicule',
                        helperText: _vehicles.where((v) => v.isActive).isEmpty
                            ? 'Aucun véhicule configuré'
                            : null,
                      ),
                      items: _vehicles
                          .where((v) => v.isActive)
                          .map(
                            (v) => DropdownMenuItem(
                              value: v.name,
                              child: Text(
                                v.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) =>
                          setDialogState(() => selectedVehicleName = v),
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
                                        '${p.key} · ${formatQty(p.value)} kg',
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
                            '${formatQty(remainAfter)} kg',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'Créée en attente : le stock ne sera déduit qu\'à la validation.',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
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
                onPressed: (isBusy || qty <= 0 || qty > available)
                    ? null
                    : () async {
                        if (selectedFarm == null) {
                          setDialogState(
                            () => error = 'Choisissez la ferme destinataire.',
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
                        final result = await runBlocking(
                          context,
                          () => _mongoService.createDelivery(
                            usineId: widget.usine.id!,
                            formulaId: selectedFormulaId!,
                            farmName: selectedFarm!.name,
                            quantity: qty,
                            driverName: selectedDriverName,
                            vehicle: selectedVehicleName,
                          ),
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
                          'Livraison créée : ${formatQty(qty)} kg vers ${selectedFarm!.name} — en attente de validation.',
                        );
                      },
                child: const Text('Créer la livraison'),
              ),
            ],
          );
        },
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
          d.destinationLabel,
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
                  )
                else if (d.isPending)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'En attente de validation — le stock ne sera déduit qu\'à ce moment-là.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                      ),
                    ),
                  )
                else if (d.validatedAt != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Validée le ${DateFormat('dd/MM/yyyy · HH:mm').format(d.validatedAt!)}'
                      '${d.validatedBy != null ? " par ${d.validatedBy}" : ""}.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                _detailRow(
                  'Date',
                  DateFormat('dd/MM/yyyy · HH:mm').format(d.createdAt),
                ),
                _detailRow(
                  'Aliment',
                  '${d.formulaName} · ${formatQty(d.quantity)} kg',
                ),
                _detailRow(
                  'Lot(s) d\'aliment',
                  d.isPending ? 'À attribuer à la validation' : d.lotsLabel,
                ),
                if (d.lotNumberSujets != null)
                  _detailRow('Lot de sujets', d.lotNumberSujets!),
                if (d.driverName != null)
                  _detailRow('Chauffeur', d.driverName!),
                if (d.vehicle != null) _detailRow('Véhicule', d.vehicle!),
                if (_perms.seeCosts && !d.isPending)
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
          if (!d.isCancelled &&
              (_perms.manageDelivery ||
                  (_perms.validateDelivery && d.isPending)))
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showCancelDeliveryDialog(d);
              },
              child: Text(
                d.isPending ? 'Refuser la livraison' : 'Annuler la livraison',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          if (d.isPending && _perms.validateDelivery)
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                final err = await runBlocking(
                  context,
                  () => _mongoService.validateDelivery(d.id),
                );
                if (err != null) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(err)));
                  return;
                }
                await _refreshAll();
                if (!context.mounted) return;
                Navigator.pop(context);
                _snack('Livraison validée : le stock a été déduit.');
              },
              child: const Text('Valider'),
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
          title: Text(
            d.isPending ? 'Refuser la livraison' : 'Annuler la livraison',
            style: const TextStyle(
              color: Colors.redAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d.isPending
                    ? 'Cette livraison n\'a pas encore été validée : aucun stock n\'a été déduit, elle sera simplement rejetée.'
                    : '${formatQty(d.quantity)} kg de ${d.formulaName} reviendront en stock (lots ${d.lotsLabel}).',
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
                final err = await runBlocking(
                  context,
                  () => _mongoService.cancelDelivery(
                    d.id,
                    reasonController.text.trim(),
                  ),
                );
                if (err != null) {
                  setDialogState(() => error = err);
                  return;
                }
                await _refreshAll();
                if (!context.mounted) return;
                Navigator.pop(context);
                _snack(
                  d.isPending
                      ? 'Livraison refusée.'
                      : 'Livraison annulée, stock reversé.',
                );
              },
              child: Text(
                d.isPending ? 'Confirmer le refus' : 'Confirmer l\'annulation',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    final page = _deliveryPage;
    final totalPages = page == null || page.totalCount == 0
        ? 1
        : (page.totalCount / _pageSize).ceil();
    return Column(
      children: [
        if (_perms.manageDelivery)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
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
                  'Lot de sujets et lot d\'aliment automatiques',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            ),
          ),
        if (_perms.manageDelivery)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: ListTile(
                onTap: _showManageDriversVehiclesDialog,
                leading: CircleAvatar(
                  backgroundColor: Colors.blueGrey.withValues(alpha: 0.1),
                  child: const Icon(
                    Icons.badge_outlined,
                    color: Colors.blueGrey,
                  ),
                ),
                title: const Text(
                  'Chauffeurs & véhicules',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Liste utilisée lors de la saisie des livraisons',
                  style: TextStyle(fontSize: 12),
                ),
                trailing: const Icon(Icons.chevron_right, color: Colors.grey),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
                          (f) => DropdownMenuItem(
                            value: f.id,
                            child: Text(f.name),
                          ),
                        ),
                  ],
                  onChanged: _applyHistoryFilter,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: '${_historySortBy}_$_historySortOrder',
                  decoration: const InputDecoration(
                    labelText: 'Trier par',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'createdAt_desc',
                      child: Text('Date (récent → ancien)'),
                    ),
                    DropdownMenuItem(
                      value: 'createdAt_asc',
                      child: Text('Date (ancien → récent)'),
                    ),
                    DropdownMenuItem(
                      value: 'farmName_asc',
                      child: Text('Ferme (A → Z)'),
                    ),
                    DropdownMenuItem(
                      value: 'driverName_asc',
                      child: Text('Chauffeur (A → Z)'),
                    ),
                    DropdownMenuItem(
                      value: 'vehicle_asc',
                      child: Text('Véhicule (A → Z)'),
                    ),
                    DropdownMenuItem(
                      value: 'quantity_desc',
                      child: Text('Quantité (grande → petite)'),
                    ),
                    DropdownMenuItem(
                      value: 'quantity_asc',
                      child: Text('Quantité (petite → grande)'),
                    ),
                  ],
                  onChanged: _applyHistorySort,
                ),
              ),
            ],
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
                              (d.isCancelled
                                      ? Colors.grey
                                      : (d.isPending
                                            ? Colors.amber.shade800
                                            : Colors.teal))
                                  .withValues(alpha: 0.1),
                          child: Icon(
                            d.isCancelled
                                ? Icons.undo_rounded
                                : (d.isPending
                                      ? Icons.hourglass_top_rounded
                                      : Icons.local_shipping_outlined),
                            color: d.isCancelled
                                ? Colors.grey
                                : (d.isPending
                                      ? Colors.amber.shade800
                                      : Colors.teal),
                            size: 20,
                          ),
                        ),
                        title: Text(
                          '${DateFormat('dd/MM/yyyy').format(d.createdAt)} · ${d.destinationLabel}',
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
                              : (d.isPending
                                    ? 'En attente de validation — aliment ${d.formulaName}${[d.driverName, d.vehicle].where((e) => e != null && e.isNotEmpty).isNotEmpty ? " · ${[d.driverName, d.vehicle].where((e) => e != null && e.isNotEmpty).join(' — ')}" : ""}'
                                    : '${d.lotNumberSujets != null ? "Lot ${d.lotNumberSujets} (sujets) · " : ""}'
                                          '${[d.driverName, d.vehicle].where((e) => e != null && e.isNotEmpty).join(' — ')}'
                                          '${d.driverName != null ? " · " : ""}aliment ${d.lotsLabel}'
                                          '${_perms.seeCosts ? " · ${d.totalCost.toStringAsFixed(0)} F" : ""}'),
                          style: TextStyle(
                            color: d.isCancelled
                                ? Colors.red.shade300
                                : (d.isPending
                                      ? Colors.amber.shade800
                                      : Colors.grey.shade600),
                            fontSize: 11.5,
                          ),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${formatQty(d.quantity)} kg',
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
                            if (d.isCancelled || d.isPending)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: d.isCancelled
                                      ? Colors.red.shade50
                                      : Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  d.isCancelled ? 'ANNULÉE' : 'EN ATTENTE',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w800,
                                    color: d.isCancelled
                                        ? Colors.red.shade700
                                        : Colors.amber.shade900,
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
          'LIVRAISONS',
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _buildBody(),
    );
  }
}
