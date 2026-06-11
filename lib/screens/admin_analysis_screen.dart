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
  bool _showLines = true; // Toggle for line vs scatter
  DateTime? _startDate;
  DateTime? _endDate;
  
  Map<String, List<dynamic>> _analysisData = {};
  Map<String, Map<String, double>> _regressions = {};
  
  final List<Color> _roomColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.indigo,
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
      
      _calculateRegressions(formattedData);
      
      setState(() {
        _analysisData = formattedData;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  void _calculateRegressions(Map<String, List<dynamic>> data) {
    _regressions.clear();
    data.forEach((room, points) {
      if (points.length < 2) return;
      
      int n = points.length;
      double sumX = 0; // Sum of timestamps
      double sumY = 0; // Sum of homogeneity
      double sumXY = 0; // Sum of timestamp * homogeneity
      double sumX2 = 0; // Sum of timestamp^2
      
      for (var p in points) {
        // Use seconds for timestamp to avoid excessive values
        double x = DateTime.parse(p['date']).millisecondsSinceEpoch / 1000.0;
        double y = (p['homogeneity'] as num).toDouble();
        
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
      }
      
      // Slope formula: (n*Σxy - Σx*Σy) / (n*Σx² - (Σx)²)
      double denominator = (n * sumX2 - sumX * sumX);
      if (denominator == 0) return;
      
      double a = (n * sumXY - sumX * sumY) / denominator;
      
      // Intercept formula: (Σy - a*Σx) / n
      double b = (sumY - a * sumX) / n;
      
      _regressions[room] = {'a': a, 'b': b};
    });
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _startDate = picked);
      _loadAnalysisData();
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        // Set to end of day
        _endDate = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      });
      _loadAnalysisData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ANALYSE D\'HOMOGÉNÉITÉ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        centerTitle: true,
      ),
      body: _isLoadingFarms 
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildControls(),
                Expanded(
                  child: _isLoadingData 
                      ? const Center(child: CircularProgressIndicator())
                      : _analysisData.isEmpty 
                          ? _buildNoData()
                          : _buildAnalysisView(),
                ),
              ],
            ),
    );
  }

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Column(
        children: [
          DropdownButtonFormField<Farm>(
            value: _selectedFarm,
            decoration: InputDecoration(
              labelText: 'Choisir un site (Ferme)',
              prefixIcon: const Icon(Icons.agriculture, color: Colors.orange),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
            onChanged: (val) {
              setState(() => _selectedFarm = val);
              _loadAnalysisData();
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Vue:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Courbes', style: TextStyle(fontSize: 10)),
                selected: _showLines,
                onSelected: (val) => setState(() => _showLines = val),
                selectedColor: Colors.orange.withValues(alpha: 0.2),
                checkmarkColor: Colors.orange,
              ),
              const SizedBox(width: 8),
              const Text('Période:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Tout', style: TextStyle(fontSize: 10)),
                selected: _isAllHistory,
                onSelected: (val) {
                  setState(() => _isAllHistory = true);
                  _loadAnalysisData();
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Par période', style: TextStyle(fontSize: 11)),
                selected: !_isAllHistory,
                onSelected: (val) {
                  setState(() => _isAllHistory = false);
                  if (_startDate == null) {
                    _startDate = DateTime.now().subtract(const Duration(days: 30));
                    _endDate = DateTime.now();
                  }
                  _loadAnalysisData();
                },
              ),
            ],
          ),
          if (!_isAllHistory) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectStartDate,
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(
                      _startDate == null ? 'Début' : DateFormat('dd/MM/yy').format(_startDate!),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectEndDate,
                    icon: const Icon(Icons.calendar_today, size: 14),
                    label: Text(
                      _endDate == null ? 'Fin' : DateFormat('dd/MM/yy').format(_endDate!),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
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
          const Text('Aucune donnée d\'analyse pour ce site', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildAnalysisView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildChartSection(),
          const SizedBox(height: 24),
          _buildRegressionSummary(),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildChartSection() {
    return Container(
      height: 400,
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          const Text('Évolution de l\'Homogénéité (%)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 20),
          Expanded(
            child: LineChart(
              LineChartData(
                lineBarsData: _buildLineBars(),
                titlesData: _buildTitles(),
                gridData: const FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: true, border: Border.all(color: Colors.grey.shade300)),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.blueGrey.withValues(alpha: 0.8),
                    getTooltipItems: (List<LineBarSpot> touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${spot.y.toStringAsFixed(1)}%',
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildLegend(),
        ],
      ),
    );
  }

  List<LineChartBarData> _buildLineBars() {
    List<LineChartBarData> bars = [];
    int colorIndex = 0;
    
    _analysisData.forEach((room, points) {
      final color = _roomColors[colorIndex % _roomColors.length];
      
      // Real points curve or scatter
      bars.add(LineChartBarData(
        spots: points.map((p) {
          double x = DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble();
          double y = (p['homogeneity'] as num).toDouble();
          return FlSpot(x, y);
        }).toList(),
        isCurved: _showLines,
        color: _showLines ? color : Colors.transparent, // Hide line if not toggled
        barWidth: _showLines ? 3 : 0,
        dotData: FlDotData(
          show: true,
          getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(
            radius: 4,
            color: color,
            strokeWidth: 1,
            strokeColor: Colors.white,
          ),
        ),
      ));
      
      // Regression dashed line
      if (_regressions.containsKey(room)) {
        final reg = _regressions[room]!;
        final firstX = DateTime.parse(points.first['date']).millisecondsSinceEpoch.toDouble();
        final lastX = DateTime.parse(points.last['date']).millisecondsSinceEpoch.toDouble();
        
        // y = ax + b
        double y1 = reg['a']! * (firstX / 1000.0) + reg['b']!;
        double y2 = reg['a']! * (lastX / 1000.0) + reg['b']!;
        
        bars.add(LineChartBarData(
          spots: [
            FlSpot(firstX, y1),
            FlSpot(lastX, y2),
          ],
          isCurved: false,
          color: color.withValues(alpha: 0.6), // More visible regression line
          barWidth: 2,
          dashArray: [5, 5],
          dotData: const FlDotData(show: false),
        ));
      }
      
      colorIndex++;
    });
    
    return bars;
  }

  FlTitlesData _buildTitles() {
    // Dynamically calculate interval based on date range to avoid overlapping labels
    double? bottomInterval;
    if (_analysisData.isNotEmpty) {
      final allPoints = _analysisData.values.expand((x) => x).toList();
      if (allPoints.isNotEmpty) {
        final first = DateTime.parse(allPoints.first['date']).millisecondsSinceEpoch;
        final last = DateTime.parse(allPoints.last['date']).millisecondsSinceEpoch;
        final diff = last - first;
        if (diff > 0) {
          // Aim for about 5-6 labels
          bottomInterval = diff / 5.0;
        }
      }
    }

    return FlTitlesData(
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          interval: bottomInterval,
          getTitlesWidget: (value, meta) {
            final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
            return SideTitleWidget(
              meta: meta,
              angle: -45, // Rotate labels for better fit
              space: 10,
              child: Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
            );
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 45,
          getTitlesWidget: (value, meta) {
            if (value < 0 || value > 100) return const SizedBox();
            return SideTitleWidget(
              meta: meta,
              child: Text('${value.toInt()}%', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: List.generate(_analysisData.keys.length, (index) {
        final room = _analysisData.keys.elementAt(index);
        final color = _roomColors[index % _roomColors.length];
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 10, height: 10, color: color),
            const SizedBox(width: 4),
            Text(room, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        );
      }),
    );
  }

  Widget _buildRegressionSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tendance par Salle', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        ..._regressions.entries.map((e) {
          final slope = e.value['a']!;
          final isImproving = slope > 0;
          // Growth per week (slope is per second)
          final weeklyGrowth = slope * 60 * 60 * 24 * 7;
          
          return Card(
            elevation: 0,
            color: isImproving ? Colors.green.shade50 : Colors.red.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Icon(
                isImproving ? Icons.trending_up : Icons.trending_down,
                color: isImproving ? Colors.green : Colors.red,
              ),
              title: Text(e.key, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                isImproving 
                  ? 'Amélioration de l\'uniformité.' 
                  : 'Dégradation de l\'uniformité.',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${weeklyGrowth > 0 ? "+" : ""}${weeklyGrowth.toStringAsFixed(1)}%',
                    style: TextStyle(fontWeight: FontWeight.bold, color: isImproving ? Colors.green : Colors.red),
                  ),
                  const Text('par semaine', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
