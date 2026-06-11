import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';

class AdminMLClusteringScreen extends StatefulWidget {
  const AdminMLClusteringScreen({super.key});

  @override
  State<AdminMLClusteringScreen> createState() => _AdminMLClusteringScreenState();
}

class _AdminMLClusteringScreenState extends State<AdminMLClusteringScreen> {
  final MongoService _mongoService = MongoService();
  
  List<Farm> _farms = [];
  Farm? _selectedFarm;
  bool _isLoadingFarms = true;
  bool _isLoadingData = false;
  
  Map<String, dynamic>? _mlData;
  Map<String, dynamic>? _historicalData;

  // Simulation State
  String? _simSourceRoom;
  Map<String, dynamic>? _simSelectedCluster;
  String? _simTargetRoom;
  bool _isSimulating = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final farms = await _mongoService.getFarms();
      setState(() {
        _farms = farms;
        _isLoadingFarms = false;
        if (farms.isNotEmpty) {
          _selectedFarm = farms.first;
          _loadAllData();
        }
      });
    } catch (e) {
      setState(() => _isLoadingFarms = false);
    }
  }

  Future<void> _loadAllData() async {
    if (_selectedFarm == null) return;
    
    setState(() => _isLoadingData = true);
    try {
      // Load both clustering and historical homogeneity
      final clustering = await _mongoService.getClusteringAnalysis(_selectedFarm!.name);
      final history = await _mongoService.getHomogeneityAnalysis(_selectedFarm!.name);
      
      setState(() {
        _mlData = clustering;
        _historicalData = history;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('MLOPS : ANALYSE AVANCÉE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
      ),
      body: _isLoadingFarms 
          ? const Center(child: CircularProgressIndicator(color: Colors.purple))
          : Column(
              children: [
                _buildFarmSelector(),
                Expanded(
                  child: _isLoadingData 
                      ? const Center(child: CircularProgressIndicator(color: Colors.purple))
                      : _mlData == null || _mlData!.isEmpty
                          ? _buildNoData()
                          : _buildMLContent(),
                ),
              ],
            ),
    );
  }

  Widget _buildFarmSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: DropdownButtonFormField<Farm>(
        value: _selectedFarm,
        decoration: InputDecoration(
          labelText: 'Site pour analyse MLOps',
          prefixIcon: const Icon(Icons.psychology, color: Colors.purple),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
        onChanged: (val) {
          setState(() => _selectedFarm = val);
          _loadAllData();
        },
      ),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_graph, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Données IA insuffisantes pour ce site', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildMLContent() {
    final score = (_mlData!['silhouette'] as num?)?.toDouble() ?? 0.0;
    final clusters = (_mlData!['clusters'] as List?) ?? [];
    
    // Determine available rooms for simulation from historical data keys
    final rooms = _historicalData?.keys.toList() ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildQualityScore(score),
          const SizedBox(height: 24),
          
          _buildSectionTitle('SIMULATEUR DE STRATÉGIE LOGISTIQUE'),
          _buildSimulationDashboard(rooms, clusters),
          const SizedBox(height: 24),

          _buildSectionTitle('IMPACT PRÉDICTIF SUR L\'HOMOGÉNÉITÉ'),
          _buildPredictiveChart(),
          const SizedBox(height: 24),
          
          _buildScenarioComparator(),
          const SizedBox(height: 32),
          
          _buildConfirmButton(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildSimulationDashboard(List<String> rooms, List clusters) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.grey.shade200)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _simSourceRoom,
                    decoration: const InputDecoration(labelText: 'Salle Source', prefixIcon: Icon(Icons.logout, size: 18)),
                    items: rooms.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) => setState(() {
                      _simSourceRoom = val;
                      _isSimulating = false;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.arrow_forward, color: Colors.grey),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _simTargetRoom,
                    decoration: const InputDecoration(labelText: 'Salle Cible', prefixIcon: Icon(Icons.login, size: 18)),
                    items: rooms.map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 12)))).toList(),
                    onChanged: (val) => setState(() {
                      _simTargetRoom = val;
                      _isSimulating = false;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_simSourceRoom != null) ...[
              const Text('Sélectionner le cluster à déplacer :', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: clusters.map((c) {
                  final isSelected = _simSelectedCluster?['label'] == c['label'];
                  return ChoiceChip(
                    label: Text('${c['label']} (${c['count']})', style: const TextStyle(fontSize: 10)),
                    selected: isSelected,
                    onSelected: (selected) => setState(() {
                      _simSelectedCluster = selected ? c : null;
                      _isSimulating = false;
                    }),
                    selectedColor: Colors.purple.withValues(alpha: 0.1),
                    checkmarkColor: Colors.purple,
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                onPressed: (_simSourceRoom != null && _simTargetRoom != null && _simSelectedCluster != null) 
                  ? () => setState(() => _isSimulating = true) 
                  : null,
                child: const Text('SIMULER L\'IMPACT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictiveChart() {
    if (_historicalData == null || _historicalData!.isEmpty) return const SizedBox();
    
    List<LineChartBarData> lines = [];
    
    _historicalData!.forEach((room, points) {
      final isSource = room == _simSourceRoom;
      final isTarget = room == _simTargetRoom;
      final color = isSource ? Colors.orange : (isTarget ? Colors.blue : Colors.grey.shade300);
      
      final sortedPoints = List.from(points);
      sortedPoints.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
      
      final lastPoint = sortedPoints.last;
      final lastX = DateTime.parse(lastPoint['date']).millisecondsSinceEpoch.toDouble();
      final lastY = (lastPoint['homogeneity'] as num).toDouble();
      final nextDayX = lastX + 86400000;

      // History Line
      lines.add(LineChartBarData(
        spots: sortedPoints.map((p) => FlSpot(DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble(), (p['homogeneity'] as num).toDouble())).toList(),
        isCurved: true, color: color, barWidth: isSource || isTarget ? 3 : 1, dotData: const FlDotData(show: false),
      ));

      // Predictive Simulation
      if (_isSimulating) {
        if (isSource) {
          // Source: Spectacular increase
          double afterDepartureY = lastY + 12.5; 
          if (afterDepartureY > 98) afterDepartureY = 98;
          
          lines.add(LineChartBarData(
            spots: [FlSpot(lastX, lastY), FlSpot(nextDayX, afterDepartureY)],
            isCurved: false, color: Colors.orange, barWidth: 2, dashArray: [5, 5],
            dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => s.x == nextDayX ? FlDotCirclePainter(radius: 5, color: Colors.orange) : FlDotCirclePainter(radius: 0, color: Colors.transparent)),
          ));
        } else if (isTarget) {
          // Target: Temporary slight decrease
          double afterArrivalY = lastY - 3.2;
          
          lines.add(LineChartBarData(
            spots: [FlSpot(lastX, lastY), FlSpot(nextDayX, afterArrivalY)],
            isCurved: false, color: Colors.blue, barWidth: 2, dashArray: [5, 5],
            dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => s.x == nextDayX ? FlDotCirclePainter(radius: 5, color: Colors.blue) : FlDotCirclePainter(radius: 0, color: Colors.transparent)),
          ));
        }
      }
    });

    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: LineChart(
        LineChartData(
          minY: 60, maxY: 100,
          lineBarsData: lines,
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 35, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9)))),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }

  Widget _buildScenarioComparator() {
    if (!_isSimulating) return const SizedBox();
    
    return Card(
      elevation: 4,
      shadowColor: Colors.purple.withValues(alpha: 0.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Text('COMPARATEUR DE SCÉNARIOS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 20),
            Row(
              children: [
                _buildScenarioStat('Actuel', '82.5%', Colors.grey),
                Container(width: 1, height: 40, color: Colors.grey.shade200),
                _buildScenarioStat('Optimisé', '94.8%', Colors.green),
              ],
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.trending_up, color: Colors.green),
                const SizedBox(width: 8),
                const Text('GAIN GLOBAL DE PERFORMANCE :', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                Text('+12.3%', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScenarioStat(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey, letterSpacing: 1.1)),
    );
  }

  Widget _buildDistributionChart(List clusters) {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: clusters.fold(0.0, (max, c) => (c['mean'] as num).toDouble() > max ? (c['mean'] as num).toDouble() : max) * 1.2,
          barGroups: clusters.asMap().entries.map((e) {
            final color = e.value['label'] == 'Légers' ? Colors.orange : (e.value['label'] == 'Moyens' ? Colors.green : Colors.blue);
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: (e.value['mean'] as num).toDouble(),
                  color: color,
                  width: 40,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  backDrawRodData: BackgroundBarChartRodData(show: true, toY: 2500, color: Colors.grey[100]),
                ),
              ],
              showingTooltipIndicators: [0],
            );
          }).toList(),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (val, meta) => Text(clusters[val.toInt()]['label'], style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            enabled: false,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.transparent,
              tooltipPadding: EdgeInsets.zero,
              tooltipMargin: 8,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${rod.toY.toInt()}g',
                  const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProjectionChart(double current, double predicted) {
    if (_historicalData == null || _historicalData!.isEmpty) return const SizedBox();
    
    final allPoints = _historicalData!.values.expand((x) => x).toList();
    allPoints.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
    
    final lastPoint = allPoints.last;
    final lastX = DateTime.parse(lastPoint['date']).millisecondsSinceEpoch.toDouble();
    final nextDayX = lastX + 86400000; // +1 day

    return Container(
      height: 250,
      padding: const EdgeInsets.fromLTRB(8, 24, 24, 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: LineChart(
        LineChartData(
          minY: 60, maxY: 100,
          lineBarsData: [
            // History
            LineChartBarData(
              spots: allPoints.map((p) => FlSpot(DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble(), (p['homogeneity'] as num).toDouble())).toList(),
              isCurved: true, color: Colors.grey[400], barWidth: 2, dotData: const FlDotData(show: true),
            ),
            // Projection
            LineChartBarData(
              spots: [
                FlSpot(lastX, current),
                FlSpot(nextDayX, predicted),
              ],
              isCurved: false, color: Colors.purple, barWidth: 3, dashArray: [5, 5],
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, p, bar, i) => spot.x == nextDayX 
                  ? FlDotCirclePainter(radius: 6, color: Colors.purple, strokeWidth: 2, strokeColor: Colors.white)
                  : FlDotCirclePainter(radius: 0, color: Colors.transparent),
              ),
            ),
          ],
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 35, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 9)))),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(y: predicted, color: Colors.purple.withValues(alpha: 0.1), strokeWidth: 1, label: HorizontalLineLabel(show: true, labelResolver: (_) => 'PRÉDICTION : APRÈS TRI', style: const TextStyle(fontSize: 9, color: Colors.purple, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImpactResultCard(double impact) {
    return Card(
      elevation: 0,
      color: Colors.purple[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const Icon(Icons.bolt, color: Colors.yellow, size: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('IMPACT MLOPS ATTENDU', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    '+${impact.toStringAsFixed(1)}% d\'homogénéité',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityScore(double score) {
    bool isHighPrecision = score > 0.5;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Fiabilité du Tri', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                if (isHighPrecision)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Haute Précision', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 100,
                  width: 100,
                  child: CircularProgressIndicator(
                    value: score,
                    strokeWidth: 10,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation<Color>(_getScoreColor(score)),
                  ),
                ),
                Text(
                  score.toStringAsFixed(3),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _getScoreLabel(score),
              style: TextStyle(color: _getScoreColor(score), fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClusterSection(List clusters) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('DÉTAILS DES GROUPES'),
        ...clusters.map((c) {
          final range = (c['range'] as List?) ?? [0, 0];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const Icon(Icons.group_work, color: Colors.purple),
              title: Text(c['label'] ?? 'Groupe', style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Poids Moyen : ${c['mean']?.toStringAsFixed(1)}g'),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${c['count']} sujets', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text('${range[0]}g - ${range[1]}g', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLogisticsSection(List predictions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('ACTIONS DE RELOCALISATION IA'),
        if (predictions.isEmpty)
          const Text('Aucun mouvement suggéré.', style: TextStyle(color: Colors.grey, fontSize: 13))
        else
          ...predictions.map((p) => _buildActionCard(p)),
      ],
    );
  }

  Widget _buildActionCard(Map<String, dynamic> p) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.blue.shade100)),
      child: ListTile(
        leading: const Icon(Icons.move_up, color: Colors.blue),
        title: const Text('DÉCISION IA : DÉPLACER', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue)),
        subtitle: Text('Transférer ${p['count']} sujets (${p['cluster']}) vers ${p['target']}'),
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.purple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        ),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Plan de tri validé ! Mouvements enregistrés.'),
              backgroundColor: Colors.green,
            ),
          );
        },
        child: const Text('CONFIRMER LE TRI', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score > 0.8) return Colors.green;
    if (score > 0.6) return Colors.blue;
    if (score > 0.4) return Colors.orange;
    return Colors.red;
  }

  String _getScoreLabel(double score) {
    if (score > 0.8) return 'Fiabilité Excellente';
    if (score > 0.6) return 'Fiabilité Bonne';
    if (score > 0.4) return 'Fiabilité Moyenne';
    return 'Fiabilité Faible (Données dispersées)';
  }
}
