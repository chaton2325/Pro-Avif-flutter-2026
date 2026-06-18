import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/weighing_session.dart';
import '../models/weight_standard.dart';
import '../models/weight_history_entry.dart';
import '../services/mongo_service.dart';

class ExportService {
  static Future<void> exportToPdf(WeighingSession session) async {
    final pdf = pw.Document();
    final mongoService = MongoService();

    // Fetch data for charts
    List<WeightStandard> standards = [];
    List<WeightHistoryEntry> history = [];
    List<dynamic> homogeneityHistory = [];
    try {
      final results = await Future.wait([
        mongoService.getWeightStandards(session.sex ?? 'Mâle'),
        mongoService.getWeightEvolution(
          farmName: session.farmName,
          roomName: session.roomName,
          sex: session.sex ?? 'Mâle',
          lotNumber: session.lotNumber,
        ),
        mongoService.getRoomHomogeneityHistory(
          session.farmName,
          session.roomName,
          session.sex ?? 'Mâle',
          lotNumber: session.lotNumber,
        ),
      ]);
      standards = results[0] as List<WeightStandard>;
      history = results[1] as List<WeightHistoryEntry>;
      homogeneityHistory = results[2] as List<dynamic>;
      
      standards.sort((a, b) => a.week.compareTo(b.week));
      history.sort((a, b) => a.week.compareTo(b.week));
      // Sort homogeneity history by date
      homogeneityHistory.sort((a, b) => DateTime.parse(a['date']).compareTo(DateTime.parse(b['date'])));
    } catch (e) {
      print("Error fetching report data: $e");
    }

    // Stats calculations
    final double sum = session.weights.reduce((a, b) => a + b);
    final double mean = sum / session.weights.length;
    final double plus10 = mean * 1.10;
    final double minus10 = mean * 0.90;
    
    // Variance and SD
    final double variance = session.weights.map((w) => pow(w - mean, 2)).reduce((a, b) => a + b) / session.weights.length;
    final double sd = sqrt(variance);
    final double cv = (sd / mean) * 100;
    
    final double minWeight = session.weights.reduce((a, b) => a < b ? a : b);
    final double maxWeight = session.weights.reduce((a, b) => a > b ? a : b);

    // Homogeneous count
    final int homogeneousCount = session.weights.where((w) => w >= minus10 && w <= plus10).length;
    final int totalCount = session.weights.length;

    // Diagnostic
    String diagnostic = "CONFORME";
    double standardWeight = 0;
    double gap = 0;
    PdfColor diagColor = PdfColors.green;
    if (standards.isNotEmpty) {
      final std = standards.firstWhere((s) => s.week == session.age, orElse: () => standards.last);
      standardWeight = std.weight;
      gap = mean - standardWeight;
      
      if (mean < standardWeight) {
        diagnostic = "SOUS-POIDS";
        diagColor = PdfColors.orange;
      } else if (mean > standardWeight) {
        diagnostic = "SUR-POIDS";
        diagColor = PdfColors.purple;
      } else {
        diagnostic = "CONFORME";
        diagColor = PdfColors.green;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('RAPPORT DE PESEE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      pw.Text('Généré le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Site: ${session.farmName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      pw.Text('Salle: ${session.roomName}'),
                      pw.Text('Lot: ${session.lotNumber ?? 'N/A'}'),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Diagnostic Badge
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: pw.BoxDecoration(
                color: diagColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('STATUT CROISSANCE :', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                  pw.Text(diagnostic, style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Performance Analysis Section
            pw.Text('ANALYSE DE PERFORMANCE VS STANDARD', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Poids Moyen Réel', '${mean.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('Norme Standard', '${standardWeight.toStringAsFixed(0)} g')),
                pw.Expanded(child: _buildPdfStatItem('Écart (g)', '${gap >= 0 ? "+" : ""}${gap.toStringAsFixed(1)} g', color: diagColor)),
                pw.Expanded(child: _buildPdfStatItem('Âge', '${session.age} sem.')),
              ],
            ),
            pw.SizedBox(height: 20),

            // Statistics Section
            pw.Text('STATISTIQUES DE LA PESÉE', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Intervalle Inf. Saisie', '${session.lowerInterval?.toStringAsFixed(0) ?? "N/A"} g')),
                pw.Expanded(child: _buildPdfStatItem('Intervalle Sup. Saisie', '${session.upperInterval?.toStringAsFixed(0) ?? "N/A"} g')),
                pw.Expanded(child: _buildPdfStatItem('Homogénéité', '${session.homogeneity.toStringAsFixed(1)} %')),
                pw.Expanded(child: _buildPdfStatItem('Sujets Homogènes', '$homogeneousCount / $totalCount')),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('PM - 10%', '${minus10.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('PM + 10%', '${plus10.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('Poids Min', '${minWeight.toStringAsFixed(0)} g')),
                pw.Expanded(child: _buildPdfStatItem('Poids Max', '${maxWeight.toStringAsFixed(0)} g')),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Opérateur', session.operator)),
                pw.Expanded(child: _buildPdfStatItem('Sexe', session.sex ?? 'Tout')),
                pw.Expanded(child: pw.SizedBox()),
                pw.Expanded(child: pw.SizedBox()),
              ],
            ),
            pw.SizedBox(height: 30),

            // Weights Table
            pw.Text('DÉTAIL DES PESÉES ACTUELLES (${session.weights.length} sujets)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            _buildWeightsGrid(session.weights, minus10, plus10),
            pw.SizedBox(height: 8),
            pw.Row(
              children: [
                pw.Container(width: 10, height: 10, color: PdfColors.red),
                pw.SizedBox(width: 8),
                pw.Text('Note : Les cases sur fond rouge indiquent les sujets non homogènes (hors de l\'intervalle PM +/- 10%)', 
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700, fontStyle: pw.FontStyle.italic)),
              ],
            ),

            pw.SizedBox(height: 30),

            // Charts Section
            pw.Text('ÉVOLUTION DES PERFORMANCES', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 15),

            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Poids vs Standards (g)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Container(width: double.infinity, child: _buildWeightEvolutionChart(standards, history)),
                pw.SizedBox(height: 25),
                pw.Text('Homogénéité (%)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Container(width: double.infinity, child: _buildHomogeneityEvolutionChart(homogeneityHistory)),
              ],
            ),
            pw.SizedBox(height: 30),


          ];
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Rapport_${session.farmName}_Lot_${session.lotNumber ?? "NA"}.pdf');
  }

  static pw.Widget _buildWeightEvolutionChart(List<WeightStandard> standards, List<WeightHistoryEntry> history) {
    if (standards.isEmpty && history.isEmpty) return pw.SizedBox(height: 100, child: pw.Center(child: pw.Text('Pas de données')));

    return pw.Container(
      height: 150,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis(List.generate(10, (i) => i.toDouble() * 5), format: (v) => 'S${v.toInt()}'),
          yAxis: pw.FixedAxis([0, 1000, 2000, 3000, 4000, 5000], format: (v) => '${v.toInt()}'),
        ),
        datasets: [
          if (standards.isNotEmpty)
            pw.LineDataSet(
              color: PdfColors.green100,
              isCurved: true,
              drawSurface: true,
              surfaceColor: PdfColors.green50,
              data: standards.map((s) => pw.PointChartValue(s.week.toDouble(), s.maxWeight)).toList(),
            ),
          if (history.isNotEmpty)
            pw.LineDataSet(
              color: PdfColors.indigo,
              isCurved: true,
              drawPoints: true,
              pointSize: 2,
              data: history.map((e) => pw.PointChartValue(e.week.toDouble(), e.averageWeight)).toList(),
            ),
        ],
      ),
    );
  }

  static pw.Widget _buildHomogeneityEvolutionChart(List<dynamic> history) {
    if (history.isEmpty) return pw.SizedBox(height: 100, child: pw.Center(child: pw.Text('Pas de données')));

    // Limit to last 10 weighings for readability on X axis
    final recentHistory = history.length > 10 ? history.sublist(history.length - 10) : history;

    return pw.Container(
      height: 150,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis(
            List.generate(recentHistory.length, (i) => i.toDouble()),
            format: (v) {
              int index = v.toInt();
              if (index >= 0 && index < recentHistory.length) {
                final dateStr = recentHistory[index]['date'];
                return DateFormat('dd/MM').format(DateTime.parse(dateStr));
              }
              return '';
            },
          ),
          yAxis: pw.FixedAxis([0, 20, 40, 60, 80, 100], format: (v) => '${v.toInt()}%'),
        ),
        datasets: [
          pw.LineDataSet(
            color: PdfColors.orange,
            isCurved: true,
            drawPoints: true,
            pointSize: 2,
            data: List.generate(recentHistory.length, (i) {
              final h = (recentHistory[i]['homogeneity'] as num).toDouble();
              return pw.PointChartValue(i.toDouble(), h);
            }), 
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfHistogram(List<double> weights) {
    if (weights.isEmpty) return pw.SizedBox();

    final double minW = weights.reduce((a, b) => a < b ? a : b);
    final double maxW = weights.reduce((a, b) => a > b ? a : b);
    final double range = maxW - minW;
    final int bucketCount = 10;
    final double bucketSize = range / bucketCount;

    Map<int, int> buckets = {};
    for (var w in weights) {
      int index = ((w - minW) / bucketSize).floor();
      if (index >= bucketCount) index = bucketCount - 1;
      buckets[index] = (buckets[index] ?? 0) + 1;
    }

    int maxFreq = buckets.values.isEmpty ? 1 : buckets.values.reduce((a, b) => a > b ? a : b);
    if (maxFreq < 1) maxFreq = 1;

    final yTicks = List.generate(5, (i) => (i * maxFreq / 4).toDouble());

    return pw.Container(
      height: 150,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis(
            List.generate(bucketCount, (i) => i.toDouble()),
            format: (v) => (minW + (v * bucketSize)).toStringAsFixed(0),
          ),
          yAxis: pw.FixedAxis(
            yTicks,
            format: (v) => v.toInt().toString(),
          ),
        ),
        datasets: [
          pw.BarDataSet(
            color: PdfColors.indigo400,
            data: List.generate(bucketCount, (i) {
              return pw.PointChartValue(i.toDouble(), (buckets[i] ?? 0).toDouble());
            }),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildPdfInfoItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  static pw.Widget _buildPdfStatItem(String label, String value, {PdfColor? color}) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.indigo700)),
      ],
    );
  }

  static pw.Widget _buildWeightsGrid(List<double> weights, double min, double max) {
    const int weightsPerLine = 21;
    List<pw.Widget> rows = [];

    for (int i = 0; i < weights.length; i += weightsPerLine) {
      int end = (i + weightsPerLine < weights.length) ? i + weightsPerLine : weights.length;
      List<double> lineWeights = weights.sublist(i, end);

      rows.add(
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.start,
          children: lineWeights.map((w) {
            bool isHomogeneous = w >= min && w <= max;
            return pw.Container(
              width: 25,
              height: 18,
              margin: const pw.EdgeInsets.all(1),
              decoration: pw.BoxDecoration(
                color: isHomogeneous ? null : PdfColors.red,
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
              ),
              alignment: pw.Alignment.center,
              child: pw.Text(
                w.toStringAsFixed(0),
                style: pw.TextStyle(
                  fontSize: 7,
                  color: isHomogeneous ? PdfColors.black : PdfColors.white,
                  fontWeight: isHomogeneous ? pw.FontWeight.normal : pw.FontWeight.bold,
                ),
              ),
            );
          }).toList(),
        ),
      );
    }

    return pw.Column(children: rows);
  }

  static Future<void> exportToExcel(WeighingSession session) async {
    final excel = Excel.createExcel();
    final mongoService = MongoService();
    final sheet = excel['Rapport de Pesée'];
    excel.delete('Sheet1');

    // Fetch evolution data for Excel too
    List<WeightStandard> standards = [];
    List<WeightHistoryEntry> history = [];
    try {
      final results = await Future.wait([
        mongoService.getWeightStandards(session.sex ?? 'Mâle'),
        mongoService.getWeightEvolution(
          farmName: session.farmName,
          roomName: session.roomName,
          sex: session.sex ?? 'Mâle',
          lotNumber: session.lotNumber,
        ),
      ]);
      standards = results[0] as List<WeightStandard>;
      history = results[1] as List<WeightHistoryEntry>;
      standards.sort((a, b) => a.week.compareTo(b.week));
      history.sort((a, b) => a.week.compareTo(b.week));
    } catch (e) {
      print("Error fetching evolution data for Excel: $e");
    }

    // Header
    sheet.appendRow([TextCellValue('RAPPORT DE PERFORMANCE - PRO-AVIF')]);
    sheet.appendRow([TextCellValue('Date du rapport: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}')]);
    sheet.appendRow([]);

    // General Info
    sheet.appendRow([TextCellValue('INFORMATIONS GÉNÉRALES')]);
    sheet.appendRow([TextCellValue('Bâtiment (Site)'), TextCellValue(session.farmName)]);
    sheet.appendRow([TextCellValue('Salle'), TextCellValue(session.roomName)]);
    sheet.appendRow([TextCellValue('Numéro de Lot'), TextCellValue(session.lotNumber ?? 'N/A')]);
    sheet.appendRow([TextCellValue('Opérateur'), TextCellValue(session.operator)]);
    sheet.appendRow([TextCellValue('Sexe'), TextCellValue(session.sex ?? 'Tout')]);
    sheet.appendRow([TextCellValue('Âge du lot'), IntCellValue(session.age)]);
    sheet.appendRow([]);

    // Stats calculations
    final double sum = session.weights.reduce((a, b) => a + b);
    final double mean = sum / session.weights.length;
    final double plus10 = mean * 1.10;
    final double minus10 = mean * 0.90;
    final double minWeight = session.weights.reduce((a, b) => a < b ? a : b);
    final double maxWeight = session.weights.reduce((a, b) => a > b ? a : b);

    // Diagnostic
    double standardWeight = 0;
    double gap = 0;
    String status = "CONFORME";
    if (standards.isNotEmpty) {
      final std = standards.firstWhere((s) => s.week == session.age, orElse: () => standards.last);
      standardWeight = std.weight;
      gap = mean - standardWeight;
      if (mean < standardWeight) status = "SOUS-POIDS";
      else if (mean > standardWeight) status = "SUR-POIDS";
    }

    // Performance Analysis Section
    sheet.appendRow([TextCellValue('ANALYSE DE PERFORMANCE VS STANDARD')]);
    sheet.appendRow([TextCellValue('Statut de Croissance'), TextCellValue(status)]);
    sheet.appendRow([TextCellValue('Poids Moyen Réel (g)'), DoubleCellValue(mean)]);
    sheet.appendRow([TextCellValue('Norme Standard (g)'), DoubleCellValue(standardWeight)]);
    sheet.appendRow([TextCellValue('Écart (g)'), DoubleCellValue(gap)]);
    sheet.appendRow([]);

    // Detailed Stats Section
    sheet.appendRow([TextCellValue('STATISTIQUES DÉTAILLÉES')]);
    sheet.appendRow([TextCellValue('Homogénéité (%)'), DoubleCellValue(session.homogeneity)]);
    sheet.appendRow([TextCellValue('Intervalle Inf. Saisie (g)'), DoubleCellValue(session.lowerInterval ?? 0)]);
    sheet.appendRow([TextCellValue('Intervalle Sup. Saisie (g)'), DoubleCellValue(session.upperInterval ?? 0)]);
    sheet.appendRow([TextCellValue('PM - 10% (g)'), DoubleCellValue(minus10)]);
    sheet.appendRow([TextCellValue('PM + 10% (g)'), DoubleCellValue(plus10)]);
    sheet.appendRow([TextCellValue('Poids Minimum (g)'), DoubleCellValue(minWeight)]);
    sheet.appendRow([TextCellValue('Poids Maximum (g)'), DoubleCellValue(maxWeight)]);
    sheet.appendRow([TextCellValue('Total Sujets Pesés'), IntCellValue(session.weights.length)]);
    sheet.appendRow([]);

    // Evolution Data Section (Charts Data)
    sheet.appendRow([TextCellValue('DONNÉES D\'ÉVOLUTION (CHART DATA)')]);
    sheet.appendRow([TextCellValue('Semaine'), TextCellValue('Standard (g)'), TextCellValue('Réel (g)')]);
    
    // Merge standards and history by week for the table
    Set<int> allWeeks = {...standards.map((s) => s.week), ...history.map((h) => h.week)};
    List<int> sortedWeeks = allWeeks.toList()..sort();
    
    for (var week in sortedWeeks) {
      final std = standards.firstWhere((s) => s.week == week, orElse: () => WeightStandard(day: 0, week: week, weight: 0, minWeight: 0, maxWeight: 0));
      final hist = history.firstWhere((h) => h.week == week, orElse: () => WeightHistoryEntry(age: 0, week: week, averageWeight: 0, homogeneity: 0, timestamp: DateTime.now()));
      
      sheet.appendRow([
        IntCellValue(week),
        DoubleCellValue(std.weight),
        DoubleCellValue(hist.averageWeight > 0 ? hist.averageWeight : 0),
      ]);
    }
    sheet.appendRow([]);

    // Detail weights table
    sheet.appendRow([TextCellValue('DÉTAIL DES PESÉES INDIVIDUELLES')]);
    sheet.appendRow([TextCellValue('N° Sujet'), TextCellValue('Poids (g)'), TextCellValue('Statut Homogénéité')]);

    for (int i = 0; i < session.weights.length; i++) {
      final w = session.weights[i];
      final isHomogeneous = w >= minus10 && w <= plus10;
      sheet.appendRow([
        IntCellValue(i + 1),
        DoubleCellValue(w),
        TextCellValue(isHomogeneous ? 'Homogène' : 'Non Homogène'),
      ]);
    }

    final fileBytes = excel.save();
    if (fileBytes != null) {
      final tempDir = await getTemporaryDirectory();
      final fileName = 'Rapport_Complet_${session.farmName}_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Rapport Complet Pro-Avif - ${session.farmName}');
    }
  }
}
