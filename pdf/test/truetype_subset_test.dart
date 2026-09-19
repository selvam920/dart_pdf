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

import 'package:pdf/src/pdf/font/ttf_parser.dart';
import 'package:pdf/src/pdf/font/ttf_writer.dart';
import 'package:test/test.dart';

/// The single byte codes a simple `/TrueType` font can address.
Map<int, int> simpleCharMap(TtfParser font) {
  final map = <int, int>{};
  for (var i = 32; i <= 255; i++) {
    final glyph = font.charToGlyphIndexMap[i];
    if (glyph != null) {
      map[i] = glyph;
    }
  }
  return map;
}

void main() {
  late TtfParser original;

  setUpAll(() {
    original = TtfParser(
      File('open-sans.ttf').readAsBytesSync().buffer.asByteData(),
    );
  });

  test('a subset built for the simple path reparses', () {
    final charMap = simpleCharMap(original);
    final data = TtfWriter(original).withChars(
      charMap.values.toSet().toList(),
      unicodeToGlyph: charMap,
    );

    // The constructor asserts the font carries every table it needs.
    final subset = TtfParser(data.buffer.asByteData());
    expect(subset.charToGlyphIndexMap, isNotEmpty);
  });

  test('every addressable code resolves through the subset cmap', () {
    final charMap = simpleCharMap(original);
    final data = TtfWriter(original).withChars(
      charMap.values.toSet().toList(),
      unicodeToGlyph: charMap,
    );
    final subset = TtfParser(data.buffer.asByteData());

    for (final code in charMap.keys) {
      expect(
        subset.charToGlyphIndexMap[code],
        isNotNull,
        reason: 'code $code (${String.fromCharCode(code)}) lost in the subset',
      );
    }
  });

  test('the glyph a code resolves to is the original outline', () {
    final charMap = simpleCharMap(original);
    final spaceGlyph = original.charToGlyphIndexMap[32];
    final data = TtfWriter(original).withChars(
      charMap.values.toSet().toList(),
      unicodeToGlyph: charMap,
    );
    final subset = TtfParser(data.buffer.asByteData());

    var compared = 0;
    for (final entry in charMap.entries) {
      // The writer deliberately empties the space glyph, and a compound
      // glyph has its component indexes rewritten for the subset, so neither
      // can be compared byte for byte.
      if (entry.value == spaceGlyph) {
        continue;
      }
      final before = original.readGlyph(entry.value);
      if (before.compounds.isNotEmpty) {
        continue;
      }

      final after = subset.readGlyph(subset.charToGlyphIndexMap[entry.key]!);
      expect(
        after.data,
        before.data,
        reason: 'outline changed for ${String.fromCharCode(entry.key)}',
      );
      compared++;
    }

    expect(compared, greaterThan(50), reason: 'too few glyphs checked');
  });

  test('advance widths survive the subset', () {
    final charMap = simpleCharMap(original);
    final data = TtfWriter(original).withChars(
      charMap.values.toSet().toList(),
      unicodeToGlyph: charMap,
    );
    final subset = TtfParser(data.buffer.asByteData());

    for (final entry in charMap.entries) {
      final before = original.glyphInfoMap[entry.value];
      final after =
          subset.glyphInfoMap[subset.charToGlyphIndexMap[entry.key]!];
      if (before == null || after == null) {
        continue;
      }
      expect(
        after.advanceWidth,
        closeTo(before.advanceWidth, 0.0001),
        reason: 'width changed for ${String.fromCharCode(entry.key)}',
      );
    }
  });

  test('the subset is much smaller than the original font', () {
    final charMap = simpleCharMap(original);
    final data = TtfWriter(original).withChars(
      charMap.values.toSet().toList(),
      unicodeToGlyph: charMap,
    );
    expect(data.length, lessThan(original.bytes.lengthInBytes));
  });

  test('the CID path keeps its placeholder cmap', () {
    // Passing no map must not change what the Type0 path has always written:
    // a (3, 10) format 12 table, which that path never reads.
    final glyphs = simpleCharMap(original).values.toSet().toList();
    final data = TtfWriter(original).withChars(glyphs);
    final bytes = data.buffer.asByteData();

    // Walk the table directory to find 'cmap'.
    final numTables = bytes.getUint16(4);
    var offset = -1;
    for (var i = 0; i < numTables; i++) {
      final tag = String.fromCharCodes(
        data.sublist(12 + i * 16, 12 + i * 16 + 4),
      );
      if (tag == 'cmap') {
        offset = bytes.getUint32(12 + i * 16 + 8);
      }
    }
    expect(offset, isNot(-1));
    expect(bytes.getUint16(offset + 4), 3); // platform
    expect(bytes.getUint16(offset + 6), 10); // encoding
    expect(bytes.getUint16(offset + 12), 12); // subtable format
  });
}
