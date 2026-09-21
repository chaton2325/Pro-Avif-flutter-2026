import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/usine.dart';
import '../models/farm.dart';
import '../models/feed_stock.dart';
import '../models/delivery_resource.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';

/// Une ligne d'aliment dans le formulaire — plusieurs lignes (plusieurs gammes d'aliment)
/// partagent la même ferme/chauffeur/véhicule et sont créées ensemble via
/// POST /deliveries/batch (un Delivery par ligne côté serveur, structure inchangée).
class _DeliveryDraftLine {
  String? formulaId;
  final TextEditingController quantityController = TextEditingController();

  _DeliveryDraftLine({this.formulaId});

  void dispose() => quantityController.dispose();
}

/// Nouvelle livraison — écran dédié (pas une modale) pour laisser assez de place à
/// plusieurs aliments à la fois : chacun avec son propre stock, prévisualisation FIFO et
/// quantité, sous une ferme/chauffeur/véhicule communs.
class NewDeliveryScreen extends StatefulWidget {
  final Usine usine;
  final List<FeedStockSummary> stock;
  final List<Farm> farms;
  final List<DeliveryResource> drivers;
  final List<DeliveryResource> vehicles;

  const NewDeliveryScreen({
    super.key,
    required this.usine,
    required this.stock,
    required this.farms,
    required this.drivers,
    required this.vehicles,
  });

  @override
  State<NewDeliveryScreen> createState() => _NewDeliveryScreenState();
}

class _NewDeliveryScreenState extends State<NewDeliveryScreen> {
  final MongoService _mongoService = MongoService();
  Farm? _selectedFarm;
  String? _currentLotSujets;
  bool _lotLoading = false;
  String? _selectedDriverName;
  String? _selectedVehicleName;
  String? _error;
  bool _isBusy = false;
  late List<_DeliveryDraftLine> _lines;

