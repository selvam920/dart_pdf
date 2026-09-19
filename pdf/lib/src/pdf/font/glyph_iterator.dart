import 'glyph_info.dart';
import 'gsub_parser.dart';
import 'ttf_parser.dart';

class GlyphIterator {
  GlyphIterator(this.font, List<int> glyphIndexes, [this.options]) {
    glyphIds = glyphIndexes;
    reset(options);
  }
  List<GlyphInfo> glyphs = [];
  LookupFlag? options;
  int index = 0;
  Map<String, bool>? flags;
  int markAttachmentType = 0;
  late TtfParser font;

  /// Derived from [glyphs] instead of being cached, because a substitution
  /// rewrites a glyph id in place and a cached copy would go stale.
  List<int> get glyphIds => glyphs.map((g) => g.id).toList();

  set glyphIds(List<int> val) {
    glyphs = val.map((int glyphId) => GlyphInfo(font, glyphId)).toList();
  }

  GlyphInfo get cur => glyphs[index];

  void reset(LookupFlag? options, [int i = 0]) {
    // Assigning to the field, not to the parameter: nested lookups read
    // `options` back to restore the flags of the lookup they interrupted.
    this.options = options;
    flags = options?.flags;
    markAttachmentType = options?.markAttachmentType ?? 0;
    index = i;
  }

  bool shouldIgnore(GlyphInfo glyph) {
    return flags != null &&
        ((flags!['ignoreMarks']! && glyph.isMark) ||
            (flags!['ignoreBaseGlyphs']! && glyph.isBase) ||
            (flags!['ignoreLigatures']! && glyph.isLigature) ||
            (markAttachmentType > 0 &&
                glyph.isMark &&
                glyph.markAttachmentType != markAttachmentType));
  }

  GlyphInfo? move(int dir) {
    index += dir;
    while (0 <= index && index < glyphs.length && shouldIgnore(glyphs[index])) {
      index += dir;
    }

    if (0 > index || index >= glyphs.length) {
      return null;
    }

    return glyphs[index];
  }

  GlyphInfo? next() {
    return move(1);
  }

  GlyphInfo? prev() {
    return move(-1);
  }

  GlyphInfo? peek([int count = 1]) {
    final idx = index;
    final res = increment(count);
    index = idx;
    return res;
  }

  int peekIndex([int count = 1]) {
    final idx = index;
    increment(count);
    final res = index;
    index = idx;
    return res;
  }

  GlyphInfo? increment([int count = 1]) {
    final dir = count < 0 ? -1 : 1;
    count = count.abs();
    while (count-- > 0) {
      move(dir);
    }

    if (0 > index || index >= glyphs.length) {
      return null;
    }

    return glyphs[index];
  }
}
