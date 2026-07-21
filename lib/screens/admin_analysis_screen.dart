import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/farm.dart';
import '../models/lot.dart';
import '../models/weight_history_entry.dart';
import '../models/weight_standard.dart';
import '../services/mongo_service.dart';
import 'fullscreen_analysis_view.dart';

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

  // Visibilité des courbes du graphique combiné (homogénéité / poids moyen / standard)
  bool _showHomogeneityCurve = true;
  bool _showWeightCurve = true;
  bool _showStandardCurve = true;

  Map<String, List<dynamic>> _analysisData = {};
  Map<String, List<WeightHistoryEntry>> _weightData = {};
  final Map<String, List<WeightStandard>> _standardsBySex = {};
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
        _farms = results[0] as List<Farm>..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
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

      // Charge la courbe standard (référence) par sexe, comme dans la fenêtre Croissance.
      final uniqueSexes = formattedData.keys.map(_sexFromKey).toSet();
      await Future.wait(uniqueSexes.map((sex) async {
        if (_standardsBySex.containsKey(sex)) return;
        try {
          _standardsBySex[sex] = await _mongoService.getWeightStandards(sex);
        } catch (_) {
          _standardsBySex[sex] = [];
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

  /// Affiche le détail d'un point de courbe touché (date, semaine, valeurs).
  void _showPointDetailsModal(BuildContext context, {required String title, required Color color, required int week, DateTime? date, required Map<String, String> values}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _modalRow('Semaine', 'S$week'),
            if (date != null) _modalRow('Date', DateFormat('dd/MM/yyyy').format(date)),
            ...values.entries.map((e) => _modalRow(e.key, e.value)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('FERMER', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  /// Construit les valeurs affichées dans le modal d'un point "poids moyen" : la norme
  /// standard de la même semaine (si disponible), la plage attendue, l'écart et le statut.
  Map<String, String> _weightPointDetails(WeightHistoryEntry w, List<WeightStandard> standards) {
    final values = <String, String>{'Poids moyen': '${w.averageWeight.toStringAsFixed(0)}g'};
    WeightStandard? standard;
    for (final s in standards) {
      if (s.week == w.week) {
        standard = s;
        break;
      }
    }
    if (standard != null) {
      final diff = w.averageWeight - standard.weight;
      final diffStr = '${diff >= 0 ? "+" : ""}${diff.toStringAsFixed(0)}g';
      final status = diff.abs() < 1 ? 'CONFORME' : (diff < 0 ? 'SOUS-POIDS' : 'SUR-POIDS');
      values['Norme standard'] = '${standard.weight.toStringAsFixed(0)}g';
      values['Écart vs standard'] = diffStr;
      values['Statut'] = status;
    }
    return values;
  }

  /// Affiche, pour une semaine donnée, toutes les informations disponibles (date, âge,
  /// homogénéité, poids moyen, norme standard) quel que soit le point/la courbe touchée.
  void _showWeekDetailsModal(BuildContext context, {required int week, required Color color, required List<dynamic> homogeneityPoints, required List<WeightHistoryEntry> weightPoints, required List<WeightStandard> standards}) {
    dynamic homogEntry;
    for (final p in homogeneityPoints) {
      if (((p['age'] as num?)?.toInt()) == week) {
        homogEntry = p;
        break;
      }
    }
    WeightHistoryEntry? weightEntry;
    for (final w in weightPoints) {
      if (w.week == week) {
        weightEntry = w;
        break;
      }
    }

    DateTime? date = weightEntry?.timestamp;
    if (homogEntry != null) {
      date = DateTime.tryParse(homogEntry['date'].toString()) ?? date;
    }

    final values = <String, String>{};
    if (homogEntry != null) {
      values['Homogénéité'] = '${(homogEntry['homogeneity'] as num).toStringAsFixed(1)}%';
    }
    if (weightEntry != null) {
      values.addAll(_weightPointDetails(weightEntry, standards));
    } else {
      WeightStandard? standard;
      for (final s in standards) {
        if (s.week == week) {
          standard = s;
          break;
        }
      }
      if (standard != null) {
        values['Norme standard'] = '${standard.weight.toStringAsFixed(0)}g';
      }
    }

    if (values.isEmpty) return;

    _showPointDetailsModal(context, title: 'Semaine S$week', color: color, week: week, date: date, values: values);
  }

  Widget _modalRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
          const SizedBox(width: 16),
          Flexible(child: Text(value, textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
        ],
      ),
    );
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

  // ---------------------------------------------------------------------
  // FILTRES (compacts)
  // ---------------------------------------------------------------------

  Widget _buildControls() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: _compactDropdown<Farm>(
                  value: _selectedFarm,
                  label: 'Site',
                  items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedFarm = val);
                    _loadAnalysisData();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: _compactDropdown<Lot>(
                  value: _selectedLot,
                  label: 'Lot',
                  items: _lots.map((l) => DropdownMenuItem(value: l, child: Text(l.number, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (val) {
                    setState(() => _selectedLot = val);
                    _loadAnalysisData();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _compactDropdown<String?>(
                  value: _selectedSex,
                  label: 'Sexe',
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tout', style: TextStyle(fontSize: 12))),
                    ...['Mâle', 'Femelle'].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))),
                  ],
                  onChanged: (val) {
                    setState(() => _selectedSex = val);
                    _loadAnalysisData();
                  },
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _showLines = !_showLines),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _showLines ? Colors.indigo.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.show_chart, size: 18, color: _showLines ? Colors.indigo : Colors.grey),
                ),
              ),
            ],
          ),
          if (_availableRooms.isNotEmpty) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _compactChoiceChip('Toutes les salles', _selectedRooms.isEmpty, () => setState(() => _selectedRooms.clear()), Colors.indigo),
                  ..._availableRooms.map((room) => _compactChoiceChip(room, _selectedRooms.contains(room), () => _toggleRoom(room), Colors.indigo)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _compactToggleChip('Homogénéité', Colors.indigo, _showHomogeneityCurve, (val) => setState(() => _showHomogeneityCurve = val)),
                _compactToggleChip('Poids moyen', Colors.green, _showWeightCurve, (val) => setState(() => _showWeightCurve = val)),
                _compactToggleChip('Standard', Colors.grey.shade400, _showStandardCurve, (val) => setState(() => _showStandardCurve = val)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactDropdown<T>({required T? value, required String label, required List<DropdownMenuItem<T>> items, required void Function(T?) onChanged}) {
    return DropdownButtonFormField<T>(
      value: value,
      isDense: true,
      isExpanded: true,
      dropdownColor: Colors.white,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 10),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _compactChoiceChip(String label, bool selected, VoidCallback onTap, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: color.withOpacity(0.15),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 4),
      ),
    );
  }

  Widget _compactToggleChip(String label, Color color, bool selected, void Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        avatar: CircleAvatar(backgroundColor: color, radius: 5),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: onChanged,
        selectedColor: color.withOpacity(0.15),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 4),
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

  // ---------------------------------------------------------------------
  // GRAPHIQUES
  // ---------------------------------------------------------------------

  Widget _buildChartSection() {
    List<Widget> children = [];
    final filtered = _filteredAnalysisData;

    // 1. Vue d'ensemble (toutes les courbes d'homogénéité) — masquée si la courbe est décochée
    if (_showHomogeneityCurve) {
      children.add(_buildChartContainer(
        title: 'VUE D\'ENSEMBLE',
        seriesData: filtered,
      ));
    }

    // 2. Graphiques individuels par salle/sexe : homogénéité + poids moyen + standard fusionnés
    int i = 0;
    filtered.forEach((seriesName, points) {
      final sex = _sexFromKey(seriesName);
      children.add(_buildCombinedChartContainer(seriesName, points, _weightData[seriesName] ?? [], _standardsBySex[sex] ?? [], i));
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
          double x = ((p['age'] as num?)?.toDouble() ?? 0);
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
  /// et poids standard de référence (axe droit, g) sur le même tracé, en abscisse l'âge
  /// en semaines. Le poids est normalisé sur 0-100 pour partager l'échelle du graphique ;
  /// les titres de l'axe droit re-convertissent en grammes réels.
  Widget _buildCombinedChartContainer(String title, List<dynamic> homogeneityPoints, List<WeightHistoryEntry> weightPoints, List<WeightStandard> standards, int colorIndex) {
    final homogColor = _seriesColors[colorIndex % _seriesColors.length];
    const weightColor = Colors.green;
    final standardColor = Colors.grey.shade400;

    final realWeeks = weightPoints.map((w) => w.week).toSet();
    final matchedStandards = standards.where((s) => realWeeks.contains(s.week)).toList()
      ..sort((a, b) => a.week.compareTo(b.week));
    final dataHasStandard = matchedStandards.isNotEmpty;
    final dataHasWeight = weightPoints.isNotEmpty;

    final showHomog = _showHomogeneityCurve;
    final showWeight = _showWeightCurve && dataHasWeight;
    final showStandard = _showStandardCurve && dataHasStandard;

    final homogSpots = showHomog ? homogeneityPoints.map((p) {
      double x = ((p['age'] as num?)?.toDouble() ?? 0);
      double y = (p['homogeneity'] as num).toDouble();
      return FlSpot(x, y);
    }).toList() : <FlSpot>[];

    double minW = 0, maxW = 100;
    if (dataHasWeight || dataHasStandard) {
      final values = [
        ...weightPoints.map((w) => w.averageWeight),
        ...matchedStandards.map((s) => s.weight),
      ];
      minW = values.reduce((a, b) => a < b ? a : b);
      maxW = values.reduce((a, b) => a > b ? a : b);
      if (maxW == minW) maxW = minW + 1;
    }
    final weightSpotsNormalized = showWeight ? weightPoints.map((w) {
      double x = w.week.toDouble();
      double normalized = ((w.averageWeight - minW) / (maxW - minW)) * 100;
      return FlSpot(x, normalized);
    }).toList() : <FlSpot>[];
    final standardSpotsNormalized = showStandard ? matchedStandards.map((s) {
      double x = s.week.toDouble();
      double normalized = ((s.weight - minW) / (maxW - minW)) * 100;
      return FlSpot(x, normalized);
    }).toList() : <FlSpot>[];

    final allWeeks = [
      ...homogeneityPoints.map((p) => ((p['age'] as num?)?.toInt() ?? 0)),
      ...weightPoints.map((w) => w.week),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(title.toUpperCase(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900, letterSpacing: 0.5)),
              ),
              IconButton(
                icon: const Icon(Icons.fullscreen, color: Colors.indigo, size: 20),
                tooltip: 'Vue développée',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenCombinedAnalysisView(
                  title: title,
                  homogeneityPoints: homogeneityPoints,
                  weightPoints: weightPoints,
                  standards: standards,
                  seriesColor: homogColor,
                  showHomogeneityCurve: _showHomogeneityCurve,
                  showWeightCurve: _showWeightCurve,
                  showStandardCurve: _showStandardCurve,
                  showLines: _showLines,
                ))),
              ),
            ],
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
          child: allWeeks.isEmpty
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
                      LineChartBarData(
                        spots: standardSpotsNormalized,
                        isCurved: true,
                        color: standardColor,
                        barWidth: _showLines ? 2 : 0,
                        dashArray: const [4, 4],
                        dotData: const FlDotData(show: false),
                      ),
                    ],
                    titlesData: _buildDualTitles(allWeeks, minW, maxW, showWeight || showStandard),
                    gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.05), strokeWidth: 1)),
                    borderData: FlBorderData(show: false),
                    lineTouchData: LineTouchData(
                      touchCallback: (event, response) {
                        if (event is! FlTapUpEvent || response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) return;
                        final week = response.lineBarSpots!.first.x.toInt();
                        _showWeekDetailsModal(context, week: week, color: homogColor, homogeneityPoints: homogeneityPoints, weightPoints: weightPoints, standards: standards);
                      },
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
                            if (s.barIndex == 1) {
                              return LineTooltipItem(
                                'Poids moyen\n',
                                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                children: [TextSpan(text: '${realWeight.toStringAsFixed(0)}g', style: const TextStyle(color: weightColor, fontSize: 11, fontWeight: FontWeight.w900))],
                              );
                            }
                            return LineTooltipItem(
                              'Standard\n',
                              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              children: [TextSpan(text: '${realWeight.toStringAsFixed(0)}g', style: TextStyle(color: standardColor, fontSize: 11, fontWeight: FontWeight.w900))],
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
        _buildCombinedLegend(homogColor, weightColor, standardColor, showHomog, showWeight, showStandard),
        const SizedBox(height: 32),
      ],
    );
  }

  FlTitlesData _buildDualTitles(List<int> weeks, double minW, double maxW, bool hasWeight) {
    if (weeks.isEmpty) return const FlTitlesData();
    double minX = weeks.reduce((a, b) => a < b ? a : b).toDouble();
    double maxX = weeks.reduce((a, b) => a > b ? a : b).toDouble();
    double? bottomInterval;
    if (maxX > minX) bottomInterval = (maxX - minX) / 4.0;
    if (bottomInterval != null && bottomInterval < 1) bottomInterval = 1;

    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: bottomInterval,
          getTitlesWidget: (value, meta) {
            return SideTitleWidget(meta: meta, space: 8, child: Text('S${value.toInt()}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade400)));
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

  Widget _buildCombinedLegend(Color homogColor, Color weightColor, Color standardColor, bool showHomog, bool showWeight, bool showStandard) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          if (showHomog)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: homogColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('Homogénéité (%)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          if (showWeight)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: weightColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              const Text('Poids moyen (g)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
          if (showStandard)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 16, height: 4, decoration: BoxDecoration(color: standardColor, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              const Text('Standard théorique (g)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ]),
        ],
      ),
    );
  }

  Widget _buildChartContainer({
    required String title,
    required Map<String, List<dynamic>> seriesData,
  }) {
    final seriesNames = seriesData.keys.toList();
    final dataValues = seriesData.values.toList();
    final bars = _buildAllLineBars(seriesData);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
          child: Row(
            children: [
              Expanded(
                child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade900, letterSpacing: 0.5)),
              ),
              IconButton(
                icon: const Icon(Icons.fullscreen, color: Colors.indigo, size: 20),
                tooltip: 'Vue développée',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FullscreenOverviewAnalysisView(
                  seriesData: seriesData,
                  seriesColors: _seriesColors,
                  showLines: _showLines,
                ))),
              ),
            ],
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
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent || response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) return;
                  final spot = response.lineBarSpots!.first;
                  final idx = spot.barIndex;
                  if (idx >= dataValues.length || spot.spotIndex >= dataValues[idx].length) return;
                  final p = dataValues[idx][spot.spotIndex];
                  _showPointDetailsModal(context,
                      title: seriesNames[idx],
                      color: _seriesColors[idx % _seriesColors.length],
                      week: spot.x.toInt(),
                      date: DateTime.tryParse(p['date'].toString()),
                      values: {'Homogénéité': '${(p['homogeneity'] as num).toStringAsFixed(1)}%'});
                },
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
        const SizedBox(height: 16),
        _buildLegend(seriesNames),
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

  FlTitlesData _buildTitles(List<List<dynamic>> dataValues) {
    double minX = double.maxFinite;
    double maxX = double.minPositive;
    bool hasData = false;

    for (var points in dataValues) {
      for (var p in points) {
        double x = ((p['age'] as num?)?.toDouble() ?? 0);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        hasData = true;
      }
    }

    if (!hasData) return const FlTitlesData();

    double? bottomInterval;
    if (maxX > minX) bottomInterval = (maxX - minX) / 4.0;
    if (bottomInterval != null && bottomInterval < 1) bottomInterval = 1;

    return FlTitlesData(
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 28,
          interval: bottomInterval,
          getTitlesWidget: (value, meta) {
            return SideTitleWidget(
              meta: meta,
              space: 10,
              child: Text('S${value.toInt()}', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.grey.shade400)),
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
