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

import 'dart:convert';
import 'dart:typed_data';

import '../document.dart';
import '../font/arabic.dart' as arabic;
import '../font/bidi_utils.dart' as bidi;
import '../font/font_metrics.dart';
import '../font/indic_shaper.dart';
import '../font/ttf_parser.dart';
import '../font/ttf_writer.dart';
import '../format/array.dart';
import '../format/dict.dart';
import '../format/name.dart';
import '../format/num.dart';
import '../format/stream.dart';
import '../format/string.dart';
import '../options.dart';
import 'font.dart';
import 'font_descriptor.dart';
import 'object.dart';
import 'object_stream.dart';
import 'unicode_cmap.dart';

class PdfTtfFont extends PdfFont {
  /// Constructs a [PdfTtfFont]
  PdfTtfFont(PdfDocument pdfDocument, ByteData bytes, {bool protect = false})
    : font = TtfParser(bytes),
      super.create(pdfDocument, subtype: '/TrueType') {
    file = PdfObjectStream(pdfDocument, isBinary: true);
    unicodeCMap = PdfUnicodeCmap(pdfDocument, protect);
    descriptor = PdfFontDescriptor(this, file);
    widthsObject = PdfObject<PdfArray>(pdfDocument, params: PdfArray());
  }

  /// Whether this font should take the CID `/Type0` path.
  ///
  /// Reads [PdfSettings.simpleTrueTypeFonts] rather than a static, because
  /// [PdfDocument.save] writes on a separate isolate where statics start fresh
  /// — a static would be seen by putText() but not by prepare().
  bool get _useType0 => font.unicode && !settings.simpleTrueTypeFonts;

  /// Whether this font is written as a CID `/Type0` font.
  ///
  /// Consumers must key off this rather than `font.unicode`, which only reports
  /// the sfnt version tag and stays true even when the simple `/TrueType` path
  /// is taken. [PdfFontDescriptor] needs it to pick symbolic vs nonsymbolic.
  bool get isCidFont => _useType0;

  @override
  String get subtype => _useType0 ? '/Type0' : super.subtype;

  late PdfUnicodeCmap unicodeCMap;

  late PdfFontDescriptor descriptor;

  late PdfObjectStream file;

  late PdfObject<PdfArray> widthsObject;

  final TtfParser font;

  @override
  String get fontName => font.fontName;

  @override
  double get ascent => font.ascent.toDouble() / font.unitsPerEm;

  @override
  double get descent => font.descent.toDouble() / font.unitsPerEm;

  @override
  int get unitsPerEm => font.unitsPerEm;

  @override
  PdfFontMetrics glyphMetrics(int charCode, [bool? isGlyphIndex]) {
    final g =
        isGlyphIndex == true ? charCode : font.charToGlyphIndexMap[charCode];

    if (g == null) {
      return PdfFontMetrics.zero;
    }

    if (useBidi && bidi.isArabicDiacriticValue(charCode)) {
      final metric = font.glyphInfoMap[g] ?? PdfFontMetrics.zero;
      return metric.copyWith(advanceWidth: 0);
    }

    if (useArabic && arabic.isArabicDiacriticValue(charCode)) {
      final metric = font.glyphInfoMap[g] ?? PdfFontMetrics.zero;
      return metric.copyWith(advanceWidth: 0);
    }

    return font.glyphInfoMap[g] ?? PdfFontMetrics.zero;
  }

  void _buildTrueType(PdfDict params) {
    const charMin = 32;
    const charMax = 255;

    // A simple font addresses glyphs through single byte codes, so only the
    // glyphs those codes reach can ever be drawn. Embedding the whole file
    // instead meant a CJK font contributed megabytes of glyphs this path
    // cannot select.
    //
    // The codes are written by PdfFont.putText as latin1, and /Widths below
    // is built the same way, so the subset maps each code to the glyph the
    // declared width belongs to.
    final unicodeToGlyph = <int, int>{};
    for (var i = charMin; i <= charMax; i++) {
      final glyph = font.charToGlyphIndexMap[i];
      if (glyph != null) {
        unicodeToGlyph[i] = glyph;
      }
    }

    final glyphs = unicodeToGlyph.values.toSet().toList();
    if (glyphs.isEmpty) {
      // Nothing in this font is reachable through a single byte code. Keep a
      // valid font by emitting .notdef alone rather than an empty glyf table.
      glyphs.add(0);
    }

    final data = TtfWriter(font).withChars(
      glyphs,
      unicodeToGlyph: unicodeToGlyph,
    );
    file.buf.putBytes(data);
    file.params['/Length1'] = PdfNum(data.length);

    params['/BaseFont'] = PdfName('/$fontName');
    params['/FontDescriptor'] = descriptor.ref();
    for (var i = charMin; i <= charMax; i++) {
      widthsObject.params.add(
        PdfNum((glyphMetrics(i).advanceWidth * 1000.0).toInt()),
      );
    }
    params['/FirstChar'] = PdfNum(charMin);
    params['/LastChar'] = PdfNum(charMax);
    params['/Widths'] = widthsObject.ref();
  }

