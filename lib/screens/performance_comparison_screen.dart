import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/weight_standard.dart';
import '../models/weight_history_entry.dart';
import '../services/mongo_service.dart';
import 'fullscreen_performance_view.dart';

class PerformanceComparisonScreen extends StatefulWidget {
  final String farmName;
  final String roomName;
  final String sex;
  final String? lotNumber;

  const PerformanceComparisonScreen({
    super.key,
    required this.farmName,
    required this.roomName,
    required this.sex,
    this.lotNumber,
  });

  @override
  State<PerformanceComparisonScreen> createState() => _PerformanceComparisonScreenState();
}

class _PerformanceComparisonScreenState extends State<PerformanceComparisonScreen> {
  final MongoService _mongoService = MongoService();
  List<WeightStandard> _standards = [];
  List<WeightHistoryEntry> _realHistory = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _mongoService.getWeightStandards(widget.sex),
        _mongoService.getWeightEvolution(
          farmName: widget.farmName,
          roomName: widget.roomName,
          sex: widget.sex,
          lotNumber: widget.lotNumber,
        ),
      ]);

      setState(() {
        _standards = results[0] as List<WeightStandard>;
        _realHistory = results[1] as List<WeightHistoryEntry>;
        _standards.sort((a, b) => a.week.compareTo(b.week));
        _realHistory.sort((a, b) => a.week.compareTo(b.week));
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = "Erreur de chargement des données: $e";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('SUIVI DE PERFORMANCE', 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 0.5)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo.shade900,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : _errorMessage != null
              ? _buildErrorView()
              : _buildContentView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: _fetchData, child: const Text('Réessayer')),
        ],
      ),
    );
  }

  Widget _buildContentView() {
    if (_realHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            const Text('Aucun historique de pesée pour ce lot', 
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoSummary(),
          const SizedBox(height: 24),
          _buildAnalysisBadge(),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('GRAPHIQUE DE PERFORMANCE', 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenPerformanceView(
                    standards: _standards,
                    realHistory: _realHistory,
                    title: 'Performance: ${widget.lotNumber ?? widget.roomName}',
                  )));
                },
                icon: const Icon(Icons.fullscreen, size: 18),
                label: const Text('DÉVELOPPER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  backgroundColor: Colors.indigo.withOpacity(0.05),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildChartContainer(),
          const SizedBox(height: 24),
          _buildLegend(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildInfoSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildSummaryItem('Sexe', widget.sex, widget.sex == 'Mâle' ? Colors.blue : Colors.pink),
          _buildSummaryItem('Bâtiment', widget.roomName, Colors.indigo),
          if (widget.lotNumber != null) _buildSummaryItem('Lot', widget.lotNumber!, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: color)),
      ],
    );
  }

  Widget _buildAnalysisBadge() {
    if (_realHistory.isEmpty || _standards.isEmpty) return const SizedBox();
    
    final lastReal = _realHistory.last;
    final standardAtLastWeek = _standards.firstWhere(
      (s) => s.week == lastReal.week, 
      orElse: () => _standards.last
    );

    String status = "DANS LES STANDARDS";
    Color color = Colors.green;
    IconData icon = Icons.check_circle_outline;

    if (lastReal.averageWeight < standardAtLastWeek.minWeight) {
      status = "SOUS-POIDS";
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
    } else if (lastReal.averageWeight > standardAtLastWeek.maxWeight) {
      status = "SUR-POIDS";
      color = Colors.purple;
      icon = Icons.trending_up_rounded;
    }

    final diff = ((lastReal.averageWeight - standardAtLastWeek.weight) / standardAtLastWeek.weight * 100).toStringAsFixed(1);
    final diffPrefix = double.parse(diff) >= 0 ? "+" : "";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 13)),
                Text('Écart par rapport à l\'idéal : $diffPrefix$diff%', 
                  style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
              ],
            ),
          ),
          Text('${lastReal.averageWeight.toStringAsFixed(0)}g', 
            style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildChartContainer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 32, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: _buildChart(),
      ),
    );
  }

  Widget _buildChart() {
    if (_standards.isEmpty && _realHistory.isEmpty) return const SizedBox();

    // Mapping spots
    final minSpots = _standards.map((s) => FlSpot(s.week.toDouble(), s.minWeight)).toList();
    final maxSpots = _standards.map((s) => FlSpot(s.week.toDouble(), s.maxWeight)).toList();
    final realSpots = _realHistory.map((h) => FlSpot(h.week.toDouble(), h.averageWeight)).toList();

    // Determine max values for axes
    double maxWeek = 0;
    if (_standards.isNotEmpty) maxWeek = _standards.last.week.toDouble();
    if (_realHistory.isNotEmpty && _realHistory.last.week > maxWeek) {
      maxWeek = _realHistory.last.week.toDouble();
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 500,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
        ),
        titlesData: _buildTitles(),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          // barIndex 0: Min Standard (Transparent)
          LineChartBarData(
            spots: minSpots,
            isCurved: true,
            color: Colors.transparent,
            dotData: const FlDotData(show: false),
          ),
          // barIndex 1: Max Standard (Transparent)
          LineChartBarData(
            spots: maxSpots,
            isCurved: true,
            color: Colors.transparent,
            dotData: const FlDotData(show: false),
          ),
          // barIndex 2: Actual Data (Visible)
          LineChartBarData(
            spots: realSpots,
            isCurved: true,
            color: Colors.indigo,
            barWidth: 4,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                bool isLast = index == realSpots.length - 1;
                if (isLast) {
                  final week = spot.x.toInt();
                  final standard = _standards.firstWhere((s) => s.week == week, orElse: () => _standards.last);
                  
                  Color dotColor = Colors.green; // Conforme
                  if (spot.y < standard.minWeight) {
                    dotColor = Colors.red; // Sous-poids
                  } else if (spot.y > standard.maxWeight) {
                    dotColor = Colors.orange; // Sur-poids
                  }

                  return FlDotCirclePainter(
                    radius: 7,
                    color: dotColor,
                    strokeWidth: 3,
                    strokeColor: Colors.white,
                  );
                }
                return FlDotCirclePainter(
                  radius: 4,
                  color: Colors.indigo,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                );
              },
            ),
            belowBarData: BarAreaData(show: false),
          ),
        ],
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 0,
            toIndex: 1,
            color: Colors.green.withOpacity(0.2), // Soft green zone
          ),
        ],
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => Colors.indigo.shade900,
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                if (spot.barIndex != 2) return null; // Show only for actual data
                
                final week = spot.x.toInt();
                final real = _realHistory.firstWhere((h) => h.week == week, orElse: () => _realHistory.first);
                final standard = _standards.firstWhere((s) => s.week == week, orElse: () => _standards.first);
                
                return LineTooltipItem(
                  'Semaine $week\n',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  children: [
                    TextSpan(
                      text: 'Réel: ${real.averageWeight.toStringAsFixed(1)}g\n',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
                    ),
                    TextSpan(
                      text: 'Intervalle: ${standard.minWeight.toStringAsFixed(0)}-${standard.maxWeight.toStringAsFixed(0)}g',
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontWeight: FontWeight.normal, fontSize: 11),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
        minY: 0,
        minX: 0,
        maxX: maxWeek + 0.5,
      ),
    );
  }

  FlTitlesData _buildTitles() {
    return FlTitlesData(
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: 2,
          getTitlesWidget: (value, meta) {
            if (value % 1 != 0 || value < 0) return const SizedBox();
            return SideTitleWidget(
              meta: meta,
              space: 10,
              child: Text('S${value.toInt()}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 45,
          interval: 1000,
          getTitlesWidget: (value, meta) {
            return SideTitleWidget(
              meta: meta,
              child: Text('${value.toInt()}g',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildLegendItem('Performance Réelle', Colors.indigo, isLine: true),
              const Spacer(),
              _buildLegendItem('Idéal Théorique', Colors.grey.shade400, isDotted: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildLegendItem('Plage de Tolérance', Colors.greenAccent.withOpacity(0.3), isBox: true),
              const Spacer(),
              _buildLegendItem('Point Actuel', Colors.red, isDot: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, {bool isLine = false, bool isDotted = false, bool isBox = false, bool isDot = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isLine) Container(width: 16, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        if (isDotted) Row(children: List.generate(3, (i) => Container(width: 4, height: 2, margin: const EdgeInsets.symmetric(horizontal: 1), color: color))),
        if (isBox) Container(width: 16, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        if (isDot) Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
      ],
    );
  }
}
