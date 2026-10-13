import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/farm_daily_report.dart';
import 'mongo_service.dart';

// Palette du module Rapport Journalier (voir DailyReportColors), en couleurs PDF. Une couleur =
// un sens : vert = structure/validé, rose/bleu = femelles/mâles, rouge = mortalité,
// ambre = aliment, violet = production, bleu clair = eau.
const _green900 = PdfColor.fromInt(0xFF12331A);
const _green700 = PdfColor.fromInt(0xFF206B2E);
const _green100 = PdfColor.fromInt(0xFFE2F3E1);
const _amber = PdfColor.fromInt(0xFFA8720C);
const _amberBg = PdfColor.fromInt(0xFFFDF1DA);
const _purple = PdfColor.fromInt(0xFF6D28D9);
const _purpleBg = PdfColor.fromInt(0xFFEDE4FB);
const _blue = PdfColor.fromInt(0xFF1D6FB8);
const _blueBg = PdfColor.fromInt(0xFFE0EDF9);
const _red = PdfColor.fromInt(0xFFC62828);
const _redBg = PdfColor.fromInt(0xFFFDECEA);
const _female = PdfColor.fromInt(0xFFC2185B);
const _femaleBg = PdfColor.fromInt(0xFFFCE4EC);
const _male = PdfColor.fromInt(0xFF1565C0);
const _maleBg = PdfColor.fromInt(0xFFE3F2FD);
const _ink = PdfColor.fromInt(0xFF1F2A1F);
const _muted = PdfColor.fromInt(0xFF6B756B);
const _line = PdfColor.fromInt(0xFFD9DED6);

const _statusLabels = {
  'present': 'Présent',
  'repos': 'Repos',
  'absent': 'Absent',
  'malade': 'Malade',
  'permission': 'Permission',
  'affecte': 'Affecté',
  'sanctionne': 'Sanctionné',
};

/// Export PDF d'un rapport journalier VALIDÉ : une seule page A4 (le contenu est réduit au
/// besoin plutôt que de déborder), nom de fichier explicite pour s'identifier d'un coup d'œil
/// dans WhatsApp : « Rapport_Journalier_Batiment_Lot-X_date.pdf ».
class DailyReportPdfService {
  DailyReportPdfService._();

  /// Seul un rapport validé s'exporte (règle métier) — à tester avant d'afficher le bouton.
  static bool canExport(FarmDailyReport report) => report.status == 'valide';

  static String fileName(FarmDailyReport r) {
    String clean(String s) {
      const from = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
      const to = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';
      var out = s.trim();
      for (var i = 0; i < from.length; i++) {
        out = out.replaceAll(from[i], to[i]);
      }
      return out.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    }

    final parts = [
      'Rapport_Journalier',
      clean(r.farmName),
      if (r.lotNumber != null && r.lotNumber!.trim().isNotEmpty) 'Lot-${clean(r.lotNumber!)}',
      r.date,
    ];
    return '${parts.join('_')}.pdf';
  }

  /// Génère le PDF et ouvre le partage système (WhatsApp, e-mail, enregistrer…).
  static Future<void> exportAndShare(FarmDailyReport report) async {
    final bytes = await build(report);
    await Printing.sharePdf(bytes: bytes, filename: fileName(report));
  }