  @override
  void initState() {
    super.initState();
    _lines = [
      _DeliveryDraftLine(
        formulaId: widget.stock
            .firstWhere((s) => s.totalStock > 0, orElse: () => widget.stock.first)
            .formulaId,
      ),
    ];
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  List<MapEntry<String, double>> _previewFifo(List<FeedStockBatch> batches, double qty) {
    double remaining = qty;
    final result = <MapEntry<String, double>>[];
    for (final b in batches) {
      if (remaining <= 0) break;
      final take = remaining < b.remainingQuantity ? remaining : b.remainingQuantity;
      if (take <= 0) continue;
      result.add(MapEntry(b.lotNumber, take));
      remaining -= take;
    }
    return result;
  }

  double _availableFor(String? formulaId) {
    final entry = widget.stock.where((s) => s.formulaId == formulaId).toList();
    return entry.isNotEmpty ? entry.first.totalStock : 0.0;
  }

  List<FeedStockBatch> _batchesFor(String? formulaId) {
    final entry = widget.stock.where((s) => s.formulaId == formulaId).toList();
    return entry.isNotEmpty ? entry.first.batches : <FeedStockBatch>[];
  }

  Future<void> _fetchLot() async {
    if (_selectedFarm == null) return;
    setState(() => _lotLoading = true);
    final lot = await _mongoService.getCurrentLotForFarm(_selectedFarm!.name);
    if (!mounted) return;
    setState(() {
      _currentLotSujets = lot;
      _lotLoading = false;
    });
  }

  Future<Farm?> _pickFarm() async {
    final searchController = TextEditingController();
    return showModalBottomSheet<Farm>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        List<Farm> filtered = List.of(widget.farms);
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
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Rechercher une ferme...',
                        prefixIcon: const Icon(Icons.search, color: Colors.orange),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      onChanged: (query) {
                        final q = query.toLowerCase();
                        setSheetState(() {
                          filtered = widget.farms.where((f) => f.name.toLowerCase().contains(q)).toList();
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('Aucune ferme trouvée', style: TextStyle(color: Colors.grey.shade500)))
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                            itemBuilder: (_, i) {
                              final farm = filtered[i];
                              return ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFFFF3E0),
                                  child: Icon(Icons.agriculture_rounded, color: Colors.orange, size: 20),
                                ),
                                title: Text(farm.name, style: const TextStyle(fontWeight: FontWeight.w600)),
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

  Future<void> _submit() async {
    if (_selectedFarm == null) {
      setState(() => _error = 'Choisissez la ferme destinataire.');
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    final farmName = _selectedFarm!.name;
    String? resultError;
    double totalQty = 0;
    String snackMessage;
    if (_lines.length == 1) {
      final qty = parseQty(_lines.first.quantityController.text) ?? 0;
      totalQty = qty;
      final result = await runBlocking(
        context,
        () => _mongoService.createDelivery(
          usineId: widget.usine.id!,
          formulaId: _lines.first.formulaId!,
          farmName: farmName,
          quantity: qty,
          driverName: _selectedDriverName,
          vehicle: _selectedVehicleName,
        ),
      );
      resultError = result.error;
      snackMessage = 'Livraison créée : ${formatQty(totalQty)} kg vers $farmName — en attente de validation.';
    } else {
      final result = await runBlocking(
        context,
        () => _mongoService.createDeliveryBatch(
          usineId: widget.usine.id!,
          farmName: farmName,
          driverName: _selectedDriverName,
          vehicle: _selectedVehicleName,
          lines: _lines
              .map((l) => (formulaId: l.formulaId!, quantity: parseQty(l.quantityController.text) ?? 0))
              .toList(),
        ),
      );
      totalQty = result.deliveries.fold(0, (a, d) => a + d.quantity);
      resultError = result.error;
      snackMessage =
          '${_lines.length} livraisons créées (${formatQty(totalQty)} kg au total) vers $farmName — en attente de validation.';
    }
    if (resultError != null) {
      if (!mounted) return;
      setState(() {
        _error = resultError;
        _isBusy = false;
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, snackMessage);
  }

  @override
  Widget build(BuildContext context) {
    final qtyByFormula = <String, double>{};
    for (final l in _lines) {
      if (l.formulaId == null) continue;
      qtyByFormula[l.formulaId!] = (qtyByFormula[l.formulaId!] ?? 0) + (parseQty(l.quantityController.text) ?? 0);
    }
    bool lineExceeds(_DeliveryDraftLine l) {
      if (l.formulaId == null) return false;
      return (qtyByFormula[l.formulaId!] ?? 0) > _availableFor(l.formulaId);
    }

    final anyIncomplete =
        _lines.any((l) => l.formulaId == null || (parseQty(l.quantityController.text) ?? 0) <= 0);
    final anyExceeds = _lines.any(lineExceeds);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_lines.length > 1 ? 'Nouvelle livraison (${_lines.length} aliments)' : 'Nouvelle livraison'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await _pickFarm();
              if (picked == null) return;
              setState(() {
                _selectedFarm = picked;
                _currentLotSujets = null;
              });
              _fetchLot();
            },
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Ferme',
                  suffixIcon: Icon(Icons.arrow_drop_down),
                  border: OutlineInputBorder(),
                ),
                child: Text(
                  _selectedFarm?.name ?? 'Choisir une ferme',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _selectedFarm == null ? Colors.grey.shade600 : Colors.black87),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Text('Lot de sujets en cours', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const Spacer(),
                if (_lotLoading)
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                else
                  Text(
                    _currentLotSujets ?? (_selectedFarm == null ? '—' : 'Aucun lot actif'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: _currentLotSujets == null && _selectedFarm != null ? Colors.orange.shade800 : Colors.black87,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedDriverName,
              decoration: InputDecoration(
                labelText: 'Chauffeur',
                border: const OutlineInputBorder(),
                helperText: widget.drivers.where((d) => d.isActive).isEmpty ? 'Aucun chauffeur configuré' : null,
              ),
              items: widget.drivers
                  .where((d) => d.isActive)
                  .map((d) => DropdownMenuItem(value: d.name, child: Text(d.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedDriverName = v),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _selectedVehicleName,
              decoration: InputDecoration(
                labelText: 'Véhicule',
                border: const OutlineInputBorder(),
                helperText: widget.vehicles.where((v) => v.isActive).isEmpty ? 'Aucun véhicule configuré' : null,
              ),
              items: widget.vehicles
                  .where((v) => v.isActive)
                  .map((v) => DropdownMenuItem(value: v.name, child: Text(v.name, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedVehicleName = v),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Aliments à livrer',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < _lines.length; i++) _lineCard(i, lineExceeds),
          // Plus d'aliment distinct à proposer au-delà de ceux déjà choisis : inutile
          // d'ajouter une ligne qui ne pourrait que dupliquer un aliment déjà pris.
          if (_lines.length < widget.stock.length)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _lines.add(_DeliveryDraftLine(formulaId: _firstUnusedFormulaId()));
                }),
                icon: const Icon(Icons.add_circle_outline, size: 18),
                label: const Text('Ajouter un aliment'),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Créée(s) en attente : le stock ne sera déduit qu\'à la validation.',
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12.5)),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: (_isBusy || anyIncomplete || anyExceeds) ? null : _submit,
              child: _isBusy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(
                      _lines.length > 1 ? 'Créer les ${_lines.length} livraisons' : 'Créer la livraison',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// Le même aliment ne peut pas être choisi sur deux lignes de la même livraison (déjà pris
  /// ailleurs) — sinon deux lignes du même aliment se disputeraient silencieusement le même
  /// stock disponible sans que ce soit visible à l'écran.
  List<FeedStockSummary> _selectableStockFor(_DeliveryDraftLine line) {
    final usedByOthers = _lines.where((l) => l != line).map((l) => l.formulaId).whereType<String>().toSet();
    return widget.stock.where((s) => s.formulaId == line.formulaId || !usedByOthers.contains(s.formulaId)).toList();
  }

  /// Premier aliment avec du stock qui n'est pas déjà pris par une autre ligne — pour
  /// pré-remplir une nouvelle ligne sans dupliquer un choix existant.
  String? _firstUnusedFormulaId() {
    final used = _lines.map((l) => l.formulaId).whereType<String>().toSet();
    final unused = widget.stock.where((s) => !used.contains(s.formulaId));
    final withStock = unused.where((s) => s.totalStock > 0);
    if (withStock.isNotEmpty) return withStock.first.formulaId;
    if (unused.isNotEmpty) return unused.first.formulaId;
    return widget.stock.isNotEmpty ? widget.stock.first.formulaId : null;
  }

  Widget _lineCard(int i, bool Function(_DeliveryDraftLine) lineExceeds) {
    final line = _lines[i];
    final available = _availableFor(line.formulaId);
    final qty = parseQty(line.quantityController.text) ?? 0;
    final preview = _previewFifo(_batchesFor(line.formulaId), qty);
    final exceeds = lineExceeds(line);
    final selectableStock = _selectableStockFor(line);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        // Dégradé jaune -> bleu volontairement voyant : chaque aliment à livrer doit se
        // remarquer immédiatement au milieu du reste du formulaire (ferme/chauffeur/véhicule).
        gradient: LinearGradient(
          colors: [Colors.amber.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.blue.shade200.withValues(alpha: 0.6), blurRadius: 12, offset: const Offset(0, 5)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _lines.length > 1 ? 'Aliment ${i + 1}' : 'Aliment',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      color: Colors.white,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                if (_lines.length > 1)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
                    onPressed: () => setState(() {
                      _lines.removeAt(i).dispose();
                    }),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: line.formulaId,
                  decoration: const InputDecoration(labelText: 'Aliment', border: OutlineInputBorder()),
                  items: selectableStock
                      .map((s) => DropdownMenuItem(
                            value: s.formulaId,
                            child: Text('${s.formulaName} · ${formatQty(s.totalStock)} kg dispo', overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => line.formulaId = v),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12)),
                  child: Row(
                    children: [
                      const Text('Stock disponible', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const Spacer(),
                      Text('${formatQty(available)} kg', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: line.quantityController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      // Point OU virgule comme séparateur décimal (clavier numérique en
                      // français) — jamais les deux à la fois.
                      RegExp(r'^\d*[.,]?\d*$'),
                    ),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Quantité à livrer (kg)',
                    border: const OutlineInputBorder(),
                    errorText: exceeds ? 'Dépasse le stock disponible (${formatQty(available)} kg)' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (preview.isNotEmpty) ...[
                  const SizedBox(height: 12),
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
                        const Text("Lot(s) d'aliment attribué(s) (AUTO)", style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: preview
                              .map((p) => Chip(
                                    visualDensity: VisualDensity.compact,
                                    label: Text('${p.key} · ${formatQty(p.value)} kg', style: const TextStyle(fontSize: 11)),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
