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

import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';

void main() {
  test('reads a complete printer', () {
    final printer = Printer.fromMap(<dynamic, dynamic>{
      'url': 'ipp://printer.local',
      'name': 'Office',
      'model': 'Laser 9000',
      'location': 'Floor 2',
      'comment': 'Colour',
      'default': true,
      'available': false,
    });

    expect(printer.url, 'ipp://printer.local');
    expect(printer.name, 'Office');
    expect(printer.model, 'Laser 9000');
    expect(printer.location, 'Floor 2');
    expect(printer.comment, 'Colour');
    expect(printer.isDefault, isTrue);
    expect(printer.isAvailable, isFalse);
  });

  test('a printer with no url falls back to its name', () {
    // A queue with a nil URL on iOS, or a driver that reports no device name.
    final printer = Printer.fromMap(<dynamic, dynamic>{'name': 'Office'});

    expect(printer.url, 'Office');
    expect(printer.name, 'Office');
  });

  test('a printer with neither url nor name does not throw', () {
    final printer = Printer.fromMap(<dynamic, dynamic>{});

    expect(printer.url, '');
    expect(printer.name, '');
    expect(printer.isDefault, isFalse);
    expect(printer.isAvailable, isTrue);
  });
}
