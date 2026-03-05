import 'glyph_iterator.dart';
import 'gsub_parser.dart';
import 'ot_processor.dart';
import 'ttf_parser.dart';

/* Unicode-based Indic character categories */

/// Left-positioned matras that visually appear before the base consonant
/// but are stored after it in Unicode. These must be reordered.
bool _isLeftMatra(int codepoint) {
  // Devanagari
  if (codepoint == 0x093F) {
    return true; // ि
  }
  // Bengali
  if (codepoint == 0x09BF || codepoint == 0x09C7 || codepoint == 0x09C8) {
    return true; // ি ে ৈ
  }
  // Gurmukhi
  if (codepoint == 0x0A3F) {
    return true; // ਿ
  }
  // Gujarati
  if (codepoint == 0x0ABF) {
    return true; // િ
  }
  // Oriya
  if (codepoint == 0x0B3F || codepoint == 0x0B47 || codepoint == 0x0B48) {
    return true; // ି େ ୈ
  }
  // Tamil
  if (codepoint >= 0x0BC6 && codepoint <= 0x0BC8) {
    return true; // ெ ே ை
  }
  // Telugu
  if (codepoint >= 0x0C46 && codepoint <= 0x0C48) {
    return true; // ె  ే  ై
  }
  // Kannada
  if (codepoint >= 0x0CC6 && codepoint <= 0x0CC8) {
    return true; // ೆ ೇ ೈ
  }
  // Malayalam
  if (codepoint >= 0x0D46 && codepoint <= 0x0D48) {
    return true; // െ േ ൈ
  }
  // Sinhala
  if (codepoint == 0x0DD9 || codepoint == 0x0DDA || codepoint == 0x0DDC) {
    return true; // ෙ ේ ො
  }
  return false;
}

/// Two-part vowels that decompose into left-matra + right component
/// Returns [leftPart, rightPart] codepoints, or null if not a compound vowel.
List<int>? _decomposeCompoundVowel(int codepoint) {
  // Devanagari
  if (codepoint == 0x094B) {
    return [0x093F, 0x0947]; // ो -> ि + े (not standard)
  }
  // Actually Devanagari ो doesn't decompose in shaping

  // Bengali
  if (codepoint == 0x09CB) {
    return [0x09C7, 0x09BE]; // ো -> ে + া
  }
  if (codepoint == 0x09CC) {
    return [0x09C7, 0x09D7]; // ৌ -> ে + ৗ
  }

  // Oriya
  if (codepoint == 0x0B4B) {
    return [0x0B47, 0x0B3E]; // ୋ -> େ + ା
  }
  if (codepoint == 0x0B4C) {
    return [0x0B47, 0x0B57]; // ୌ -> େ + ୗ
  }

  // Tamil
  if (codepoint == 0x0BCA) {
    return [0x0BC6, 0x0BBE]; // ொ -> ெ + ா
  }
  if (codepoint == 0x0BCB) {
    return [0x0BC7, 0x0BBE]; // ோ -> ே + ா
  }
  if (codepoint == 0x0BCC) {
    return [0x0BC6, 0x0BD7]; // ௌ -> ெ + ௗ
  }

  // Malayalam
  if (codepoint == 0x0D4A) {
    return [0x0D46, 0x0D3E]; // ൊ -> െ + ാ
  }
  if (codepoint == 0x0D4B) {
    return [0x0D47, 0x0D3E]; // ോ -> േ + ാ
  }
  if (codepoint == 0x0D4C) {
    return [0x0D46, 0x0D57]; // ൌ -> െ + ൗ
  }

  // Sinhala
  if (codepoint == 0x0DDC) {
    return [0x0DD9, 0x0DCF]; // ො -> ෙ + ා
  }
  if (codepoint == 0x0DDD) {
    return [0x0DD9, 0x0DDF]; // ෝ -> ෙ + ෟ (not standard)
  }
  if (codepoint == 0x0DDE) {
    return [0x0DD9, 0x0DDE]; // skip
  }

  // Kannada
  if (codepoint == 0x0CCA) {
    return [0x0CC6, 0x0CC2]; // ೊ -> ೆ + ೂ
  }
  if (codepoint == 0x0CCB) {
    return [0x0CC6, 0x0CC2]; // ೋ -> ೆ + ೂ (+ 0x0CD5)
  }

  return null;
}

/// Check if codepoint is a virama/halant/hasanta
bool _isVirama(int codepoint) {
  return codepoint == 0x094D || // Devanagari
      codepoint == 0x09CD || // Bengali
      codepoint == 0x0A4D || // Gurmukhi
      codepoint == 0x0ACD || // Gujarati
      codepoint == 0x0B4D || // Oriya
      codepoint == 0x0BCD || // Tamil
      codepoint == 0x0C4D || // Telugu
      codepoint == 0x0CCD || // Kannada
      codepoint == 0x0D4D || // Malayalam
      codepoint == 0x0DCA; // Sinhala
}

