import 'dart:io';

import 'package:pdf/src/pdf/font/glyph_iterator.dart';
import 'package:pdf/src/pdf/font/indic_shaper.dart';
import 'package:pdf/src/pdf/font/ot_processor.dart';
import 'package:pdf/src/pdf/font/ttf_parser.dart';

void main() {
  final file = File('NotoSansGujarati-Regular.ttf');
  if (!file.existsSync()) {
    print('Font not found');
    return;
  }

  final fontData = file.readAsBytesSync();
  final parser = TtfParser(fontData.buffer.asByteData());
  print('Font: ${parser.fontName}');

  // વર્લ્ડ = વ ર ્ લ ્ ડ
  final word = 'વર્લ્ડ';
  final codepoints = word.runes.toList();
  print('\nWord: $word');
  print('Codepoints: ${codepoints.map((c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ')}');

  final initialGlyphs = codepoints.map((r) => parser.charToGlyphIndexMap[r] ?? 0).toList();
  print('Initial glyphs: $initialGlyphs');
  final shaped = indicShaper(List<int>.from(initialGlyphs), parser, codepoints);
  print('Shaped: $shaped');

  // Print glyph advance widths
  print('\nGlyph details:');
  for (final gid in shaped) {
    final metrics = parser.glyphInfoMap[gid];
    print('  glyph $gid: advance=${metrics?.advanceWidth ?? "N/A"}');
  }

  // Trace stages
  final features = getFeatureMap(parser);
  final stages = setupStages();
  final stageNames = [
    'rvrn/ltra/ltrm/frac/numr/dnom', 'locl/ccmp', 'initialReorder',
    'nukt', 'akhn', 'rphf', 'rkrf', 'pref', 'blwf', 'abvf', 'half', 'pstf',
    'vatu', 'cjct', 'cfar', 'finalReorder', 'pres/abvs/blws/psts/haln/...',
  ];

  print('\n=== Stage trace ===');
  var glyphs = List<int>.from(initialGlyphs);
  for (var si = 0; si < stages.length; si++) {
    final stage = stages[si];
    final before = List<int>.from(glyphs);
    final name = si < stageNames.length ? stageNames[si] : 'stage$si';
    if (stage is Function(List<int>, String)) {
      glyphs = stage(List<int>.from(glyphs), 'gujarati');
    } else if (stage is List<String>) {
      final gi = GlyphIterator(parser, List<int>.from(glyphs));
      final ot = OTProcessor(parser, gi);
      final lookups = ot.lookupsForFeatures(stage, features);
      ot.applyLookups(lookups);
      glyphs = ot.glyphIterator.glyphs.map((g) => g.id).toList();
      if (before.length != glyphs.length || !_eq(before, glyphs)) {
        print('  Stage $si ($name) [${lookups.length} lookups]: $before -> $glyphs');
      }
    }
  }
  print('  Final: $glyphs');

  // Now test with MANUALLY reordered codepoints (reph moved after base)
  // Original: વ ર ્ લ ્ ડ
  // Syllables: [વ] [ર ્ લ ્ ড]
  // In syllable 2: Ra+virama at start, base = ড
  // After reph reorder: [વ] [લ ્ ড ર ্]
  // Full: વ લ ্ ড ​ ্
  final reorderedCP = [0x0AB5, 0x0AB2, 0x0ACD, 0x0AA1, 0x0AB0, 0x0ACD];
  print('\n=== Test with manually reph-reordered codepoints ===');
  print('Reordered: ${reorderedCP.map((c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ')}');
  final reorderedGlyphs = reorderedCP.map((cp) => parser.charToGlyphIndexMap[cp] ?? 0).toList();
  print('Glyph IDs: $reorderedGlyphs');

  var g2 = List<int>.from(reorderedGlyphs);
  for (var si = 0; si < stages.length; si++) {
    final stage = stages[si];
    final before = List<int>.from(g2);
    final name = si < stageNames.length ? stageNames[si] : 'stage$si';
    if (stage is Function(List<int>, String)) {
      g2 = stage(List<int>.from(g2), 'gujarati');
    } else if (stage is List<String>) {
      final gi = GlyphIterator(parser, List<int>.from(g2));
      final ot = OTProcessor(parser, gi);
      final lookups = ot.lookupsForFeatures(stage, features);
      ot.applyLookups(lookups);
      g2 = ot.glyphIterator.glyphs.map((g) => g.id).toList();
      if (before.length != g2.length || !_eq(before, g2)) {
        print('  Stage $si ($name): $before -> $g2');
      }
    }
  }
  print('  Final (reph reordered): $g2');
  print('\nGlyph details (reordered):');
  for (final gid in g2) {
    final metrics = parser.glyphInfoMap[gid];
    print('  glyph $gid: advance=${metrics?.advanceWidth ?? "N/A"}');
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
