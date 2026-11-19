import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Only fixed speed-enforcement cameras are returned by this service.
enum RoadAlertKind { speedCamera }

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
}

/// Loads mapped fixed speed cameras from both legacy camera tags and the
/// structured OSM enforcement relation schema. OSM coverage is not complete.
class RoadAlertService {
  RoadAlertService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

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
