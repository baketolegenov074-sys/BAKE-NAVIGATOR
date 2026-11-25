import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';


List<Map<String, dynamic>> _decodeOfflineAddressSearchIndex(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(gzip.decode(bytes)));
  if (decoded is! Map || decoded['items'] is! List) {
    throw const FormatException('Invalid offline address index');
  }
  return (decoded['items'] as List)
      .whereType<Map>()
      .map((item) {
        final record = Map<String, dynamic>.from(item);
        record['_searchFolded'] =
            _foldOfflineAddressText(record['search']?.toString() ?? '');
        record['_nameFolded'] =
            _foldOfflineAddressText(record['name']?.toString() ?? '');
        record['_streetFolded'] =
            _foldOfflineAddressText(record['street']?.toString() ?? '');
        record['_houseFolded'] =
            _foldOfflineAddressText(record['house']?.toString() ?? '');
        record['_districtFolded'] =
            _foldOfflineAddressText(record['district']?.toString() ?? '');
        return record;
      })
      .toList(growable: false);
}

String _foldOfflineAddressText(String value) {
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
  text = text.replaceAll('малл', 'молл');
  text = text.replaceAll(RegExp(r'[^0-9а-я]+'), ' ');
  return text.trim().replaceAll(RegExp(r'\s+'), ' ');
}

/// Searches a curated Shymkent directory first, then the bundled OSM index.
class OfflineAddressSearch {
  static const String _assetPath = 'assets/data/shymkent_search.json.gz';

