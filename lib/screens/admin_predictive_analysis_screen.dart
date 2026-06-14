import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/mongo_service.dart';
import '../models/farm.dart';
import '../models/lot.dart';
import 'fullscreen_chart_view.dart';


class AdminPredictiveAnalysisScreen extends StatefulWidget {
  final String? initialWeighingId;
  const AdminPredictiveAnalysisScreen({super.key, this.initialWeighingId});

  @override
  State<AdminPredictiveAnalysisScreen> createState() => _AdminPredictiveAnalysisScreenState();
}

class _AdminPredictiveAnalysisScreenState extends State<AdminPredictiveAnalysisScreen> {
  final MongoService _mongoService = MongoService();
  
  bool _isLoading = false;
  Map<String, dynamic>? _clusteringData;
  Map<String, dynamic>? _simulationResult;
  List<dynamic> _sourceHistory = [];
  List<dynamic> _targetHistory = [];
  
  // Selection state
  List<Farm> _farms = [];
  List<Lot> _lots = [];
  Farm? _selectedFarm;
  Lot? _selectedLot;
  String? _selectedRoom;
  String _selectedSex = 'Mâle';
  
  // Simulation params
  String? _simSourceRoom;
  String? _simTargetRoom;
  int? _selectedClusterId;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final futures = await Future.wait([
        _mongoService.getFarms(),
        _mongoService.getLots(),
      ]);
      
      _farms = futures[0] as List<Farm>;
      _lots = futures[1] as List<Lot>;

      if (_farms.isNotEmpty) {
        _selectedFarm = _farms.first;
        if (_selectedFarm!.rooms.isNotEmpty) {
          _selectedRoom = _selectedFarm!.rooms.first;
          _simSourceRoom = _selectedRoom;
          // Target room is usually different
          if (_selectedFarm!.rooms.length > 1) {
            _simTargetRoom = _selectedFarm!.rooms[1];
          }
        }
      }

      if (_lots.isNotEmpty) {
        _selectedLot = _lots.first;
      }
      
