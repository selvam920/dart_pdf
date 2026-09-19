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
import 'dart:typed_data';

import 'package:pdf/src/pdf/font/indic_shaper.dart';
import 'package:pdf/src/pdf/font/ttf_parser.dart';
import 'package:test/test.dart';

const _devanagariUrl =
    'https://fonts.gstatic.com/s/notosansdevanagari/v26/TuGoUUFzXI5FBtUq5a8bjKYTZjtRU6Sgv3NaV_SNmI0b8QQCQmHn6B2OHjbL_08AlXQly-AzoFoW4Ow.ttf';
const _devanagariCache = 'NotoSansDevanagari-Regular.ttf';

Future<Uint8List> downloadFont(String url, String cacheFile) async {
  final file = File(cacheFile);
  if (file.existsSync()) {
    return file.readAsBytesSync();
  }
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (prev, chunk) => prev..addAll(chunk),
    );
    final data = Uint8List.fromList(bytes);
    file.writeAsBytesSync(data);
    return data;
  } finally {
    client.close();
  }
}

List<int> glyphsFor(TtfParser font, String text) =>
    text.runes.map((cp) => font.charToGlyphIndexMap[cp] ?? 0).toList();

void main() {
  group('script detection', () {
    test('maps each supported block to its script', () {
      expect(getLangFromCodepoint(0x0915), 'hindi'); // क Devanagari
      expect(getLangFromCodepoint(0x0995), 'bengali'); // ক
      expect(getLangFromCodepoint(0x0A15), 'gurmukhi'); // ਕ
      expect(getLangFromCodepoint(0x0A95), 'gujarati'); // ક
      expect(getLangFromCodepoint(0x0B15), 'oriya'); // କ
      expect(getLangFromCodepoint(0x0B95), 'tamil'); // க
      expect(getLangFromCodepoint(0x0C15), 'telugu'); // క
      expect(getLangFromCodepoint(0x0C95), 'kannada'); // ಕ
      expect(getLangFromCodepoint(0x0D15), 'malayalam'); // ക
      expect(getLangFromCodepoint(0x0D9A), 'sinhala'); // ක
    });

    test('rejects codepoints outside the Indic blocks', () {
      for (final cp in <int>[0x0041, 0x0061, 0x0030, 0x08FF, 0x0E00, 0x4E00]) {
        expect(getLangFromCodepoint(cp), '', reason: 'U+${cp.toRadixString(16)}');
      }
    });

    test('picks the script from the text, ignoring surrounding Latin', () {
      expect(getLangForText('Invoice'.runes.toList()), '');
      expect(getLangForText('Invoice नमस्ते'.runes.toList()), 'hindi');
      expect(getLangForText('123 ৳ বাংলা'.runes.toList()), 'bengali');
    });

    test('empty text needs no shaping', () {
      expect(getLangForText(<int>[]), '');
    });
  });

  group('indicShaper', () {
    late TtfParser font;

    setUpAll(() async {
      final data = await downloadFont(_devanagariUrl, _devanagariCache);
      font = TtfParser(data.buffer.asByteData());
    });

    test('leaves Latin text untouched in an Indic font', () {
      // The font name says Devanagari, but the text has no Indic character,
      // so the shaping pipeline must not run at all.
      const text = 'Invoice 123';
      final glyphs = glyphsFor(font, text);
      final shaped = indicShaper(glyphs, font, text.runes.toList());
      expect(shaped, glyphs);
    });

    test('reorders and substitutes Indic text', () {
      // ि is a left matra: stored after its consonant but drawn before it,
      // so a shaped run must differ from the raw codepoint-order mapping.
      const text = 'हिन्दी';
      final glyphs = glyphsFor(font, text);
      final shaped = indicShaper(glyphs, font, text.runes.toList());
      expect(shaped, isNot(glyphs));
      expect(shaped, isNotEmpty);
    });

    test('repeated shaping is stable', () {
      // The result is memoised per font; a second call must return exactly
      // what the first one produced.
      for (final text in <String>['नमस्ते', 'कर्म', 'श्री', 'Invoice 123']) {
        final codepoints = text.runes.toList();
        final first = indicShaper(glyphsFor(font, text), font, codepoints);
        final second = indicShaper(glyphsFor(font, text), font, codepoints);
        expect(second, first, reason: text);
      }
    });

    test('distinct strings do not share a cache entry', () {
      final a = indicShaper(glyphsFor(font, 'कर्म'), font, 'कर्म'.runes.toList());
      final b = indicShaper(
        glyphsFor(font, 'धर्म'),
        font,
        'धर्म'.runes.toList(),
      );
      expect(a, isNot(b));
    });
  });
}
