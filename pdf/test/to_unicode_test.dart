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

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

/// Uncompressed so the CMap is greppable.
Future<String> buildPdf(String text) async {
  final data = File('open-sans.ttf').readAsBytesSync();
  final ttf = pw.Font.ttf(data.buffer.asByteData());
  final doc = pw.Document(compress: false);
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Text(text, style: pw.TextStyle(font: ttf, fontSize: 12)),
    ),
  );
  return String.fromCharCodes(await doc.save());
}

/// The `<cid> <unicode>` pairs of every bfchar section in [pdf].
Map<int, String> bfchars(String pdf) {
  final result = <int, String>{};
  final sections = RegExp(
    r'beginbfchar(.*?)endbfchar',
    dotAll: true,
  ).allMatches(pdf);
  for (final section in sections) {
    for (final line in RegExp(
      r'<([0-9A-F]+)>\s*<([0-9A-F]+)>',
    ).allMatches(section.group(1)!)) {
      result[int.parse(line.group(1)!, radix: 16)] = line.group(2)!;
    }
  }
  return result;
}

void main() {
  test('maps CIDs to the source text, not to glyph indexes', () async {
    final pdf = await buildPdf('Hi');
    final map = bfchars(pdf);

    expect(map.values, contains('0048'), reason: 'H is U+0048');
    expect(map.values, contains('0069'), reason: 'i is U+0069');

    // In Open Sans these are the glyph indexes of H and i. Emitting them as
    // the Unicode destination is what made readers extract '+K' for 'Hi'.
    expect(map.values, isNot(contains('002B')));
    expect(map.values, isNot(contains('004B')));
  });

  test('covers every character of the text', () async {
    const text = 'Hello World 123';
    final pdf = await buildPdf(text);
    final destinations = bfchars(pdf).values.toSet();

    for (final rune in text.runes) {
      if (rune == 0x20) {
        continue; // spaces are not written as glyphs
      }
      final hex = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
      expect(
        destinations,
        contains(hex),
        reason: 'no mapping for ${String.fromCharCode(rune)}',
      );
    }
  });

  test('splits into sections of at most 100 entries', () async {
    // Enough distinct characters to need more than one section.
    final text = <String>[
      for (var c = 0x21; c <= 0x7E; c++) String.fromCharCode(c),
      for (var c = 0xA1; c <= 0xFF; c++) String.fromCharCode(c),
    ].join();

    final pdf = await buildPdf(text);
    final sections = RegExp(
      r'(\d+) beginbfchar',
      dotAll: true,
    ).allMatches(pdf);

    expect(sections, isNotEmpty);
    for (final section in sections) {
      expect(int.parse(section.group(1)!), lessThanOrEqualTo(100));
    }
    expect(bfchars(pdf).length, greaterThan(100));
  });

  test('a protected document exposes no text', () async {
    final data = File('open-sans.ttf').readAsBytesSync();
    final ttf = pw.TtfFont(data.buffer.asByteData(), protect: true);
    final doc = pw.Document(compress: false);
    doc.addPage(
      pw.Page(
        build: (_) =>
            pw.Text('Secret', style: pw.TextStyle(font: ttf, fontSize: 12)),
      ),
    );
    final pdf = String.fromCharCodes(await doc.save());

    for (final destination in bfchars(pdf).values) {
      expect(destination, '0020');
    }
  });
}
