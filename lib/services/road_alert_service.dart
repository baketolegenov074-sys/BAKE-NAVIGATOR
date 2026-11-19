import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Roadside hazards retrieved from OpenStreetMap.
enum RoadAlertKind { speedCamera, roadworks }

class RoadAlert {
  const RoadAlert({
    required this.id,
    required this.kind,
    required this.location,
    required this.distanceMeters,
    this.maxSpeedKmh,
    this.direction,
    this.name,
  });

  final String id;
  final RoadAlertKind kind;
  final LatLng location;
  final double distanceMeters;
  final int? maxSpeedKmh;
  final String? direction;
  final String? name;
}

/// Loads mapped fixed speed cameras and roadworks near the current GPS fix.
///
/// OSM coverage depends on local mapping completeness. Missing objects must
/// never be interpreted as proof that no camera or roadworks are present.
class RoadAlertService {
  RoadAlertService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<RoadAlert>> fetchNearby(
    LatLng point, {
    int radiusMeters = 1500,
  }) async {
    final radius = radiusMeters.clamp(100, 5000);
    final query = '[out:json][timeout:15];('
        'node(around:$radius,${point.latitude},${point.longitude})[highway=speed_camera];'
        'way(around:$radius,${point.latitude},${point.longitude})[highway=speed_camera];'
        'node(around:$radius,${point.latitude},${point.longitude})[highway=construction];'
        'way(around:$radius,${point.latitude},${point.longitude})[highway=construction];'
        'way(around:$radius,${point.latitude},${point.longitude})[construction];'
        ' );out center;';
    const endpoints = [
      'https://overpass-api.de/api/interpreter',
      'https://overpass.kumi.systems/api/interpreter',
    ];
    http.Response? successfulResponse;
    String? lastError;

    for (var index = 0; index < endpoints.length; index++) {
      try {
        final candidate = await _client
            .post(
              Uri.parse(endpoints[index]),
              headers: const {
                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                'User-Agent': 'BAKE-Navigator/1.0 (OpenStreetMap road alerts)',
              },
              body: {'data': query},
            )
            .timeout(const Duration(seconds: 18));

        if (candidate.statusCode == 200) {
          successfulResponse = candidate;
          break;
        }

        final status = candidate.statusCode;
        if (status == 429) {
          lastError = 'Сервис ограничил частоту запросов (HTTP 429). Повторите позже.';
        } else if (status == 502 || status == 503 || status == 504) {
          lastError = 'Сервер дорожных данных временно перегружен (HTTP $status).';
        } else {
          lastError = 'Сервис дорожных данных ответил с ошибкой (HTTP $status).';
        }
      } on TimeoutException {
        lastError = 'Сервер дорожных данных не ответил вовремя.';
      } on http.ClientException {
        lastError = 'Не удалось подключиться к серверу дорожных данных.';
      } catch (exception) {
        lastError = 'Ошибка запроса дорожных данных: $exception';
      }

      // Give the primary service a moment before trying the backup endpoint.
      if (index + 1 < endpoints.length) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    final response = successfulResponse;
    if (response == null) {
      throw Exception(lastError ?? 'Сервис дорожных предупреждений временно недоступен.');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Некорректный ответ дорожных данных.');
    }
    final elements = decoded['elements'];
    if (elements is! List) return const [];

    final alerts = <RoadAlert>[];
    for (final element in elements) {
      if (element is! Map<String, dynamic>) continue;
      final tags = element['tags'];
      if (tags is! Map<String, dynamic>) continue;

      final highway = tags['highway']?.toString();
      final isCamera = highway == 'speed_camera';
      final isRoadworks = highway == 'construction' ||
          tags.containsKey('construction') ||
          tags.containsKey('construction:lanes');
      if (!isCamera && !isRoadworks) continue;

      final latValue = element['lat'] ?? (element['center'] is Map
          ? (element['center'] as Map)['lat']
          : null);
      final lonValue = element['lon'] ?? (element['center'] is Map
          ? (element['center'] as Map)['lon']
          : null);
      final lat = (latValue as num?)?.toDouble();
      final lon = (lonValue as num?)?.toDouble();
      if (lat == null || lon == null) continue;

      final distance = const Distance().as(
        LengthUnit.Meter,
        point,
        LatLng(lat, lon),
      );
      final rawLimit = tags['maxspeed']?.toString();
      final parsedLimit = rawLimit == null
          ? null
          : int.tryParse(RegExp(r'\d+').firstMatch(rawLimit)?.group(0) ?? '');
      final id = '${element['type'] ?? 'object'}/${element['id'] ?? ''}';

      alerts.add(RoadAlert(
        id: id,
        kind: isCamera ? RoadAlertKind.speedCamera : RoadAlertKind.roadworks,
        location: LatLng(lat, lon),
        distanceMeters: distance,
        maxSpeedKmh: parsedLimit,
        direction: tags['direction']?.toString(),
        name: (tags['name'] ?? tags['description'])?.toString(),
      ));
    }

    alerts.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
    return alerts;
  }

  void dispose() => _client.close();
}
