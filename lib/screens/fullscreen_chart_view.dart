import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class FullscreenChartView extends StatefulWidget {
  final List<dynamic> sourceHistory;
  final List<dynamic> targetHistory;
  final double sourceBefore;
  final double sourceAfter;
  final bool isSourcePositive;
  final double targetBefore;
  final double targetAfter;
  final bool isTargetPositive;

  const FullscreenChartView({
    super.key,
    required this.sourceHistory,
    required this.targetHistory,
    required this.sourceBefore,
    required this.sourceAfter,
    required this.isSourcePositive,
    required this.targetBefore,
    required this.targetAfter,
    required this.isTargetPositive,
  });

  @override
  State<FullscreenChartView> createState() => _FullscreenChartViewState();
}

class _FullscreenChartViewState extends State<FullscreenChartView> {
  int _currentIndex = 0;
  bool _showProjected = false;
  bool _showCurve = true;
  bool _showRegression = true;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final charts = [
      {'title': 'SOURCE', 'history': widget.sourceHistory, 'before': widget.sourceBefore, 'after': widget.sourceAfter, 'positive': widget.isSourcePositive},
      {'title': 'CIBLE', 'history': widget.targetHistory, 'before': widget.targetBefore, 'after': widget.targetAfter, 'positive': widget.isTargetPositive},
    ];

    final currentChart = charts[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Vue détaillée : ${currentChart['title']}', style: const TextStyle(color: Colors.indigo)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          _buildActionButton(Icons.auto_graph, _showProjected ? 'Mode Actuel' : 'Mode Projeté', () => setState(() => _showProjected = !_showProjected)),
          _buildActionButton(_showCurve ? Icons.show_chart : Icons.hide_source, 'Ligne', () => setState(() => _showCurve = !_showCurve)),
          _buildActionButton(_showRegression ? Icons.trending_up : Icons.trending_flat, 'Régression', () => setState(() => _showRegression = !_showRegression)),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.indigo),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: _currentIndex > 0 ? () => setState(() => _currentIndex--) : null),
          Expanded(
            child: _buildChart(
              currentChart['title'] as String,
              currentChart['history'] as List<dynamic>,
              currentChart['before'] as double,
              currentChart['after'] as double,
              currentChart['positive'] as bool,
            ),
          ),
          IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: _currentIndex < charts.length - 1 ? () => setState(() => _currentIndex++) : null),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: TextButton.icon(
        icon: Icon(icon, color: Colors.indigo, size: 18),
        label: Text(label, style: const TextStyle(color: Colors.indigo, fontSize: 12, fontWeight: FontWeight.bold)),
        onPressed: onPressed,
        style: TextButton.styleFrom(backgroundColor: Colors.indigo.shade50),
      ),
    );
  }

  Widget _buildChart(String title, List<dynamic> history, double current, double predicted, bool isPositive) {
    List<FlSpot> historicalSpots = (List.from(history)..sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])))).map((p) => FlSpot(DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble(), (p['homogeneity'] as num).toDouble())).toList();
    
    double nowTime = historicalSpots.isNotEmpty ? historicalSpots.last.x : DateTime.now().millisecondsSinceEpoch.toDouble();
    double step = 24 * 60 * 60 * 1000.0;
    double predictedTime = nowTime + step;
    
    List<FlSpot> displaySpots = List.from(historicalSpots);
    if (_showProjected && displaySpots.isNotEmpty) {
      displaySpots.removeLast();
      displaySpots.add(FlSpot(nowTime, predicted));
    }

    // Linear Regression Calculation
    List<FlSpot> regressionSpots = [];
    if (_showRegression && displaySpots.length > 1) {
      double n = displaySpots.length.toDouble();
      double sumX = displaySpots.fold(0.0, (sum, spot) => sum + spot.x);
      double sumY = displaySpots.fold(0.0, (sum, spot) => sum + spot.y);
      double sumXY = displaySpots.fold(0.0, (sum, spot) => sum + (spot.x * spot.y));
      double sumX2 = displaySpots.fold(0.0, (sum, spot) => sum + (spot.x * spot.x));
      
      double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      double intercept = (sumY - slope * sumX) / n;
      
      regressionSpots = [
        FlSpot(displaySpots.first.x, slope * displaySpots.first.x + intercept),
        FlSpot(displaySpots.last.x, slope * displaySpots.last.x + intercept),
      ];
    }
    
    double minX = displaySpots.isNotEmpty ? displaySpots.first.x : nowTime;
    double maxX = predictedTime;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Expanded(
            child: LineChart(LineChartData(
              minY: 0, maxY: 100, minX: minX, maxX: maxX,
              lineBarsData: [
                if (_showCurve) LineChartBarData(spots: displaySpots, isCurved: true, color: _showProjected ? (isPositive ? Colors.green : Colors.red) : Colors.grey.shade400, barWidth: 2, dotData: const FlDotData(show: false)),
                LineChartBarData(spots: displaySpots, isCurved: false, color: Colors.transparent, dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: _showProjected ? (isPositive ? Colors.green : Colors.red) : Colors.grey.shade400))),
                if (_showRegression && regressionSpots.isNotEmpty) LineChartBarData(spots: regressionSpots, isCurved: false, color: Colors.blue.shade800, barWidth: 2, dashArray: [5, 5]),
              ],
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Text(DateFormat('dd/MM').format(DateTime.fromMillisecondsSinceEpoch(v.toInt())), style: const TextStyle(fontSize: 12)))),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 12)))),
              ),
            )),
          ),
        ],
      ),
    );
  }
}