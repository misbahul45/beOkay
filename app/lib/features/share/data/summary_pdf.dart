import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'share_repository.dart';

Future<pw.ThemeData> pdfTheme() async => pw.ThemeData.withFont(
  base: pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Regular.ttf')),
  bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Inter-Bold.ttf')),
);

Future<Uint8List> buildSummaryPdf(
  ReportSummary s, {
  pw.ThemeData? theme,
}) async {
  final doc = pw.Document(
    title: 'Ringkasan beOkay ${s.days} hari',
    author: 'beOkay',
    creator: s.version,
  );
  final ready = s.statistics.where((x) => x.ready).toList();
  pw.Widget table(List<String> head, List<List<String>> rows) =>
      pw.TableHelper.fromTextArray(
        headers: head,
        data: rows,
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerDecoration: const pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFEEF2F5),
        ),
        cellAlignment: pw.Alignment.centerLeft,
      );
  doc.addPage(
    pw.MultiPage(
      theme: theme ?? await pdfTheme(),
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      footer: (c) => pw.Text(
        'beOkay · ${s.version} · halaman ${c.pageNumber}/${c.pagesCount}',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      build: (_) => [
        pw.Text(
          'Ringkasan catatan ${s.days} hari',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          '${s.name} · ${s.start} sampai ${s.end} · dibuat ${s.generated}',
          style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey800),
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Ringkasan deskriptif',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (ready.isEmpty)
          pw.Text(
            'Belum cukup catatan pada periode ini.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          table(
            ['Ukuran', 'Nilai', 'Dasar'],
            [
              for (final x in ready)
                [
                  x.label,
                  x.display,
                  '${x.sampleCount} ${x.sampleUnit} · data ${x.daysWithData}/${x.totalDays} hari',
                ],
            ],
          ),
        if (s.stepsDays > 0) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Langkah harian dari perangkat: median ${s.stepsMedian?.round() ?? '–'} langkah dari ${s.stepsDays} hari.',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          'Ukuran tubuh dan hasil lab terakhir',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (s.measures.isEmpty)
          pw.Text(
            'Belum ada yang dicatat.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          table(
            ['Jenis', 'Nilai', 'Tanggal'],
            [
              for (final m in s.measures) [m.label, m.value, m.date],
            ],
          ),
        pw.SizedBox(height: 14),
        pw.Text(
          'Obat yang dicatat pengguna',
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        if (s.medications.isEmpty)
          pw.Text(
            'Tidak ada obat aktif yang dicatat.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          for (final m in s.medications)
            pw.Bullet(text: m, style: const pw.TextStyle(fontSize: 10)),
        pw.SizedBox(height: 18),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: const pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFFFF7E6),
          ),
          child: pw.Text(s.disclaimer, style: const pw.TextStyle(fontSize: 9)),
        ),
      ],
    ),
  );
  return doc.save();
}
