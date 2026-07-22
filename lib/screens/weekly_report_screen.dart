import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../models/farm.dart';
import '../models/lot.dart';
import '../models/weekly_report.dart';
import '../services/mongo_service.dart';

/// Génération du rapport hebdomadaire de pesée au format WhatsApp.
/// Si [fixedFarm] est fourni (utilisateur non-admin), le bâtiment est déjà connu et
/// seul le lot est à choisir. Sinon (admin), le bâtiment est aussi à sélectionner.
class WeeklyReportScreen extends StatefulWidget {
  final Farm? fixedFarm;

  const WeeklyReportScreen({super.key, this.fixedFarm});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  final MongoService _mongoService = MongoService();

  List<Farm> _farms = [];
  List<Lot> _lots = [];
  Farm? _selectedFarm;
  Lot? _selectedLot;

  bool _isLoading = true;
  bool _isFetchingReport = false;
  String? _error;
  WeeklyReport? _report;

  // Semaine affichée : priorité à la semaine actuelle (détectée automatiquement au premier
  // chargement), mais modifiable ensuite via le sélecteur.
  int? _selectedWeek;

  final Map<int, TextEditingController> _effectifControllers = {};
  final Map<int, TextEditingController> _rationControllers = {};

  bool get _needsFarmPicker => widget.fixedFarm == null;

  @override
  void initState() {
    super.initState();
    _selectedFarm = widget.fixedFarm;
    _loadInitialData();
  }

