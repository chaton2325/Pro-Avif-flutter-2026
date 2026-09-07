import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/stock_movement.dart';
import '../services/mongo_service.dart';
import '../utils/quantity_format.dart';

const Map<String, IconData> _movementIcons = {
  'reception': Icons.call_received_rounded,
  'production_validee': Icons.precision_manufacturing_outlined,
  'production_consommation': Icons.local_fire_department_outlined,
  'livraison': Icons.local_shipping_outlined,
  'livraison_matiere': Icons.local_shipping_outlined,
  'annulation_livraison': Icons.undo_rounded,
  'perte': Icons.warning_amber_rounded,
  'gain': Icons.add_circle_outline,
};

const Map<String, String> _movementTypeLabels = {
  'reception': 'Réception',
  'production_validee': 'Production validée',
  'production_consommation': 'Consommation fabrication',
  'livraison': 'Livraison',
  'livraison_matiere': 'Livraison directe',
  'annulation_livraison': 'Livraison annulée',
  'perte': 'Perte déclarée',
  'gain': 'Écart d\'inventaire (gain)',
};

/// Historique complet des mouvements de stock (approvisionnement ET décrément confondus :
/// réceptions, fabrication, livraisons, pertes/inventaire) d'UNE matière première ou d'UN
/// aliment précis — réservé à l'admin (manageAdmin ou viewMovementHistory), accessible
/// depuis Stock & Inventaire. Pagination côté serveur (30 par page), pensée pour tenir même
/// avec un long historique déjà accumulé, jamais un chargement complet en mémoire.
class UsineStockMovementHistoryScreen extends StatefulWidget {
  final String materialOrFeedName;
  final String? rawMaterialId;
  final String? formulaId;

  const UsineStockMovementHistoryScreen({
    super.key,
    required this.materialOrFeedName,
    this.rawMaterialId,
    this.formulaId,
  });

  @override
  State<UsineStockMovementHistoryScreen> createState() =>
      _UsineStockMovementHistoryScreenState();
}

class _UsineStockMovementHistoryScreenState
    extends State<UsineStockMovementHistoryScreen> {
  final MongoService _mongoService = MongoService();
  static const int _pageSize = 30;

  StockMovementPage? _page;
  bool _isLoading = true;
  String? _error;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  Future<void> _loadPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final page = await _mongoService.getStockMovements(
        rawMaterialId: widget.rawMaterialId,
        formulaId: widget.formulaId,
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
        _error = 'Erreur de chargement : $e';
        _isLoading = false;
      });
    }
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    _loadPage();
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
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

  void _showMovementDetailDialog(StockMovement m) {
    final color = m.isEntry ? Colors.green : Colors.redAccent;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          m.label,
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
                _detailRow('Type', _movementTypeLabels[m.type] ?? m.type),
                _detailRow(
                  'Date',
                  DateFormat('dd/MM/yyyy · HH:mm').format(m.date),
                ),
                _detailRow(
                  'Quantité',
                  '${m.isEntry ? "+" : ""}${formatQty(m.quantity)} ${m.unit}',
                ),
                if (m.lotNumber != null) _detailRow('Lot', m.lotNumber!),
                _detailRow('Enregistré par', m.performedBy ?? '—'),
                if (m.note != null && m.note!.trim().isNotEmpty)
                  _detailRow('Remarque', m.note!),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Effet sur le stock',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      m.isEntry ? 'Entrée' : 'Sortie',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
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
        title: Text(
          'MOUVEMENTS — ${widget.materialOrFeedName.toUpperCase()}',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: .5,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
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
                      'Aucun mouvement enregistré pour le moment.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    itemCount: page.items.length,
                    itemBuilder: (context, index) {
                      final m = page.items[index];
                      final color = m.isEntry ? Colors.green : Colors.redAccent;
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
                          onTap: () => _showMovementDetailDialog(m),
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.12),
                            child: Icon(
                              _movementIcons[m.type] ?? Icons.swap_vert_rounded,
                              color: color,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            m.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${DateFormat('dd/MM/yyyy · HH:mm').format(m.date)}'
                                '${m.lotNumber != null ? " · ${m.lotNumber}" : ""}',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 11.5,
                                ),
                              ),
                              if (m.performedBy != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'par ${m.performedBy}',
                                    style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 10.5,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: m.performedBy != null,
                          trailing: Text(
                            '${m.isEntry ? "+" : ""}${formatQty(m.quantity)} ${m.unit}',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
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
                    'Page ${_currentPage + 1} / $totalPages · ${page.totalCount} mouvement(s)',
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
