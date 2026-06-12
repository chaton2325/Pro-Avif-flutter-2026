import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';

class AdminAnalysisScreen extends StatefulWidget {
  const AdminAnalysisScreen({super.key});

  @override
  State<AdminAnalysisScreen> createState() => _AdminAnalysisScreenState();
}

class _AdminAnalysisScreenState extends State<AdminAnalysisScreen> {
  final MongoService _mongoService = MongoService();
  
  List<Farm> _farms = [];
  Farm? _selectedFarm;
  bool _isLoadingFarms = true;
  bool _isLoadingData = false;
  
  // Date filtering
  bool _isAllHistory = true;
  bool _showLines = true;
  DateTime? _startDate;
  DateTime? _endDate;
  
  Map<String, List<dynamic>> _analysisData = {};
  
  final List<Color> _seriesColors = [
    Colors.indigo,
    Colors.pink,
    Colors.teal,
    Colors.orange,
    Colors.purple,
    Colors.blue,
    Colors.red,
    Colors.amber,
  ];

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
          _loadAnalysisData();
        }
      });
    } catch (e) {
      setState(() => _isLoadingFarms = false);
    }
  }

  Future<void> _loadAnalysisData() async {
    if (_selectedFarm == null) return;
    
    setState(() => _isLoadingData = true);
    try {
      final data = await _mongoService.getHomogeneityAnalysis(
        _selectedFarm!.name,
        startDate: _isAllHistory ? null : _startDate?.toIso8601String(),
        endDate: _isAllHistory ? null : _endDate?.toIso8601String(),
      );
      
      final Map<String, List<dynamic>> formattedData = {};
      data.forEach((key, value) {
        final list = List<dynamic>.from(value);
        list.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
        formattedData[key] = list;
      });
      
      setState(() {
        _analysisData = formattedData;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('ÉVOLUTION DE L\'HOMOGÉNÉITÉ', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.5, fontSize: 16)),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo.shade900,
        centerTitle: true,
      ),
      body: _isLoadingFarms 
          ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
          : Column(
              children: [
                _buildControls(),
                Expanded(
                  child: _isLoadingData 
                      ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
                      : _analysisData.isEmpty 
                          ? _buildNoData()
                          : _buildChartSection(),
                ),
              ],
            ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: Column(
        children: [
          DropdownButtonFormField<Farm>(
            value: _selectedFarm,
            dropdownColor: Colors.white,
            decoration: InputDecoration(
              labelText: 'Site de production',
              prefixIcon: const Icon(Icons.location_on, color: Colors.indigo),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
            onChanged: (val) {
              setState(() => _selectedFarm = val);
              _loadAnalysisData();
            },
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Tout l\'historique', style: TextStyle(fontSize: 11)),
                  selected: _isAllHistory,
                  onSelected: (val) {
                    setState(() => _isAllHistory = true);
                    _loadAnalysisData();
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Sélectionner Période', style: TextStyle(fontSize: 11)),
                  selected: !_isAllHistory,
                  onSelected: (val) {
                    setState(() => _isAllHistory = false);
                  },
                ),
                const SizedBox(width: 12),
                if (!_isAllHistory) ...[
                  _buildDateBtn(_startDate, 'Début', () async {
                    final d = await showDatePicker(context: context, initialDate: _startDate ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime.now());
                    if (d != null) { setState(() => _startDate = d); _loadAnalysisData(); }
                  }),
                  const SizedBox(width: 8),
                  _buildDateBtn(_endDate, 'Fin', () async {
                    final d = await showDatePicker(context: context, initialDate: _endDate ?? DateTime.now(), firstDate: _startDate ?? DateTime(2020), lastDate: DateTime.now());
                    if (d != null) { setState(() => _endDate = DateTime(d.year, d.month, d.day, 23, 59, 59)); _loadAnalysisData(); }
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateBtn(DateTime? date, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
        child: Row(
          children: [
            const Icon(Icons.calendar_month, size: 14, color: Colors.indigo),
            const SizedBox(width: 6),
            Text(date == null ? label : DateFormat('dd/MM/yy').format(date), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo)),
          ],
        ),
      ),
    );
  }

  Widget _buildNoData() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Aucune donnée pour ce site', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Container(
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
                lineBarsData: _buildAllLineBars(),
                titlesData: _buildTitles(),
                gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1)),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.indigo.shade900,
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((s) {
                        final seriesName = _analysisData.keys.elementAt(s.barIndex);
                        return LineTooltipItem(
                          '$seriesName\n',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          children: [
                            TextSpan(
                              text: '${s.y.toStringAsFixed(1)}%',
                              style: TextStyle(color: s.bar.color, fontSize: 11, fontWeight: FontWeight.w900),
                            ),
                          ],
                        );
                      }).toList();
                    },
                  ),
                ),
                minY: 0,
                maxY: 100,
              ),
            ),
          ),
          const SizedBox(height: 24),
          _buildLegend(),
        ],
      ),
    );
  }

  List<LineChartBarData> _buildAllLineBars() {
    List<LineChartBarData> bars = [];
    int i = 0;
    _analysisData.forEach((seriesName, points) {
      final color = _seriesColors[i % _seriesColors.length];
      bars.add(LineChartBarData(
        spots: points.map((p) {
          double x = DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble();
          double y = (p['homogeneity'] as num).toDouble();
          return FlSpot(x, y);
        }).toList(),
        isCurved: true,
        color: color,
        barWidth: 4,
        isStrokeCapRound: true,
        dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 5, color: color, strokeWidth: 2, strokeColor: Colors.white)),
        belowBarData: BarAreaData(show: true, color: color.withOpacity(0.02)),
      ));
      i++;
    });
    return bars;
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: _analysisData.keys.toList().asMap().entries.map((e) {
          final color = _seriesColors[e.key % _seriesColors.length];
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(e.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          );
        }).toList(),
      ),
    );
  }

  FlTitlesData _buildTitles() {
    double minX = double.maxFinite;
    double maxX = double.minPositive;
    
    _analysisData.values.forEach((points) {
      for (var p in points) {
        double x = DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble();
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
      }
    });

    double? bottomInterval;
    if (maxX > minX) bottomInterval = (maxX - minX) / 4.0;

    return FlTitlesData(
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: bottomInterval,
          getTitlesWidget: (value, meta) {
            final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
            return SideTitleWidget(
              meta: meta,
              space: 10,
              child: Text(DateFormat('dd/MM').format(date), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade400)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            if (value % 20 != 0) return const SizedBox();
            return SideTitleWidget(
              meta: meta,
              child: Text('${value.toInt()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade400)),
            );
          },
        ),
      ),
    );
  }
}