  @override
  void dispose() {
    for (final c in _effectifControllers.values) {
      c.dispose();
    }
    for (final c in _rationControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      final lots = await _mongoService.getLots();
      List<Farm> farms = [];
      if (_needsFarmPicker) {
        farms = await _mongoService.getFarms();
        farms.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      }
      if (!mounted) return;
      setState(() {
        _lots = lots..sort((a, b) => a.number.toLowerCase().compareTo(b.number.toLowerCase()));
        _farms = farms;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _generateReport() async {
    if (_selectedFarm == null || _selectedLot == null) return;
    setState(() {
      _isFetchingReport = true;
      _error = null;
      _report = null;
      _effectifControllers.clear();
      _rationControllers.clear();
    });

    try {
      final report = await _mongoService.getWeeklyReport(
        farmName: _selectedFarm!.name,
        lotNumber: _selectedLot!.number,
        week: _selectedWeek,
      );
      if (!mounted) return;
      if (report == null || report.groups.isEmpty) {
        setState(() {
          _isFetchingReport = false;
          _error = "Aucune pesée trouvée pour la semaine sélectionnée.";
        });
        return;
      }
      setState(() {
        _report = report;
        _selectedWeek = report.week; // priorité à la semaine actuelle au premier chargement
        for (int i = 0; i < report.groups.length; i++) {
          _effectifControllers[i] = TextEditingController();
          _rationControllers[i] = TextEditingController();
        }
        _isFetchingReport = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingReport = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _changeWeek(int delta) {
    if (_selectedWeek == null) return;
    setState(() => _selectedWeek = _selectedWeek! + delta);
    _generateReport();
  }

  String _signed(double? v, {int decimals = 0}) {
    if (v == null) return 'N/A';
    final rounded = double.parse(v.toStringAsFixed(decimals));
    final sign = rounded >= 0 ? '+' : '';
    return '$sign${rounded.toStringAsFixed(decimals)}';
  }

  String _buildWhatsAppText(WeeklyReport report) {
    final buffer = StringBuffer();
    buffer.writeln('WEEKLY WEIGHT ANALYSIS ');
    buffer.writeln('*${report.farmName.toUpperCase()}*');
    buffer.writeln('*Lot ${report.lotNumber}*');
    buffer.writeln();
    buffer.writeln('*Week* ${report.week}');
    buffer.writeln('*Date* ${DateFormat('dd/MM/yyyy').format(report.dateStart)} au ${DateFormat('dd/MM/yyyy').format(report.dateEnd)}');
    buffer.writeln();
    buffer.writeln('*Birds weight*');

    for (int i = 0; i < report.groups.length; i++) {
      final g = report.groups[i];
      final effectif = _effectifControllers[i]?.text.trim() ?? '';
      final rationTotal = double.tryParse(_rationControllers[i]?.text.trim() ?? '') ?? 0;
      final rationDaily = rationTotal / 7;

      buffer.writeln();
      buffer.writeln('*${g.sex.toUpperCase()}*');
      buffer.writeln('*${g.roomName}*');
      buffer.writeln('👉Body weight: ${g.bodyWeight?.toStringAsFixed(0) ?? "N/A"}g');
      buffer.writeln('👉Normal weight: ${g.normalWeight?.toStringAsFixed(0) ?? "N/A"}g');
      buffer.writeln('👉Difference: ${_signed(g.difference)}g');
      buffer.writeln('👉Gain: ${g.gain != null ? "${_signed(g.gain)}g" : "N/A"}');
      buffer.writeln('👉Homogénéité: ${g.homogeneity?.toStringAsFixed(0) ?? "N/A"}%${g.homogeneityDelta != null ? "(${_signed(g.homogeneityDelta)})" : ""}');
      buffer.writeln('👉Next weight: ${g.nextWeekNormalWeight?.toStringAsFixed(0) ?? "N/A"}g');
      buffer.writeln('👉Effectif: $effectif sujets');
      buffer.writeln('👉Ration servie: ${rationTotal.toStringAsFixed(0)}g (${rationDaily.toStringAsFixed(0)}g/jr)');
    }

    return buffer.toString().trim();
  }

  void _shareReport() {
    final report = _report;
    if (report == null) return;

    for (int i = 0; i < report.groups.length; i++) {
      final effectifEmpty = _effectifControllers[i]?.text.trim().isEmpty ?? true;
      final rationEmpty = _rationControllers[i]?.text.trim().isEmpty ?? true;
      if (effectifEmpty || rationEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Merci de renseigner l'Effectif et la Ration pour chaque salle/sexe.")),
        );
        return;
      }
    }

    final text = _buildWhatsAppText(report);
    SharePlus.instance.share(ShareParams(text: text));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('RAPPORT HEBDOMADAIRE', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.orange,
        elevation: 1,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSelectionCard(),
                  if (_selectedWeek != null) ...[
                    const SizedBox(height: 16),
                    _buildWeekStepperCard(),
                  ],
                  const SizedBox(height: 16),
                  if (_isFetchingReport) const Center(child: CircularProgressIndicator(color: Colors.orange)),
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12)),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    ),
                  if (_report != null) ..._buildReportPreview(_report!),
                ],
              ),
            ),
    );
  }

  Widget _buildSelectionCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('SÉLECTION', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: Colors.grey, letterSpacing: 1)),
          const SizedBox(height: 12),
          if (_needsFarmPicker) ...[
            DropdownButtonFormField<Farm>(
              value: _selectedFarm,
              decoration: const InputDecoration(labelText: 'Bâtiment', border: OutlineInputBorder()),
              items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
              onChanged: (val) => setState(() { _selectedFarm = val; _report = null; _selectedWeek = null; _error = null; }),
            ),
            const SizedBox(height: 12),
          ],
          DropdownButtonFormField<Lot>(
            value: _selectedLot,
            decoration: const InputDecoration(labelText: 'Lot', border: OutlineInputBorder()),
            items: _lots.map((l) => DropdownMenuItem(value: l, child: Text(l.number))).toList(),
            onChanged: (val) => setState(() { _selectedLot = val; _report = null; _selectedWeek = null; _error = null; }),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedFarm != null && _selectedLot != null && !_isFetchingReport) ? _generateReport : null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('GÉNÉRER LE RAPPORT', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// Indépendant du succès/échec de la dernière génération : reste affiché et utilisable
  /// (flèches) même si la semaine sélectionnée n'a aucune pesée, pour pouvoir y revenir.
  Widget _buildWeekStepperCard() {
    final week = _selectedWeek;
    if (week == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Semaine', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _isFetchingReport ? null : () => _changeWeek(-1),
                  ),
                  Text('$week', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _isFetchingReport ? null : () => _changeWeek(1),
                  ),
                ],
              ),
            ],
          ),
          if (_report != null) ...[
            Text('${DateFormat('dd/MM/yyyy').format(_report!.dateStart)} au ${DateFormat('dd/MM/yyyy').format(_report!.dateEnd)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
            const SizedBox(height: 4),
            Text('${_report!.farmName} · Lot ${_report!.lotNumber}', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildReportPreview(WeeklyReport report) {
    return [
      for (int i = 0; i < report.groups.length; i++) _buildGroupCard(i, report.groups[i]),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _shareReport,
          icon: const Icon(Icons.share),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
          label: const Text('PARTAGER LE RAPPORT', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
      const SizedBox(height: 24),
    ];
  }

  Widget _buildGroupCard(int index, WeeklyReportGroup g) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${g.sex} — ${g.roomName}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Colors.indigo)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _miniStat('Body weight', '${g.bodyWeight?.toStringAsFixed(0) ?? "N/A"}g'),
              _miniStat('Normal weight', '${g.normalWeight?.toStringAsFixed(0) ?? "N/A"}g'),
              _miniStat('Écart', '${_signed(g.difference)}g'),
              _miniStat('Gain', g.gain != null ? '${_signed(g.gain)}g' : 'N/A'),
              _miniStat('Homogénéité', '${g.homogeneity?.toStringAsFixed(0) ?? "N/A"}%${g.homogeneityDelta != null ? "(${_signed(g.homogeneityDelta)})" : ""}'),
              _miniStat('Next weight', '${g.nextWeekNormalWeight?.toStringAsFixed(0) ?? "N/A"}g'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _effectifControllers[index],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Effectif', border: OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _rationControllers[index],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Ration totale semaine (g)', border: OutlineInputBorder(), isDense: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
