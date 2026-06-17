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
    String diagnostic = "DANS LES STANDARDS";
    String gapInfo = "";
    PdfColor diagColor = PdfColors.green;
    if (standards.isNotEmpty) {
      final std = standards.firstWhere((s) => s.week == session.age, orElse: () => standards.last);
      if (mean < std.minWeight) {
        double gap = std.weight - mean;
        diagnostic = "SOUS-POIDS";
        gapInfo = " (-${gap.toStringAsFixed(1)} g)";
        diagColor = PdfColors.orange;
      } else if (mean > std.maxWeight) {
        double gap = mean - std.weight;
        diagnostic = "SUR-POIDS";
        gapInfo = " (+${gap.toStringAsFixed(1)} g)";
        diagColor = PdfColors.purple;
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
                      pw.Text('RAPPORT DE PERFORMANCE', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
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
                  pw.Text('$diagnostic$gapInfo', style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Statistics Section
            pw.Text('RÉSUMÉ DE LA PESÉE ACTUELLE', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Poids Moyen (PM)', '${mean.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('PM - 10%', '${minus10.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('PM + 10%', '${plus10.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('Homogénéité', '${session.homogeneity.toStringAsFixed(1)} %')),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Sujets Homogènes', '$homogeneousCount / $totalCount')),
                pw.Expanded(child: _buildPdfStatItem('Opérateur', session.operator)),
                pw.Expanded(child: _buildPdfStatItem('Âge', '${session.age} sem.')),
                pw.Expanded(child: _buildPdfStatItem('Sexe', session.sex ?? 'Tout')),
              ],
            ),
            pw.SizedBox(height: 30),

            // Weights Table
            pw.Text('DÉTAIL DES PESÉES ACTUELLES (${session.weights.length} sujets)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            _buildWeightsGrid(session.weights, minus10, plus10),

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

  static pw.Widget _buildPdfStatItem(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo700)),
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
    final sheet = excel['Rapport de Pesée'];
    excel.delete('Sheet1');

    sheet.appendRow([TextCellValue('RAPPORT DE PESÉE - PRO-AVIF')]);
    sheet.appendRow([TextCellValue('Date: ${DateFormat('dd/MM/yyyy HH:mm').format(session.timestamp)}')]);
    sheet.appendRow([]);

    sheet.appendRow([TextCellValue('INFORMATIONS GÉNÉRALES')]);
    sheet.appendRow([TextCellValue('Ferme'), TextCellValue(session.farmName)]);
    sheet.appendRow([TextCellValue('Salle'), TextCellValue(session.roomName)]);
    sheet.appendRow([TextCellValue('Lot'), TextCellValue(session.lotNumber ?? 'N/A')]);
    sheet.appendRow([TextCellValue('Opérateur'), TextCellValue(session.operator)]);
    sheet.appendRow([TextCellValue('Sexe'), TextCellValue(session.sex ?? 'Tout')]);
    sheet.appendRow([TextCellValue('Âge'), IntCellValue(session.age)]);
    sheet.appendRow([]);

    final double sum = session.weights.reduce((a, b) => a + b);
    final double mean = sum / session.weights.length;
    final double minWeight = session.weights.reduce((a, b) => a < b ? a : b);
    final double maxWeight = session.weights.reduce((a, b) => a > b ? a : b);

    sheet.appendRow([TextCellValue('STATISTIQUES')]);
    sheet.appendRow([TextCellValue('Poids Moyen (g)'), DoubleCellValue(mean)]);
    sheet.appendRow([TextCellValue('Homogénéité (%)'), DoubleCellValue(session.homogeneity)]);
    sheet.appendRow([TextCellValue('Total Sujets'), IntCellValue(session.weights.length)]);
    sheet.appendRow([TextCellValue('Poids Minimum'), DoubleCellValue(minWeight)]);
    sheet.appendRow([TextCellValue('Poids Maximum'), DoubleCellValue(maxWeight)]);
    sheet.appendRow([]);

    sheet.appendRow([TextCellValue('DÉTAIL DES PESÉES')]);
    sheet.appendRow([TextCellValue('N°'), TextCellValue('Poids (g)'), TextCellValue('Statut')]);

    final double plus10 = mean * 1.10;
    final double minus10 = mean * 0.90;

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
      final fileName = 'Pesee_${session.farmName}_${DateFormat('yyyyMMdd').format(session.timestamp)}.xlsx';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Rapport de Pesée - ${session.farmName}');
    }
  }
}
