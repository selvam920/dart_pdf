/*
 * Copyright (C) 2017, David PHAM-VAN <dev.nfet.net@gmail.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../data.dart';

Future<Uint8List> generateIndic(PdfPageFormat format, CustomData data) async {
  final doc = pw.Document();

  final fontBase =
      data.testing ? pw.Font.helvetica() : await PdfGoogleFonts.notoSansRegular();

  final Map<String, pw.Font> fonts = data.testing
      ? {}
      : {
          'Hindi': await PdfGoogleFonts.notoSansDevanagariRegular(),
          'Bengali': await PdfGoogleFonts.notoSansBengaliRegular(),
          'Gujarati': await PdfGoogleFonts.notoSansGujaratiRegular(),
          'Gurmukhi': await PdfGoogleFonts.notoSansGurmukhiRegular(),
          'Kannada': await PdfGoogleFonts.notoSansKannadaRegular(),
          'Malayalam': await PdfGoogleFonts.notoSansMalayalamRegular(),
          'Odia': await PdfGoogleFonts.notoSansOriyaRegular(),
          'Sinhala': await PdfGoogleFonts.notoSansSinhalaRegular(),
          'Tamil': await PdfGoogleFonts.notoSansTamilRegular(),
          'Telugu': await PdfGoogleFonts.notoSansTeluguRegular(),
        };

  final samples = {
    'Hindi': 'नमस्ते दुनिया',
    'Bengali': 'হ্যালো দুনিয়া',
    'Gujarati': 'હેલો વર્લ્ડ',
    'Gurmukhi': 'ਹੈਲੋ ਵਰਲਡ',
    'Kannada': 'ಹಲೋ ವರ್ಲ್ಡ್',
    'Malayalam': 'ഹലോ വേൾഡ്',
    'Odia': 'ହେଲୋ ୱାର୍ଲ୍ଡ',
    'Sinhala': 'හෙලෝ වර්ල්ඩ්',
    'Tamil': 'ஹலோ வேர்ல்ட்',
    'Telugu': 'హలో వరల్డ్',
  };

  doc.addPage(
    pw.MultiPage(
      pageFormat: format,
      build: (context) => [
        pw.Header(
          level: 0,
          child: pw.Text('Indian Languages',
              style: pw.TextStyle(font: fontBase, fontSize: 24)),
        ),
        pw.Padding(padding: const pw.EdgeInsets.all(10)),
        for (var entry in samples.entries)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Row(
              children: [
                pw.SizedBox(
                  width: 100,
                  child: pw.Text(entry.key,
                      style: pw.TextStyle(
                          font: fontBase, fontWeight: pw.FontWeight.bold)),
                ),
                pw.Text(
                  entry.value,
                  style: pw.TextStyle(
                    font: data.testing ? pw.Font.helvetica() : fonts[entry.key],
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  return doc.save();
}
