import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

List<List<String>> _parseCsvInBackground(String input) => RoadAlertService._parseCsv(input);
dynamic _decodeJsonInBackground(String input) => jsonDecode(input);

/// Loads fixed speed cameras plus the separately typed Shymkent camera layer.
enum RoadAlertKind { speedCamera, trafficSignalCamera, surveillanceCamera, sergekCamera, unknownCamera }

class RoadAlert {
  const RoadAlert({
    required this.id,
    required this.kind,
    required this.location,
    required this.distanceMeters,
    this.maxSpeedKmh,
    this.direction,
    this.name,
    this.bearingDegrees,
    this.isApproximate = false,
    this.source,
    this.verificationStatus,
  });

  final String id;
  final RoadAlertKind kind;
  final LatLng location;
  final double distanceMeters;
  final int? maxSpeedKmh;
  final String? direction;
  final String? name;

  /// Direction of travel enforced by an OSM enforcement relation, if known.
  final double? bearingDegrees;
  /// True when the coordinate is only a nearby address/intersection reference.
  /// Approximate points are map-only and must never trigger spoken warnings.
  final bool isApproximate;
  final String? source;
  final String? verificationStatus;
}


enum RoadFeatureKind { pedestrianCrossing, school }

class RoadFeature {
  const RoadFeature({
    required this.id,
    required this.kind,
    required this.location,
    this.name,
    this.isApproximate = false,
  });

  final String id;
  final RoadFeatureKind kind;
  final LatLng location;
  final String? name;
  final bool isApproximate;
}

/// Loads mapped fixed speed cameras from both legacy camera tags and the
/// structured OSM enforcement relation schema. OSM coverage is not complete.
class RoadAlertService {
  RoadAlertService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Loads the Kazakhstan camera dataset packaged inside the APK.
  /// No GPS, internet access, or active route is required.
  Future<List<RoadAlert>> loadBundledCameras() async {
    final csv = await rootBundle.loadString('assets/data/kazakhstan_speed_cameras.csv');
    final rows = await compute(_parseCsvInBackground, csv);
    if (rows.length < 2) throw const FormatException('Offline camera database is empty.');
    final headers = rows.first.map((v) => v.trim().toLowerCase()).toList();
    final idCol = headers.indexOf('id');
    final latCol = headers.indexOf('latitude');
    final lonCol = headers.indexOf('longitude');
    final nameCol = headers.indexOf('name');
    final typeCol = headers.indexOf('type');
    final speedCol = headers.indexOf('maxspeed');
    if (idCol < 0 || latCol < 0 || lonCol < 0) {
      throw const FormatException('Unknown offline camera database format.');
    }
    final cameras = <RoadAlert>[];
    for (final row in rows.skip(1)) {
      final requiredIndex = [idCol, latCol, lonCol].reduce((a, b) => a > b ? a : b);
      if (row.length <= requiredIndex) continue;
      final id = row[idCol].trim();
      final lat = double.tryParse(row[latCol].trim());
      final lon = double.tryParse(row[lonCol].trim());
      if (id.isEmpty || lat == null || lon == null) continue;
      if (lat < 40 || lat > 56 || lon < 46 || lon > 88) continue;
      final speed = speedCol >= 0 && speedCol < row.length
          ? int.tryParse(RegExp(r'\d+').firstMatch(row[speedCol])?.group(0) ?? '')
          : null;
      final name = nameCol >= 0 && nameCol < row.length ? row[nameCol].trim() : '';
      final type = typeCol >= 0 && typeCol < row.length ? row[typeCol].trim() : '';
      cameras.add(RoadAlert(
        id: 'osm/$id',
        kind: RoadAlertKind.speedCamera,
        location: LatLng(lat, lon),
        distanceMeters: 0,
        maxSpeedKmh: speed,
        name: [name, type].where((v) => v.isNotEmpty).join(' · '),
      ));
    }
    if (cameras.isEmpty) throw const FormatException('No Kazakhstan camera coordinates found.');
    return cameras;
  }