  static Future<Uint8List> build(FarmDailyReport r) async {
    // Bâtiment en production ? Sinon pas de section production (eau seule), sauf si le rapport
    // contient déjà des œufs saisis — même règle que le récapitulatif à l'écran.
    var isProduction = true;
    try {
      final farm = await MongoService().getFarmById(r.farmId);
      if (farm != null) isProduction = farm.isProduction;
    } catch (_) {}
    final hasEggs = r.production.any((p) => p.oac + p.po + p.dj + p.cas + p.sal > 0);
    final showProduction = isProduction || hasEggs;

    final doc = pw.Document(title: fileName(r).replaceAll('.pdf', ''), author: 'Pro-Avif');
    const pageWidth = 595.28 - 2 * 22; // A4 - marges
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(22),
        build: (_) => pw.FittedBox(
          // Garantit « une seule page » : si le contenu est plus haut que la page, il est
          // réduit proportionnellement au lieu de déborder.
          fit: pw.BoxFit.scaleDown,
          alignment: pw.Alignment.topCenter,
          child: pw.SizedBox(width: pageWidth, child: _content(r, showProduction)),
        ),
      ),
    );
    return doc.save();
  }

  // ---------------------------------------------------------------- contenu

  static pw.Widget _content(FarmDailyReport r, bool showProduction) {
    final dateObj = DateTime.tryParse(r.date);
    final dateLabel = dateObj != null ? DateFormat('dd/MM/yyyy').format(dateObj) : r.date;
    final validatedAt = r.validatedAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(r.validatedAt!) : null;

    final totalStartF = r.startCounts.fold<int>(0, (a, e) => a + e.femaleCount) + r.clinicStart.femaleCount;
    final totalStartM = r.startCounts.fold<int>(0, (a, e) => a + e.maleCount) + r.clinicStart.maleCount;
    final totalEndF = r.endCounts.fold<int>(0, (a, e) => a + e.femaleCount) + r.clinicEnd.femaleCount;
    final totalEndM = r.endCounts.fold<int>(0, (a, e) => a + e.maleCount) + r.clinicEnd.maleCount;
    final totalEggs = r.production.fold<int>(0, (a, p) => a + p.oac + p.po + p.dj + p.cas + p.sal);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ---- En-tête
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: const pw.BoxDecoration(
            color: _green900,
            borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('RAPPORT JOURNALIER', style: pw.TextStyle(color: PdfColors.white, fontSize: 9, letterSpacing: 1.2)),
                    pw.SizedBox(height: 3),
                    pw.Text(r.farmName, style: pw.TextStyle(color: PdfColors.white, fontSize: 19, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      [
                        'Lot ${r.lotNumber ?? "non défini"}',
                        if (r.ageDays != null) 'Âge ${r.ageDays} j (S${r.ageWeeks})',
                        dateLabel,
                      ].join('   |   '),
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
                    ),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const pw.BoxDecoration(
                  color: _green700,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  children: [
                    pw.Text('VALIDÉ', style: pw.TextStyle(color: PdfColors.white, fontSize: 12, fontWeight: pw.FontWeight.bold)),
                    if (validatedAt != null)
                      pw.Text(validatedAt, style: const pw.TextStyle(color: PdfColors.white, fontSize: 7.5)),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 10),

        // ---- Chiffres clés
        pw.Row(
          children: [
            _kpi('Effectif restant', '$totalEndF F  |  $totalEndM M', _green700, _green100),
            pw.SizedBox(width: 6),
            _kpi(
              'Mortalité du jour',
              '${r.mortality.totalFemale} F  |  ${r.mortality.totalMale} M',
              _red,
              _redBg,
            ),
            pw.SizedBox(width: 6),
            _kpi('Aliment consommé', '${_n(r.aliment.totalConsumedKg)} kg', _amber, _amberBg),
            pw.SizedBox(width: 6),
            if (showProduction)
              _kpi(
                'Taux de ponte',
                r.layingRatePercent != null ? '${r.layingRatePercent!.toStringAsFixed(1)} %' : '-',
                _purple,
                _purpleBg,
              )
            else
              _kpi('Eau', '${_n(r.waterLiters ?? 0)} L', _blue, _blueBg),
          ],
        ),
        pw.SizedBox(height: 10),

        // ---- Effectifs
        _section('EFFECTIFS PAR SALLE', _green700),
        _headcountTable(r, totalStartF, totalStartM, totalEndF, totalEndM),
        if (r.transfers.isNotEmpty) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            'Déplacement de sujets effectué ce jour entre salles (détail ci-dessous) : '
            'les effectifs restants en tiennent compte.',
            style: pw.TextStyle(fontSize: 8, color: _blue, fontStyle: pw.FontStyle.italic),
          ),
        ],
        pw.SizedBox(height: 8),

        // ---- Mortalité
        _section('MORTALITÉ', _red),
        _mortalityBlock(r),
        pw.SizedBox(height: 8),

        // ---- Aliment
        _section('ALIMENT', _amber),
        _feedBlock(r),
        pw.SizedBox(height: 8),

        // ---- Production / eau
        if (showProduction) ...[
          _section('PRODUCTION D\'OEUFS', _purple),
          _productionTable(r, totalEggs),
          pw.SizedBox(height: 4),
          _waterLine(r),
        ] else ...[
          _section('EAU', _blue),
          _waterLine(r),
        ],

        // ---- Transferts
        if (r.transfers.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _section('TRANSFERTS ENTRE SALLES', _blue),
          _table(
            header: const ['De la salle', 'Vers la salle', 'Femelles', 'Mâles'],
            rows: [
              for (final t in r.transfers) [t.fromRoom, t.toRoom, '${t.femaleCount}', '${t.maleCount}'],
            ],
            total: [
              'Sujets déplacés',
              '',
              '${r.transfers.fold<int>(0, (a, t) => a + t.femaleCount)}',
              '${r.transfers.fold<int>(0, (a, t) => a + t.maleCount)}',
            ],
            columnTints: const [null, null, _femaleBg, _maleBg],
            columnInk: const [_ink, _ink, _female, _male],
            headerColor: _blue,
          ),
        ],

        // ---- Traitements
        if (r.treatments.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _section('TRAITEMENTS', _blue),
          pw.Wrap(
            spacing: 14,
            runSpacing: 3,
            children: [
              for (final t in r.treatments)
                pw.Text(
                  '${t.type == 'vaccin' ? 'Vaccin' : 'Médicament'} : ${t.name}'
                  '${t.dose != null ? " (${t.dose})" : ""}'
                  '${t.date != null ? " - ${DateFormat('dd/MM').format(t.date!)}" : ""}',
                  style: const pw.TextStyle(fontSize: 8.5, color: _ink),
                ),
            ],
          ),
        ],

        // ---- Personnel
        if (r.staffStatuses.isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _section('PERSONNEL', _green700),
          _staffBlock(r),
        ],

        // ---- Observation
        if (r.observation != null && r.observation!.trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          _section('OBSERVATION', _muted),
          pw.Text(r.observation!.trim(), style: const pw.TextStyle(fontSize: 8.5, color: _ink)),
        ],

        pw.SizedBox(height: 12),
        pw.Divider(color: _line, thickness: 0.8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Validé${r.validatedBy != null ? " par ${r.validatedBy}" : ""}'
              '${validatedAt != null ? " le $validatedAt" : ""}'
              '${r.submittedBy != null ? "  |  Saisi par ${r.submittedBy}" : ""}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
            pw.Text(
              'Pro-Avif  |  généré le ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 7.5, color: _muted),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- blocs

  static pw.Widget _headcountTable(FarmDailyReport r, int sF, int sM, int eF, int eM) {
    final rows = <List<String>>[
      for (final s in r.startCounts)
        () {
          final end = r.endCounts.where((e) => e.roomName == s.roomName);
          final e = end.isEmpty ? null : end.first;
          return [
            s.roomName,
            '${s.femaleCount}',
            '${e?.femaleCount ?? s.femaleCount}',
            '${s.maleCount}',
            '${e?.maleCount ?? s.maleCount}',
          ];
        }(),
      [
        'Clinique',
        '${r.clinicStart.femaleCount}',
        '${r.clinicEnd.femaleCount}',
        '${r.clinicStart.maleCount}',
        '${r.clinicEnd.maleCount}',
      ],
    ];
    return _table(
      header: const ['Salle', 'Début F', 'Restant F', 'Début M', 'Restant M'],
      rows: rows,
      total: ['Total', '$sF', '$eF', '$sM', '$eM'],
      columnTints: const [null, _femaleBg, _femaleBg, _maleBg, _maleBg],
      columnInk: const [_ink, _female, _female, _male, _male],
      headerColor: _green700,
    );
  }

  static pw.Widget _mortalityBlock(FarmDailyReport r) {
    final m = r.mortality;
    final rows = <List<String>>[
      for (final byRoom in m.byRoom)
        () {
          final cum = m.cumulativeByRoom.where((c) => c.roomName == byRoom.roomName);
          final c = cum.isEmpty ? null : cum.first;
          return [
            byRoom.roomName,
            '${byRoom.femaleCount}',
            '${byRoom.maleCount}',
            '${c?.femaleCount ?? 0}',
            '${c?.maleCount ?? 0}',
          ];
        }(),
      [
        'Clinique',
        '${m.clinic.femaleCount}',
        '${m.clinic.maleCount}',
        '${m.cumulativeClinicFemale}',
        '${m.cumulativeClinicMale}',
      ],
    ];
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _table(
          header: const ['Salle', 'Jour F', 'Jour M', 'Cumul F', 'Cumul M'],
          rows: rows,
          total: [
            'Total',
            '${m.totalFemale}',
            '${m.totalMale}',
            '${m.cumulativeFemale}',
            '${m.cumulativeMale}',
          ],
          columnTints: const [null, _femaleBg, _maleBg, _femaleBg, _maleBg],
          columnInk: const [_ink, _female, _male, _female, _male],
          headerColor: _red,
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          'Taux cumulé : femelles ${m.rateFemalePercent?.toStringAsFixed(2) ?? "-"} %   |   '
          'mâles ${m.rateMalePercent?.toStringAsFixed(2) ?? "-"} %',
          style: pw.TextStyle(fontSize: 8.5, color: _red, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.Widget _feedBlock(FarmDailyReport r) {
    final a = r.aliment;
    final consumption = r.aliment.consumptionByRoom.where((c) => c.quantityKg > 0).toList();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          children: [
            _stat('Reçu', '${_n(a.receivedTotalKg)} kg'),
            _stat('Stock avant', '${_n(a.stockBeforeKg)} kg'),
            _stat('Consommé', '${_n(a.totalConsumedKg)} kg', color: _amber),
            _stat('Stock après', '${_n(a.stockAfterKg)} kg'),
            _stat('Sécurité', a.securityStockDays != null ? '${a.securityStockDays!.round()} j' : '-'),
          ],
        ),
        if (consumption.isNotEmpty) ...[
          pw.SizedBox(height: 4),
          _table(
            header: const ['Salle', 'Aliment', 'Femelles (kg)', 'Mâles (kg)', 'Total (kg)'],
            rows: [
              for (final c in consumption)
                [
                  c.roomName,
                  c.formulaName ?? '-',
                  _n(c.femaleQuantityKg ?? 0),
                  _n(c.maleQuantityKg ?? 0),
                  _n(c.quantityKg),
                ],
            ],
            columnTints: const [null, null, _femaleBg, _maleBg, _amberBg],
            columnInk: const [_ink, _ink, _female, _male, _amber],
            headerColor: _amber,
          ),
        ],
      ],
    );
  }

  static pw.Widget _productionTable(FarmDailyReport r, int totalEggs) {
    int sum(int Function(RoomProduction) f) => r.production.fold<int>(0, (a, p) => a + f(p));
    final rows = [
      for (final p in r.production)
        [
          p.roomName,
          '${p.oac}',
          '${p.po}',
          '${p.dj}',
          '${p.cas}',
          '${p.sal}',
          '${p.oac + p.po + p.dj + p.cas + p.sal}',
          '${p.tpPercent.toStringAsFixed(1)} %',
          '${p.dePercent.toStringAsFixed(1)} %',
          p.ecartPercent != null ? '${p.ecartPercent!.toStringAsFixed(1)} %' : '-',
        ],
    ];
    final layingRate = r.layingRatePercent;
    return _table(
      header: const ['Salle', 'OAC', 'PO', 'DJ', 'CAS', 'SAL', 'Total', 'TP', '%DE', 'Écart'],
      rows: rows,
      total: [
        'Total',
        '${sum((p) => p.oac)}',
        '${sum((p) => p.po)}',
        '${sum((p) => p.dj)}',
        '${sum((p) => p.cas)}',
        '${sum((p) => p.sal)}',
        '$totalEggs',
        layingRate != null ? '${layingRate.toStringAsFixed(1)} %' : '-',
        '',
        '',
      ],
      columnTints: const [null, null, null, null, null, null, _purpleBg, _purpleBg, null, null],
      columnInk: const [_ink, _ink, _ink, _ink, _ink, _ink, _purple, _purple, _ink, _ink],
      headerColor: _purple,
      fontSize: 8,
    );
  }

  static pw.Widget _waterLine(FarmDailyReport r) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: const pw.BoxDecoration(
        color: _blueBg,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(5)),
      ),
      child: pw.Row(
        children: [
          pw.Text('Eau consommée : ', style: const pw.TextStyle(fontSize: 9, color: _ink)),
          pw.Text(
            '${_n(r.waterLiters ?? 0)} L',
            style: pw.TextStyle(fontSize: 9.5, color: _blue, fontWeight: pw.FontWeight.bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _staffBlock(FarmDailyReport r) {
    final groups = <String, List<String>>{};
    for (final s in r.staffStatuses) {
      groups.putIfAbsent(s.status, () => []).add(s.name);
    }
    const order = ['present', 'repos', 'permission', 'malade', 'absent', 'affecte', 'sanctionne'];
    final keys = [
      ...order.where(groups.containsKey),
      ...groups.keys.where((k) => !order.contains(k)),
    ];
    PdfColor colorFor(String k) => switch (k) {
          'present' => _green700,
          'absent' => _red,
          'malade' => const PdfColor.fromInt(0xFFE65100),
          'sanctionne' => const PdfColor.fromInt(0xFF7A0000),
          _ => _muted,
        };
    return pw.Wrap(
      spacing: 14,
      runSpacing: 3,
      children: [
        for (final k in keys)
          pw.RichText(
            text: pw.TextSpan(
              children: [
                pw.TextSpan(
                  text: '${_statusLabels[k] ?? k} (${groups[k]!.length}) : ',
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: colorFor(k)),
                ),
                pw.TextSpan(
                  text: groups[k]!.join(', '),
                  style: const pw.TextStyle(fontSize: 8.5, color: _ink),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ---------------------------------------------------------------- briques

  static String _n(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  static pw.Widget _section(String text, PdfColor color) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.Container(width: 3, height: 11, color: color),
          pw.SizedBox(width: 6),
          pw.Text(text, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _kpi(String label, String value, PdfColor color, PdfColor bg) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(7)),
          border: pw.Border.all(color: color, width: 0.8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
            pw.SizedBox(height: 2),
            pw.Text(value, style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _stat(String label, String value, {PdfColor color = _ink}) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: _muted)),
          pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _table({
    required List<String> header,
    required List<List<String>> rows,
    List<String>? total,
    required List<PdfColor?> columnTints,
    required List<PdfColor> columnInk,
    required PdfColor headerColor,
    double fontSize = 8.5,
  }) {
    pw.Widget cell(String text, int col, {bool head = false, bool bold = false, PdfColor? bg}) {
      return pw.Container(
        color: head ? headerColor : (bg ?? columnTints[col]),
        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
        child: pw.Text(
          text,
          textAlign: col == 0 ? pw.TextAlign.left : pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: head ? fontSize - 0.5 : fontSize,
            fontWeight: head || bold || col == 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: head ? PdfColors.white : columnInk[col],
          ),
        ),
      );
    }

    return pw.ClipRRect(
      horizontalRadius: 5,
      verticalRadius: 5,
      child: pw.Table(
        border: const pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _line, width: 0.5),
          bottom: pw.BorderSide(color: _line, width: 0.5),
        ),
        columnWidths: {
          0: const pw.FlexColumnWidth(2.4),
          for (var i = 1; i < header.length; i++) i: const pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(children: [for (var i = 0; i < header.length; i++) cell(header[i], i, head: true)]),
          for (final row in rows) pw.TableRow(children: [for (var i = 0; i < row.length; i++) cell(row[i], i)]),
          if (total != null)
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _green100),
              children: [for (var i = 0; i < total.length; i++) cell(total[i], i, bold: true, bg: _green100)],
            ),
        ],
      ),
    );
  }
}