/// Check if codepoint is an Indic consonant
bool _isConsonant(int codepoint) {
  return (codepoint >= 0x0915 && codepoint <= 0x0939) || // Devanagari
      (codepoint >= 0x0958 && codepoint <= 0x0961) || // Devanagari extended
      (codepoint >= 0x0995 && codepoint <= 0x09B9) || // Bengali
      (codepoint >= 0x09DC && codepoint <= 0x09DF) || // Bengali extended
      (codepoint >= 0x0A15 && codepoint <= 0x0A39) || // Gurmukhi
      (codepoint >= 0x0A59 && codepoint <= 0x0A5E) || // Gurmukhi extended
      (codepoint >= 0x0A95 && codepoint <= 0x0AB9) || // Gujarati
      (codepoint >= 0x0B15 && codepoint <= 0x0B39) || // Oriya
      (codepoint >= 0x0B5C && codepoint <= 0x0B5D) || // Oriya extended
      codepoint == 0x0B71 || // Oriya WA
      (codepoint >= 0x0B95 && codepoint <= 0x0BB9) || // Tamil
      (codepoint >= 0x0C15 && codepoint <= 0x0C39) || // Telugu
      (codepoint >= 0x0C58 && codepoint <= 0x0C5A) || // Telugu extended
      (codepoint >= 0x0C95 && codepoint <= 0x0CB9) || // Kannada
      (codepoint >= 0x0CDE && codepoint == 0x0CDE) || // Kannada FA
      (codepoint >= 0x0D15 && codepoint <= 0x0D39) || // Malayalam
      (codepoint >= 0x0D9A && codepoint <= 0x0DC6); // Sinhala
}

/// Check if codepoint is RA in a script that uses reph
bool _isRa(int codepoint) {
  return codepoint == 0x0930 || // Devanagari
      codepoint == 0x09B0 || // Bengali
      codepoint == 0x0A30 || // Gurmukhi
      codepoint == 0x0AB0 || // Gujarati
      codepoint == 0x0B30 || // Oriya
      codepoint == 0x0CB0 || // Kannada
      codepoint == 0x0D30; // Malayalam
}

/// Decompose compound vowels, reorder reph, and reorder left-positioned matras.
/// This operates on codepoints, before glyph ID mapping.
List<int> _reorderCodepoints(List<int> codepoints) {
  // Step 1: Decompose compound vowels
  final decomposed = <int>[];
  for (final cp in codepoints) {
    final parts = _decomposeCompoundVowel(cp);
    if (parts != null) {
      decomposed.addAll(parts);
    } else {
      decomposed.add(cp);
    }
  }

  // Step 2: Reorder reph (Ra+virama at cluster start → after base consonant).
  // In Indic scripts, Ra+virama at the start of a consonant cluster forms
  // reph (a mark above the base consonant). The Ra+virama needs to move
  // to after the base consonant so the reph glyph ends up in the correct
  // position in the glyph stream.
  final reph = List<int>.from(decomposed);
  for (var i = 0; i < reph.length - 2; i++) {
    if (_isRa(reph[i]) &&
        i + 1 < reph.length &&
        _isVirama(reph[i + 1]) &&
        i + 2 < reph.length &&
        _isConsonant(reph[i + 2])) {
      // Check Ra is at cluster start (not preceded by virama)
      if (i == 0 || !_isVirama(reph[i - 1])) {
        // Find the base consonant (last consonant in the cluster)
        var base = i + 2;
        while (base + 2 < reph.length &&
            _isVirama(reph[base + 1]) &&
            _isConsonant(reph[base + 2])) {
          base += 2;
        }
        // Move Ra+virama from [i, i+1] to after base
        final ra = reph.removeAt(i);
        final virama = reph.removeAt(i);
        // base shifted left by 2 due to removal
        reph.insert(base - 1, ra);
        reph.insert(base, virama);
        // Skip past the reordered cluster
        i = base;
      }
    }
  }

  // Step 3: Reorder left-matras before their base consonant cluster.
  // A left-matra should move before the consonant cluster it follows.
  // A consonant cluster is: C (virama C)* where C is a consonant.
  final result = List<int>.from(reph);
  for (var i = 1; i < result.length; i++) {
    if (_isLeftMatra(result[i])) {
      // Find the start of the consonant cluster
      var clusterStart = i - 1;
      // Skip back over virama+consonant pairs
      while (clusterStart >= 2 &&
          _isVirama(result[clusterStart]) &&
          _isConsonant(result[clusterStart - 1])) {
        clusterStart -= 2;
      }
      // Only reorder if clusterStart points to a consonant
      if (clusterStart < i && _isConsonant(result[clusterStart])) {
        final matra = result.removeAt(i);
        result.insert(clusterStart, matra);
      }
    }
  }

  return result;
}

