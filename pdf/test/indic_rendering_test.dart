import 'dart:io';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:test/test.dart';

Future<Uint8List> downloadFont(String url, String cacheFile) async {
  final file = File(cacheFile);
  if (file.existsSync()) {
    return file.readAsBytesSync();
  }
  final client = HttpClient();
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
        <int>[], (prev, chunk) => prev..addAll(chunk));
    final data = Uint8List.fromList(bytes);
    file.writeAsBytesSync(data);
    return data;
  } finally {
    client.close();
  }
}

void main() {
  final fontsToTest = <String, Map<String, String>>{
    'Tamil': {
      'url':
          'https://fonts.gstatic.com/s/notosanstamil/v27/ieVc2YdFI3GCY6SyQy1KfStzYKZgzN1z4LKDbeZce-0429tBManUktuex7vGor0RqKDt_EvT.ttf',
      'cache': 'NotoSansTamil-Regular.ttf',
      'sample': 'ஹலோ வேர்ல்ட்',
    },
    'Devanagari': {
      'url':
          'https://fonts.gstatic.com/s/notosansdevanagari/v26/TuGoUUFzXI5FBtUq5a8bjKYTZjtRU6Sgv3NaV_SNmI0b8QQCQmHn6B2OHjbL_08AlXQly-AzoFoW4Ow.ttf',
      'cache': 'NotoSansDevanagari-Regular.ttf',
      'sample': 'नमस्ते दुनिया',
    },
    'Bengali': {
      'url':
          'https://fonts.gstatic.com/s/notosansbengali/v20/Cn-SJsCGWQxOjaGwMQ6fIiMywrNJIky6nvd8BjzVMvJx2mcSPVFpVEqE-6KmsolLudCk8izI0lc.ttf',
      'cache': 'NotoSansBengali-Regular.ttf',
      'sample': 'হ্যালো দুনিয়া',
    },
    'Telugu': {
      'url':
          'https://fonts.gstatic.com/s/notosanstelugu/v26/0FlxVOGZlE2Rrtr-HmgkMWJNjJ5_RyT8o8c7fHkeg-esVC5dzHkHIJQqrEntezbqQUbf-3v37w.ttf',
      'cache': 'NotoSansTelugu-Regular.ttf',
      'sample': 'హలో వరల్డ్',
    },
    'Gujarati': {
      'url':
          'https://fonts.gstatic.com/s/notosansgujarati/v25/wlpWgx_HC1ti5ViekvcxnhMlCVo3f5pv17ivlzsUB14gg1TMR2Gw4VceEl7MA_ypFwPM_OdiEH0s.ttf',
      'cache': 'NotoSansGujarati-Regular.ttf',
      'sample': 'હેલો વર્લ્ડ',
    },
    'Gurmukhi': {
      'url':
          'https://fonts.gstatic.com/s/notosansgurmukhi/v26/w8g9H3EvQP81sInb43inmyN9zZ7hb7ATbSWo4q8dJ74a3cVrYFQ_bogT0-gPeG1OenbxZ_trdp7h.ttf',
      'cache': 'NotoSansGurmukhi-Regular.ttf',
      'sample': 'ਹੈਲੋ ਵਰਲਡ',
    },
    'Kannada': {
      'url':
          'https://fonts.gstatic.com/s/notosanskannada/v27/8vIs7xs32H97qzQKnzfeXycxXZyUmySvZWItmf1fe6TVmgop9ndpS-BqHEyGrDvNzSIMLsPKrkY.ttf',
      'cache': 'NotoSansKannada-Regular.ttf',
      'sample': 'ಹಲೋ ವರ್ಲ್ಡ್',
    },
    'Malayalam': {
      'url':
          'https://fonts.gstatic.com/s/notosansmalayalam/v26/sJoi3K5XjsSdcnzn071rL37lpAOsUThnDZIfPdbeSNzVakglNM-Qw8EaeB8Nss-_RuD9BFzEr6HxEA.ttf',
      'cache': 'NotoSansMalayalam-Regular.ttf',
      'sample': 'ഹലോ വേൾഡ്',
    },
    'Oriya': {
      'url':
          'https://fonts.gstatic.com/s/notosansoriya/v31/AYCppXfzfccDCstK_hrjDyADv5e9748vhj3CJBLHIARtgD6TJQS0dJT5Ivj0f6_c6LhHBRe-.ttf',
      'cache': 'NotoSansOriya-Regular.ttf',
      'sample': 'ହେଲୋ ୱର୍ଲ୍ଡ',
    },
    'Sinhala': {
      'url':
          'https://fonts.gstatic.com/s/notosanssinhala/v26/yMJ2MJBya43H0SUF_WmcBEEf4rQVO2P524V5N_MxQzQtb-tf5dJbC30Fu9zUwg2a5lgLpJwbQRM.ttf',
      'cache': 'NotoSansSinhala-Regular.ttf',
      'sample': 'හෙලෝ වර්ල්ඩ්',
    },
  };

  test('Download and test all Indic fonts', () async {
    final pdf = pw.Document();
    var errorCount = 0;

    for (final entry in fontsToTest.entries) {
      final name = entry.key;
      final url = entry.value['url']!;
      final cache = entry.value['cache']!;
      final sample = entry.value['sample']!;

      print('--- Testing $name ---');
      try {
        final fontData = await downloadFont(url, cache);
        print('  Font size: ${fontData.length} bytes');

        final font = pw.Font.ttf(fontData.buffer.asByteData());

        pdf.addPage(
          pw.Page(
            build: (context) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('$name: $sample',
                    style: pw.TextStyle(font: font, fontSize: 24)),
              ],
            ),
          ),
        );
        print('  OK - page added for $name');
      } catch (e, stack) {
        errorCount++;
        print('  ERROR for $name: $e');
        print(stack);
      }
    }

    try {
      final output = await pdf.save();
      print('\nPDF generated successfully, ${output.length} bytes');
      File('indic_all_test.pdf').writeAsBytesSync(output);
      print('Written to indic_all_test.pdf');
    } catch (e, stack) {
      print('PDF save error: $e');
      print(stack);
    }

    expect(errorCount, 0, reason: 'All Indic fonts should render without errors');
  }, timeout: Timeout(Duration(minutes: 5)));
}
