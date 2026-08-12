// ignore_for_file: public_member_api_docs, avoid_redundant_argument_values

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'invoice.dart';

Future<void> main() async {
  runApp(const MyApp('Printing Demo'));
}

enum _Demo {
  printingDemo('Printing Demo'),
  invoiceSinglePage('Invoice (1 page)'),
  invoiceTwoPages('Invoice (2 pages)'),
  invoiceFourPages('Invoice (4 pages)'),
  invoiceGst('Invoice (GST, CGST + SGST)'),
  invoiceIgst('Invoice (GST, interstate IGST)'),
  invoiceCharges('Invoice (GST + delivery/discount)'),
  invoiceGstFourPages('Invoice (GST, 4 pages)');

  const _Demo(this.label);

  final String label;
}

class MyApp extends StatefulWidget {
  const MyApp(this.title, {super.key});

  final String title;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  var _demo = _Demo.printingDemo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            PopupMenuButton<_Demo>(
              initialValue: _demo,
              onSelected: (demo) => setState(() => _demo = demo),
              itemBuilder: (context) => [
                for (final demo in _Demo.values)
                  PopupMenuItem(value: demo, child: Text(demo.label)),
              ],
            ),
          ],
        ),
        body: PdfPreview(
          build: (format) => _generatePdf(format, _demo),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePdf(PdfPageFormat format, _Demo demo) {
    switch (demo) {
      case _Demo.printingDemo:
        return _generatePrintingDemo(format, widget.title);
      case _Demo.invoiceSinglePage:
        return generateInvoice(format);
      case _Demo.invoiceTwoPages:
        return generateInvoice(format, itemCount: 45);
      case _Demo.invoiceFourPages:
        return generateInvoice(format, itemCount: 94);
      case _Demo.invoiceGst:
        return generateInvoice(format, showGstSummary: true);
      case _Demo.invoiceIgst:
        return generateInvoice(format, showGstSummary: true, interstate: true);
      case _Demo.invoiceCharges:
        return generateInvoice(format, showGstSummary: true, withCharges: true);
      case _Demo.invoiceGstFourPages:
        return generateInvoice(format, itemCount: 94, showGstSummary: true);
    }
  }
}

Future<Uint8List> _generatePrintingDemo(
    PdfPageFormat format, String title) async {
  final pdf = pw.Document(version: PdfVersion.pdf_1_5, compress: true);
  final font = await PdfGoogleFonts.nunitoExtraLight();

  pdf.addPage(
    pw.Page(
      pageFormat: format,
      build: (context) {
        return pw.Column(
          children: [
            pw.SizedBox(
              width: double.infinity,
              child: pw.FittedBox(
                child: pw.Text(title, style: pw.TextStyle(font: font)),
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Flexible(child: pw.FlutterLogo()),
          ],
        );
      },
    ),
  );

  return pdf.save();
}