  /// Loads Shymkent camera records exported from OpenStreetMap.
  /// Node coordinates are retained as mapped camera positions. Way/relation
  /// centers are map-only approximations and never trigger spoken alerts.
  /// Ordinary surveillance objects are also map-only unless tagged as speed cameras.
  Future<List<RoadAlert>> loadShymkentOsmCameras() async {
    final raw = await rootBundle.loadString('assets/data/shymkent_cameras.json');
    final decoded = await compute(_decodeJsonInBackground, raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Некорректный JSON камер Шымкента.');
    }
    final elements = decoded['cameras'];
    if (elements is! List) {
      throw const FormatException('В JSON отсутствует список cameras.');
    }

    final result = <RoadAlert>[];
    for (final item in elements) {
      if (item is! Map) continue;
      final lat = (item['latitude'] as num?)?.toDouble();
      final lon = (item['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) continue;
      if (lat < 42.0 || lat > 42.7 || lon < 69.2 || lon > 70.0) continue;

      final tags = item['tags'] is Map
          ? Map<String, dynamic>.from(item['tags'] as Map)
          : <String, dynamic>{};
      final highway = (item['highway'] ?? tags['highway'])?.toString();
      final manMade = (item['man_made'] ?? tags['man_made'])?.toString();
      final osmType = item['osm_type']?.toString() ?? 'node';
      final isSpeedCamera = highway == 'speed_camera';
      final isSurveillance = manMade == 'surveillance';
      if (!isSpeedCamera && !isSurveillance) continue;

      final rawSpeed = item['maxspeed']?.toString() ?? tags['maxspeed']?.toString();
      final speed = rawSpeed == null
          ? null
          : int.tryParse(RegExp(r'\d+').firstMatch(rawSpeed)?.group(0) ?? '');
      final name = item['name']?.toString() ??
          tags['name']?.toString() ??
          (isSpeedCamera ? 'Камера контроля скорости' : 'Камера наблюдения');
      final isExactNode = osmType == 'node';
      final id = item['osm_id']?.toString() ?? 'unknown';

      result.add(RoadAlert(
        id: 'shymkent/osm/$osmType/$id',
        kind: isSpeedCamera
            ? RoadAlertKind.speedCamera
            : RoadAlertKind.surveillanceCamera,
        location: LatLng(lat, lon),
        distanceMeters: 0,
        maxSpeedKmh: isSpeedCamera ? speed : null,
        direction: item['direction']?.toString() ?? tags['direction']?.toString(),
        name: name,
        isApproximate: !isExactNode || !isSpeedCamera,
        source: 'OpenStreetMap',
        verificationStatus: isExactNode
            ? 'osm_node_not_field_verified'
            : 'osm_center_approximate',
      ));
    }
    return result;
  }

  /// Returns every Shymkent source record, including address-only entries.
  /// Address-only records are for the directory and must not be mapped as GPS points.
  Future<List<Map<String, String>>> loadShymkentCameraDirectory() async {
    final csv = await rootBundle.loadString('assets/data/shymkent_camera_candidates.csv');
    final rows = await compute(_parseCsvInBackground, csv);
    if (rows.length < 2) {
      throw const FormatException('Shymkent camera candidate database is empty.');
    }
    final headers = rows.first.map((value) => value.trim().toLowerCase()).toList();
    return rows.skip(1).where((row) => row.any((value) => value.trim().isNotEmpty)).map((row) {
      return Map<String, String>.fromIterables(
        headers,
        List<String>.generate(
          headers.length,
          (index) => index < row.length ? row[index].trim() : '',
        ),
      );
    }).toList();
  }

  /// Loads the first Shymkent camera layer. Rows without verified GPS coordinates
  /// remain documented in the CSV but are intentionally not placed on the map.
  /// Approximate landmark coordinates are visibly marked and never trigger alerts.
  Future<List<RoadAlert>> loadBundledShymkentCameraCandidates() async {
    final csv = await rootBundle.loadString('assets/data/shymkent_camera_candidates.csv');
    final rows = await compute(_parseCsvInBackground, csv);
    if (rows.length < 2) {
      throw const FormatException('Shymkent camera candidate database is empty.');
    }
    final headers = rows.first.map((v) => v.trim().toLowerCase()).toList();
    int col(String name) => headers.indexOf(name);
    final idCol = col('id');
    final nameCol = col('name');
    final latCol = col('latitude');
    final lonCol = col('longitude');
    final categoryCol = col('category');
    final precisionCol = col('precision');
    final sourceCol = col('source');
    final notesCol = col('notes');
    if ([idCol, nameCol, latCol, lonCol, categoryCol, precisionCol]
        .any((index) => index < 0)) {
      throw const FormatException('Unknown Shymkent camera database format.');
    }
    final result = <RoadAlert>[];
    for (final row in rows.skip(1)) {
      final maxIndex = [idCol, nameCol, latCol, lonCol, categoryCol, precisionCol]
          .reduce((a, b) => a > b ? a : b);
      if (row.length <= maxIndex) continue;
      final id = row[idCol].trim();
      final lat = double.tryParse(row[latCol].trim());
      final lon = double.tryParse(row[lonCol].trim());
      // Address-only records are retained in the source file until their
      // physical camera positions can be confirmed.
      if (id.isEmpty || lat == null || lon == null) continue;
      if (lat < 42.0 || lat > 42.7 || lon < 69.2 || lon > 70.0) continue;
      final category = row[categoryCol].trim().toLowerCase();
      final precision = row[precisionCol].trim().toLowerCase();
      // Approximate address/intersection references are not camera coordinates.
      // Keep them in the directory CSV, but never draw them as map markers.
      if (precision != 'exact') continue;
      final kind = switch (category) {
        'speed' => RoadAlertKind.speedCamera,
        'traffic_signal' => RoadAlertKind.trafficSignalCamera,
        'surveillance' => RoadAlertKind.surveillanceCamera,
        'sergek' => RoadAlertKind.sergekCamera,
        _ => RoadAlertKind.unknownCamera,
      };
      final name = row[nameCol].trim();
      final source = sourceCol >= 0 && sourceCol < row.length
          ? row[sourceCol].trim()
          : null;
      final notes = notesCol >= 0 && notesCol < row.length
          ? row[notesCol].trim()
          : '';
      result.add(RoadAlert(
        id: 'shymkent/$id',
        kind: kind,
        location: LatLng(lat, lon),
        distanceMeters: 0,
        name: name.isEmpty ? notes : name,
        isApproximate: precision != 'exact',
        source: source,
        verificationStatus: precision,
      ));
    }
    return result;
  }


  /// Loads nearby mapped schools and pedestrian crossings from OpenStreetMap.
  /// School polygons use their geometric center; crossings are exact mapped nodes.
  Future<List<RoadFeature>> fetchNearbyFeatures(
    LatLng point, {
    int radiusMeters = 1800,
  }) async {
    final radius = radiusMeters.clamp(300, 5000);
    final lat = point.latitude;
    final lon = point.longitude;
    final query = '[out:json][timeout:20];('
        'node(around:$radius,$lat,$lon)[highway=crossing];'
        'node(around:$radius,$lat,$lon)[crossing];'
        'node(around:$radius,$lat,$lon)[amenity=school];'
        'way(around:$radius,$lat,$lon)[amenity=school];'
        ');out center tags;';
    const endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
    ];
    http.Response? response;
    for (final endpoint in endpoints) {
      try {
        final candidate = await _client.post(
          Uri.parse(endpoint),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent': 'BAKE-Navigator/1.0 (Shymkent road safety alerts)',
          },
          body: {'data': query},
        ).timeout(const Duration(seconds: 23));
        if (candidate.statusCode == 200) {
          response = candidate;
          break;
        }
      } catch (_) {
        // Try the next public Overpass endpoint.
      }
    }
    if (response == null) {
      throw Exception('Сервис объектов OpenStreetMap временно недоступен.');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic> || decoded['elements'] is! List) {
      throw const FormatException('Некорректный ответ объектов OpenStreetMap.');
    }
    final result = <String, RoadFeature>{};
    for (final raw in decoded['elements'] as List) {
      if (raw is! Map) continue;
      final tags = _tags(raw['tags']);
      final kind = tags['amenity'] == 'school'
          ? RoadFeatureKind.school
          : (tags['highway'] == 'crossing' || tags.containsKey('crossing'))
              ? RoadFeatureKind.pedestrianCrossing
              : null;
      if (kind == null) continue;
      final location = _elementLocation(raw);
      if (location == null) continue;
      final type = raw['type']?.toString() ?? 'node';
      final id = raw['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final distance = const Distance().as(
        LengthUnit.Meter, point, location,
      );
      if (distance > radius) continue;
      final name = (tags['name'] ?? tags['ref'])?.toString();
      result['osm/$type/$id'] = RoadFeature(
        id: 'osm/$type/$id',
        kind: kind,
        location: location,
        name: name,
        isApproximate: type != 'node',
      );
    }
    return result.values.toList();
  }