  void _buildType0(PdfDict params) {
    int charMin;
    int charMax;

    final ttfWriter = TtfWriter(font);
    final data = ttfWriter.withChars(unicodeCMap.cmap);
    file.buf.putBytes(data);
    file.params['/Length1'] = PdfNum(data.length);

    final descendantFont = PdfDict.values({
      '/Type': const PdfName('/Font'),
      '/BaseFont': PdfName('/$fontName'),
      '/FontFile2': file.ref(),
      '/FontDescriptor': descriptor.ref(),
      '/W': PdfArray([const PdfNum(0), widthsObject.ref()]),
      '/CIDToGIDMap': const PdfName('/Identity'),
      '/DW': const PdfNum(1000),
      '/Subtype': const PdfName('/CIDFontType2'),
      '/CIDSystemInfo': PdfDict.values({
        '/Supplement': const PdfNum(0),
        '/Registry': PdfString.fromString('Adobe'),
        '/Ordering': PdfString.fromString('Identity-H'),
      }),
    });

    params['/BaseFont'] = PdfName('/$fontName');
    params['/Encoding'] = const PdfName('/Identity-H');
    params['/DescendantFonts'] = PdfArray([descendantFont]);
    params['/ToUnicode'] = unicodeCMap.ref();

    charMin = 0;
    charMax = unicodeCMap.cmap.length - 1;
    for (var i = charMin; i <= charMax; i++) {
      widthsObject.params.add(
        PdfNum(
          (glyphMetrics(unicodeCMap.cmap[i], true).advanceWidth * 1000.0)
              .toInt(),
        ),
      );
    }
  }

  @override
  void prepare() {
    super.prepare();

    if (_useType0) {
      _buildType0(params);
    } else {
      _buildTrueType(params);
    }
  }

  @override
  void putText(PdfStream stream, String text) {
    if (!_useType0) {
      // Without the return the simple encoding is emitted and then the hex CID
      // string is appended on top of it, corrupting the text.
      return super.putText(stream, text);
    }

    var charIndexes = getCharIndexes(text.runes);
    final codepoints = text.runes.toList();
    charIndexes = indicShaper(charIndexes, font, codepoints);

    // The CIDs written below are glyph indexes, so /ToUnicode has to be told
    // separately what text each one came from. Shaping can merge or reorder
    // glyphs; when it left the count alone the correspondence is still
    // positional, otherwise fall back to asking the font which codepoint
    // reaches the glyph.
    final aligned = charIndexes.length == codepoints.length;

    stream.putByte(0x3c);
    for (var i = 0; i < charIndexes.length; i++) {
      final rune = charIndexes[i];
      var char = unicodeCMap.cmap.indexOf(rune);
      if (char == -1) {
        char = unicodeCMap.cmap.length;
        unicodeCMap.cmap.add(rune);

        final source = aligned ? codepoints[i] : _codepointForGlyph(rune);
        if (source != null) {
          unicodeCMap.unicode[char] = <int>[source];
        }
      }

      stream.putBytes(latin1.encode(char.toRadixString(16).padLeft(4, '0')));
    }
    stream.putByte(0x3e);
  }

  @override
  PdfFontMetrics stringMetrics(String s, {double letterSpacing = 0}) {
    if (s.isEmpty || !font.unicode) {
      return super.stringMetrics(s, letterSpacing: letterSpacing);
    }

    var charIndexes = getCharIndexes(s.runes);
    final codepoints = s.runes.toList();
    charIndexes = indicShaper(charIndexes, font, codepoints);

    final metrics = charIndexes.map((g) => glyphMetrics(g, true));
    return PdfFontMetrics.append(metrics, letterSpacing: letterSpacing);
  }

  @override
  bool isRuneSupported(int charCode) {
    return font.charToGlyphIndexMap.containsKey(charCode);
  }

  List<int> getCharIndexes(Runes chars) {
    return chars.map((char) => font.charToGlyphIndexMap[char] ?? 0).toList();
  }

  Map<int, int>? _glyphToCodepoint;

  /// A codepoint that reaches [glyph] through the font's cmap, if any.
  ///
  /// Several codepoints can share a glyph, in which case any of them describes
  /// it well enough for text extraction.
  int? _codepointForGlyph(int glyph) {
    final map = _glyphToCodepoint ??= <int, int>{
      for (final entry in font.charToGlyphIndexMap.entries)
        entry.value: entry.key,
    };
    return map[glyph];
  }
}
