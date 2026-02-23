import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

void main() {
  test('Indic fonts rendering test', () async {
    final pdf = pw.Document();

    // Use the Google Fonts endpoint to download test fonts
    final fontsToTest = <String, String>{
      'Tamil': 'https://fonts.gstatic.com/s/notosanstamil/v27/ieVc2YdFI3GCY6SyQy1KfStzYKZgzN1z4LKDbeZce-0429tBManUktuex7vGor0RqKDt_EvT.ttf',
      'Devanagari': 'https://fonts.gstatic.com/s/notosansdevanagari/v26/TuGoUVpzXI5FBtUq5a8bjKYTZjtRU6Sgv3NaV_SNmI0b6w.ttf',
      'Bengali': 'https://fonts.gstatic.com/s/notosansbengali/v20/Cn-SJsCGWQxOjaGwMQ6fIiMywrNJIky6nvd8BjzVMvJx2mcSPVFpVEqE-6KmsolLudCk8izI0lc.ttf',
      'Telugu': 'https://fonts.gstatic.com/s/notosanstelugu/v26/0teleQpBWBkOG-HhKoEJTjhqSU1IbVr6UZZhkco9HIZ0NiAnXMG.ttf',
    };

    final samples = {
      'Hindi': 'नमस्ते दुनिया',
      'Bengali': 'হ্যালো দুনিয়া',
      'Tamil': 'ஹலோ வேர்ல்ட்',
      'Telugu': 'హలో వరల్డ్',
    };

    // If we have local font files, use those
    final localFonts = <String, String>{
      'Tamil': 'NotoSansTamil-Regular.ttf',
      'Devanagari': 'NotoSansDevanagari-Regular.ttf',
      'Bengali': 'NotoSansBengali-Regular.ttf',
      'Telugu': 'NotoSansTelugu-Regular.ttf',
    };

    for (final entry in localFonts.entries) {
      final file = File(entry.value);
      if (!file.existsSync()) {
        print('Font file ${entry.value} not found, skipping');
        continue;
      }

      print('Testing font: ${entry.key} (${entry.value})');
      try {
        final fontData = file.readAsBytesSync();
        final font = pw.Font.ttf(fontData.buffer.asByteData());
        final sampleText = samples[entry.key] ?? 'Test';

        pdf.addPage(
          pw.Page(
            build: (context) => pw.Text(
              '${entry.key}: $sampleText',
              style: pw.TextStyle(font: font, fontSize: 20),
            ),
          ),
        );
        print('  OK - page added for ${entry.key}');
      } catch (e, stack) {
        print('  ERROR for ${entry.key}: $e');
        print(stack);
      }
    }

    try {
      final output = await pdf.save();
      print('PDF generated successfully, ${output.length} bytes');
      File('indic_test.pdf').writeAsBytesSync(output);
    } catch (e, stack) {
      print('PDF save error: $e');
      print(stack);
    }
  });

  test('Indic font from ByteData with offset', () {
    // Simulate what Flutter does when loading assets - the ByteData
    // may have a non-zero offsetInBytes
    final fontFiles = <String>[
      'NotoSansTamil-Regular.ttf',
      'NotoSansDevanagari-Regular.ttf',
    ];

    for (final fontFile in fontFiles) {
      final file = File(fontFile);
      if (!file.existsSync()) {
        print('Font file $fontFile not found, skipping offset test');
        continue;
      }

      final originalBytes = file.readAsBytesSync();
      print('Testing $fontFile with simulated offset...');

      // Create a buffer with padding to simulate non-zero offsetInBytes
      final paddedLength = originalBytes.length + 100;
      final paddedBuffer = Uint8List(paddedLength);
      paddedBuffer.setRange(50, 50 + originalBytes.length, originalBytes);
      final byteData = ByteData.sublistView(paddedBuffer, 50,
          50 + originalBytes.length);

      try {
        final font = pw.Font.ttf(byteData);
        print('  Font loaded OK: ${font.fontName}');
      } catch (e, stack) {
        print('  ERROR: $e');
        print(stack);
      }
    }
  });
}
