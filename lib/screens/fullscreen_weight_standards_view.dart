import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/weight_standard.dart';

class FullscreenWeightStandardsView extends StatefulWidget {
  final List<WeightStandard> standards;
  final String sex;

  const FullscreenWeightStandardsView({
    super.key,
    required this.standards,
    required this.sex,
  });

  @override
  State<FullscreenWeightStandardsView> createState() => _FullscreenWeightStandardsViewState();
}

class _FullscreenWeightStandardsViewState extends State<FullscreenWeightStandardsView> {
  @override
  void initState() {
    super.initState();
    // Force Landscape
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Hide status bar for better immersion
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Restore Portrait and status bar
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('Standard de Croissance : ${widget.sex}', 
          style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.indigo),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 40, 10),
              child: _buildChart(),
            ),
          ),
          _buildLegend(),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('Idéal Théorique', Colors.indigo, isLine: true),
        const SizedBox(width: 32),
        _buildLegendItem('Plage Acceptable', Colors.greenAccent.withOpacity(0.5), isLine: false),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, {required bool isLine}) {
    return Row(
      children: [
        Container(
          width: 20,
          height: isLine ? 3 : 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  Widget _buildChart() {
    final spots = widget.standards.map((s) => FlSpot(s.week.toDouble(), s.weight)).toList();
    final minSpots = widget.standards.map((s) => FlSpot(s.week.toDouble(), s.minWeight)).toList();
    final maxSpots = widget.standards.map((s) => FlSpot(s.week.toDouble(), s.maxWeight)).toList();

    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: maxSpots,
            isCurved: true,
            color: Colors.transparent,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: minSpots,
            isCurved: true,
            color: Colors.transparent,
            dotData: const FlDotData(show: false),
          ),
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Colors.indigo,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                radius: 3,
                color: Colors.indigo,
                strokeWidth: 1,
                strokeColor: Colors.white,
              ),
            ),
          ),
        ],
        betweenBarsData: [
          BetweenBarsData(
            fromIndex: 0,
            toIndex: 1,
            color: Colors.greenAccent.withOpacity(0.35),
          ),
        ],
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              // Show every 5 weeks to keep it clean in landscape
              interval: 5,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  meta: meta,
                  space: 8,
                  child: Text('S${value.toInt()}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: 500,
              getTitlesWidget: (value, meta) {
                return SideTitleWidget(
                  meta: meta,
                  child: Text('${value.toInt()}g',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade500)),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          verticalInterval: 5,
          horizontalInterval: 500,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
          getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchSpotThreshold: 20,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => Colors.indigo.shade900,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                if (spot.barIndex != 2) return null; // Indigo reference line
                
                final week = spot.x.toInt();
                final standard = widget.standards.firstWhere(
                  (s) => s.week == week, 
                  orElse: () => widget.standards.first
                );
                
                return LineTooltipItem(
                  'Jour: ${standard.day}\nPoids: ${standard.weight.toStringAsFixed(0)}g\nSemaine $week',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                );
              }).toList();
            },
          ),
        ),
        minY: 0,
      ),
    );
  }
}
