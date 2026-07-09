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
  bool _showProjected = false;
  bool _showCurve = true;
  bool _showRegression = true;

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
        title: Text('Vue détaillée : ${currentChart['title']}', style: const TextStyle(color: Colors.indigo)),
        backgroundColor: Colors.white,
        elevation: 1,
        actions: [
          _buildActionButton(Icons.auto_graph, _showProjected ? 'Mode Actuel' : 'Mode Projeté', () => setState(() => _showProjected = !_showProjected)),
          _buildActionButton(_showCurve ? Icons.show_chart : Icons.hide_source, 'Ligne', () => setState(() => _showCurve = !_showCurve)),
          _buildActionButton(_showRegression ? Icons.trending_up : Icons.trending_flat, 'Régression', () => setState(() => _showRegression = !_showRegression)),
        ],
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.indigo),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: _currentIndex > 0 ? () => setState(() => _currentIndex--) : null),
          Expanded(
            child: _buildChart(
              currentChart['title'] as String,
              currentChart['history'] as List<dynamic>,
              currentChart['before'] as double,
              currentChart['after'] as double,
              currentChart['positive'] as bool,
            ),
          ),
          IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: _currentIndex < charts.length - 1 ? () => setState(() => _currentIndex++) : null),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: TextButton.icon(
        icon: Icon(icon, color: Colors.indigo, size: 18),
        label: Text(label, style: const TextStyle(color: Colors.indigo, fontSize: 12, fontWeight: FontWeight.bold)),
        onPressed: onPressed,
        style: TextButton.styleFrom(backgroundColor: Colors.indigo.shade50),
      ),
    );
  }

  Widget _buildChart(String title, List<dynamic> history, double current, double predicted, bool isPositive) {
    // Abscisses en semaines (âge du lot), comme dans le module Analyse.
    final sortedHistory = List<dynamic>.from(history)..sort((a, b) => ((a['age'] as num?) ?? 0).compareTo((b['age'] as num?) ?? 0));
    List<FlSpot> historicalSpots = sortedHistory.map((p) => FlSpot(((p['age'] as num?)?.toDouble() ?? 0), (p['homogeneity'] as num).toDouble())).toList();

    double lastWeek = historicalSpots.isNotEmpty ? historicalSpots.last.x : 0;

    List<FlSpot> displaySpots = List.from(historicalSpots);
    if (_showProjected && displaySpots.isNotEmpty) {
      displaySpots.removeLast();
      displaySpots.add(FlSpot(lastWeek, predicted));
    }

    // Régression linéaire de l'homogénéité, prolongée d'une semaine (S+1 ≈ 7 jours).
    List<FlSpot> regressionSpots = [];
    FlSpot? prediction7DaySpot;
    if (_showRegression && displaySpots.length > 1) {
      double n = displaySpots.length.toDouble();
      double sumX = displaySpots.fold(0.0, (sum, spot) => sum + spot.x);
      double sumY = displaySpots.fold(0.0, (sum, spot) => sum + spot.y);
      double sumXY = displaySpots.fold(0.0, (sum, spot) => sum + (spot.x * spot.y));
      double sumX2 = displaySpots.fold(0.0, (sum, spot) => sum + (spot.x * spot.x));

      double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      double intercept = (sumY - slope * sumX) / n;

      double xNextWeek = displaySpots.last.x + 1;
      double yNextWeek = (slope * xNextWeek + intercept).clamp(0.0, 100.0);

      prediction7DaySpot = FlSpot(xNextWeek, yNextWeek);

      regressionSpots = [
        FlSpot(displaySpots.first.x, slope * displaySpots.first.x + intercept),
        prediction7DaySpot,
      ];
    }

    // ---- Poids moyen (axe droit) + régression à S+1 ----
    final weightEntries = sortedHistory.where((p) => p['avgWeight'] != null).toList();
    List<FlSpot> weightRawSpots = weightEntries.map((p) => FlSpot(((p['age'] as num?)?.toDouble() ?? 0), (p['avgWeight'] as num).toDouble())).toList();

    List<FlSpot> weightRegressionRaw = [];
    if (_showRegression && weightRawSpots.length > 1) {
      double n = weightRawSpots.length.toDouble();
      double sumX = weightRawSpots.fold(0.0, (sum, spot) => sum + spot.x);
      double sumY = weightRawSpots.fold(0.0, (sum, spot) => sum + spot.y);
      double sumXY = weightRawSpots.fold(0.0, (sum, spot) => sum + (spot.x * spot.y));
      double sumX2 = weightRawSpots.fold(0.0, (sum, spot) => sum + (spot.x * spot.x));

      double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
      double intercept = (sumY - slope * sumX) / n;

      double xNextWeek = weightRawSpots.last.x + 1;
      double yNextWeek = slope * xNextWeek + intercept;
      if (yNextWeek < 0) yNextWeek = 0;

      weightRegressionRaw = [
        FlSpot(weightRawSpots.first.x, slope * weightRawSpots.first.x + intercept),
        FlSpot(xNextWeek, yNextWeek),
      ];
    }

    // Normalisation 0-100 pour partager l'échelle ; l'axe droit ré-affiche les grammes réels.
    final hasWeight = weightRawSpots.isNotEmpty;
    double minW = 0, maxW = 1;
    if (hasWeight) {
      final allW = [...weightRawSpots.map((s) => s.y), ...weightRegressionRaw.map((s) => s.y)];
      minW = allW.reduce((a, b) => a < b ? a : b);
      maxW = allW.reduce((a, b) => a > b ? a : b);
      if (maxW == minW) maxW = minW + 1;
    }
    double normW(double y) => ((y - minW) / (maxW - minW)) * 100;
    List<FlSpot> weightSpots = weightRawSpots.map((s) => FlSpot(s.x, normW(s.y))).toList();
    List<FlSpot> weightRegSpots = weightRegressionRaw.map((s) => FlSpot(s.x, normW(s.y))).toList();

    double minX = displaySpots.isNotEmpty ? displaySpots.first.x : lastWeek;
    if (weightSpots.isNotEmpty && weightSpots.first.x < minX) minX = weightSpots.first.x;
    double maxX = prediction7DaySpot != null ? prediction7DaySpot.x : lastWeek + 1;
    if (weightRegSpots.isNotEmpty && weightRegSpots.last.x > maxX) maxX = weightRegSpots.last.x;
    if (weightSpots.isNotEmpty && weightSpots.last.x > maxX) maxX = weightSpots.last.x;

    double weekInterval = ((maxX - minX) / 6.0).ceilToDouble();
    if (weekInterval < 1) weekInterval = 1;

    // Construction des courbes avec suivi des index (les barres sont conditionnelles).
    final bars = <LineChartBarData>[];
    int homogRegIdx = -1, weightCurveIdx = -1, weightRegIdx = -1;
    if (_showCurve) {
      bars.add(LineChartBarData(spots: displaySpots, isCurved: true, color: _showProjected ? (isPositive ? Colors.green : Colors.red) : Colors.grey.shade400, barWidth: 2, dotData: const FlDotData(show: false)));
    }
    bars.add(LineChartBarData(
      spots: displaySpots,
      isCurved: false,
      color: Colors.transparent,
      dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: _showProjected ? (isPositive ? Colors.green : Colors.red) : Colors.grey.shade400)),
    ));
    if (_showRegression && regressionSpots.isNotEmpty) {
      homogRegIdx = bars.length;
      bars.add(LineChartBarData(
        spots: regressionSpots,
        isCurved: false,
        color: Colors.blue.shade800,
        barWidth: 2,
        dashArray: [5, 5],
        dotData: FlDotData(
          show: true,
          getDotPainter: (s, p, b, i) => i == 1
              ? FlDotCirclePainter(radius: 6, color: Colors.purple, strokeWidth: 2, strokeColor: Colors.white)
              : FlDotCirclePainter(radius: 3, color: Colors.blue.shade800, strokeWidth: 1, strokeColor: Colors.white),
        ),
      ));
    }
    if (hasWeight) {
      weightCurveIdx = bars.length;
      bars.add(LineChartBarData(
        spots: weightSpots,
        isCurved: true,
        color: Colors.green,
        barWidth: 3,
        dashArray: const [6, 4],
        isStrokeCapRound: true,
        dotData: FlDotData(show: true, getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 4, color: Colors.green, strokeWidth: 2, strokeColor: Colors.white)),
      ));
    }
    if (weightRegSpots.isNotEmpty) {
      weightRegIdx = bars.length;
      bars.add(LineChartBarData(
        spots: weightRegSpots,
        isCurved: false,
        color: Colors.teal.shade700,
        barWidth: 2,
        dashArray: [5, 5],
        dotData: FlDotData(
          show: true,
          getDotPainter: (s, p, b, i) => i == 1
              ? FlDotCirclePainter(radius: 6, color: Colors.teal, strokeWidth: 2, strokeColor: Colors.white)
              : FlDotCirclePainter(radius: 3, color: Colors.teal.shade700, strokeWidth: 1, strokeColor: Colors.white),
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _chartLegendItem('Homogénéité (%)', Colors.grey.shade400),
              if (_showRegression) _chartLegendItem('Régression homog.', Colors.blue.shade800),
              if (hasWeight) _chartLegendItem('Poids moyen (g)', Colors.green),
              if (weightRegSpots.isNotEmpty) _chartLegendItem('Poids prédit (+1 sem)', Colors.teal),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(LineChartData(
              minY: -5, maxY: 105, minX: minX, maxX: maxX,
              lineBarsData: bars,
              lineTouchData: LineTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchCallback: (event, response) {
                  if (event is! FlTapUpEvent || response == null || response.lineBarSpots == null || response.lineBarSpots!.isEmpty) return;
                  final week = response.lineBarSpots!.first.x.round();
                  _showPointModal(
                    week: week,
                    sortedHistory: sortedHistory,
                    lastRealWeek: lastWeek.round(),
                    predictedHomogeneity: prediction7DaySpot != null && prediction7DaySpot.x.round() == week ? prediction7DaySpot.y : null,
                    predictedWeight: weightRegressionRaw.isNotEmpty && weightRegressionRaw.last.x.round() == week ? weightRegressionRaw.last.y : null,
                  );
                },
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (spot) => Colors.indigo.shade50,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final week = 'S${spot.x.round()}';

                      if (spot.barIndex == weightCurveIdx || spot.barIndex == weightRegIdx) {
                        final realWeight = minW + (spot.y / 100) * (maxW - minW);
                        if (spot.barIndex == weightRegIdx && spot.spotIndex == 1) {
                          return LineTooltipItem('Poids prédit (+1 sem)\n$week: ${realWeight.toStringAsFixed(0)}g', const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold));
                        }
                        return LineTooltipItem('$week: ${realWeight.toStringAsFixed(0)}g', const TextStyle(color: Colors.green, fontWeight: FontWeight.bold));
                      }

                      String text = '$week: ${spot.y.toStringAsFixed(1)}%';
                      if (spot.barIndex == homogRegIdx && spot.spotIndex == 1) {
                         final lastHistValue = historicalSpots.isNotEmpty ? historicalSpots.last.y : current;
                         text += '\nGain (vs dernier): ${((spot.y - lastHistValue) / lastHistValue * 100).toStringAsFixed(1)}%';
                         return LineTooltipItem(text, const TextStyle(color: Colors.purple, fontWeight: FontWeight.bold));
                      }

                      return LineTooltipItem(text, const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold));
                    }).toList();
                  }
                )
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, interval: weekInterval, reservedSize: 25, getTitlesWidget: (v, m) => Text('S${v.toInt()}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)))),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (v, m) => Text('${v.toInt()}%', style: const TextStyle(fontSize: 10)))),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: hasWeight, reservedSize: 42, getTitlesWidget: (v, m) {
                  if (!hasWeight || v % 20 != 0 || v < 0 || v > 100) return const SizedBox();
                  final realWeight = minW + (v / 100) * (maxW - minW);
                  return Text('${realWeight.toStringAsFixed(0)}g', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green.shade600));
                })),
              ),
            )),
          ),
        ],
      ),
    );
  }

  /// Modal affiché au clic sur un point : date, semaine, homogénéité, poids moyen
  /// (et valeurs prédites si le point est la projection à +1 semaine).
  void _showPointModal({
    required int week,
    required List<dynamic> sortedHistory,
    required int lastRealWeek,
    double? predictedHomogeneity,
    double? predictedWeight,
  }) {
    dynamic entry;
    for (final p in sortedHistory) {
      if (((p['age'] as num?)?.round() ?? -1) == week) {
        entry = p;
        break;
      }
    }

    final isPrediction = entry == null && week > lastRealWeek;
    final values = <String, String>{};
    DateTime? date;

    if (entry != null) {
      date = DateTime.tryParse(entry['date'].toString());
      values['Homogénéité'] = '${(entry['homogeneity'] as num).toStringAsFixed(1)}%';
      if (entry['avgWeight'] != null) {
        values['Poids moyen'] = '${(entry['avgWeight'] as num).toStringAsFixed(0)}g';
      }
    }
    if (isPrediction) {
      if (predictedHomogeneity != null) values['Homogénéité prédite'] = '${predictedHomogeneity.toStringAsFixed(1)}%';
      if (predictedWeight != null) values['Poids moyen prédit'] = '${predictedWeight.toStringAsFixed(0)}g';
    }

    if (values.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 12, height: 12, decoration: BoxDecoration(color: isPrediction ? Colors.teal : Colors.indigo, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(isPrediction ? 'Prédiction S$week (+1 sem)' : 'Semaine S$week', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
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

  Widget _chartLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
      ],
    );
  }
}
