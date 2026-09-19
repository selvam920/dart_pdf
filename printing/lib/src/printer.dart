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

import 'package:meta/meta.dart';

/// Information about a printer
@immutable
class Printer {
  /// Create a printer information
  const Printer({
    required this.url,
    String? name,
    this.model,
    this.location,
    this.comment,
    bool? isDefault,
    bool? isAvailable,
  }) : name = name ?? url,
       isDefault = isDefault ?? false,
       isAvailable = isAvailable ?? true;

  /// Create an information object from a dictionnary
  ///
  /// A platform that reports a printer with no url — a queue with a nil URL on
  /// iOS, a driver that returns no device name — used to throw a TypeError out
  /// of the implicit cast to a non-nullable String. Fall back to the name, and
  /// to an empty url only when neither is given, so listing printers cannot
  /// fail because of one bad entry.
  factory Printer.fromMap(Map<dynamic, dynamic> map) {
    final url = map['url'] as String?;
    final name = map['name'] as String?;

    return Printer(
      url: url ?? name ?? '',
      name: name,
      model: map['model'] as String?,
      location: map['location'] as String?,
      comment: map['comment'] as String?,
      isDefault: map['default'] as bool?,
      isAvailable: map['available'] as bool?,
    );
  }

  /// The platform specific printer identification
  final String url;

  /// The display name of the printer
  final String name;

  /// The printer model
  final String? model;

  /// The physical location of the printer
  final String? location;

  /// A user comment about the printer
  final String? comment;

  /// Is this the default printer on the system
  final bool isDefault;

  /// The printer is available for printing
  final bool isAvailable;

  @override
  String toString() =>
      '''
$runtimeType $name
  url:$url
  location:$location
  model:$model
  comment:$comment
  isDefault:$isDefault
  isAvailable: $isAvailable''';

  Map<String, Object?> toMap() => {
    'url': url,
    'name': name,
    'model': model,
    'location': location,
    'comment': comment,
    'default': isDefault,
    'available': isAvailable,
  };
}
