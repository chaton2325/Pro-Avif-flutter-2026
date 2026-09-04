import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/usine.dart';
import '../models/daily_report.dart';
import '../models/feed_stock.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';

/// Rapport de production journalier — reprend, bien plus lisible, la même structure que
/// le rapport papier tenu à l'usine : matière reçue, matière sortie (consommée en
/// fabrication), production du jour, livraison aliment, puis stock aliment usine et
/// matière en stock. Le bouton de partage génère un texte prêt pour WhatsApp (*gras*,
/// sections séparées) plutôt que de faire lire ce rapport dans l'app aux destinataires.
class UsineDailyReportScreen extends StatefulWidget {
  final Usine usine;
  final PostePermissions? permissions;
  const UsineDailyReportScreen({
    super.key,
    required this.usine,
    this.permissions,
  });

  @override
  State<UsineDailyReportScreen> createState() =>
      _UsineDailyReportScreenState();
}

class _UsineDailyReportScreenState extends State<UsineDailyReportScreen> {
  final MongoService _mongoService = MongoService();
  final NumberFormat _qtyFmt = NumberFormat('#,##0.##', 'fr_FR');

  DateTime _selectedDate = DateTime.now();
  DailyReport? _report;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final report = await _mongoService.getDailyReport(
      widget.usine.id!,
      _selectedDate,
    );
    if (!mounted) return;
    setState(() {
      _report = report;
      _isLoading = false;
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(primary: Colors.orange),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _load();
  }

  String _fmtQty(double v, String unit) => '${_qtyFmt.format(v)} $unit';

  String _buildWhatsAppText(DailyReport r) {
    final buffer = StringBuffer();
    const sep = '───────────────';

    buffer.writeln('📋 *RAPPORT DE PRODUCTION*');
    buffer.writeln('🏭 *${widget.usine.name.toUpperCase()}*');
    buffer.writeln('📅 ${DateFormat('dd/MM/yyyy').format(_selectedDate)}');

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('🌾 *MATIÈRE REÇUE*');
    buffer.writeln(sep);
    if (r.receptions.isEmpty) {
      buffer.writeln('_Aucune réception_');
    } else {
      for (final m in r.receptions) {
        buffer.writeln('• ${m.materialName} : ${_fmtQty(m.quantity, m.unit)}');
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('📤 *MATIÈRE SORTIE* (production)');
    buffer.writeln(sep);
    if (r.consumption.isEmpty) {
      buffer.writeln('_Aucune sortie_');
    } else {
      for (final m in r.consumption) {
        buffer.writeln('• ${m.materialName} : ${_fmtQty(m.quantity, m.unit)}');
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('🏭 *PRODUCTION*');
    buffer.writeln(sep);
    if (r.production.isEmpty) {
      buffer.writeln('_Aucune fabrication_');
    } else {
      for (final p in r.production) {
        buffer.writeln(
          '• ${p.formulaName} (${p.lotNumber}) : ${_fmtQty(p.actualQuantityProduced, "kg")}',
        );
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('🚚 *LIVRAISON ALIMENT*');
    buffer.writeln(sep);
    if (r.deliveries.isEmpty) {
      buffer.writeln('_Aucune livraison_');
    } else {
      for (final d in r.deliveries) {
        final lots = d.lotsLabel.isEmpty ? '' : ' (lot ${d.lotsLabel})';
        buffer.writeln(
          '• ${d.formulaName} → ${d.farmName} : ${_fmtQty(d.quantity, "kg")}$lots',
        );
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('📦 *LIVRAISON MATIÈRE (clients)*');
    buffer.writeln(sep);
    if (r.materialDeliveries.isEmpty) {
      buffer.writeln('_Aucune livraison_');
    } else {
      for (final d in r.materialDeliveries) {
        final lots = d.lotsLabel.isEmpty ? '' : ' (lot ${d.lotsLabel})';
        buffer.writeln(
          '• ${d.materialName} → ${d.clientName} : ${_fmtQty(d.quantity, d.unit)}$lots',
        );
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('⏳ *LIVRAISON ALIMENT (en attente de validation)*');
    buffer.writeln(sep);
    if (r.pendingDeliveries.isEmpty) {
      buffer.writeln('_Aucune livraison en attente_');
    } else {
      for (final d in r.pendingDeliveries) {
        buffer.writeln(
          '• ${d.formulaName} → ${d.farmName} : ${_fmtQty(d.quantity, "kg")}',
        );
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('⏳ *LIVRAISON MATIÈRE (clients, en attente de validation)*');
    buffer.writeln(sep);
    if (r.pendingMaterialDeliveries.isEmpty) {
      buffer.writeln('_Aucune livraison en attente_');
    } else {
      for (final d in r.pendingMaterialDeliveries) {
        buffer.writeln(
          '• ${d.materialName} → ${d.clientName} : ${_fmtQty(d.quantity, d.unit)}',
        );
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('📦 *STOCK ALIMENT USINE*');
    buffer.writeln(sep);
    if (r.feedStock.isEmpty) {
      buffer.writeln('_Aucune référence_');
    } else {
      for (final s in r.feedStock) {
        final flag = s.status == 'rupture'
            ? ' ⚠️ RUPTURE'
            : (s.status == 'bas' ? ' ⚠️ BAS' : '');
        buffer.writeln(
          '• ${s.formulaName} : ${_fmtQty(s.totalStock, "kg")}$flag',
        );
      }
    }

    buffer.writeln();
    buffer.writeln(sep);
    buffer.writeln('🗄️ *MATIÈRE EN STOCK*');
    buffer.writeln(sep);
    if (r.materialStock.isEmpty) {
      buffer.writeln('_Aucune matière_');
    } else {
      for (final m in r.materialStock) {
        buffer.writeln('• ${m.materialName} : ${_fmtQty(m.quantity, m.unit)}');
      }
    }

    buffer.writeln();
    buffer.writeln(
      '_Généré le ${DateFormat('dd/MM/yyyy à HH:mm').format(DateTime.now())}_',
    );

    return buffer.toString().trim();
  }

  void _shareWhatsApp() {
    final r = _report;
    if (r == null) return;
    SharePlus.instance.share(ShareParams(text: _buildWhatsAppText(r)));
  }

  Widget _headerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.shade600,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'RAPPORT DU',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(_selectedDate),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.usine.name,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          OutlinedButton.icon(
            onPressed: _pickDate,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white70),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.calendar_month_outlined, size: 16),
            label: const Text('Changer', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String emoji,
    required String title,
    required List<Widget> rows,
    String emptyLabel = 'Aucun mouvement',
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: .3,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          if (rows.isEmpty)
            Text(
              emptyLabel,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12.5),
            )
          else
            ...rows,
        ],
      ),
    );
  }

  Widget _materialRow(String name, double qty, String unit) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            _fmtQty(qty, unit),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _productionRow(DailyReportProductionLine p) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.formulaName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  p.lotNumber,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ),
          Text(
            _fmtQty(p.actualQuantityProduced, 'kg'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _deliveryRow(DailyReportDeliveryLine d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d.formulaName} → ${d.farmName}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (d.lotsLabel.isNotEmpty)
                  Text(
                    'lot ${d.lotsLabel}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _fmtQty(d.quantity, 'kg'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _materialDeliveryRow(DailyReportMaterialDeliveryLine d) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${d.materialName} → ${d.clientName}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (d.lotsLabel.isNotEmpty)
                  Text(
                    'lot ${d.lotsLabel}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            _fmtQty(d.quantity, d.unit),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _feedStockRow(FeedStockSummary s) {
    final color = s.status == 'rupture'
        ? Colors.grey.shade600
        : (s.status == 'bas' ? Colors.orange.shade800 : Colors.green.shade700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.formulaName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          if (s.status != 'ok')
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                s.status == 'rupture' ? 'RUPTURE' : 'BAS',
                style: TextStyle(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          Text(
            _fmtQty(s.totalStock, 'kg'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _report;
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text(
          'RAPPORT DE PRODUCTION',
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
            onPressed: _load,
          ),
          IconButton(
            icon: const Icon(Icons.share, color: Colors.green),
            tooltip: 'Partager (WhatsApp)',
            onPressed: r == null ? null : _shareWhatsApp,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : r == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Impossible de charger le rapport.',
                      style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: Colors.orange,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _headerCard(),
                  const SizedBox(height: 20),
                  _sectionCard(
                    emoji: '🌾',
                    title: 'MATIÈRE REÇUE',
                    emptyLabel: 'Aucune réception ce jour',
                    rows: r.receptions
                        .map((m) => _materialRow(m.materialName, m.quantity, m.unit))
                        .toList(),
                  ),
                  _sectionCard(
                    emoji: '📤',
                    title: 'MATIÈRE SORTIE (production)',
                    emptyLabel: 'Aucune sortie de matière ce jour',
                    rows: r.consumption
                        .map((m) => _materialRow(m.materialName, m.quantity, m.unit))
                        .toList(),
                  ),
                  _sectionCard(
                    emoji: '🏭',
                    title: 'PRODUCTION',
                    emptyLabel: 'Aucune fabrication ce jour',
                    rows: r.production.map(_productionRow).toList(),
                  ),
                  _sectionCard(
                    emoji: '🚚',
                    title: 'LIVRAISON ALIMENT',
                    emptyLabel: 'Aucune livraison ce jour',
                    rows: r.deliveries.map(_deliveryRow).toList(),
                  ),
                  _sectionCard(
                    emoji: '📦',
                    title: 'LIVRAISON MATIÈRE (clients)',
                    emptyLabel: 'Aucune livraison ce jour',
                    rows: r.materialDeliveries
                        .map(_materialDeliveryRow)
                        .toList(),
                  ),
                  _sectionCard(
                    emoji: '⏳',
                    title: 'LIVRAISON ALIMENT (en attente)',
                    emptyLabel: 'Aucune livraison en attente',
                    rows: r.pendingDeliveries.map(_deliveryRow).toList(),
                  ),
                  _sectionCard(
                    emoji: '⏳',
                    title: 'LIVRAISON MATIÈRE (clients, en attente)',
                    emptyLabel: 'Aucune livraison en attente',
                    rows: r.pendingMaterialDeliveries
                        .map(_materialDeliveryRow)
                        .toList(),
                  ),
                  _sectionCard(
                    emoji: '📦',
                    title: 'STOCK ALIMENT USINE',
                    emptyLabel: 'Aucune référence produite',
                    rows: r.feedStock.map(_feedStockRow).toList(),
                  ),
                  _sectionCard(
                    emoji: '🗄️',
                    title: 'MATIÈRE EN STOCK',
                    emptyLabel: 'Aucune matière première',
                    rows: r.materialStock
                        .map((m) => _materialRow(m.materialName, m.quantity, m.unit))
                        .toList(),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _shareWhatsApp,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text(
                        'Partager sur WhatsApp',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
