import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/lot.dart';
import '../models/weight_history_entry.dart';
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
  Map<String, List<WeightHistoryEntry>> _weightData = {};
  Set<String> _selectedRooms = {};

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
      print("🔍 LOADING ANALYSIS DATA for Lot: ${_selectedLot!.number}");
      final data = await _mongoService.getHomogeneityAnalysis(
        _selectedFarm!.name,
        lotNumber: _selectedLot!.number,
        sex: _selectedSex,
        startDate: _isAllHistory ? null : _startDate?.toIso8601String(),
        endDate: _isAllHistory ? null : _endDate?.toIso8601String(),
      );
      
      print("✅ RECEIVED DATA KEYS: ${data.keys}");
      
      final Map<String, List<dynamic>> formattedData = {};
      data.forEach((key, value) {
        final list = List<dynamic>.from(value);
        list.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
        formattedData[key] = list;
      });

      // Charge l'évolution du poids moyen pour chaque série (salle/sexe) afin de la fusionner
      // avec l'homogénéité sur le même graphique.
      final Map<String, List<WeightHistoryEntry>> weightData = {};
      await Future.wait(formattedData.keys.map((key) async {
        try {
          final room = _roomFromKey(key);
          final sex = _sexFromKey(key);
          final history = await _mongoService.getWeightEvolution(
            farmName: _selectedFarm!.name,
            roomName: room,
            sex: sex,
            lotNumber: _selectedLot!.number,
          );
          weightData[key] = history;
        } catch (_) {
          weightData[key] = [];
        }
      }));

      setState(() {
        _analysisData = formattedData;
        _weightData = weightData;
        _isLoadingData = false;
      });
    } catch (e) {
      setState(() => _isLoadingData = false);
    }
  }

  String _roomFromKey(String key) => key.split(' - ').first;

  String _sexFromKey(String key) {
    final afterDash = key.substring(_roomFromKey(key).length + 3);
    return afterDash.split(' (Lot:').first.trim();
  }

  List<String> get _availableRooms => _selectedFarm?.rooms ?? [];

  Map<String, List<dynamic>> get _filteredAnalysisData {
    if (_selectedRooms.isEmpty) return _analysisData;
    return Map.fromEntries(
      _analysisData.entries.where((e) => _selectedRooms.contains(_roomFromKey(e.key))),
    );
  }

  void _toggleRoom(String room) {
    setState(() {
      if (_selectedRooms.contains(room)) {
        _selectedRooms.remove(room);
      } else {
        if (_selectedRooms.length >= 2) {
          // On ne garde que la sélection la plus récente pour respecter la limite de 2 salles.
          _selectedRooms.remove(_selectedRooms.first);
        }
        _selectedRooms.add(room);
      }
    });
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
                      : _filteredAnalysisData.isEmpty
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
          if (_availableRooms.isNotEmpty) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Toutes les salles', style: TextStyle(fontSize: 11)),
                    selected: _selectedRooms.isEmpty,
                    onSelected: (_) => setState(() => _selectedRooms.clear()),
                    selectedColor: Colors.indigo.shade100,
                  ),
                  ..._availableRooms.map((room) => FilterChip(
                        label: Text(room, style: const TextStyle(fontSize: 11)),
                        selected: _selectedRooms.contains(room),
                        onSelected: (_) => _toggleRoom(room),
                        selectedColor: Colors.indigo.shade100,
                      )),
                ],
              ),
            ),
          ],
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
    final filtered = _filteredAnalysisData;

    // 1. Vue d'ensemble (toutes les courbes d'homogénéité)
    children.add(_buildChartContainer(
      title: 'VUE D\'ENSEMBLE',
      bars: _buildAllLineBars(filtered),
      dataValues: filtered.values,
      seriesNames: filtered.keys.toList(),
      showLegend: true,
    ));

    // 2. Graphiques individuels par salle/sexe : homogénéité + poids moyen fusionnés
    int i = 0;
    filtered.forEach((seriesName, points) {
      children.add(_buildCombinedChartContainer(seriesName, points, _weightData[seriesName] ?? [], i));
      i++;
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: children),
    );
  }

  List<LineChartBarData> _buildAllLineBars(Map<String, List<dynamic>> data) {
    List<LineChartBarData> bars = [];
    int i = 0;
    data.forEach((seriesName, points) {
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

  /// Graphique combiné par salle/sexe/lot : homogénéité (axe gauche, %) + poids moyen
  /// (axe droit, g) sur le même tracé. Le poids est normalisé sur 0-100 pour partager
  /// l'échelle du graphique ; les titres de l'axe droit re-convertissent en grammes réels.
  Widget _buildCombinedChartContainer(String title, List<dynamic> homogeneityPoints, List<WeightHistoryEntry> weightPoints, int colorIndex) {
    final homogColor = _seriesColors[colorIndex % _seriesColors.length];
    const weightColor = Colors.green;

    final homogSpots = homogeneityPoints.map((p) {
      double x = DateTime.parse(p['date']).millisecondsSinceEpoch.toDouble();
      double y = (p['homogeneity'] as num).toDouble();
      return FlSpot(x, y);
    }).toList();

    double minW = 0, maxW = 100;
    final hasWeight = weightPoints.isNotEmpty;
    if (hasWeight) {
      final weights = weightPoints.map((w) => w.averageWeight).toList();
      minW = weights.reduce((a, b) => a < b ? a : b);
      maxW = weights.reduce((a, b) => a > b ? a : b);
      if (maxW == minW) maxW = minW + 1;
    }
    final weightSpotsNormalized = weightPoints.map((w) {
      double x = w.timestamp.millisecondsSinceEpoch.toDouble();
      double normalized = ((w.averageWeight - minW) / (maxW - minW)) * 100;
      return FlSpot(x, normalized);
    }).toList();

    final allDates = [
      ...homogeneityPoints.map((p) => DateTime.parse(p['date'])),
      ...weightPoints.map((w) => w.timestamp),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Text(title.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900, letterSpacing: 0.5)),
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
          child: allDates.isEmpty
              ? const Center(child: Text('Aucune donnée', style: TextStyle(color: Colors.grey)))
              : LineChart(
                  LineChartData(
                    lineBarsData: [
                      LineChartBarData(
                        spots: homogSpots,
                        isCurved: true,
                        color: homogColor,
                        barWidth: _showLines ? 4 : 0,
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 5, color: homogColor, strokeWidth: 2, strokeColor: Colors.white)),
                        belowBarData: BarAreaData(show: _showLines, color: homogColor.withOpacity(0.02)),
                      ),
                      LineChartBarData(
                        spots: weightSpotsNormalized,
                        isCurved: true,
                        color: weightColor,
                        barWidth: _showLines ? 3 : 0,
                        dashArray: const [6, 4],
                        isStrokeCapRound: true,
                        dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: weightColor, strokeWidth: 2, strokeColor: Colors.white)),
                      ),
                    ],
                    titlesData: _buildDualTitles(allDates, minW, maxW, hasWeight),
                    gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1)),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipColor: (touchedSpot) => Colors.indigo.shade900,
                        getTooltipItems: (List<LineBarSpot> touchedSpots) {
                          return touchedSpots.map((s) {
                            if (s.barIndex == 0) {
                              return LineTooltipItem(
                                'Homogénéité\n',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                children: [TextSpan(text: '${s.y.toStringAsFixed(1)}%', style: TextStyle(color: homogColor, fontSize: 11, fontWeight: FontWeight.w900))],
                              );
                            }
                            final realWeight = minW + (s.y / 100) * (maxW - minW);
                            return LineTooltipItem(
                              'Poids moyen\n',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              children: [TextSpan(text: '${realWeight.toStringAsFixed(0)}g', style: const TextStyle(color: weightColor, fontSize: 11, fontWeight: FontWeight.w900))],
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
        const SizedBox(height: 16),
        _buildCombinedLegend(homogColor, weightColor, hasWeight),
        const SizedBox(height: 32),
      ],
    );
  }

  FlTitlesData _buildDualTitles(List<DateTime> dates, double minW, double maxW, bool hasWeight) {
    if (dates.isEmpty) return const FlTitlesData();
    double minX = dates.map((d) => d.millisecondsSinceEpoch.toDouble()).reduce((a, b) => a < b ? a : b);
    double maxX = dates.map((d) => d.millisecondsSinceEpoch.toDouble()).reduce((a, b) => a > b ? a : b);
    double? bottomInterval;
    if (maxX > minX) bottomInterval = (maxX - minX) / 4.0;

    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 32,
          interval: bottomInterval,
          getTitlesWidget: (value, meta) {
            final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
            return SideTitleWidget(meta: meta, space: 10, child: Text(DateFormat('dd/MM').format(date), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade400)));
          },
        ),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 40,
          getTitlesWidget: (value, meta) {
            if (value % 20 != 0) return const SizedBox();
            return SideTitleWidget(meta: meta, child: Text('${value.toInt()}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.grey.shade400)));
          },
        ),
      ),
      rightTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: hasWeight,
          reservedSize: 44,
          getTitlesWidget: (value, meta) {
            if (!hasWeight || value % 20 != 0) return const SizedBox();
            final realWeight = minW + (value / 100) * (maxW - minW);
            return SideTitleWidget(meta: meta, child: Text('${realWeight.toStringAsFixed(0)}g', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.green.shade400)));
          },
        ),
      ),
    );
  }

  Widget _buildCombinedLegend(Color homogColor, Color weightColor, bool hasWeight) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: homogColor, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            const Text('Homogénéité (%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ]),
          if (hasWeight)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: weightColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('Poids moyen (g)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
        ],
      ),
    );
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