/* Legacy glyph-level reorder functions (called during shaping stages) */

List<int> initialReorder(List<int> glyphIndexes, String lang) {
  // Glyph-level reordering is now minimal since we handle reordering
  // at the codepoint level in _reorderCodepoints before glyph mapping.
  return glyphIndexes;
}

List<int> finalReorder(List<int> glyphIndexes, String lang) {
  return glyphIndexes;
}

String getLang(String fontName) {
  final name = fontName.toLowerCase();
  if (name.contains('tamil')) {
    return 'tamil';
  } else if (name.contains('devanagari') ||
      name.contains('hindi') ||
      name.contains('marathi') ||
      name.contains('nepali') ||
      name.contains('sanskrit')) {
    return 'hindi';
  } else if (name.contains('telugu')) {
    return 'telugu';
  } else if (name.contains('bengali') || name.contains('assamese')) {
    return 'bengali';
  } else if (name.contains('gujarati')) {
    return 'gujarati';
  } else if (name.contains('kannada')) {
    return 'kannada';
  } else if (name.contains('malayalam')) {
    return 'malayalam';
  } else if (name.contains('oriya') || name.contains('odia')) {
    return 'oriya';
  } else if (name.contains('gurmukhi') || name.contains('punjabi')) {
    return 'gurmukhi';
  } else if (name.contains('sinhala')) {
    return 'sinhala';
  }
  return '';
}

bool isIndicShaperSupported(String lang) {
  return [
    'tamil',
    'hindi',
    'telugu',
    'bengali',
    'gujarati',
    'kannada',
    'malayalam',
    'oriya',
    'gurmukhi',
    'sinhala',
  ].contains(lang);
}

var variationFeatures = ['rvrn'];
var directionalFeatures = {
  'ltr': ['ltra', 'ltrm'],
  'rtl': ['rtla', 'rtlm']
};
var fractionalFeatures = ['frac', 'numr', 'dnom'];
var commonFeatures = ['rlig', 'mark', 'mkmk'];
var horizontalFeatures = ['calt', 'clig', 'liga', 'rclt', 'curs', 'kern'];

List<dynamic> setupStages() {
  final stages = <dynamic>[];
  stages.add([
    ...variationFeatures,
    ...directionalFeatures['ltr']!,
    ...fractionalFeatures
  ]);
  stages.add(['locl', 'ccmp']);
  stages.add(initialReorder);
  stages.add(['nukt']);
  stages.add(['akhn']);
  stages.add(['rphf']);
  stages.add(['rkrf']);
  stages.add(['pref']);
  stages.add(['blwf']);
  stages.add(['abvf']);
  stages.add(['half']);
  stages.add(['pstf']);
  stages.add(['vatu']);
  stages.add(['cjct']);
  stages.add(['cfar']);
  stages.add(finalReorder);
  stages.add({
    'pres',
    'abvs',
    'blws',
    'psts',
    'haln',
    'dist',
    'abvm',
    'blwm',
    'calt',
    'clig',
    ...commonFeatures,
    ...horizontalFeatures
  }.toList());
  return stages;
}

Map<String, FeatureRecord> getFeatureMap(TtfParser font) {
  final features = <String, FeatureRecord>{};
  for (var record in font.gsub!.featureList.featureRecords) {
    features[record.featureTag] = record;
  }
  return features;
}

List<int> indicShaper(List<int> glyphIndexes, TtfParser font,
    [List<int>? codepoints]) {
  final lang = getLang(font.fontName);
  if (isIndicShaperSupported(lang)) {
    // If codepoints are provided, do Unicode-level reordering first,
    // then re-map to glyph IDs
    if (codepoints != null) {
      final reordered = _reorderCodepoints(codepoints);
      glyphIndexes = reordered
          .map((cp) => font.charToGlyphIndexMap[cp] ?? 0)
          .toList();
    }

    final features = getFeatureMap(font);
    final stages = setupStages();
    for (var stage in stages) {
      final glyphIterator = GlyphIterator(font, glyphIndexes);
      if (stage is Function(List<int>, String)) {
        glyphIndexes = stage(glyphIndexes, lang);
      } else if (stage is List<String>) {
        final ot = OTProcessor(font, glyphIterator);
        final lookups = ot.lookupsForFeatures(stage, features);
        ot.applyLookups(lookups);
        glyphIndexes = ot.glyphIterator.glyphs.map((g) => g.id).toList();
      }
    }
  }
  return glyphIndexes;
}
