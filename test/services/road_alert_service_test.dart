import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bake_navigator/services/road_alert_service.dart';
import 'package:latlong2/latlong.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Shymkent camera assets', () {
    final service = RoadAlertService();

    test('loads the OSM camera JSON with valid Shymkent coordinates', () async {
      final cameras = await service.loadShymkentOsmCameras();

      expect(cameras, hasLength(28));
      expect(cameras.every((camera) =>
          camera.location.latitude >= 42.0 &&
          camera.location.latitude <= 42.7 &&
          camera.location.longitude >= 69.2 &&
          camera.location.longitude <= 70.0), isTrue);
      expect(cameras.where((camera) =>
          camera.kind == RoadAlertKind.speedCamera), hasLength(22));
      expect(cameras.where((camera) =>
          camera.kind == RoadAlertKind.surveillanceCamera), hasLength(6));
    });

    test('does not treat ordinary surveillance cameras as speed alerts', () async {
      final cameras = await service.loadShymkentOsmCameras();
      final surveillance = cameras.where(
        (camera) => camera.kind == RoadAlertKind.surveillanceCamera,
      );

      expect(surveillance, isNotEmpty);
      expect(surveillance.every((camera) => camera.isApproximate), isTrue);
      expect(surveillance.every((camera) => camera.maxSpeedKmh == null), isTrue);
    });

    test('does not put approximate CSV address references on the map', () async {
      final cameras = await service.loadBundledShymkentCameraCandidates();

      expect(cameras, isEmpty);
    });

    test('keeps address-only camera records in the directory', () async {
      final entries = await service.loadShymkentCameraDirectory();

      expect(entries, hasLength(30));
      expect(entries.any((entry) =>
          entry['precision'] == 'address_only' &&
          (entry['latitude'] ?? '').isEmpty &&
          (entry['longitude'] ?? '').isEmpty), isTrue);
    });
  });

  group('Nearby OSM camera response', () {
    test('parses speed-camera nodes and sorts them by distance', () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        return http.Response(jsonEncode({
          'elements': [
            {
              'type': 'node',
              'id': 2,
              'lat': 42.3000,
              'lon': 69.6000,
              'tags': {'highway': 'speed_camera', 'maxspeed': '60'},
            },
            {
              'type': 'node',
              'id': 1,
              'lat': 42.3001,
              'lon': 69.6000,
              'tags': {'highway': 'speed_camera'},
            },
          ],
        }), 200);
      });
      final service = RoadAlertService(client: client);

      final cameras = await service.fetchNearby(
        const LatLng(42.3000, 69.6000),
      );

      expect(cameras, hasLength(2));
      expect(cameras.first.id, 'node/2');
      expect(cameras.first.maxSpeedKmh, 60);
      expect(cameras.every((camera) =>
          camera.kind == RoadAlertKind.speedCamera), isTrue);
      client.close();
    });

    test('ignores non-camera OSM objects', () async {
      final client = MockClient((request) async => http.Response(
        jsonEncode({
          'elements': [
            {
              'type': 'node',
              'id': 9,
              'lat': 42.3000,
              'lon': 69.6000,
              'tags': {'amenity': 'parking'},
            },
          ],
        }),
        200,
      ));
      final service = RoadAlertService(client: client);

      final cameras = await service.fetchNearby(
        const LatLng(42.3000, 69.6000),
      );

      expect(cameras, isEmpty);
      client.close();
    });
  });
}
