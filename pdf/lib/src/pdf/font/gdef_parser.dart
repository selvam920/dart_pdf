import 'dart:typed_data';

import 'gsub_parser.dart';

class GDEFParser {
  GDEFParser({required this.data, this.startPosition = 0}) {
    try {
      final base = startPosition;
      final glyphClassDefOffset = data.getUint16(base + 4);
      final markAttachClassDefOffset = data.getUint16(base + 10);
      glyphClassDef = glyphClassDefOffset != 0
          ? ClassDef.parse(data, base + glyphClassDefOffset)
          : null;
      attachList = null;
      ligCaretList = null;
      markAttachClassDef = markAttachClassDefOffset != 0
          ? ClassDef.parse(data, base + markAttachClassDefOffset)
          : null;
    } catch (e, stack) {
      print('Error parsing GDEF table: $e');
      print(stack);
      rethrow;
    }
  }
  final ByteData data;
  final int startPosition;
  late ClassDef? glyphClassDef;
  late ClassDef? markAttachClassDef;
  dynamic attachList;
  dynamic ligCaretList;
}
