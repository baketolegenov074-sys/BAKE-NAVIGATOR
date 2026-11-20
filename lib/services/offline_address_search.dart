import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// Searches the bundled Shymkent OSM address/POI index without network access.
class OfflineAddressSearch {
  static const String _assetPath = 'assets/data/shymkent_search.json.gz';

  Future<void>? _loading;
  List<Map<String, dynamic>> _items = <Map<String, dynamic>>[];

  Future<void> initialize() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      final decoded = jsonDecode(utf8.decode(gzip.decode(bytes)));
      if (decoded is! Map || decoded['items'] is! List) {
        throw const FormatException('Invalid offline address index');
      }
      _items = (decoded['items'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    } catch (error) {
      _items = <Map<String, dynamic>>[];
      // The app remains usable with Photon when the bundled index is absent.
      // ignore: avoid_print
      print('BAKE offline address index could not be loaded: $error');
    }
  }

  Future<List<Map<String, dynamic>>> search(
    String query, {
    LatLng? near,
    int limit = 10,
  }) async {
    await initialize();
    final normalizedQuery = _fold(query);
    final queryTokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toSet()
        .toList();
    if (queryTokens.isEmpty || _items.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final matches = <({int score, double distance, Map<String, dynamic> item})>[];
    for (final item in _items) {
      final haystack = _fold(item['search']?.toString() ?? '');
      if (haystack.isEmpty) continue;

      var score = 0;
      var allTokensMatch = true;
      for (final token in queryTokens) {
        if (haystack.contains(token)) {
          score += 20;
        } else {
          allTokensMatch = false;
          break;
        }
      }
      if (!allTokensMatch) continue;

      if (haystack.contains(normalizedQuery)) score += 60;
      final house = _fold(item['house']?.toString() ?? '');
      if (house.isNotEmpty && queryTokens.contains(house)) score += 45;
      final name = _fold(item['name']?.toString() ?? '');
      if (name.isNotEmpty && queryTokens.every(name.contains)) score += 25;
      final street = _fold(item['street']?.toString() ?? '');
      if (street.isNotEmpty && queryTokens.every(street.contains)) score += 18;

      final lat = (item['lat'] as num?)?.toDouble();
      final lon = (item['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final distance = near == null
          ? 0.0
          : const Distance().as(
              LengthUnit.Kilometer,
              near,
              LatLng(lat, lon),
            );
      matches.add((score: score, distance: distance, item: item));
    }

    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.distance.compareTo(b.distance);
    });

    return matches.take(limit).map((match) {
      final item = match.item;
      final name = item['name']?.toString() ?? '';
      final street = item['street']?.toString() ?? '';
      final house = item['house']?.toString() ?? '';
      final label = item['label']?.toString() ?? '';
      return <String, dynamic>{
        '_offline': true,
        'type': 'Feature',
        'properties': <String, dynamic>{
          'name': name,
          'street': street,
          'housenumber': house,
          'city': 'Шымкент',
          'label': label,
          'type': item['kind']?.toString() ?? 'place',
        },
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[
            (item['lon'] as num).toDouble(),
            (item['lat'] as num).toDouble(),
          ],
        },
      };
    }).toList(growable: false);
  }

  String _fold(String value) {
    var text = value.toLowerCase().replaceAll('ё', 'е');
    const kazakhToRussian = <String, String>{
      'ә': 'а',
      'ғ': 'г',
      'қ': 'к',
      'ң': 'н',
      'ө': 'о',
      'ұ': 'у',
      'ү': 'у',
      'һ': 'х',
      'і': 'и',
    };
    kazakhToRussian.forEach((from, to) {
      text = text.replaceAll(from, to);
    });

    const digraphs = <String, String>{
      'shch': 'щ',
      'zh': 'ж',
      'ch': 'ч',
      'sh': 'ш',
      'kh': 'х',
      'gh': 'г',
      'ng': 'н',
      'yo': 'е',
      'yu': 'ю',
      'ya': 'я',
      'ts': 'ц',
    };
    digraphs.forEach((from, to) {
      text = text.replaceAll(from, to);
    });
    const latin = <String, String>{
      'a': 'а', 'b': 'б', 'c': 'к', 'd': 'д', 'e': 'е',
      'f': 'ф', 'g': 'г', 'h': 'х', 'i': 'и', 'j': 'ж',
      'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н', 'o': 'о',
      'p': 'п', 'q': 'к', 'r': 'р', 's': 'с', 't': 'т',
      'u': 'у', 'v': 'в', 'w': 'в', 'x': 'кс', 'y': 'ы',
      'z': 'з',
    };
    text = text.replaceAllMapped(
      RegExp('[a-z]'),
      (match) => latin[match.group(0)] ?? match.group(0)!,
    );
    text = text.replaceAll(RegExp(r'[^0-9а-я]+'), ' ');
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}