      if (_selectedFarm != null && _selectedRoom != null && _selectedLot != null) {
        await _fetchAnalysisData();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchAnalysisData() async {
    final lot = _selectedLot;
    if (_selectedFarm == null || _selectedRoom == null || lot == null) return;

    setState(() => _isLoading = true);

    try {
      final data = await _mongoService.getLatestAnalysis(
        farmName: _selectedFarm!.name,
        roomName: _selectedRoom!,
        sex: _selectedSex,
        lotNumber: lot.number,
      );

      // CHARGEMENT DE L'HISTORIQUE ICI
      final history = await _mongoService.getRoomHomogeneityHistory(
        _selectedFarm!.name,
        _selectedRoom!,
        _selectedSex,
        lotNumber: lot.number,
      );

      setState(() {
        _clusteringData = data;
        _sourceHistory = history; // Mettre à jour l'historique utilisé par le graphique
        _isLoading = false;
        _simulationResult = null;
        _selectedClusterId = null;
      });
    } catch (e) {
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur d\'analyse: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _runSimulation() async {
    if (_selectedFarm == null || _simSourceRoom == null || _simTargetRoom == null || _selectedClusterId == null || _selectedLot == null) return;
    
    setState(() => _isLoading = true);
    try {
      final result = await _mongoService.simulateMove(
        farmName: _selectedFarm!.name,
        sourceRoom: _simSourceRoom!,
        targetRoom: _simTargetRoom!,
        sex: _selectedSex,
        lotNumber: _selectedLot!.number,
        clusterId: _selectedClusterId!,
      );
      
      if (result.containsKey('error')) {
        setState(() => _isLoading = false);
        _showErrorDialog(result['error']);
        return;
      }

      // Fetch real history for trend charts (Room - Sex)
      final srcHist = await _mongoService.getRoomHomogeneityHistory(_selectedFarm!.name, _simSourceRoom!, _selectedSex, lotNumber: _selectedLot!.number);
      final tgtHist = await _mongoService.getRoomHomogeneityHistory(_selectedFarm!.name, _simTargetRoom!, _selectedSex, lotNumber: _selectedLot!.number);
      
      setState(() {
        _simulationResult = result;
        _sourceHistory = srcHist;
        _targetHistory = tgtHist;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erreur lors de la simulation'), backgroundColor: Colors.red));
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Action Impossible', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('COMPRIS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('IA : Optimisation & Simulation', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo.shade900,
        centerTitle: true,
      ),
      body: _isLoading && _farms.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo, strokeWidth: 3))
          : SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSexSelector(),
                  const SizedBox(height: 16),
                  _buildSelectors(),
                  const SizedBox(height: 24),
                  if (_clusteringData != null) ...[
                    _buildSectionHeader('TABLEAU DE BORD IA ($_selectedSex)', Icons.dashboard_customize),
                    const SizedBox(height: 12),
                    _buildClusteringDashboard(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('TENDANCE DE LA SALLE', Icons.trending_up),
                    const SizedBox(height: 12),
                    _buildTrendAnalysis(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('SIMULATEUR DE TRANSFERT', Icons.rebase_edit),
                    const SizedBox(height: 12),
                    _buildSimulatorInterface(),
                    if (_simulationResult != null) ...[
                      const SizedBox(height: 32),
                      _buildSectionHeader('PRÉDICTIONS DE TRANSFERT', Icons.online_prediction),
                      const SizedBox(height: 12),
                      _buildSimulationResults(),
                    ],
                    const SizedBox(height: 60),
                  ] else if (!_isLoading)
                    _buildNoDataPrompt(),
                ],
              ),
            ),
    );
  }

  Widget _buildSexSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
      child: Row(
        children: [
          Expanded(child: _buildSexOption('Mâle', Icons.male)),
          Expanded(child: _buildSexOption('Femelle', Icons.female)),
        ],
      ),
    );
  }

  Widget _buildSexOption(String sex, IconData icon) {
    bool isSelected = _selectedSex == sex;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedSex = sex;
          _simulationResult = null;
        });
        _fetchAnalysisData();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(color: isSelected ? Colors.indigo.shade600 : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20),
            const SizedBox(width: 8),
            Text(sex, style: TextStyle(color: isSelected ? Colors.white : Colors.grey.shade600, fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.indigo.shade400),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.indigo.shade400, letterSpacing: 1.2)),
      ],
    );
  }

  Widget _buildSelectors() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))]),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          DropdownButtonFormField<Farm>(
            value: _selectedFarm,
            dropdownColor: Colors.white,
            decoration: InputDecoration(
              labelText: 'Ferme / Bâtiment',
              prefixIcon: const Icon(Icons.agriculture_rounded, color: Colors.indigo, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true, fillColor: Colors.grey.shade50,
            ),
            items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedFarm = val;
                _selectedRoom = val?.rooms.first;
                _simSourceRoom = _selectedRoom;
                _simulationResult = null;
              });
              _fetchAnalysisData();
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<Lot>(
            value: _selectedLot,
            dropdownColor: Colors.white,
            decoration: InputDecoration(
              labelText: 'Numéro de Lot',
              prefixIcon: const Icon(Icons.inventory_2_rounded, color: Colors.indigo, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true, fillColor: Colors.grey.shade50,
            ),
            items: _lots.map((l) => DropdownMenuItem(value: l, child: Text(l.number))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedLot = val;
                _simulationResult = null;
              });
              _fetchAnalysisData();
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _selectedRoom,
            dropdownColor: Colors.white,
            decoration: InputDecoration(
              labelText: 'Salle à Analyser',
              prefixIcon: const Icon(Icons.meeting_room_rounded, color: Colors.indigo, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true, fillColor: Colors.grey.shade50,
            ),
            items: (_selectedFarm?.rooms ?? []).map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
            onChanged: (val) {
              setState(() {
                _selectedRoom = val;
                _simSourceRoom = val;
                _simulationResult = null;
              });
              _fetchAnalysisData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildClusteringDashboard() {
    final silhouette = (_clusteringData!['silhouette'] as num?)?.toDouble() ?? 0.0;
    final homogeneity = (_clusteringData!['currentHomogeneity'] as num?)?.toDouble() ?? 0.0;
    final clusters = (_clusteringData!['clusters'] as List?) ?? [];

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard('Homogénéité', '${homogeneity.toStringAsFixed(1)}%', Icons.auto_graph_rounded, Colors.blue.shade600)),
            const SizedBox(width: 12),
            Expanded(child: _buildSilhouetteScore(silhouette)),
          ],
        ),
        const SizedBox(height: 16),
        _buildWeightHistogram(clusters),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        ],
      ),
    );
  }

  Widget _buildSilhouetteScore(double score) {
    Color color = score > 0.5 ? Colors.green.shade600 : (score > 0.25 ? Colors.orange.shade600 : Colors.red.shade600);
    String label = score > 0.5 ? 'EXCELLENT' : (score > 0.25 ? 'MOYEN' : 'MÉDIOCRE');

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.psychology_rounded, color: Colors.purple, size: 20)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w900))),
            ],
          ),
          const SizedBox(height: 12),
          Text('COHÉSION IA', style: TextStyle(color: Colors.grey.shade500, fontSize: 11, fontWeight: FontWeight.w700)),
          Text(score.toStringAsFixed(3), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 22)),
        ],
      ),
    );
  }

  Widget _buildWeightHistogram(List clusters) {
    List<BarChartGroupData> groups = [];
    double maxVal = 0;
    for (int i = 0; i < clusters.length; i++) {
      final count = (clusters[i]['count'] as num).toDouble();
      if (count > maxVal) maxVal = count;
      groups.add(BarChartGroupData(x: i, barRods: [BarChartRodData(toY: count, color: _getClusterColor(i), width: 34, borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), backDrawRodData: BackgroundBarChartRodData(show: true, toY: maxVal * 1.2, color: Colors.grey.shade50))], showingTooltipIndicators: [0]));
    }
    return Container(
      height: 280, width: double.infinity, padding: const EdgeInsets.fromLTRB(12, 40, 12, 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: BarChart(BarChartData(
        alignment: BarChartAlignment.spaceAround, maxY: maxVal * 1.35, barGroups: groups,
        titlesData: FlTitlesData(show: true, bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) => val.toInt() < clusters.length ? Padding(padding: const EdgeInsets.only(top: 10.0), child: Text(clusters[val.toInt()]['label'] ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade600))) : const SizedBox())), leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
        gridData: const FlGridData(show: false), borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(enabled: true, touchTooltipData: BarTouchTooltipData(getTooltipColor: (group) => Colors.indigo.shade900, getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem('${clusters[groupIndex]['label']}\n${rod.toY.toInt()} Sujets\n${clusters[groupIndex]['mean'].toStringAsFixed(0)}g', const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))),
      )),
    );
  }

  Widget _buildTrendAnalysis() {
    // Tenter de récupérer regressionData, sinon utiliser l'historique de la salle
    List<dynamic> regressionData = (_clusteringData!['regressionData'] as List?) ?? [];
    if (regressionData.isEmpty) {
      regressionData = _sourceHistory;
    }
    
    if (regressionData.isEmpty) return const SizedBox();
    
    regressionData.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
    List<FlSpot> spots = regressionData.map((p) => FlSpot(DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble(), (p['homogeneity'] as num).toDouble())).toList();
    
    double? bottomInterval;
    if (spots.length > 1) bottomInterval = (spots.last.x - spots.first.x) / 4.0;

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('QUALITÉ DU LOT ($_selectedSex)', style: TextStyle(color: Colors.grey.shade400, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1))]),
        const SizedBox(height: 24),
        SizedBox(height: 200, child: LineChart(LineChartData(
          minY: 0, maxY: 100, // Ajusté pour mieux voir la variation
          lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.indigo.shade600, barWidth: 5, isStrokeCapRound: true, dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 5, color: Colors.indigo, strokeWidth: 2, strokeColor: Colors.white)), belowBarData: BarAreaData(show: true, color: Colors.indigo.withValues(alpha: 0.05)))],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 35, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade400)))),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 32, interval: bottomInterval, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(DateFormat('dd/MM').format(DateTime.fromMillisecondsSinceEpoch(v.toInt())), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade400))))),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withValues(alpha: 0.05), strokeWidth: 1)), borderData: FlBorderData(show: false),
        ))),
      ]),
    );
  }

  Widget _buildSimulatorInterface() {
    final clusters = (_clusteringData!['clusters'] as List?) ?? [];
    final rooms = _selectedFarm?.rooms ?? [];
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.indigo.shade50, width: 2)), padding: const EdgeInsets.all(20),
      child: Column(children: [
        Row(children: [
          Expanded(child: _buildSimpleDropdown('Source', _simSourceRoom, rooms, (v) => setState(() => _simSourceRoom = v))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.swap_horiz_rounded, color: Colors.indigo, size: 28)),
          Expanded(child: _buildSimpleDropdown('Cible', _simTargetRoom, rooms, (v) => setState(() => _simTargetRoom = v))),
        ]),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _selectedClusterId, dropdownColor: Colors.white,
          decoration: InputDecoration(labelText: 'Groupe $_selectedSex à déplacer', prefixIcon: const Icon(Icons.groups_rounded, color: Colors.indigo, size: 20), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey.shade50),
          items: clusters.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text('${c['label']} (${c['count']} sujets)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)))).toList(),
          onChanged: (val) => setState(() => _selectedClusterId = val),
        ),
        const SizedBox(height: 20),
        SizedBox(width: double.infinity, height: 54, child: ElevatedButton.icon(onPressed: (_simSourceRoom != null && _simTargetRoom != null && _selectedClusterId != null && _simSourceRoom != _simTargetRoom) ? _runSimulation : null, icon: const Icon(Icons.rocket_launch_rounded, size: 20), label: const Text('SIMULER LES IMPACTS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)), style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0))),
      ]),
    );
  }

  Widget _buildSimpleDropdown(String label, String? value, List<String> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(value: value, dropdownColor: Colors.white, decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.indigo.shade300, fontSize: 11, fontWeight: FontWeight.w800), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), filled: true, fillColor: Colors.grey.shade50, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)), items: items.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))).toList(), onChanged: onChanged);
  }

  Widget _buildSimulationResults() {
    final source = _simulationResult!['source'];
    final target = _simulationResult!['target'];
    final moved = _simulationResult!['moved'];
    final range = (moved['range'] as List?) ?? [0, 0];
    return Column(children: [
      _buildMovedClusterCard(moved, range),
      const SizedBox(height: 20),
      _buildRoomImpactCard('SOURCE : ${source['room']}', source, _sourceHistory, true),
      const SizedBox(height: 20),
      _buildRoomImpactCard('CIBLE : ${target['room']}', target, _targetHistory, false),
      const SizedBox(height: 16),
      ElevatedButton.icon(
        icon: const Icon(Icons.fullscreen),
        label: const Text('DÉVELOPPER LES GRAPHIQUES'),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => FullscreenChartView(
            sourceHistory: _sourceHistory,
            targetHistory: _targetHistory,
            sourceBefore: (source['before']['homogeneity'] as num).toDouble(),
            sourceAfter: (source['after']['homogeneity'] as num).toDouble(),
            isSourcePositive: ((source['gain'] ?? 0) as num) >= 0,
            targetBefore: (target['before']['homogeneity'] as num).toDouble(),
            targetAfter: (target['after']['homogeneity'] as num).toDouble(),
            isTargetPositive: ((target['impact'] ?? 0) as num) >= 0,
          )));
        },
      ),
      const SizedBox(height: 24),
      Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('DISTRIBUTION THÉORIQUE APRÈS TRANSFERT', style: TextStyle(color: Colors.grey.shade500, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1)), const SizedBox(height: 20), _buildDistributionCurve(target['after']['weights'] as List)])),
    ]);
  }

  Widget _buildMovedClusterCard(Map<String, dynamic> moved, List range) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.indigo.shade600, Colors.indigo.shade800]), borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))]), child: Row(children: [Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.move_down_rounded, color: Colors.white, size: 24)), const SizedBox(width: 16), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Transfert de ${moved['count']} sujets (${moved['clusterLabel']})', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 15)), const SizedBox(height: 2), Text('Calibrage IA : ${range[0].toStringAsFixed(0)}g à ${range[1].toStringAsFixed(0)}g', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.8), fontWeight: FontWeight.w600))]))]));
  }

  Widget _buildRoomImpactCard(String title, Map<String, dynamic> data, List<dynamic> history, bool isSource) {
    final before = (data['before']['homogeneity'] as num).toDouble();
    final after = (data['after']['homogeneity'] as num).toDouble();
    final change = (isSource ? data['gain'] : data['impact']) as num;
    final isPositive = change >= 0;
    return Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.all(20), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 0.5)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: (isPositive ? Colors.green : Colors.red).withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text('${isPositive ? "+" : ""}${change.toStringAsFixed(2)}%', style: TextStyle(color: isPositive ? Colors.green.shade700 : Colors.red.shade700, fontWeight: FontWeight.w900, fontSize: 12)))]), const SizedBox(height: 20), Row(children: [_buildSimpleStat('ACTUEL', before, Colors.grey.shade400), const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Divider())), _buildSimpleStat('PRÉDIT', after, isPositive ? Colors.green.shade600 : Colors.red.shade600)]), const SizedBox(height: 24), Text('HISTORIQUE & PRÉDICTION D\'HOMOGÉNÉITÉ', style: TextStyle(color: Colors.grey.shade400, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 0.5)), const SizedBox(height: 12), _buildPredictionTrendChart(history, before, after, isPositive)]));
  }

  Widget _buildSimpleStat(String label, double value, Color color) {
    return Column(children: [Text(label, style: TextStyle(color: Colors.grey.shade400, fontSize: 9, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text('${value.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: color))]);
  }

  Widget _buildPredictionTrendChart(List<dynamic> history, double current, double predicted, bool isPositive) {
    print("DEBUG TREND CHART: history length = ${history.length}, history = $history");
    List<FlSpot> historicalSpots = (List.from(history)..sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])))).map((p) => FlSpot(DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble(), (p['homogeneity'] as num).toDouble())).toList();
    print("DEBUG TREND CHART: historicalSpots = $historicalSpots");
    
    double nowTime = historicalSpots.isNotEmpty ? historicalSpots.last.x : DateTime.now().millisecondsSinceEpoch.toDouble();
    double step = 24 * 60 * 60 * 1000.0; 
    double predictedTime = nowTime + step;
    double futureTime = predictedTime + step;
    List<FlSpot> predictiveSpots = [if (historicalSpots.isNotEmpty) historicalSpots.last else FlSpot(nowTime, current), FlSpot(predictedTime, predicted)];
    double futureProj = predicted + (predicted - current);
    if (futureProj > 100) futureProj = 100;
    if (futureProj < 0) futureProj = 0;
    List<FlSpot> futureSpots = [FlSpot(predictedTime, predicted), FlSpot(futureTime, futureProj)];
    double minX = historicalSpots.isNotEmpty ? historicalSpots.first.x : nowTime;
    double maxX = futureTime;
    double? bottomInterval;
    if (maxX > minX) bottomInterval = (maxX - minX) / 4.0;
    
    print("DEBUG TREND CHART: spotsCount = ${historicalSpots.length + predictiveSpots.length + futureSpots.length}");

    return SizedBox(height: 120, width: double.infinity, child: LineChart(LineChartData(
      minY: 0, maxY: 100, minX: minX, maxX: maxX,
      lineBarsData: [
        if (historicalSpots.isNotEmpty) LineChartBarData(spots: historicalSpots, isCurved: true, color: Colors.grey.shade300, barWidth: 3, dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 3, color: Colors.grey.shade400, strokeWidth: 1, strokeColor: Colors.white))), 
        LineChartBarData(spots: predictiveSpots, isCurved: false, color: isPositive ? Colors.green : Colors.red, barWidth: 4, dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: isPositive ? Colors.green : Colors.red, strokeWidth: 2, strokeColor: Colors.white))), 
        LineChartBarData(spots: futureSpots, isCurved: false, color: Colors.grey.withValues(alpha: 0.3), barWidth: 2, dashArray: [5, 5], dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 3, color: Colors.grey.shade300, strokeWidth: 1, strokeColor: Colors.white)))
      ],
      titlesData: FlTitlesData(leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: TextStyle(fontSize: 8, color: Colors.grey.shade300, fontWeight: FontWeight.bold)))), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, interval: bottomInterval, getTitlesWidget: (v, m) { if (v == predictedTime) return const Text('Prédit', style: TextStyle(fontSize: 8, color: Colors.grey, fontWeight: FontWeight.bold)); if (v == futureTime) return const Text('Futur', style: TextStyle(fontSize: 8, color: Colors.grey)); return Text(DateFormat('dd/MM').format(DateTime.fromMillisecondsSinceEpoch(v.toInt())), style: const TextStyle(fontSize: 8, color: Colors.grey)); })), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withValues(alpha: 0.05))), borderData: FlBorderData(show: false),
    )));
  }

  Widget _buildDistributionCurve(List weights) {
    if (weights.isEmpty) return const SizedBox();
    Map<int, int> freq = {};
    for (var w in weights) { int bucket = ((w as num).toInt() / 25).floor() * 25; freq[bucket] = (freq[bucket] ?? 0) + 1; }
    List<FlSpot> spots = (freq.keys.toList()..sort()).map((b) => FlSpot(b.toDouble(), freq[b]!.toDouble())).toList();
    return SizedBox(height: 150, width: double.infinity, child: LineChart(LineChartData(
      lineBarsData: [LineChartBarData(spots: spots, isCurved: true, color: Colors.indigo.shade600, barWidth: 3, dotData: const FlDotData(show: false), belowBarData: BarAreaData(show: true, color: Colors.indigo.withOpacity(0.1)))],
      titlesData: FlTitlesData(leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 4), child: Text('${v.toInt()}g', style: TextStyle(fontSize: 8, color: Colors.grey.shade400, fontWeight: FontWeight.bold))))), rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false))),
      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.03))), borderData: FlBorderData(show: false),
    )));
  }

  Widget _buildNoDataPrompt() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const SizedBox(height: 80), Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.indigo.withOpacity(0.05), blurRadius: 20)]), child: Icon(Icons.analytics_outlined, size: 70, color: Colors.indigo.shade200)), const SizedBox(height: 24), Text('PRÊT POUR L\'OPTIMISATION', style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.w900, fontSize: 18)), const SizedBox(height: 12), Text('Veuillez sélectionner une salle pour activer\nles prédictions et simulations IA.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500, fontSize: 14, fontWeight: FontWeight.w500))]));
  }

  Color _getClusterColor(int index) {
    final colors = [Colors.blue.shade400, Colors.orange.shade400, Colors.green.shade400, Colors.purple.shade400, Colors.red.shade400, Colors.teal.shade400, Colors.indigo.shade400, Colors.pink.shade400];
    return colors[index % colors.length];
  }
}
