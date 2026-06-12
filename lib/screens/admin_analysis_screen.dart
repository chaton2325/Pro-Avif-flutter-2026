import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/lot.dart';
import '../services/mongo_service.dart';

class AdminAnalysisScreen extends StatefulWidget {
  const AdminAnalysisScreen({super.key});

  @override
  State<AdminAnalysisScreen> createState() => _AdminAnalysisScreenState();
}

class _AdminAnalysisScreenState extends State<AdminAnalysisScreen> {
  final MongoService _mongoService = MongoService();
  
  List<Farm> _farms = [];
  List<Lot> _lots = [];
  Farm? _selectedFarm;
  Lot? _selectedLot;
  String? _selectedSex; 
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
      final results = await Future.wait([
        _mongoService.getFarms(),
        _mongoService.getLots(),
      ]);
      setState(() {
        _farms = results[0] as List<Farm>;
        _lots = results[1] as List<Lot>;
        _isLoadingFarms = false;
        if (_farms.isNotEmpty) _selectedFarm = _farms.first;
        if (_lots.isNotEmpty) _selectedLot = _lots.first;
        if (_selectedFarm != null && _selectedLot != null) {
          _loadAnalysisData();
        }
      });
    } catch (e) {
      setState(() => _isLoadingFarms = false);
    }
  }

  Future<void> _loadAnalysisData() async {
    if (_selectedFarm == null || _selectedLot == null) return;
    
    setState(() => _isLoadingData = true);
    try {
      final data = await _mongoService.getHomogeneityAnalysis(
        _selectedFarm!.name,
        lotNumber: _selectedLot!.number,
        sex: _selectedSex,
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Farm>(
                  value: _selectedFarm,
                  isDense: true,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Site',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedFarm = val);
                    _loadAnalysisData();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<Lot>(
                  value: _selectedLot,
                  isDense: true,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Lot',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: _lots.map((l) => DropdownMenuItem(value: l, child: Text(l.number, style: const TextStyle(fontSize: 12)))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedLot = val);
                    _loadAnalysisData();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _selectedSex,
                  isDense: true,
                  dropdownColor: Colors.white,
                  decoration: InputDecoration(
                    labelText: 'Sexe',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tout', style: TextStyle(fontSize: 12))),
                    ...['Mâle', 'Femelle'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12))))
                  ].toList(),
                  onChanged: (val) {
                    setState(() => _selectedSex = val);
                    _loadAnalysisData();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SwitchListTile(
                  title: const Text('Lignes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  value: _showLines,
                  activeColor: Colors.indigo,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _showLines = val),
                ),
              ),
            ],
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
    List<Widget> children = [];
    
    // 1. Vue d'ensemble (toutes les courbes)
    children.add(_buildChartContainer(
      title: 'VUE D\'ENSEMBLE',
      bars: _buildAllLineBars(),
      dataValues: _analysisData.values,
      seriesNames: _analysisData.keys.toList(),
      showLegend: true,
    ));
    
    // 2. Graphiques individuels par salle/sexe
    int i = 0;
    _analysisData.forEach((seriesName, points) {
      children.add(_buildChartContainer(
        title: seriesName.toUpperCase(),
        bars: _buildLineBarsForSeries(seriesName, points, i),
        dataValues: [points],
        seriesNames: [seriesName],
        showLegend: false,
      ));
      i++;
    });
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: children),
    );
  }

  List<LineChartBarData> _buildAllLineBars() {
    List<LineChartBarData> bars = [];
    int i = 0;
    _analysisData.forEach((seriesName, points) {
      bars.addAll(_buildLineBarsForSeries(seriesName, points, i));
      i++;
    });
    return bars;
  }

  List<LineChartBarData> _buildLineBarsForSeries(String seriesName, List<dynamic> points, int colorIndex) {
    final color = _seriesColors[colorIndex % _seriesColors.length];
    return [
      LineChartBarData(
        spots: points.map((p) {
          double x = DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble();
          double y = (p['homogeneity'] as num).toDouble();
          return FlSpot(x, y);
        }).toList(),
        isCurved: true,
        color: color,
        barWidth: _showLines ? 4 : 0,
        isStrokeCapRound: true,
        dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 5, color: color, strokeWidth: 2, strokeColor: Colors.white)),
        belowBarData: BarAreaData(show: _showLines, color: color.withOpacity(0.02)),
      )
    ];
  }

  Widget _buildChartContainer({
    required String title,
    required List<LineChartBarData> bars,
    required Iterable<List<dynamic>> dataValues,
    required List<String> seriesNames,
    bool showLegend = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900, letterSpacing: 0.5),
          ),
        ),
        Container(
          height: 350,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 32, 24, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 8))],
          ),
          child: LineChart(
            LineChartData(
              lineBarsData: bars,
              titlesData: _buildTitles(dataValues),
              gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1)),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => Colors.indigo.shade900,
                  getTooltipItems: (List<LineBarSpot> touchedSpots) {
                    return touchedSpots.map((s) {
                      final name = seriesNames[s.barIndex];
                      return LineTooltipItem(
                        '$name\n',
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
        if (showLegend) ...[
          const SizedBox(height: 16),
          _buildLegend(seriesNames),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildLegend(List<String> seriesNames) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        children: seriesNames.map((name) {
          int index = _analysisData.keys.toList().indexOf(name);
          final color = _seriesColors[index % _seriesColors.length];
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
            ],
          );
        }).toList(),
      ),
    );
  }

  FlTitlesData _buildTitles(Iterable<List<dynamic>> dataValues) {
    double minX = double.maxFinite;
    double maxX = double.minPositive;
    bool hasData = false;

    for (var points in dataValues) {
      for (var p in points) {
        double x = DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble();
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        hasData = true;
      }
    }

    if (!hasData) return const FlTitlesData();

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
