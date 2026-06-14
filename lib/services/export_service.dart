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

class ExportService {
  static Future<void> exportToPdf(WeighingSession session) async {
    final pdf = pw.Document();

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
                      pw.Text('RAPPORT DE PESÉE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
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

            // Condensed Info Card
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfInfoItem('Opérateur', session.operator),
                  _buildPdfInfoItem('Sexe', session.sex ?? 'Tout'),
                  _buildPdfInfoItem('Âge', '${session.age} jours'),
                  _buildPdfInfoItem('Total Sujets', '${session.weights.length}'),
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // Statistics Section
            pw.Text('STATISTIQUES GÉNÉRALES', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.Divider(thickness: 1),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Poids Moyen', '${mean.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('Homogénéité', '${session.homogeneity.toStringAsFixed(1)} %')),
                pw.Expanded(child: _buildPdfStatItem('Écart-Type', sd.toStringAsFixed(2))),
                pw.Expanded(child: _buildPdfStatItem('CV (%)', '${cv.toStringAsFixed(2)} %')),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Minimum', '${minWeight.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('Maximum', '${maxWeight.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('Plage +/- 10%', '${minus10.toStringAsFixed(0)} - ${plus10.toStringAsFixed(0)} g')),
                pw.Expanded(child: pw.SizedBox()),
              ],
            ),
            pw.SizedBox(height: 30),

            // Legend
            pw.Row(
              children: [
                pw.Container(width: 12, height: 12, color: PdfColors.red),
                pw.SizedBox(width: 5),
                pw.Text('Non Homogène (hors +/- 10%)', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(width: 20),
                pw.Container(width: 12, height: 12, decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey))),
                pw.SizedBox(width: 5),
                pw.Text('Homogène', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.SizedBox(height: 10),

            // Weights Table
            pw.Text('DÉTAIL DES PESÉES', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            _buildWeightsGrid(session.weights, minus10, plus10),
            pw.SizedBox(height: 30),

            // Distribution Chart (Simple Histogram)
            pw.Text('DISTRIBUTION DES POIDS', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 10),
            _buildPdfHistogram(session.weights),
          ];
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'Pesee_${session.farmName}_${DateFormat('yyyyMMdd').format(session.timestamp)}.pdf');
  }

  static pw.Widget _buildPdfHistogram(List<double> weights) {
    if (weights.isEmpty) return pw.SizedBox();

    // Create buckets
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
    const int weightsPerLine = 18;
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

    // Metadata
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

    // Stats
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

    // Weights Table
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

    // Save and Share
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