  static List<List<String>> _parseCsv(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var quoted = false;
    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (ch == '"') {
        if (quoted && i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (ch == ',' && !quoted) {
        row.add(field.toString());
        field.clear();
      } else if ((ch == '\n' || ch == '\r') && !quoted) {
        if (ch == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        if (row.any((v) => v.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(ch);
      }
    }
    if (field.isNotEmpty || row.isNotEmpty) {
      row.add(field.toString());
      if (row.any((v) => v.isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  Future<List<RoadAlert>> fetchNearby(
    LatLng point, {
    int radiusMeters = 1500,
  }) async {
    final radius = radiusMeters.clamp(100, 5000);
    final lat = point.latitude;
    final lon = point.longitude;
    final query = '[out:json][timeout:25];('
        'node(around:$radius,$lat,$lon)[highway=speed_camera];'
        'way(around:$radius,$lat,$lon)[highway=speed_camera];'
        'relation(around:$radius,$lat,$lon)[type=enforcement][enforcement~"^(maxspeed|average_speed)\$"];'
        ');out geom;';
    const endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
    ];
    http.Response? response;
    String? lastError;

    for (var i = 0; i < endpoints.length; i++) {
      try {
        final candidate = await _client.post(
          Uri.parse(endpoints[i]),
          headers: const {
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'User-Agent': 'BAKE-Navigator/1.0 (OpenStreetMap speed camera alerts)',
          },
          body: {'data': query},
        ).timeout(const Duration(seconds: 28));
        if (candidate.statusCode == 200) {
          response = candidate;
          break;
        }
        lastError = candidate.statusCode == 429
            ? 'Сервис OpenStreetMap ограничил частоту запросов (HTTP 429).'
            : 'Сервис OpenStreetMap ответил с ошибкой (HTTP ${candidate.statusCode}).';
      } on TimeoutException {
        lastError = 'Сервер OpenStreetMap не ответил вовремя.';
      } on http.ClientException {
        lastError = 'Не удалось подключиться к серверу OpenStreetMap.';
      } catch (e) {
        lastError = 'Ошибка запроса камер: $e';
      }
      if (i + 1 < endpoints.length) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    if (response == null) {
      throw Exception(lastError ?? 'Сервис камер временно недоступен.');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Некорректный ответ OpenStreetMap.');
    }
    final rawElements = decoded['elements'];
    if (rawElements is! List) return const [];

    final elements = <String, Map<String, dynamic>>{};
    for (final raw in rawElements) {
      if (raw is Map<String, dynamic>) {
        final key = '${raw['type']}/${raw['id']}';
        elements[key] = raw;
      }
    }

    final alertsById = <String, RoadAlert>{};
    for (final element in elements.values) {
      final tags = _tags(element['tags']);
      final type = element['type']?.toString();
      final id = '${type ?? 'object'}/${element['id'] ?? ''}';

      if (type == 'node' && tags['highway'] == 'speed_camera') {
        final location = _nodeLocation(element);
        if (location != null) {
          _addAlert(alertsById, id, tags, location, point);
        }
      } else if (type == 'way' && tags['highway'] == 'speed_camera') {
        final location = _elementLocation(element);
        if (location != null) {
          _addAlert(alertsById, id, tags, location, point);
        }
      } else if (type == 'relation' &&
          tags['type'] == 'enforcement' &&
          (tags['enforcement'] == 'maxspeed' ||
              tags['enforcement'] == 'average_speed')) {
        final members = element['members'];
        if (members is! List) continue;
        LatLng? device;
        LatLng? from;
        LatLng? to;
        for (final rawMember in members) {
          if (rawMember is! Map) continue;
          final role = rawMember['role']?.toString();
          final memberLocation = _elementLocation(rawMember);
          if (role == 'device') device ??= memberLocation;
          if (role == 'from') from ??= memberLocation;
          if (role == 'to') to ??= memberLocation;
        }
        final location = device;
        if (location == null) continue;
        final bearing = from != null && to != null
            ? _bearing(from, to)
            : null;
        _addAlert(
          alertsById,
          id,
          tags,
          location,
          point,
          bearingDegrees: bearing,
        );
      }
    }

    final alerts = alertsById.values.toList()
      ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return alerts;
  }

  static Map<String, dynamic> _tags(dynamic value) =>
      value is Map<String, dynamic> ? value : <String, dynamic>{};

  static LatLng? _nodeLocation(Map element) {
    final lat = (element['lat'] as num?)?.toDouble();
    final lon = (element['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return LatLng(lat, lon);
  }

  static LatLng? _elementLocation(Map element) {
    final direct = _nodeLocation(element);
    if (direct != null) return direct;
    final center = element['center'];
    if (center is Map) {
      final lat = (center['lat'] as num?)?.toDouble();
      final lon = (center['lon'] as num?)?.toDouble();
      if (lat != null && lon != null) return LatLng(lat, lon);
    }
    final geometry = element['geometry'];
    if (geometry is List && geometry.isNotEmpty) {
      final points = <LatLng>[];
      for (final item in geometry) {
        if (item is! Map) continue;
        final lat = (item['lat'] as num?)?.toDouble();
        final lon = (item['lon'] as num?)?.toDouble();
        if (lat != null && lon != null) points.add(LatLng(lat, lon));
      }
      if (points.isNotEmpty) {
        final avgLat = points.map((p) => p.latitude).reduce((a, b) => a + b) / points.length;
        final avgLon = points.map((p) => p.longitude).reduce((a, b) => a + b) / points.length;
        return LatLng(avgLat, avgLon);
      }
    }
    return null;
  }

  static double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _addAlert(
    Map<String, RoadAlert> output,
    String id,
    Map<String, dynamic> tags,
    LatLng location,
    LatLng origin, {
    double? bearingDegrees,
  }) {
    final distance = const Distance().as(LengthUnit.Meter, origin, location);
    final rawLimit = tags['maxspeed']?.toString();
    final parsedLimit = rawLimit == null
        ? null
        : int.tryParse(RegExp(r'\d+').firstMatch(rawLimit)?.group(0) ?? '');
    output[id] = RoadAlert(
      id: id,
      kind: RoadAlertKind.speedCamera,
      location: location,
      distanceMeters: distance,
      maxSpeedKmh: parsedLimit,
      direction: tags['direction']?.toString(),
      name: (tags['name'] ?? tags['description'])?.toString(),
      bearingDegrees: bearingDegrees,
    );
  }

  void dispose() => _client.close();
}
