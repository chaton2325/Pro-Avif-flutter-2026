import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/weight_history_entry.dart';
import '../models/weight_standard.dart';

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

mixin _LandscapeLock<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
    super.dispose();
  }
}

/// Vue plein écran (paysage) du graphique combiné homogénéité + poids moyen + standard
/// pour une salle/sexe/lot donné, avec appui sur un point pour afficher son détail.
class FullscreenCombinedAnalysisView extends StatefulWidget {
  final String title;
  final List<dynamic> homogeneityPoints;
  final List<WeightHistoryEntry> weightPoints;
  final List<WeightStandard> standards;
  final Color seriesColor;
  final bool showHomogeneityCurve;
  final bool showWeightCurve;
  final bool showStandardCurve;
  final bool showLines;

  const FullscreenCombinedAnalysisView({
    super.key,
    required this.title,
    required this.homogeneityPoints,
    required this.weightPoints,
    required this.standards,
    required this.seriesColor,
    required this.showHomogeneityCurve,
    required this.showWeightCurve,
    required this.showStandardCurve,
    required this.showLines,
  });

  @override
  State<FullscreenCombinedAnalysisView> createState() => _FullscreenCombinedAnalysisViewState();
}

class _FullscreenCombinedAnalysisViewState extends State<FullscreenCombinedAnalysisView> with _LandscapeLock {
  @override
  Widget build(BuildContext context) {
    const weightColor = Colors.green;
    final standardColor = Colors.grey.shade400;

    final realWeeks = widget.weightPoints.map((w) => w.week).toSet();
    final matchedStandards = widget.standards.where((s) => realWeeks.contains(s.week)).toList()
      ..sort((a, b) => a.week.compareTo(b.week));
    final dataHasStandard = matchedStandards.isNotEmpty;
    final dataHasWeight = widget.weightPoints.isNotEmpty;

    final showHomog = widget.showHomogeneityCurve;
    final showWeight = widget.showWeightCurve && dataHasWeight;
    final showStandard = widget.showStandardCurve && dataHasStandard;

    final homogSpots = showHomog ? widget.homogeneityPoints.map((p) {
      double x = ((p['age'] as num?)?.toDouble() ?? 0);
      double y = (p['homogeneity'] as num).toDouble();
      return FlSpot(x, y);
    }).toList() : <FlSpot>[];

    double minW = 0, maxW = 100;
    if (dataHasWeight || dataHasStandard) {
      final values = [
        ...widget.weightPoints.map((w) => w.averageWeight),
        ...matchedStandards.map((s) => s.weight),
      ];
      minW = values.reduce((a, b) => a < b ? a : b);
      maxW = values.reduce((a, b) => a > b ? a : b);
      if (maxW == minW) maxW = minW + 1;
    }
    final weightSpotsNormalized = showWeight ? widget.weightPoints.map((w) {
      double normalized = ((w.averageWeight - minW) / (maxW - minW)) * 100;
      return FlSpot(w.week.toDouble(), normalized);
    }).toList() : <FlSpot>[];
    final standardSpotsNormalized = showStandard ? matchedStandards.map((s) {
      double normalized = ((s.weight - minW) / (maxW - minW)) * 100;
      return FlSpot(s.week.toDouble(), normalized);
    }).toList() : <FlSpot>[];

    final allWeeks = [
      ...widget.homogeneityPoints.map((p) => ((p['age'] as num?)?.toInt() ?? 0)),
      ...widget.weightPoints.map((w) => w.week),
    ];

    double minX = 0, maxX = 10;
    if (allWeeks.isNotEmpty) {
      minX = allWeeks.reduce((a, b) => a < b ? a : b).toDouble();
      maxX = allWeeks.reduce((a, b) => a > b ? a : b).toDouble();
    }
    double? bottomInterval = maxX > minX ? (maxX - minX) / 6.0 : null;
    if (bottomInterval != null && bottomInterval < 1) bottomInterval = 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 15)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.indigo), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 28, 12),
        child: allWeeks.isEmpty
            ? const Center(child: Text('Aucune donnée', style: TextStyle(color: Colors.grey)))
            : LineChart(
                LineChartData(
                  minX: minX - 0.5,
                  maxX: maxX + 0.5,
                  minY: 0,
                  maxY: 100,
                  lineBarsData: [
                    LineChartBarData(
                      spots: homogSpots,
                      isCurved: true,
                      color: widget.seriesColor,
                      barWidth: widget.showLines ? 4 : 0,
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 6, color: widget.seriesColor, strokeWidth: 2, strokeColor: Colors.white)),
                      belowBarData: BarAreaData(show: widget.showLines, color: widget.seriesColor.withOpacity(0.03)),
                    ),
                    LineChartBarData(
                      spots: weightSpotsNormalized,
                      isCurved: true,
                      color: weightColor,
                      barWidth: widget.showLines ? 3 : 0,
                      dashArray: const [6, 4],
                      isStrokeCapRound: true,
                      dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 5, color: weightColor, strokeWidth: 2, strokeColor: Colors.white)),
                    ),
                    LineChartBarData(
                      spots: standardSpotsNormalized,
                      isCurved: true,
                      color: standardColor,
                      barWidth: widget.showLines ? 2 : 0,
                      dashArray: const [4, 4],
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                  gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.06), strokeWidth: 1)),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: bottomInterval,
                        getTitlesWidget: (value, meta) => SideTitleWidget(meta: meta, space: 8, child: Text('S${value.toInt()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600))),
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 44,
                        getTitlesWidget: (value, meta) {
                          if (value % 20 != 0) return const SizedBox();
                          return SideTitleWidget(meta: meta, child: Text('${value.toInt()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)));
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: showWeight || showStandard,
                        reservedSize: 54,
                        getTitlesWidget: (value, meta) {
                          if (!(showWeight || showStandard) || value % 20 != 0) return const SizedBox();
                          final realWeight = minW + (value / 100) * (maxW - minW);
                          return SideTitleWidget(meta: meta, child: Text('${realWeight.toStringAsFixed(0)}g', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade600)));
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchCallback: (event, response) {
                      if (event is! FlTapUpEvent || response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) return;
                      final week = response.lineBarSpots!.first.x.toInt();
                      _showWeekDetailsModal(context, week: week, color: widget.seriesColor, homogeneityPoints: widget.homogeneityPoints, weightPoints: widget.weightPoints, standards: widget.standards);
                    },
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) => Colors.indigo.shade900,
                      getTooltipItems: (List<LineBarSpot> touchedSpots) {
                        return touchedSpots.map((s) {
                          if (s.barIndex == 0) {
                            return LineTooltipItem('Homogénéité\n', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                children: [TextSpan(text: '${s.y.toStringAsFixed(1)}%', style: TextStyle(color: widget.seriesColor, fontSize: 11, fontWeight: FontWeight.w900))]);
                          }
                          final realWeight = minW + (s.y / 100) * (maxW - minW);
                          if (s.barIndex == 1) {
                            return LineTooltipItem('Poids moyen\n', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                children: [TextSpan(text: '${realWeight.toStringAsFixed(0)}g', style: const TextStyle(color: weightColor, fontSize: 11, fontWeight: FontWeight.w900))]);
                          }
                          return LineTooltipItem('Standard\n', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              children: [TextSpan(text: '${realWeight.toStringAsFixed(0)}g', style: TextStyle(color: standardColor, fontSize: 11, fontWeight: FontWeight.w900))]);
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Vue plein écran (paysage) de la vue d'ensemble : toutes les courbes d'homogénéité
/// (une par salle/sexe/lot) superposées, avec appui sur un point pour son détail.
class FullscreenOverviewAnalysisView extends StatefulWidget {
  final Map<String, List<dynamic>> seriesData;
  final List<Color> seriesColors;
  final bool showLines;

  const FullscreenOverviewAnalysisView({
    super.key,
    required this.seriesData,
    required this.seriesColors,
    required this.showLines,
  });

  @override
  State<FullscreenOverviewAnalysisView> createState() => _FullscreenOverviewAnalysisViewState();
}

class _FullscreenOverviewAnalysisViewState extends State<FullscreenOverviewAnalysisView> with _LandscapeLock {
  @override
  Widget build(BuildContext context) {
    final seriesNames = widget.seriesData.keys.toList();
    final dataValues = widget.seriesData.values.toList();

    List<LineChartBarData> bars = [];
    List<int> allWeeks = [];
    for (int i = 0; i < dataValues.length; i++) {
      final color = widget.seriesColors[i % widget.seriesColors.length];
      final spots = dataValues[i].map((p) {
        final week = ((p['age'] as num?)?.toInt() ?? 0);
        allWeeks.add(week);
        return FlSpot(week.toDouble(), (p['homogeneity'] as num).toDouble());
      }).toList();
      bars.add(LineChartBarData(
        spots: spots,
        isCurved: true,
        color: color,
        barWidth: widget.showLines ? 4 : 0,
        isStrokeCapRound: true,
        dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 6, color: color, strokeWidth: 2, strokeColor: Colors.white)),
        belowBarData: BarAreaData(show: widget.showLines, color: color.withOpacity(0.03)),
      ));
    }

    double minX = 0, maxX = 10;
    if (allWeeks.isNotEmpty) {
      minX = allWeeks.reduce((a, b) => a < b ? a : b).toDouble();
      maxX = allWeeks.reduce((a, b) => a > b ? a : b).toDouble();
    }
    double? bottomInterval = maxX > minX ? (maxX - minX) / 6.0 : null;
    if (bottomInterval != null && bottomInterval < 1) bottomInterval = 1;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('VUE D\'ENSEMBLE', style: TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold, fontSize: 15)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.indigo), onPressed: () => Navigator.of(context).pop()),
      ),
      body: Row(
        children: [
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
              child: allWeeks.isEmpty
                  ? const Center(child: Text('Aucune donnée', style: TextStyle(color: Colors.grey)))
                  : LineChart(
                      LineChartData(
                        minX: minX - 0.5,
                        maxX: maxX + 0.5,
                        minY: 0,
                        maxY: 100,
                        lineBarsData: bars,
                        gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 10, getDrawingHorizontalLine: (v) => FlLine(color: Colors.grey.withOpacity(0.06), strokeWidth: 1)),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 30,
                              interval: bottomInterval,
                              getTitlesWidget: (value, meta) => SideTitleWidget(meta: meta, space: 8, child: Text('S${value.toInt()}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600))),
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              getTitlesWidget: (value, meta) {
                                if (value % 20 != 0) return const SizedBox();
                                return SideTitleWidget(meta: meta, child: Text('${value.toInt()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)));
                              },
                            ),
                          ),
                        ),
                        lineTouchData: LineTouchData(
                          touchCallback: (event, response) {
                            if (event is! FlTapUpEvent || response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) return;
                            final spot = response.lineBarSpots!.first;
                            final idx = spot.barIndex;
                            if (idx >= dataValues.length || spot.spotIndex >= dataValues[idx].length) return;
                            final p = dataValues[idx][spot.spotIndex];
                            _showPointDetailsModal(context,
                                title: seriesNames[idx],
                                color: widget.seriesColors[idx % widget.seriesColors.length],
                                week: spot.x.toInt(),
                                date: DateTime.tryParse(p['date'].toString()),
                                values: {'Homogénéité': '${(p['homogeneity'] as num).toStringAsFixed(1)}%'});
                          },
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (touchedSpot) => Colors.indigo.shade900,
                            getTooltipItems: (List<LineBarSpot> touchedSpots) {
                              return touchedSpots.map((s) {
                                final name = seriesNames[s.barIndex];
                                return LineTooltipItem('$name\n', const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    children: [TextSpan(text: '${s.y.toStringAsFixed(1)}%', style: TextStyle(color: s.bar.color, fontSize: 11, fontWeight: FontWeight.w900))]);
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Container(
            width: 220,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, border: Border(left: BorderSide(color: Colors.grey.shade200))),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: seriesNames.asMap().entries.map((e) {
                  final color = widget.seriesColors[e.key % widget.seriesColors.length];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
