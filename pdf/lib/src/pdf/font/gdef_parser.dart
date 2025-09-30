import 'dart:typed_data';

import 'gsub_parser.dart';

class GDEFParser {
  GDEFParser({required this.data, this.startPosition = 0}) {
    final base = startPosition;
    final glyphClassDefOffset = base + data.getUint16(base + 4);
    final markAttachClassDefOffset = base + data.getUint16(base + 10);
    glyphClassDef = ClassDef.parse(data, glyphClassDefOffset);
    attachList = null;
    ligCaretList = null;
    markAttachClassDef = ClassDef.parse(data, markAttachClassDefOffset);
  }
  final ByteData data;
  final int startPosition;
  late ClassDef? glyphClassDef;
  late ClassDef? markAttachClassDef;
  dynamic attachList;
  dynamic ligCaretList;
}
