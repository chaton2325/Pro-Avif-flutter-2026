import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/raw_material.dart';
import '../models/raw_material_batch.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';
import '../widgets/blocking_loader.dart';

const List<String> _lotCloseReasons = [
  'Avarie (humidité)',
  'Séchage / évaporation',
  'Casse / manutention',
  'Autre',
];

/// Historique de tous les lots de matières premières « par lot » d'une usine, dans une
/// page dédiée avec pagination côté serveur (30 par page) — pensé pour tenir même avec
/// des milliers de lots déjà enregistrés, jamais un chargement complet en mémoire.
class UsineLotsHistoryScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineLotsHistoryScreen({
    super.key,
    required this.usine,
    this.permissions,
  });

  @override
  State<UsineLotsHistoryScreen> createState() => _UsineLotsHistoryScreenState();
}

class _UsineLotsHistoryScreenState extends State<UsineLotsHistoryScreen> {
  final MongoService _mongoService = MongoService();
  PostePermissions get _perms => widget.permissions ?? fullAccessPermissions;
  static const int _pageSize = 30;

  List<RawMaterial> _materials = [];
  RawMaterialBatchPage? _page;
  bool _isLoading = true;
  String? _error;

  String? _materialFilter; // null = toutes les matières
  String _statusFilter = 'tous'; // 'tous' | 'actif' | 'cloture'
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadMaterials();
    _loadPage();
  }

  Future<void> _loadMaterials() async {
    final materials = await _mongoService.getRawMaterials(widget.usine.id!);
    if (!mounted) return;
    setState(() => _materials = materials.where((m) => m.isParLot).toList());
  }

  Future<void> _loadPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await _mongoService.getRawMaterialBatchesHistory(
        usineId: widget.usine.id!,
        rawMaterialId: _materialFilter,
        status: _statusFilter == 'tous' ? null : _statusFilter,
        limit: _pageSize,
        skip: _currentPage * _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur de chargement : $e";
        _isLoading = false;
      });
    }
  }

  void _applyFilter(void Function() change) {
    setState(() {
      change();
      _currentPage = 0;
    });
    _loadPage();
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    _loadPage();
  }

  void _showCloseLotDialog(RawMaterialBatch batch) {
    final countedController = TextEditingController(
      text: formatQty(batch.remainingQuantity),
    );
    String reason = _lotCloseReasons.first;
    String? errorText;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final counted =
              double.tryParse(countedController.text) ??
              batch.remainingQuantity;
          final variance = batch.remainingQuantity - counted;
          final roundedVariance = variance.round();
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '${batch.lotNumber} — Clôture',
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Restant théorique : ${formatQty(batch.remainingQuantity)}',
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: countedController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Quantité comptée (pesée finale)',
                    errorText: errorText,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Text(
                  roundedVariance == 0
                      ? 'Aucun écart'
                      : (variance > 0
                            ? 'Perte constatée : ${formatQty(variance)}'
                            : 'Gain constaté : ${formatQty(-variance)}'),
                  style: TextStyle(
                    color: roundedVariance > 0
                        ? Colors.orange.shade800
                        : (roundedVariance < 0
                              ? Colors.green.shade700
                              : Colors.grey),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Motif'),
                  value: reason,
                  items: _lotCloseReasons
                      .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => reason = v!),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Annuler',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  final c = double.tryParse(countedController.text);
                  if (c == null || c < 0) {
                    setDialogState(() => errorText = 'Quantité invalide');
                    return;
                  }
                  final err = await runBlocking(
                    context,
                    () => _mongoService.closeRawMaterialBatch(
                      batch.id!,
                      c,
                      reason,
                    ),
                  );
                  if (err != null) {
                    setDialogState(() => errorText = err);
                    return;
                  }
                  await _loadPage();
                  if (!context.mounted) return;
                  Navigator.pop(context);
                },
                child: const Text('Clôturer & enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    final totalPages = page == null || page.totalCount == 0
        ? 1
        : (page.totalCount / _pageSize).ceil();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'HISTORIQUE DES LOTS',
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
            onPressed: _loadPage,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  value: _materialFilter,
                  decoration: const InputDecoration(
                    labelText: 'Matière',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Toutes les matières'),
                    ),
                    ..._materials
                        .where((m) => m.id != null)
                        .map(
                          (m) => DropdownMenuItem(
                            value: m.id,
                            child: Text(m.name),
                          ),
                        ),
                  ],
                  onChanged: (v) => _applyFilter(() => _materialFilter = v),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Tous'),
                      selected: _statusFilter == 'tous',
                      onSelected: (_) =>
                          _applyFilter(() => _statusFilter = 'tous'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Actifs'),
                      selected: _statusFilter == 'actif',
                      onSelected: (_) =>
                          _applyFilter(() => _statusFilter = 'actif'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Clôturés'),
                      selected: _statusFilter == 'cloture',
                      onSelected: (_) =>
                          _applyFilter(() => _statusFilter = 'cloture'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.orange),
                  )
                : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : (page == null || page.items.isEmpty)
                ? const Center(
                    child: Text(
                      'Aucun lot pour ce filtre.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    itemCount: page.items.length,
                    itemBuilder: (context, index) {
                      final b = page.items[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade100),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                (b.isActive ? Colors.green : Colors.grey)
                                    .withValues(alpha: 0.12),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: b.isActive ? Colors.green : Colors.grey,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            b.lotNumber,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            '${b.materialName ?? "?"} · ${b.receivedAt != null ? DateFormat('dd/MM/yyyy').format(b.receivedAt!) : ""} · ${formatQty(b.remainingQuantity)}/${formatQty(b.receivedQuantity)}'
                            '${_perms.seeCosts ? " · ${b.unitCost.toStringAsFixed(1)} F" : ""}',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          trailing: b.isActive
                              ? (_perms.manageReception
                                    ? TextButton(
                                        onPressed: () => _showCloseLotDialog(b),
                                        child: const Text('Clôturer'),
                                      )
                                    : const Text(
                                        'ACTIF',
                                        style: TextStyle(
                                          color: Colors.green,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ))
                              : const Text(
                                  'CLÔTURÉ',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
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
                    'Page ${_currentPage + 1} / $totalPages · ${page.totalCount} lot(s)',
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
      ),
    );
  }
}
