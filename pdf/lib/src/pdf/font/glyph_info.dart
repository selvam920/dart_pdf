import 'ot_processor.dart';
import 'ttf_parser.dart';

class GlyphInfo {
  GlyphInfo(this.font, int glyphId) {
    id = glyphId;
  }
  late TtfParser font;
  int _id = -1;
  bool isMultiplied = false;
  bool substituted = false;
  bool isLigated = false;
  bool isMark = false;
  bool isLigature = false;
  bool isBase = false;
  int markAttachmentType = 0;

  int get id => _id;
  set id(int val) {
    _id = val;
    substituted = true;
    final gdef = font.gdef;
    if (gdef != null && gdef.glyphClassDef != null) {
      final classID = OTProcessor.getClassID(id, gdef.glyphClassDef!);
      isBase = classID == 1;
      isLigature = classID == 2;
      isMark = classID == 3;
      markAttachmentType = gdef.markAttachClassDef != null
          ? OTProcessor.getClassID(id, gdef.markAttachClassDef!)
          : 0;
    }
  }
}
