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

import '../document.dart';
import 'object_stream.dart';

/// Unicode character map object
class PdfUnicodeCmap extends PdfObjectStream {
  /// Create a Unicode character map object
  PdfUnicodeCmap(PdfDocument pdfDocument, this.protect) : super(pdfDocument);

  /// List of characters
  final cmap = <int>[0];

  /// The text each CID was produced from, as Unicode codepoints.
  ///
  /// [cmap] holds glyph indexes, which is what the embedded subset and the
  /// width array are built from. They are not codepoints, and writing them
  /// into this map as if they were makes a reader extract the font's glyph
  /// numbering instead of the text. A CID missing from here is left unmapped,
  /// which is the honest answer for a glyph that no codepoint produced.
  final unicode = <int, List<int>>{};

  /// Protects the text from being "seen" by the PDF reader.
  final bool protect;

  /// Encode codepoints as the UTF-16BE hex a `bfchar` destination expects.
  static String _hex(List<int> codepoints) {
    final buffer = StringBuffer();
    for (final codepoint in codepoints) {
      if (codepoint > 0xFFFF) {
        final v = codepoint - 0x10000;
        buffer.write(
          (0xD800 + (v >> 10)).toRadixString(16).toUpperCase().padLeft(4, '0'),
        );
        buffer.write(
          (0xDC00 + (v & 0x3FF))
              .toRadixString(16)
              .toUpperCase()
              .padLeft(4, '0'),
        );
      } else {
        buffer.write(codepoint.toRadixString(16).toUpperCase().padLeft(4, '0'));
      }
    }
    return buffer.toString();
  }

  @override
  void prepare() {
    final entries = <int, String>{};

    if (unicode.isEmpty) {
      // Nothing recorded the source text, so read [cmap] as codepoints the way
      // this object always did.
      for (var key = 0; key < cmap.length; key++) {
        entries[key] = protect && key > 0 ? '0020' : _hex(<int>[cmap[key]]);
      }
    } else {
      for (final entry in unicode.entries) {
        entries[entry.key] = protect ? '0020' : _hex(entry.value);
      }
    }

    final keys = entries.keys.toList()..sort();

    buf.putString(
      '/CIDInit/ProcSet\nfindresource begin\n'
      '12 dict begin\n'
      'begincmap\n'
      '/CIDSystemInfo<<\n'
      '/Registry (Adobe)\n'
      '/Ordering (UCS)\n'
      '/Supplement 0\n'
      '>> def\n'
      '/CMapName/Adobe-Identity-UCS def\n'
      '/CMapType 2 def\n'
      '1 begincodespacerange\n'
      '<0000> <FFFF>\n'
      'endcodespacerange\n',
    );

    // A bfchar section may hold at most 100 entries.
    for (var start = 0; start < keys.length; start += 100) {
      final chunk = keys.skip(start).take(100).toList();
      buf.putString('${chunk.length} beginbfchar\n');
      for (final key in chunk) {
        buf.putString(
          '<${key.toRadixString(16).toUpperCase().padLeft(4, '0')}> '
          '<${entries[key]}>\n',
        );
      }
      buf.putString('endbfchar\n');
    }

    buf.putString(
      'endcmap\n'
      'CMapName currentdict /CMap defineresource pop\n'
      'end\n'
      'end',
    );
    super.prepare();
  }
}
