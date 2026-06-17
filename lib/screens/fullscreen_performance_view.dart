import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/weight_standard.dart';
import '../models/weight_history_entry.dart';

class FullscreenPerformanceView extends StatefulWidget {
  final List<WeightStandard> standards;
  final List<WeightHistoryEntry> realHistory;
  final String title;

  const FullscreenPerformanceView({
    super.key,
    required this.standards,
    required this.realHistory,
    required this.title,
  });

  @override
  State<FullscreenPerformanceView> createState() => _FullscreenPerformanceViewState();
}

class _FullscreenPerformanceViewState extends State<FullscreenPerformanceView> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
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
        title: Text(widget.title, 
          style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.indigo),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: _buildChart(),
            ),
          ),
          Container(
            width: 250,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(left: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              children: [
                _buildAnalysisBadge(),
                const Spacer(),
                _buildLegend(),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalysisBadge() {
    if (widget.realHistory.isEmpty || widget.standards.isEmpty) return const SizedBox();
    
    final lastReal = widget.realHistory.last;
    final standardAtLastWeek = widget.standards.firstWhere(
      (s) => s.week == lastReal.week, 
      orElse: () => widget.standards.last
    );

    String status = "DANS LES STANDARDS";
    Color color = Colors.green;
    IconData icon = Icons.check_circle_outline;

    if (lastReal.averageWeight < standardAtLastWeek.weight) {
      status = "SOUS-POIDS";
      color = Colors.orange;
      icon = Icons.warning_amber_rounded;
    } else if (lastReal.averageWeight > standardAtLastWeek.weight) {
      status = "SUR-POIDS";
      color = Colors.purple;
      icon = Icons.trending_up_rounded;
    }

    final diff = (lastReal.averageWeight - standardAtLastWeek.weight).abs().toStringAsFixed(0);
    final diffPrefix = (lastReal.averageWeight - standardAtLastWeek.weight) >= 0 ? "+" : "-";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(status, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          _buildBadgeStat('Poids Actuel', '${lastReal.averageWeight.toStringAsFixed(0)}g'),
          const SizedBox(height: 8),
          _buildBadgeStat('Norme Standard', '${standardAtLastWeek.weight.toStringAsFixed(0)}g'),
          const SizedBox(height: 8),
          _buildBadgeStat('Écart', '$diffPrefix$diff g', color: color),
        ],
      ),
    );
  }

  Widget _buildBadgeStat(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontWeight: FontWeight.bold)),
        Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: color ?? Colors.indigo.shade900)),
      ],
    );
  }

  Widget _buildLegend() {
    return Column(
      children: [
        _buildLegendItem('Poids Réel', Colors.indigo, isLine: true),
        const SizedBox(height: 16),
        _buildLegendItem('Standard', Colors.grey.shade400, isDotted: true),
        const SizedBox(height: 16),
        _buildLegendItem('Alerte Poids', Colors.red, isDot: true),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, {bool isLine = false, bool isDotted = false, bool isDot = false}) {
    return Row(
      children: [
        if (isLine) Container(width: 20, height: 3, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        if (isDotted) Row(children: List.generate(3, (i) => Container(width: 6, height: 2, margin: const EdgeInsets.symmetric(horizontal: 1), color: color))),
        if (isDot) Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
      ],
    );
  }

  Widget _buildChart() {
    final standardSpots = widget.standards.map((s) => FlSpot(s.week.toDouble(), s.weight)).toList();
    final realSpots = widget.realHistory.map((h) => FlSpot(h.week.toDouble(), h.averageWeight)).toList();

    double maxWeek = 0;
    if (widget.standards.isNotEmpty) maxWeek = widget.standards.last.week.toDouble();
    if (widget.realHistory.isNotEmpty && widget.realHistory.last.week > maxWeek) {
      maxWeek = widget.realHistory.last.week.toDouble();
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: true,
          verticalInterval: 5,
          horizontalInterval: 500,
          getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
          getDrawingVerticalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 5, // Show every 5 weeks in landscape
              getTitlesWidget: (value, meta) {
                if (value < 0) return const SizedBox();
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
        borderData: FlBorderData(show: false),
        lineBarsData: [
          // barIndex 0: Standard Curve (Dashed)
          LineChartBarData(
            spots: standardSpots,
            isCurved: true,
            color: Colors.grey.shade400,
            barWidth: 2,
            dashArray: [5, 5],
            dotData: const FlDotData(show: false),
          ),
          // barIndex 1: Actual Data (Visible)
          LineChartBarData(
            spots: realSpots,
            isCurved: true,
            color: Colors.indigo,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                bool isLast = index == realSpots.length - 1;
                if (isLast) {
                  final week = spot.x.toInt();
                  final standard = widget.standards.firstWhere((s) => s.week == week, orElse: () => widget.standards.last);
                  Color dotColor = Colors.green;
                  if (spot.y < standard.weight) dotColor = Colors.red;
                  else if (spot.y > standard.weight) dotColor = Colors.orange;
                  return FlDotCirclePainter(radius: 6, color: dotColor, strokeWidth: 2, strokeColor: Colors.white);
                }
                return FlDotCirclePainter(radius: 3, color: Colors.indigo, strokeWidth: 1, strokeColor: Colors.white);
              },
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => Colors.indigo.shade900,
            getTooltipItems: (List<LineBarSpot> touchedSpots) {
              return touchedSpots.map((spot) {
                if (spot.barIndex != 1) return null;
                final week = spot.x.toInt();
                final real = widget.realHistory.firstWhere((h) => h.week == week, orElse: () => widget.realHistory.first);
                final standard = widget.standards.firstWhere((s) => s.week == week, orElse: () => widget.standards.first);
                return LineTooltipItem(
                  'S$week: ${real.averageWeight.toStringAsFixed(1)}g\n(Std: ${standard.weight.toInt()}g)',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
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
}
