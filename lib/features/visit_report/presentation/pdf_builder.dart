import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/visit_summary_models.dart';

/// Builds the Visit Report PDF document.
///
/// Layout sections (in order):
///   1. Header — title, baby name, date range.
///   2. Feeding table (skipped if every day has 0 oz).
///   3. Diapers table.
///   4. Sleep table.
///   5. Vaccinations list (only if non-empty).
///   6. Concerns / Notes (only if [concerns] is non-empty after trim).
///   7. Footer disclaimer (printed on every page).
pw.Document buildVisitPdf(VisitSummaryData data, {String? concerns}) {
  final doc = pw.Document();

  final dayFmt = DateFormat.MMMd();
  final rangeFmt = DateFormat.yMMMMd();

  final hasAnyFeed = data.days.any((d) => d.totalFeedOz > 0);
  final hasVaccinations = data.vaccinations.isNotEmpty;
  final hasConcerns = concerns != null && concerns.trim().isNotEmpty;

  final headerStyle =
      pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold);
  final sectionStyle =
      pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold);
  const subtleStyle = pw.TextStyle(fontSize: 11, color: PdfColors.grey700);
  const bodyStyle = pw.TextStyle(fontSize: 11);

  pw.Widget tableCell(String text, {bool header = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 6),
        child: pw.Text(
          text,
          style: header
              ? pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                )
              : bodyStyle,
        ),
      );

  String minutesToHrMin(int min) {
    final hr = min ~/ 60;
    final m = min % 60;
    return '$hr hr $m min';
  }

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.letter,
      margin: const pw.EdgeInsets.all(36),
      footer: (ctx) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12),
        child: pw.Text(
          'Parent-recorded; not a substitute for medical examination.',
          style: pw.TextStyle(
            fontSize: 9,
            fontStyle: pw.FontStyle.italic,
            color: PdfColors.grey600,
          ),
        ),
      ),
      build: (ctx) {
        final widgets = <pw.Widget>[];

        // Header
        widgets.add(pw.Text('DreamBook Visit Report', style: headerStyle));
        widgets.add(pw.SizedBox(height: 4));
        widgets.add(pw.Text(data.babyName,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)));
        widgets.add(pw.SizedBox(height: 2));
        widgets.add(pw.Text(
          '${rangeFmt.format(data.rangeStart)} – ${rangeFmt.format(data.rangeEnd)}',
          style: subtleStyle,
        ));
        widgets.add(pw.SizedBox(height: 16));

        // Feeding
        if (hasAnyFeed) {
          widgets.add(pw.Text('Feeding', style: sectionStyle));
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: const {
              0: pw.FlexColumnWidth(1),
              1: pw.FlexColumnWidth(1),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  tableCell('Date', header: true),
                  tableCell('Total oz', header: true),
                ],
              ),
              for (final d in data.days)
                pw.TableRow(children: [
                  tableCell(dayFmt.format(d.date)),
                  tableCell('${d.totalFeedOz.toStringAsFixed(1)} oz'),
                ]),
            ],
          ));
          widgets.add(pw.SizedBox(height: 14));
        }

        // Diapers
        widgets.add(pw.Text('Diapers', style: sectionStyle));
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                tableCell('Date', header: true),
                tableCell('Wet', header: true),
                tableCell('Soiled', header: true),
              ],
            ),
            for (final d in data.days)
              pw.TableRow(children: [
                tableCell(dayFmt.format(d.date)),
                tableCell('${d.wetDiapers}'),
                tableCell('${d.soiledDiapers}'),
              ]),
          ],
        ));
        widgets.add(pw.SizedBox(height: 14));

        // Sleep
        widgets.add(pw.Text('Sleep', style: sectionStyle));
        widgets.add(pw.SizedBox(height: 6));
        widgets.add(pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.4),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey100),
              children: [
                tableCell('Date', header: true),
                tableCell('Total', header: true),
                tableCell('Longest stretch', header: true),
              ],
            ),
            for (final d in data.days)
              pw.TableRow(children: [
                tableCell(dayFmt.format(d.date)),
                tableCell(minutesToHrMin(d.totalSleepMin)),
                tableCell(minutesToHrMin(d.longestSleepStretchMin)),
              ]),
          ],
        ));
        widgets.add(pw.SizedBox(height: 14));

        // Vaccinations
        if (hasVaccinations) {
          widgets.add(pw.Text('Vaccinations', style: sectionStyle));
          widgets.add(pw.SizedBox(height: 6));
          for (final v in data.vaccinations) {
            final clinicSuffix =
                (v.clinic != null && v.clinic!.isNotEmpty) ? ' — ${v.clinic}' : '';
            widgets.add(pw.Bullet(
              text:
                  '${v.vaccineName} — ${rangeFmt.format(v.givenOn)}$clinicSuffix',
              style: bodyStyle,
            ));
          }
          widgets.add(pw.SizedBox(height: 14));
        }

        // Concerns / Notes
        if (hasConcerns) {
          widgets.add(pw.Text('Concerns / Notes', style: sectionStyle));
          widgets.add(pw.SizedBox(height: 6));
          widgets.add(pw.Text(concerns.trim(), style: bodyStyle));
          widgets.add(pw.SizedBox(height: 14));
        }

        return widgets;
      },
    ),
  );

  return doc;
}