  // Coordinates supplied by the user or verified against map/address sources.
  // Neighbourhood points are search landmarks, not cadastral boundaries.
  static const List<Map<String, dynamic>> _directory = [
    {
      'name': 'Достык',
      'lat': 42.4032,
      'lon': 69.5610,
      'kind': 'neighbourhood',
      'aliases': ['достык', 'до 100'],
    },
    {
      'name': 'Достык-2',
      'lat': 42.3894,
      'lon': 69.5741,
      'kind': 'neighbourhood',
      'aliases': ['достык 2', 'достык-2', 'достык второй'],
    },
    {
      'name': 'Школа №88',
      'lat': 42.3885,
      'lon': 69.5752,
      'kind': 'school',
      'aliases': ['школа 88', 'школа №88', '88 школа', 'мектеп 88', 'school 88'],
    },
    {
      'name': 'Нурсат',
      'lat': 42.3694,
      'lon': 69.6228,
      'kind': 'neighbourhood',
      'aliases': ['нурсат', 'нур сад', 'нур-сат'],
    },
    {
      'name': 'Асар-2',
      'lat': 42.4235,
      'lon': 69.5912,
      'kind': 'neighbourhood',
      'aliases': ['асар 2', 'асар-2'],
    },
    {
      'name': 'Бозарык',
      'lat': 42.4150,
      'lon': 69.6310,
      'kind': 'neighbourhood',
      'aliases': ['бозарык', 'бозарық'],
    },
    {
      'name': 'Акжайык',
      'lat': 42.3840,
      'lon': 69.5650,
      'kind': 'neighbourhood',
      'aliases': ['акжайык', 'ак жайык', 'ақжайық'],
    },
    {
      'name': 'Казыгурт',
      'lat': 42.293082,
      'lon': 69.550067,
      'kind': 'neighbourhood',
      'aliases': ['казыгурт', 'казыгуртский'],
    },
    {
      'name': 'Сайрам',
      'lat': 42.342803,
      'lon': 69.635981,
      'kind': 'neighbourhood',
      'aliases': ['сайрам'],
    },
    {
      'name': 'Восток',
      'label': 'Восток (ориентир, район дома 30)',
      'lat': 42.334652,
      'lon': 69.646016,
      'kind': 'neighbourhood',
      'aliases': ['восток', 'микрорайон восток'],
    },
    {
      'name': 'Самал-1',
      'lat': 42.353045,
      'lon': 69.590518,
      'kind': 'neighbourhood',
      'aliases': ['самал 1', 'самал-1', 'самал первый'],
    },
    {
      'name': 'Самал-2',
      'lat': 42.361313,
      'lon': 69.618482,
      'kind': 'neighbourhood',
      'aliases': ['самал 2', 'самал-2', 'самал второй'],
    },
    {
      'name': 'Самал-3',
      'lat': 42.373844,
      'lon': 69.552762,
      'kind': 'neighbourhood',
      'aliases': ['самал 3', 'самал-3', 'самал третий'],
    },
    {
      'name': '11-й микрорайон',
      'lat': 42.322188,
      'lon': 69.638344,
      'kind': 'neighbourhood',
      'aliases': ['11 микрорайон', '11-й микрорайон', '11 мкр', 'одиннадцатый микрорайон'],
    },
    {
      'name': '16-й микрорайон',
      'lat': 42.336245,
      'lon': 69.640284,
      'kind': 'neighbourhood',
      'aliases': ['16 микрорайон', '16-й микрорайон', '16 мкр'],
    },
    {
      'name': '17-й микрорайон',
      'lat': 42.336826,
      'lon': 69.634149,
      'kind': 'neighbourhood',
      'aliases': ['17 микрорайон', '17-й микрорайон', '17 мкр'],
    },
    {
      'name': '18-й микрорайон',
      'lat': 42.341790,
      'lon': 69.625390,
      'kind': 'neighbourhood',
      'aliases': ['18 микрорайон', '18-й микрорайон', '18 мкр'],
    },
    {
      'name': 'ЖД Вокзал',
      'lat': 42.298724,
      'lon': 69.608834,
      'kind': 'transport',
      'aliases': ['жд вокзал', 'железнодорожный вокзал', 'вокзал', 'станция шымкент'],
    },
    {
      'name': 'Аэропорт Шымкент',
      'lat': 42.3650,
      'lon': 69.47556,
      'kind': 'transport',
      'aliases': ['аэропорт', 'аэропорт шымкент'],
    },
    {
      'name': 'Верхний рынок',
      'lat': 42.310634,
      'lon': 69.605017,
      'kind': 'market',
      'aliases': ['верхний рынок', 'верхний базар'],
    },
    {
      'name': 'Бекжан базар',
      'lat': 42.348908,
      'lon': 69.530052,
      'kind': 'market',
      'aliases': ['бекжан', 'бекжан базар', 'базар бекжан'],
    },
    {
      'name': 'Mega Planet',
      'lat': 42.319167,
      'lon': 69.596279,
      'kind': 'mall',
      'aliases': ['mega planet', 'мега планет', 'мегапланет'],
    },
    {
      'name': 'Shymkent Plaza',
      'lat': 42.314642,
      'lon': 69.587922,
      'kind': 'mall',
      'aliases': ['shymkent plaza', 'шимкент плаза', 'шымкент плаза'],
    },
  ];

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
      // Gzip decompression, JSON decoding and search-field normalization are
      // CPU-heavy for the full Shymkent index; keep them off the UI isolate.
      _items = await compute(_decodeOfflineAddressSearchIndex, bytes);
    } catch (error) {
      _items = <Map<String, dynamic>>[];
      // The curated directory still works if the generated OSM index is absent.
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
    // The full OSM index can contain many thousands of records. Run matching,
    // sorting and deduplication away from the UI isolate so typing stays responsive.
    return compute<Map<String, Object?>, List<Map<String, dynamic>>>(
      _searchOfflineAddressInIsolate,
      <String, Object?>{
        'items': _items,
        'query': query,
        'nearLatitude': near?.latitude,
        'nearLongitude': near?.longitude,
        'limit': limit,
      },
    );
  }

  List<Map<String, dynamic>> _searchSync(
    String query, {
    LatLng? near,
    int limit = 10,
  }) async {
    await initialize();
    final normalizedQuery = _normalizeQuery(query);
    final queryTokens = normalizedQuery
        .split(' ')
        .where((token) => token.isNotEmpty)
        .toSet()
        .toList();
    if (queryTokens.isEmpty) return <Map<String, dynamic>>[];

    // Always search both sources. The curated directory must never suppress
    // street/house/POI records from the full OSM index just because it found
    // enough nearby aliases first.
    final directoryMatches = _searchDirectory(
      query,
      normalizedQuery,
      near: near,
      limit: limit * 3,
    );
    final indexMatches = _searchOsmIndex(
      normalizedQuery,
      queryTokens,
      near: near,
      limit: limit * 3,
    );

    final combined = <Map<String, dynamic>>[
      ...directoryMatches,
      ...indexMatches,
    ];
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final feature in combined) {
      final properties = feature['properties'] as Map<String, dynamic>;
      final coordinates = (feature['geometry'] as Map)['coordinates'] as List;
      final identity = [
        (properties['name'] ?? '').toString().toLowerCase().trim(),
        (properties['street'] ?? '').toString().toLowerCase().trim(),
        (properties['housenumber'] ?? '').toString().toLowerCase().trim(),
        coordinates[0].toStringAsFixed(5),
        coordinates[1].toStringAsFixed(5),
      ].join('|');
      if (seen.add(identity)) unique.add(feature);
    }
    unique.sort((a, b) {
      final ap = a['properties'] as Map<String, dynamic>;
      final bp = b['properties'] as Map<String, dynamic>;
      final score = ((bp['_searchScore'] as num?)?.toInt() ?? 0)
          .compareTo((ap['_searchScore'] as num?)?.toInt() ?? 0);
      if (score != 0) return score;
      final ac = (a['geometry'] as Map)['coordinates'] as List;
      final bc = (b['geometry'] as Map)['coordinates'] as List;
      final ad = near == null ? 0.0 : _distanceKm(near, LatLng(
        (ac[1] as num).toDouble(), (ac[0] as num).toDouble(),
      ));
      final bd = near == null ? 0.0 : _distanceKm(near, LatLng(
        (bc[1] as num).toDouble(), (bc[0] as num).toDouble(),
      ));
      return ad.compareTo(bd);
    });
    return unique.take(limit).toList(growable: false);
  }

  bool _matchesSearchToken(String queryToken, Iterable<String> candidates) {
    for (final candidate in candidates) {
      if (candidate == queryToken) return true;
      if (RegExp(r'^\d').hasMatch(queryToken)) continue;
      if (queryToken.length >= 3 && candidate.startsWith(queryToken)) return true;
      final limit = queryToken.length >= 9 ? 2 : queryToken.length >= 5 ? 1 : 0;
      if (limit == 0 || (candidate.length - queryToken.length).abs() > limit) continue;
      if (_editDistanceAtMost(queryToken, candidate, limit) <= limit) return true;
    }
    return false;
  }

  int _editDistanceAtMost(String a, String b, int limit) {
    if ((a.length - b.length).abs() > limit) return limit + 1;
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 1; i <= a.length; i++) {
      final current = List<int>.filled(b.length + 1, limit + 1);
      current[0] = i;
      var rowMinimum = current[0];
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        current[j] = math.min(math.min(previous[j] + 1, current[j - 1] + 1), substitution);
        if (current[j] < rowMinimum) rowMinimum = current[j];
      }
      if (rowMinimum > limit) return limit + 1;
      previous = current;
    }
    return previous[b.length];
  }

  List<Map<String, dynamic>> _searchDirectory(
    String originalQuery,
    String normalizedQuery, {
    required LatLng? near,
    required int limit,
  }) {
    final parcelQuery = RegExp(
      r'(?:^|\s)(?:участок|уч\.?|дом|д\.?|кв\.?)(?:\s|$)',
      caseSensitive: false,
    ).hasMatch(originalQuery);
    final matches = <({int score, double distance, Map<String, dynamic> item})>[];

    for (final item in _directory) {
      final rawAliases = <String>[
        item['name'] as String,
        if (item['label'] is String) item['label'] as String,
        ...((item['aliases'] as List?)?.whereType<String>() ?? const <String>[]),
      ];
      var bestScore = 0;
      for (final alias in rawAliases) {
        final foldedAlias = _normalizeQuery(alias);
        if (foldedAlias.isEmpty) continue;
        if (foldedAlias == normalizedQuery) {
          if (bestScore < 100) bestScore = 100;
        } else if (normalizedQuery.length >= 4 &&
            foldedAlias.startsWith(normalizedQuery)) {
          if (bestScore < 78) bestScore = 78;
        } else {
          final queryWords = normalizedQuery.split(' ');
          final aliasWords = foldedAlias.split(' ');
          final allWordsFound = queryWords.every((word) => _matchesSearchToken(word, aliasWords));
          if (allWordsFound) {
            final exactWords = queryWords.every(aliasWords.contains);
            final score = exactWords ? 65 : 56;
            if (bestScore < score) bestScore = score;
          }
        }
      }
      if (bestScore == 0) continue;

      final lat = (item['lat'] as num).toDouble();
      final lon = (item['lon'] as num).toDouble();
      final distance = near == null ? 0.0 : _distanceKm(near, LatLng(lat, lon));
      matches.add((score: bestScore, distance: distance, item: item));
    }

    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.distance.compareTo(b.distance);
    });

    return matches.take(limit).map((match) {
      final item = match.item;
      final canonicalLabel = item['label']?.toString() ?? item['name'].toString();
      final displayLabel = parcelQuery ? originalQuery.trim() : canonicalLabel;
      return <String, dynamic>{
        '_offline': true,
        'type': 'Feature',
        'properties': <String, dynamic>{
          'name': item['name'],
          'display_label': displayLabel,
          'label': canonicalLabel,
          'city': 'Шымкент',
          'type': item['kind'] ?? 'place',
          'source': 'BAKE local directory',
          '_searchScore': match.score * 100,
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

  List<Map<String, dynamic>> _searchOsmIndex(
    String normalizedQuery,
    List<String> queryTokens, {
    required LatLng? near,
    required int limit,
  }) {
    if (limit <= 0 || _items.isEmpty) return <Map<String, dynamic>>[];
    final matches = <({int score, double distance, Map<String, dynamic> item})>[];

    for (final item in _items) {
      final haystack = item['_searchFolded']?.toString() ?? '';
      if (haystack.isEmpty) continue;
      final haystackWords = haystack.split(' ').where((word) => word.isNotEmpty).toList();
      var score = 0;
      var allTokensMatch = true;
      for (final token in queryTokens) {
        if (haystackWords.contains(token)) {
          score += 20;
        } else if (_matchesSearchToken(token, haystackWords)) {
          score += 12;
        } else {
          allTokensMatch = false;
          break;
        }
      }
      if (!allTokensMatch) continue;
      if (haystack.contains(normalizedQuery)) score += 60;

      final house = item['_houseFolded']?.toString() ?? '';
      final name = item['_nameFolded']?.toString() ?? '';
      final street = item['_streetFolded']?.toString() ?? '';

      // Address records must match their structured street/name and house
      // number. The alias blob can contain unrelated POI names and postcodes.
      if (house.isNotEmpty) {
        final numericTokens = queryTokens
            .where((token) => RegExp(r'^\d').hasMatch(token))
            .toList(growable: false);
        if (numericTokens.isNotEmpty) {
          final requestedHouse = numericTokens.join(' ');
          final houseMatches = house == requestedHouse ||
              house == numericTokens.last ||
              house.endsWith(' $requestedHouse');
          if (!houseMatches) continue;
        }
        final houseWords = house.split(' ').where((word) => word.isNotEmpty).toSet();
        final textTokens = queryTokens
            .where((token) => !(numericTokens.contains(token) && houseWords.contains(token)))
            .toList(growable: false);
        final district = item['_districtFolded']?.toString() ?? '';
        final addressWords = ('$street $name $district')
            .split(' ')
            .where((word) => word.isNotEmpty)
            .toSet();
        if (textTokens.isNotEmpty &&
            !textTokens.every((token) => _matchesSearchToken(token, addressWords))) {
          continue;
        }
        if (numericTokens.isNotEmpty) score += 45;
      }
      if (name.isNotEmpty && queryTokens.every((token) => name.contains(token))) score += 25;
      if (street.isNotEmpty && queryTokens.every((token) => street.contains(token))) score += 18;

      final lat = (item['lat'] as num?)?.toDouble();
      final lon = (item['lon'] as num?)?.toDouble();
      if (lat == null || lon == null) continue;
      final distance = near == null ? 0.0 : _distanceKm(near, LatLng(lat, lon));
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
          'district': item['district']?.toString() ?? '',
          'city': 'Шымкент',
          'label': label,
          'type': item['kind']?.toString() ?? 'place',
          '_searchScore': match.score * 10,
          'source': 'OpenStreetMap offline index',
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

  double _distanceKm(LatLng a, LatLng b) {
    const earthRadiusKm = 6371.0088;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final deltaLat = (b.latitude - a.latitude) * math.pi / 180;
    final deltaLon = (b.longitude - a.longitude) * math.pi / 180;
    final sinLat = math.sin(deltaLat / 2);
    final sinLon = math.sin(deltaLon / 2);
    final h = (sinLat * sinLat) +
        math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
    return earthRadiusKm * 2 * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  String _normalizeQuery(String value) {
    var normalized = value.toLowerCase().replaceAll('ё', 'е');
    normalized = normalized
        .replaceAll(RegExp(r'\bдо\s*100\b'), 'достык')
        .replaceAll(RegExp(r'\bнур\s+сад\b'), 'нурсат')
        .replaceAll(RegExp(r'\bщемкент\b'), 'шымкент')
        .replaceAll(RegExp(r'\bдендро\s+парк\b'), 'дендропарк')
        .replaceAll(RegExp(r'\bдендросаябак\b'), 'дендропарк')
        .replaceAll(RegExp(r'\bмол\b'), 'молл');
    final hasParcelQualifier = RegExp(
      r'(?:^|\s)(?:участок|уч\.?)(?:\s|$)',
    ).hasMatch(normalized);
    normalized = normalized.replaceAll(
      RegExp(r'(?:^|\s)(?:участок|уч\.?|дом|д\.?|кв\.?|улица|ул\.?|проспект|пр-т|пр\.?|переулок|пер\.?|шоссе|бульвар|бул\.?)(?=\s|$)'),
      ' ',
    );
    if (hasParcelQualifier) {
      normalized = normalized.replaceFirst(RegExp(r'\s+\d+\s*$'), '');
    }
    return _fold(normalized);
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
    text = text.replaceAll('малл', 'молл');
    text = text.replaceAll(RegExp(r'[^0-9а-я]+'), ' ');
    return text.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}


List<Map<String, dynamic>> _searchOfflineAddressInIsolate(
  Map<String, Object?> payload,
) {
  final service = OfflineAddressSearch();
  final rawItems = payload['items'];
  service._items = rawItems is List
      ? rawItems.whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
      : <Map<String, dynamic>>[];
  final latitude = (payload['nearLatitude'] as num?)?.toDouble();
  final longitude = (payload['nearLongitude'] as num?)?.toDouble();
  final near = latitude == null || longitude == null
      ? null
      : LatLng(latitude, longitude);
  return service._searchSync(
    payload['query']?.toString() ?? '',
    near: near,
    limit: (payload['limit'] as num?)?.toInt() ?? 10,
  );
}
