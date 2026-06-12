import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../services/mongo_service.dart';
import '../models/farm.dart';

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
  
  // Selection state
  List<Farm> _farms = [];
  Farm? _selectedFarm;
  String? _selectedWeighingId;
  
  // Simulation params
  String? _sourceRoom;
  String? _targetRoom;
  int? _selectedClusterId;

  @override
  void initState() {
    super.initState();
    _selectedWeighingId = widget.initialWeighingId;
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      _farms = await _mongoService.getFarms();
      if (_farms.isNotEmpty) {
        // Find farm if we have a weighingId that might be linked to it
        // For now, default to first farm
        _selectedFarm = _farms.first;
      }
      
      if (_selectedWeighingId != null) {
        await _fetchClusteringData();
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchClusteringData() async {
    if (_selectedWeighingId == null) return;
    setState(() => _isLoading = true);
    try {
      final data = await _mongoService.getPredictiveClustering(_selectedWeighingId!);
      setState(() {
        _clusteringData = data;
        _isLoading = false;
        // Reset simulation if weighing changes
        _simulationResult = null;
        _selectedClusterId = null;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _runSimulation() async {
    if (_selectedFarm == null || _sourceRoom == null || _targetRoom == null || _selectedClusterId == null) return;
    
    setState(() => _isLoading = true);
    try {
      final result = await _mongoService.simulateMove(
        farmName: _selectedFarm!.name,
        sourceRoom: _sourceRoom!,
        targetRoom: _targetRoom!,
        clusterId: _selectedClusterId!,
      );
      setState(() {
        _simulationResult = result;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Analyse Prédictive & IA', style: TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading && _farms.isEmpty
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSelectors(),
                  const SizedBox(height: 20),
                  if (_clusteringData != null) ...[
                    _buildClusteringDashboard(),
                    const SizedBox(height: 24),
                    _buildTrendAnalysis(),
                    const SizedBox(height: 24),
                    _buildSimulatorInterface(),
                    if (_simulationResult != null) ...[
                      const SizedBox(height: 24),
                      _buildSimulationResults(),
                    ],
                    const SizedBox(height: 40),
                  ] else if (!_isLoading)
                    _buildNoDataPrompt(),
                ],
              ),
            ),
    );
  }

  Widget _buildSelectors() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            DropdownButtonFormField<Farm>(
              value: _selectedFarm,
              decoration: const InputDecoration(labelText: 'Sélectionner une ferme', prefixIcon: Icon(Icons.location_on, color: Colors.indigo)),
              items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedFarm = val;
                  _sourceRoom = null;
                  _targetRoom = null;
                  _simulationResult = null;
                });
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              initialValue: _selectedWeighingId,
              decoration: const InputDecoration(
                labelText: 'ID de la Pesée',
                prefixIcon: Icon(Icons.numbers, color: Colors.indigo),
                hintText: 'Entrez l\'ID pour analyse',
              ),
              onChanged: (val) => _selectedWeighingId = val,
              onFieldSubmitted: (_) => _fetchClusteringData(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _fetchClusteringData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('LANCER L\'ANALYSE IA', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClusteringDashboard() {
    final silhouette = (_clusteringData!['silhouette'] as num?)?.toDouble() ?? 0.0;
    final homogeneity = (_clusteringData!['currentHomogeneity'] as num?)?.toDouble() ?? 0.0;
    final clusters = (_clusteringData!['clusters'] as List?) ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildStatCard('Homogénéité Actuelle', '${homogeneity.toStringAsFixed(1)}%', Icons.analytics, Colors.blue)),
            const SizedBox(width: 12),
            Expanded(child: _buildSilhouetteScore(silhouette)),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Distribution des Poids par Cluster', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildWeightHistogram(clusters),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          ],
        ),
      ),
    );
  }

  Widget _buildSilhouetteScore(double score) {
    Color color = Colors.red;
    String label = 'Médiocre';
    if (score > 0.5) {
      color = Colors.green;
      label = 'Bon';
    } else if (score > 0.25) {
      color = Colors.orange;
      label = 'Moyen';
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.purple.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.psychology, color: Colors.purple, size: 20),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Score Silhouette', style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Text(score.toStringAsFixed(3), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightHistogram(List clusters) {
    List<BarChartGroupData> groups = [];
    
    for (int i = 0; i < clusters.length; i++) {
      final c = clusters[i];
      final weights = (c['weights'] as List?) ?? [];
      
      groups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: weights.length.toDouble(),
              color: _getClusterColor(i),
              width: 32,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            )
          ],
          showingTooltipIndicators: [0],
        ),
      );
    }

    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: groups.isEmpty ? 10 : groups.fold(0.0, (max, g) => g.barRods[0].toY > max ? g.barRods[0].toY : max) * 1.3,
          barGroups: groups,
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) {
                  if (val.toInt() < clusters.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(clusters[val.toInt()]['label'] ?? '', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => Colors.indigo.withOpacity(0.9),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final cluster = clusters[groupIndex];
                return BarTooltipItem(
                  '${cluster['label']}\n${rod.toY.toInt()} sujets\n${cluster['mean'].toStringAsFixed(1)}g',
                  const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrendAnalysis() {
    final regressionData = (_clusteringData!['regressionData'] as List?) ?? [];
    if (regressionData.isEmpty) return const SizedBox();

    regressionData.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));

    List<FlSpot> spots = [];
    for (int i = 0; i < regressionData.length; i++) {
      spots.add(FlSpot(i.toDouble(), (regressionData[i]['homogeneity'] as num).toDouble()));
    }

    final n = spots.length;
    double m = 0, b = 0;
    if (n > 1) {
      double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;
      for (var s in spots) {
        sumX += s.x;
        sumY += s.y;
        sumXY += s.x * s.y;
        sumX2 += s.x * s.x;
      }
      m = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      b = (sumY - m * sumX) / n;
    }

    List<FlSpot> trendSpots = [
      FlSpot(0, b),
      FlSpot((n - 1).toDouble(), m * (n - 1) + b),
    ];

    bool improving = m >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Tendance de l\'Homogénéité', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: (improving ? Colors.green : Colors.red).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Icon(improving ? Icons.trending_up : Icons.trending_down, color: improving ? Colors.green : Colors.red, size: 16),
                  const SizedBox(width: 6),
                  Text(improving ? 'Amélioration' : 'Dégradation', style: TextStyle(color: improving ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          height: 220,
          padding: const EdgeInsets.fromLTRB(12, 16, 24, 12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
          child: LineChart(
            LineChartData(
              minY: 60, maxY: 100,
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: Colors.indigo,
                  barWidth: 4,
                  dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: Colors.indigo, strokeWidth: 2, strokeColor: Colors.white)),
                  belowBarData: BarAreaData(show: true, color: Colors.indigo.withOpacity(0.05)),
                ),
                if (n > 1)
                  LineChartBarData(
                    spots: trendSpots,
                    isCurved: false,
                    color: Colors.grey.withOpacity(0.4),
                    barWidth: 2,
                    dashArray: [5, 5],
                    dotData: const FlDotData(show: false),
                  ),
              ],
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 35, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 10, color: Colors.grey)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) {
                  if (v.toInt() < regressionData.length && v.toInt() >= 0) {
                    final date = DateTime.parse(regressionData[v.toInt()]['date']);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 9, color: Colors.grey)),
                    );
                  }
                  return const SizedBox();
                })),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.1), strokeWidth: 1)),
              borderData: FlBorderData(show: false),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimulatorInterface() {
    final clusters = (_clusteringData!['clusters'] as List?) ?? [];
    final rooms = _selectedFarm?.rooms ?? [];
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Simulateur de Transfert Stratégique', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.indigo.withOpacity(0.2))),
          color: Colors.indigo.withOpacity(0.02),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sourceRoom,
                        decoration: const InputDecoration(labelText: 'Source', prefixIcon: Icon(Icons.outbound, size: 20)),
                        items: rooms.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) => setState(() => _sourceRoom = val),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(Icons.arrow_forward, color: Colors.indigo, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _targetRoom,
                        decoration: const InputDecoration(labelText: 'Cible', prefixIcon: Icon(Icons.login, size: 20)),
                        items: rooms.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)))).toList(),
                        onChanged: (val) => setState(() => _targetRoom = val),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedClusterId,
                  decoration: const InputDecoration(labelText: 'Cluster à déplacer', prefixIcon: Icon(Icons.groups, size: 20)),
                  items: clusters.map((c) => DropdownMenuItem<int>(value: c['id'], child: Text('${c['label']} (${c['count']} sujets)', style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) => setState(() => _selectedClusterId = val),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (_sourceRoom != null && _targetRoom != null && _selectedClusterId != null && _sourceRoom != _targetRoom) ? _runSimulation : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                    ),
                    child: const Text('LANCER LA SIMULATION', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSimulationResults() {
    final source = _simulationResult!['source'];
    final target = _simulationResult!['target'];
    final moved = _simulationResult!['moved'];
    final range = (moved['range'] as List?) ?? [0, 0];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Résultats de la Simulation IA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        _buildMovedClusterCard(moved, range),
        const SizedBox(height: 16),
        _buildRoomImpactCard('Source : ${source['room']}', source, true),
        const SizedBox(height: 12),
        _buildRoomImpactCard('Cible : ${target['room']}', target, false),
        const SizedBox(height: 24),
        const Text('Nouvelle Distribution Théorique (Cible)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 12),
        _buildDistributionCurve(target['after']['weights'] as List),
      ],
    );
  }

  Widget _buildMovedClusterCard(Map<String, dynamic> moved, List range) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.indigo.withOpacity(0.1))),
      child: Row(
        children: [
          const Icon(Icons.move_to_inbox, color: Colors.indigo),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Transfert : ${moved['clusterLabel']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                Text('${moved['count']} sujets | Intervalle : ${range[0].toStringAsFixed(1)}g - ${range[1].toStringAsFixed(1)}g', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomImpactCard(String title, Map<String, dynamic> data, bool isSource) {
    final before = (data['before']['homogeneity'] as num).toDouble();
    final after = (data['after']['homogeneity'] as num).toDouble();
    final change = (isSource ? data['gain'] : data['impact']) as num;
    final isPositive = change >= 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: (isPositive ? Colors.green : Colors.orange).withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '${isPositive ? "+" : ""}${change.toStringAsFixed(2)}%',
                    style: TextStyle(color: isPositive ? Colors.green : Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildBeforeAfterStat('Avant', before)),
                const Icon(Icons.arrow_forward, color: Colors.grey, size: 16),
                Expanded(child: _buildBeforeAfterStat('Après', after, color: isPositive ? Colors.green : Colors.orange)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBeforeAfterStat(String label, double value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('${value.toStringAsFixed(1)}%', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: color)),
      ],
    );
  }

  Widget _buildDistributionCurve(List weights) {
    if (weights.isEmpty) return const SizedBox();
    
    Map<int, int> freq = {};
    for (var w in weights) {
      int bucket = ((w as num).toInt() / 25).floor() * 25; // Finer precision
      freq[bucket] = (freq[bucket] ?? 0) + 1;
    }
    
    var sortedBuckets = freq.keys.toList()..sort();
    List<FlSpot> spots = sortedBuckets.map((b) => FlSpot(b.toDouble(), freq[b]!.toDouble())).toList();

    return Container(
      height: 160,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.indigo,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: Colors.indigo.withOpacity(0.1)),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, getTitlesWidget: (v, m) => Padding(padding: const EdgeInsets.only(top: 4), child: Text('${v.toInt()}g', style: const TextStyle(fontSize: 8, color: Colors.grey))))),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 5, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1)),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _buildNoDataPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 60),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.05), shape: BoxShape.circle),
            child: Icon(Icons.query_stats, size: 64, color: Colors.indigo.withOpacity(0.4)),
          ),
          const SizedBox(height: 20),
          const Text('Prêt pour l\'analyse prédictive', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('Sélectionnez une pesée pour que l\'IA calcule\nles optimisations et simulations.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Color _getClusterColor(int index) {
    final colors = [Colors.blue, Colors.orange, Colors.green, Colors.purple, Colors.red, Colors.teal, Colors.indigo, Colors.pink];
    return colors[index % colors.length];
  }
}
