import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/farm_feed_stock.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

/// Stock d'aliment de la ferme, par aliment — lecture seule pour le rédacteur (bouton "Stock
/// aliments" de son tableau de bord). Alimenté par les réceptions confirmées (routers/
/// deliveries.py) et débité par la consommation validée dans le rapport journalier
/// (routers/daily_reports.py) : ce n'est pas l'effectif/aliment "de départ" figé, c'est le
/// stock courant.
class FarmFeedStockViewScreen extends StatefulWidget {
  final String farmName;

  const FarmFeedStockViewScreen({super.key, required this.farmName});

  @override
  State<FarmFeedStockViewScreen> createState() => _FarmFeedStockViewScreenState();
}

class _FarmFeedStockViewScreenState extends State<FarmFeedStockViewScreen> {
  final MongoService _mongoService = MongoService();
  FarmFeedStock? _stock;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stock = await _mongoService.getFarmFeedStock(widget.farmName);
    if (!mounted) return;
    setState(() {
      _stock = stock;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final stock = _stock;
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Stock aliments', subtitle: widget.farmName),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: stock == null || stock.quantities.isEmpty
                    ? [_emptyState()]
                    : [
                        DailyReportStatTile(
                          value: '${stock.totalKg} kg',
                          label: 'Total en stock',
                          color: DailyReportColors.green700,
                          icon: Icons.inventory_2_rounded,
                        ),
                        if (stock.updatedAt != null) ...[
                          const SizedBox(height: 6),
                          Center(
                            child: Text(
                              'Mis à jour le ${DateFormat('dd/MM/yyyy à HH:mm').format(stock.updatedAt!)}',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        const DailyReportSectionLabel('Par aliment', icon: Icons.grain_rounded),
                        for (final q in stock.quantities.where((q) => q.quantityKg != 0)) _aliment(q),
                      ],
              ),
            ),
    );
  }

  Widget _aliment(FeedStartingQuantity q) {
    final low = q.quantityKg < 0;
    return DailyReportCard(
      accentColor: low ? Colors.red.shade600 : DailyReportColors.yellow500,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: low ? Colors.red.shade50 : DailyReportColors.yellow100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.grain_rounded, color: low ? Colors.red.shade600 : DailyReportColors.yellow600, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(q.formulaName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14))),
            Text(
              '${q.quantityKg} kg',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: low ? Colors.red.shade600 : DailyReportColors.green700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 10),
              Text('Aucun stock enregistré pour le moment.', style: TextStyle(color: Colors.grey.shade500)),
            ],
          ),
        ),
      );
}
