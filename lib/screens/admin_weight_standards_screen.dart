import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/weight_standard.dart';
import '../services/mongo_service.dart';
import 'fullscreen_weight_standards_view.dart';

class AdminWeightStandardsScreen extends StatefulWidget {
  const AdminWeightStandardsScreen({super.key});

  @override
  State<AdminWeightStandardsScreen> createState() => _AdminWeightStandardsScreenState();
}

class _AdminWeightStandardsScreenState extends State<AdminWeightStandardsScreen> {
  final MongoService _mongoService = MongoService();
  String _selectedSex = 'Mâle';
  List<WeightStandard> _standards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStandards();
  }

  Future<void> _loadStandards() async {
    setState(() => _isLoading = true);
    try {
      final data = await _mongoService.getWeightStandards(_selectedSex);
      data.sort((a, b) => a.day.compareTo(b.day));
      setState(() {
        _standards = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('STANDARDS DE CROISSANCE',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5, fontSize: 16)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo.shade900,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildSexSelector(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                : _standards.isEmpty
                    ? _buildNoData()
                    : _buildChartSection(),
          ),
        ],
      ),
    );
  }

  Widget _buildSexSelector() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Mâle', label: Text('Mâles'), icon: Icon(Icons.male)),
          ButtonSegment(value: 'Femelle', label: Text('Femelles'), icon: Icon(Icons.female)),
        ],
        selected: {_selectedSex},
        onSelectionChanged: (Set<String> newSelection) {
          setState(() {
            _selectedSex = newSelection.first;
          });
          _loadStandards();
        },
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide(color: Colors.indigo.shade100)),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) return Colors.indigo;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return Colors.indigo.shade900;
          }),
        ),
      ),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.query_stats, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Aucune donnée de standard disponible',
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _loadStandards,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            child: const Text('Réessayer', style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('ÉVOLUTION THÉORIQUE', 
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade300, letterSpacing: 1)),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenWeightStandardsView(
                    standards: _standards,
                    sex: _selectedSex,
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
          _buildMainChart(),
          const SizedBox(height: 12),
          _buildLegend(),
          const SizedBox(height: 24),
          _buildInfoCards(),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('Idéal Théorique', Colors.indigo, isLine: true),
        const SizedBox(width: 20),
        _buildLegendItem('Plage Acceptable', Colors.greenAccent.withOpacity(0.5), isLine: false),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color, {required bool isLine}) {
    return Row(
      children: [
        Container(
          width: 16,
          height: isLine ? 3 : 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildMainChart() {
    final spots = _standards.map((s) => FlSpot(s.week.toDouble(), s.weight)).toList();
    final minSpots = _standards.map((s) => FlSpot(s.week.toDouble(), s.minWeight)).toList();
    final maxSpots = _standards.map((s) => FlSpot(s.week.toDouble(), s.maxWeight)).toList();

    return Container(
      height: 400,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 32, 24, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: LineChart(
        LineChartData(
          lineBarsData: [
            // Max Weight Line (Transparent, used for shaded area)
            LineChartBarData(
              spots: maxSpots,
              isCurved: true,
              color: Colors.transparent,
              dotData: const FlDotData(show: false),
            ),
            // Min Weight Line (Transparent, used for shaded area)
            LineChartBarData(
              spots: minSpots,
              isCurved: true,
              color: Colors.transparent,
              dotData: const FlDotData(show: false),
            ),
            // Reference Weight Line
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Colors.indigo,
              barWidth: 4,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                  radius: 4,
                  color: Colors.indigo,
                  strokeWidth: 2,
                  strokeColor: Colors.white,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ),
          ],
          betweenBarsData: [
            BetweenBarsData(
              fromIndex: 0,
              toIndex: 1,
              color: Colors.greenAccent.withOpacity(0.35),
            ),
          ],
          titlesData: _buildTitles(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 500,
            getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            handleBuiltInTouches: true,
            touchSpotThreshold: 20,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (touchedSpot) => Colors.indigo.shade900,
              fitInsideHorizontally: true,
              fitInsideVertically: true,
              getTooltipItems: (List<LineBarSpot> touchedSpots) {
                return touchedSpots.map((spot) {
                  if (spot.barIndex != 2) return null; // Indigo reference line
                  
                  final week = spot.x.toInt();
                  final standard = _standards.firstWhere(
                    (s) => s.week == week, 
                    orElse: () => _standards.first
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
          interval: 2, // Labels every 2 weeks for clarity in portrait
          getTitlesWidget: (value, meta) {
            if (value % 1 != 0) return const SizedBox();
            return SideTitleWidget(
              meta: meta,
              space: 10,
              child: Text('S${value.toInt()}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.grey.shade400)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 45,
          getTitlesWidget: (value, meta) {
            if (value % 500 != 0) return const SizedBox();
            return SideTitleWidget(
              meta: meta,
              child: Text('${value.toInt()}g',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade400)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoCards() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10)],
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.indigo),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'La ligne bleue représente le poids théorique idéal. La zone ombrée indique la plage acceptable (+/- 10% environ).',
                  style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
