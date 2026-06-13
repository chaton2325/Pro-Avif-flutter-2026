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
        title: Text('Vue détaillée : ${currentChart['title']}'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: _currentIndex > 0 ? () => setState(() => _currentIndex--) : null,
          ),
          Expanded(
            child: _buildChart(
              currentChart['title'] as String,
              currentChart['history'] as List<dynamic>,
              currentChart['before'] as double,
              currentChart['after'] as double,
              currentChart['positive'] as bool,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios),
            onPressed: _currentIndex < charts.length - 1 ? () => setState(() => _currentIndex++) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildChart(String title, List<dynamic> history, double current, double predicted, bool isPositive) {
    List<FlSpot> historicalSpots = (List.from(history)..sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])))).map((p) => FlSpot(DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble(), (p['homogeneity'] as num).toDouble())).toList();
    
    double nowTime = historicalSpots.isNotEmpty ? historicalSpots.last.x : DateTime.now().millisecondsSinceEpoch.toDouble();
    double step = 24 * 60 * 60 * 1000.0;
    double predictedTime = nowTime + step;
    List<FlSpot> predictiveSpots = [if (historicalSpots.isNotEmpty) historicalSpots.last else FlSpot(nowTime, current), FlSpot(predictedTime, predicted)];
    
    double minX = historicalSpots.isNotEmpty ? historicalSpots.first.x : nowTime;
    double maxX = predictedTime;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Expanded(
            child: LineChart(LineChartData(
              minY: 0, maxY: 100, minX: minX, maxX: maxX,
              lineBarsData: [
                if (historicalSpots.isNotEmpty) LineChartBarData(spots: historicalSpots, isCurved: true, color: Colors.grey.shade300, barWidth: 3, dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: Colors.grey.shade400))),
                LineChartBarData(spots: predictiveSpots, isCurved: false, color: isPositive ? Colors.green : Colors.red, barWidth: 6, dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 6, color: isPositive ? Colors.green : Colors.red))),
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
