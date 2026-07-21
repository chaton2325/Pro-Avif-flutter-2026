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
    List<dynamic> homogeneityHistory = [];
    try {
      final results = await Future.wait([
        mongoService.getWeightStandards(session.sex ?? 'Mâle'),
        mongoService.getRoomHomogeneityHistory(
          session.farmName,
          session.roomName,
          session.sex ?? 'Mâle',
          lotNumber: session.lotNumber,
        ),
      ]);
      standards = results[0] as List<WeightStandard>;
      homogeneityHistory = results[1] as List<dynamic>;

      standards.sort((a, b) => a.week.compareTo(b.week));
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

    // Variation par rapport à la pesée précédente (semaine N-1) du même lot/salle/sexe
    double? variationN1;
    final priorEntries = homogeneityHistory.where((h) => h['age'] != null && (h['age'] as num) < session.age).toList();
    if (priorEntries.isNotEmpty) {
      priorEntries.sort((a, b) => (a['age'] as num).compareTo(b['age'] as num));
      final previousWeight = (priorEntries.last['avgWeight'] as num?)?.toDouble();
      if (previousWeight != null) variationN1 = mean - previousWeight;
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
                      pw.Text('RAPPORT DE PESEE', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo900)),
                      pw.Text('Généré le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Site: ${session.farmName}  Salle: ${session.roomName}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Lot ${session.lotNumber ?? 'N/A'} - Sexe: ${session.sex ?? 'Tout'}', style: const pw.TextStyle(fontSize: 9)),
                      pw.Text('Opérateur: ${session.operator}', style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // Diagnostic Badge
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: diagColor,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('STATUT CROISSANCE :', style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Text(diagnostic, style: pw.TextStyle(color: PdfColors.white, fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // Performance & Statistics Section (fusionnées pour compacter le rapport)
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('ANALYSE DE PERFORMANCE VS STANDARD', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                pw.Text('${session.age}e sem.', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(child: _buildPdfStatItem('Poids Moyen Réel', '${mean.toStringAsFixed(1)} g')),
                pw.Expanded(child: _buildPdfStatItem('Standard', '${standardWeight.toStringAsFixed(0)} g')),
                pw.Expanded(child: _buildPdfStatItem('Écart vs Std', '${gap >= 0 ? "+" : ""}${gap.toStringAsFixed(1)} g', color: diagColor)),
                pw.Expanded(child: _buildPdfStatItem('Homogénéité', '${session.homogeneity.toStringAsFixed(1)} %')),
                pw.Expanded(child: _buildPdfStatItem('Sujets Homog.', '$homogeneousCount / $totalCount')),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Row(
              children: [
                pw.Expanded(
                  child: _buildPdfStatItem(
                    'Variation N-1',
                    variationN1 == null ? 'N/A' : '${variationN1 >= 0 ? "+" : ""}${variationN1.toStringAsFixed(1)} g',
                    color: variationN1 != null && variationN1 < 0 ? PdfColors.red : null,
                  ),
                ),
                pw.Expanded(child: _buildPdfStatItem('Intervalle Saisi', '${session.lowerInterval?.toStringAsFixed(0) ?? "N/A"} - ${session.upperInterval?.toStringAsFixed(0) ?? "N/A"} g')),
                pw.Expanded(child: _buildPdfStatItem('Poids Min-Max', '${minWeight.toStringAsFixed(0)} - ${maxWeight.toStringAsFixed(0)} g')),
              ],
            ),
            pw.SizedBox(height: 14),

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

            pw.SizedBox(height: 14),

            // Charts Section
            pw.Text('ÉVOLUTION DES PERFORMANCES', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 8),

            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('Homogénéité & Poids Moyen (par semaine)', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Row(
                      children: [
                        _legendDot(PdfColors.orange),
                        pw.SizedBox(width: 3),
                        pw.Text('Homogénéité (%) - gauche', style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(width: 10),
                        _legendDot(PdfColors.indigo),
                        pw.SizedBox(width: 3),
                        pw.Text('Poids moyen réel (g) - droite', style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(width: 10),
                        _legendDot(PdfColors.green700),
                        pw.SizedBox(width: 3),
                        pw.Text('Poids moyen standard (g) - droite', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 5),
                pw.Container(width: double.infinity, child: _buildHomogeneityWeightChart(homogeneityHistory, standards)),
              ],
            ),
            pw.SizedBox(height: 30),

          ];
        },
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: _buildReportFileName(session, 'pdf'));
  }

  /// Nom de fichier au format Pesee_Batiment_Lot_Salle_Semaine_ChaineUnique, avec un
  /// suffixe basé sur l'horodatage pour éviter toute collision entre rapports générés.
  static String _buildReportFileName(WeighingSession session, String extension) {
    String clean(String value) => value.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '').replaceAll(RegExp(r'\s+'), '_');

    final farm = clean(session.farmName);
    final room = clean(session.roomName);
    final lot = clean(session.lotNumber ?? 'NA');
    final uniqueId = DateTime.now().millisecondsSinceEpoch.toString();

    return 'Pesee_${farm}_${lot}_${room}_S${session.age}_$uniqueId.$extension';
  }

  /// Homogénéité (%), poids moyen réel (g) et poids moyen standard (g) sur un même
  /// graphique, en abscisse les semaines. Le package `pdf` ne supporte qu'un seul système
  /// d'axes par graphique : l'homogénéité (échelle réelle 0-100%) sert d'axe gauche natif,
  /// et les deux courbes de poids sont projetées sur cette même échelle 0-100 pour être
  /// tracées sur la grille ; l'axe droit n'est qu'un habillage visuel affichant les vraies
  /// valeurs de poids aux mêmes hauteurs.
  static pw.Widget _buildHomogeneityWeightChart(List<dynamic> history, List<WeightStandard> standards) {
    if (history.isEmpty) return pw.SizedBox(height: 100, child: pw.Center(child: pw.Text('Pas de données')));

    // Une seule entrée par semaine (l'âge est déjà exprimé en semaines côté backend)
    final Map<int, dynamic> byWeek = {};
    for (final h in history) {
      if (h['age'] == null) continue;
      byWeek[(h['age'] as num).toInt()] = h;
    }
    final entries = byWeek.values.toList()..sort((a, b) => (a['age'] as num).compareTo(b['age'] as num));

    if (entries.isEmpty) return pw.SizedBox(height: 100, child: pw.Center(child: pw.Text('Pas de données')));

    final weeksInt = entries.map((e) => (e['age'] as num).toInt()).toList();
    final weeks = weeksInt.map((w) => w.toDouble()).toList();

    // Norme standard correspondant à chaque semaine observée (première entrée du CSV pour cette semaine)
    final Map<int, double> standardByWeek = {};
    for (final w in weeksInt) {
      for (final s in standards) {
        if (s.week == w) {
          standardByWeek[w] = s.weight;
          break;
        }
      }
    }

    final weightValues = entries.map((e) => (e['avgWeight'] as num?)?.toDouble()).whereType<double>().toList();
    final allWeightValues = [...weightValues, ...standardByWeek.values];
    final double minWeight = allWeightValues.isEmpty ? 0 : allWeightValues.reduce((a, b) => a < b ? a : b);
    final double maxWeight = allWeightValues.isEmpty ? 1 : allWeightValues.reduce((a, b) => a > b ? a : b);
    final double weightSpan = (maxWeight - minWeight).abs() < 0.001 ? 1 : (maxWeight - minWeight);

    double projectWeight(double w) => ((w - minWeight) / weightSpan) * 100;

    const homogeneityTicks = [0.0, 20.0, 40.0, 60.0, 80.0, 100.0];

    // Texte des axes réduit et espacement resserré pour que toutes les semaines,
    // depuis la première pesée du lot, restent lisibles sur une largeur A4 portrait.
    const axisTextStyle = pw.TextStyle(fontSize: 6, color: PdfColors.grey800);

    return pw.Container(
      height: 180,
      child: pw.Chart(
        grid: pw.CartesianGrid(
          xAxis: pw.FixedAxis(
            weeks,
            format: (v) => 'S${v.toInt()}',
            textStyle: axisTextStyle,
            margin: 4,
            divisions: true,
            divisionsColor: PdfColors.grey300,
          ),
          yAxis: pw.FixedAxis(
            homogeneityTicks,
            format: (v) => '${v.toInt()}%',
            textStyle: axisTextStyle,
            margin: 4,
            divisions: true,
            divisionsColor: PdfColors.grey300,
          ),
        ),
        right: pw.Padding(
          padding: const pw.EdgeInsets.only(left: 4),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: homogeneityTicks.reversed.map((t) {
              final w = minWeight + (t / 100) * weightSpan;
              return pw.Text('${w.toStringAsFixed(0)}g', style: pw.TextStyle(fontSize: 6, color: PdfColors.indigo));
            }).toList(),
          ),
        ),
        datasets: [
          pw.LineDataSet(
            color: PdfColors.orange,
            isCurved: true,
            drawPoints: true,
            pointSize: 1.5,
            data: entries.map((e) {
              final week = (e['age'] as num).toDouble();
              final homo = (e['homogeneity'] as num?)?.toDouble() ?? 0;
              return pw.PointChartValue(week, homo);
            }).toList(),
          ),
          pw.LineDataSet(
            color: PdfColors.indigo,
            isCurved: true,
            drawPoints: true,
            pointSize: 1.5,
            data: entries.where((e) => e['avgWeight'] != null).map((e) {
              final week = (e['age'] as num).toDouble();
              final w = (e['avgWeight'] as num).toDouble();
              return pw.PointChartValue(week, projectWeight(w));
            }).toList(),
          ),
          if (standardByWeek.isNotEmpty)
            pw.LineDataSet(
              color: PdfColors.green700,
              isCurved: true,
              drawPoints: true,
              pointSize: 1.5,
              data: weeksInt.where((w) => standardByWeek.containsKey(w)).map((w) {
                return pw.PointChartValue(w.toDouble(), projectWeight(standardByWeek[w]!));
              }).toList(),
            ),
        ],
      ),
    );
  }

  static pw.Widget _legendDot(PdfColor color) {
    return pw.Container(
      width: 6,
      height: 6,
      decoration: pw.BoxDecoration(color: color, shape: pw.BoxShape.circle),
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
        pw.Text(label, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
        pw.Text(value, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color ?? PdfColors.indigo700)),
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
      final fileName = _buildReportFileName(session, 'xlsx');
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(fileBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Rapport Complet Pro-Avif - ${session.farmName}');
    }
  }
}
