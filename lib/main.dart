import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BakeNavigatorApp());
}

class BakeNavigatorApp extends StatelessWidget {
  const BakeNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BAKE Navigator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1769AA),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const NavigatorScreen(),
    );
  }
}

class NavigatorScreen extends StatefulWidget {
  const NavigatorScreen({super.key});

  @override
  State<NavigatorScreen> createState() => _NavigatorScreenState();
}

class _NavigatorScreenState extends State<NavigatorScreen> {
  static const LatLng _shymkent = LatLng(42.3154, 69.5869);

  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();

  LatLng? _currentLocation;
  LatLng? _destination;
  List<LatLng> _routePoints = [];
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  bool _isLocating = false;
  bool _isBuildingRoute = false;
  String _message = 'Нажмите «Моё местоположение» или удерживайте точку на карте';

  @override
  void initState() {
    super.initState();
    _configureVoice();
  }

  Future<void> _configureVoice() async {
    try {
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(0.48);
      await _tts.setVolume(1.0);
    } catch (_) {
      // Voice support depends on the speech engine installed on the phone.
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _locateMe() async {
    if (_isLocating) return;

    setState(() {
      _isLocating = true;
      _message = 'Определяем GPS-положение…';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Включите геолокацию (GPS) на телефоне.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception('Разрешите приложению доступ к местоположению.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Доступ к GPS запрещён в настройках телефона.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _currentLocation = point;
        _message = 'GPS определён. Удерживайте карту, чтобы выбрать пункт назначения.';
      });
      _mapController.move(point, 15);
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _selectDestination(LatLng point) {
    setState(() {
      _destination = point;
      _routePoints = [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = 'Точка назначения выбрана. Нажмите «Построить маршрут».';
    });
  }

  Future<void> _buildRoute() async {
    if (_destination == null) {
      setState(() => _message = 'Сначала удерживайте нужное место на карте.');
      return;
    }

    if (_currentLocation == null) {
      await _locateMe();
    }
    if (_currentLocation == null || _destination == null) return;

    setState(() {
      _isBuildingRoute = true;
      _message = 'Строим маршрут…';
    });

    try {
      final start = _currentLocation!;
      final end = _destination!;
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson&steps=true',
      );

      // Public OSRM demo endpoint is for testing, not production traffic.
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('Сервис маршрутов временно недоступен.');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
        throw Exception('Маршрут не найден. Попробуйте другую точку.');
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List<dynamic>;
      final points = coordinates.map((coordinate) {
        final pair = coordinate as List<dynamic>;
        return LatLng(
          (pair[1] as num).toDouble(),
          (pair[0] as num).toDouble(),
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _routePoints = points;
        _routeDistanceMeters = (route['distance'] as num).toDouble();
        _routeDurationSeconds = (route['duration'] as num).toDouble();
        _message = 'Маршрут построен. Это предварительный расчёт для тестирования.';
      });

      if (points.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.fromLTRB(36, 100, 36, 250),
          ),
        );
      }

      final distanceKm = (_routeDistanceMeters! / 1000).toStringAsFixed(1);
      final minutes = (_routeDurationSeconds! / 60).round();
      await _tts.speak('Маршрут построен. Расстояние $distanceKm километра. '
          'Примерное время в пути $minutes минут.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBuildingRoute = false);
    }
  }

  void _clearDestination() {
    setState(() {
      _destination = null;
      _routePoints = [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = 'Маршрут очищен. Удерживайте карту, чтобы выбрать новую точку.';
    });
  }

  String _routeSummary() {
    if (_routeDistanceMeters == null || _routeDurationSeconds == null) {
      return 'Маршрут ещё не построен';
    }
    final km = (_routeDistanceMeters! / 1000).toStringAsFixed(1);
    final minutes = (_routeDurationSeconds! / 60).round();
    return '$km км · около $minutes мин';
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (_currentLocation != null)
        Marker(
          point: _currentLocation!,
          width: 44,
          height: 44,
          child: const Icon(
            Icons.my_location,
            color: Color(0xFF1769AA),
            size: 34,
          ),
        ),
      if (_destination != null)
        Marker(
          point: _destination!,
          width: 48,
          height: 48,
          child: const Icon(
            Icons.location_pin,
            color: Colors.red,
            size: 42,
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BAKE NAVIGATOR',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _shymkent,
              initialZoom: 12,
              onLongPress: (_, point) => _selectDestination(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'kz.bake.bake_navigator',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 6,
                      color: const Color(0xFF1769AA),
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            right: 12,
            child: FloatingActionButton.small(
              heroTag: 'locate',
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1769AA),
              onPressed: _isLocating ? null : _locateMe,
              child: _isLocating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.my_location),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Card(
                color: Colors.white,
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _message,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _routeSummary(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isBuildingRoute ? null : _buildRoute,
                              icon: _isBuildingRoute
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.alt_route),
                              label: const Text('Построить маршрут'),
                            ),
                          ),
                          if (_destination != null) ...[
                            const SizedBox(width: 8),
                            IconButton.filledTonal(
                              tooltip: 'Очистить маршрут',
                              onPressed: _clearDestination,
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Удерживайте нужное место на карте, чтобы выбрать пункт назначения.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
