import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Only fixed speed-enforcement cameras are returned by this service.
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

/// Loads mapped fixed speed cameras from both legacy camera tags and the
/// structured OSM enforcement relation schema. OSM coverage is not complete.
class RoadAlertService {
  RoadAlertService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Loads the Kazakhstan camera dataset packaged inside the APK.
  /// No GPS, internet access, or active route is required.
  Future<List<RoadAlert>> loadBundledCameras() async {
    final csv = await rootBundle.loadString('assets/data/kazakhstan_speed_cameras.csv');
    final rows = _parseCsv(csv);
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

  /// Loads the first Shymkent camera layer. Rows without verified GPS coordinates
  /// remain documented in the CSV but are intentionally not placed on the map.
  /// Approximate landmark coordinates are visibly marked and never trigger alerts.
  Future<List<RoadAlert>> loadBundledShymkentCameraCandidates() async {
    final csv = await rootBundle.loadString('assets/data/shymkent_camera_candidates.csv');
    final rows = _parseCsv(csv);
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
