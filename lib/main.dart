import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

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


class RouteInstruction {
  const RouteInstruction({
    required this.location,
    required this.text,
    required this.distanceMeters,
  });
  final LatLng location;
  final String text;
  final double distanceMeters;
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
  final TextEditingController _searchController = TextEditingController();
  MbTilesTileProvider? _offlineTileProvider;

  LatLng? _currentLocation;
  LatLng? _destination;
  List<LatLng> _routePoints = [];
  List<RouteInstruction> _instructions = [];
  int _instructionIndex = 0;
  bool _navigationActive = false;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  StreamSubscription<Position>? _positionSubscription;
  bool _isLocating = false;
  bool _isSearching = false;
  bool _isBuildingRoute = false;
  double? _gpsAccuracyMeters;
  int _offRouteSamples = 0;
  DateTime? _lastAutomaticReroute;
  String _message = 'Нажмите «Моё местоположение» или удерживайте точку на карте';

  @override
  void initState() {
    super.initState();
    _configureVoice();
    _loadSavedOfflineMap();
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
    _positionSubscription?.cancel();
    _offlineTileProvider?.dispose();
    _searchController.dispose();
    _tts.stop();
    super.dispose();
  }


  Future<void> _loadSavedOfflineMap() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('offline_map_path');
    if (path == null || !await File(path).exists()) return;
    try {
      final provider = MbTilesTileProvider.fromPath(path: path);
      if (!mounted) {
        provider.dispose();
        return;
      }
      setState(() => _offlineTileProvider = provider);
    } catch (_) {
      // Keep the online map available if an offline archive cannot be opened.
    }
  }

  Future<void> _openSettings() async {
    final selectedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const NavigatorSettingsScreen()),
    );
    if (!mounted || selectedPath == null) return;
    if (selectedPath == '__use_online_map__') {
      _offlineTileProvider?.dispose();
      setState(() {
        _offlineTileProvider = null;
        _message = 'Включена онлайн-карта.';
      });
      return;
    }
    try {
      final provider = MbTilesTileProvider.fromPath(path: selectedPath);
      _offlineTileProvider?.dispose();
      setState(() {
        _offlineTileProvider = provider;
        _message = 'Офлайн-карта подключена. Для построения маршрута пока нужен интернет.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Не удалось открыть офлайн-карту: $error');
    }
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
        _message = 'GPS определён. Положение будет обновляться в реальном времени.';
      });
      _mapController.move(point, 15);
      _startLiveLocationUpdates();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }


  void _startLiveLocationUpdates() {
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen(
      (position) {
        if (!mounted) return;
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _gpsAccuracyMeters = position.accuracy;
        });
        _updateNavigationProgress(_currentLocation!);
        _checkForOffRoute(position);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _message = 'Потеряна связь с GPS. Проверьте геолокацию телефона.';
        });
      },
    );
  }


  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;
    setState(() {
      _isSearching = true;
      _message = 'Ищем адрес…';
    });
    try {
      final uri = Uri.https(
        'nominatim.openstreetmap.org',
        '/search',
        {
          'q': query,
          'format': 'jsonv2',
          'limit': '6',
          'countrycodes': 'kz',
          'accept-language': 'ru',
          'addressdetails': '1',
        },
      );
      // Manual search only: respect the public Nominatim usage policy.
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'BAKE-Navigator/0.1'},
      ).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('Поиск адресов временно недоступен.');
      }
      final results = jsonDecode(response.body) as List<dynamic>;
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _message = 'Адрес не найден. Уточните название улицы или дома.');
        return;
      }
      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Найденные адреса'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = results[index] as Map<String, dynamic>;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(
                    item['display_name']?.toString() ?? 'Адрес',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(dialogContext).pop(item),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
          ],
        ),
      );
      if (selected == null || !mounted) return;
      final lat = double.tryParse(selected['lat']?.toString() ?? '');
      final lon = double.tryParse(selected['lon']?.toString() ?? '');
      if (lat == null || lon == null) {
        setState(() => _message = 'Не удалось определить координаты адреса.');
        return;
      }
      final point = LatLng(lat, lon);
      _selectDestination(point);
      _mapController.move(point, 16);
      setState(() {
        _message = 'Адрес выбран. Нажмите «Построить маршрут».';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectDestination(LatLng point) {
    setState(() {
      _destination = point;
      _routePoints = [];
      _instructions = [];
      _navigationActive = false;
      _instructionIndex = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = 'Точка назначения выбрана. Нажмите «Построить маршрут».';
    });
  }


  String _instructionText(Map<String, dynamic> step) {
    final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
    final type = maneuver['type']?.toString() ?? '';
    final modifier = maneuver['modifier']?.toString() ?? '';
    final name = (step['name']?.toString() ?? '').trim();
    final road = name.isEmpty ? '' : ' на $name';
    if (type == 'depart') return 'Начинайте движение$road';
    if (type == 'arrive') return 'Вы прибыли в пункт назначения';
    if (type == 'roundabout' || type == 'rotary') {
      return 'На круговом движении продолжайте$road';
    }
    final actions = <String, String>{
      'left': 'Поверните налево',
      'slight left': 'Плавно поверните налево',
      'sharp left': 'Резко поверните налево',
      'right': 'Поверните направо',
      'slight right': 'Плавно поверните направо',
      'sharp right': 'Резко поверните направо',
      'uturn': 'Развернитесь',
      'straight': 'Продолжайте прямо',
    };
    final action = actions[modifier] ??
        (type == 'new name' ? 'Продолжайте движение' : 'Продолжайте по маршруту');
    return '$action$road';
  }

  List<RouteInstruction> _readInstructions(Map<String, dynamic> route) {
    final result = <RouteInstruction>[];
    final legs = route['legs'] as List<dynamic>? ?? [];
    for (final legValue in legs) {
      final leg = legValue as Map<String, dynamic>;
      final steps = leg['steps'] as List<dynamic>? ?? [];
      for (final stepValue in steps) {
        final step = stepValue as Map<String, dynamic>;
        final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
        final location = maneuver['location'] as List<dynamic>?;
        if (location == null || location.length < 2) continue;
        result.add(RouteInstruction(
          location: LatLng(
            (location[1] as num).toDouble(),
            (location[0] as num).toDouble(),
          ),
          text: _instructionText(step),
          distanceMeters: (step['distance'] as num?)?.toDouble() ?? 0,
        ));
      }
    }
    return result;
  }

  Future<void> _startNavigation() async {
    if (_instructions.isEmpty || _currentLocation == null) return;
    setState(() {
      _navigationActive = true;
      _instructionIndex = _instructions.length > 1 ? 1 : 0;
      _message = 'Навигация началась. Следуйте голосовым подсказкам.';
    });
    await _speakCurrentInstruction();
  }

  Future<void> _speakCurrentInstruction() async {
    if (!_navigationActive || _instructionIndex >= _instructions.length) return;
    final instruction = _instructions[_instructionIndex];
    final meters = Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      instruction.location.latitude,
      instruction.location.longitude,
    );
    final distanceText = meters >= 1000
        ? '${(meters / 1000).toStringAsFixed(1)} километра'
        : '${meters.round()} метров';
    await _tts.speak('${instruction.text} через $distanceText.');
  }

  void _updateNavigationProgress(LatLng position) {
    if (!_navigationActive || _instructionIndex >= _instructions.length) return;
    final target = _instructions[_instructionIndex];
    final meters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      target.location.latitude,
      target.location.longitude,
    );
    if (meters <= 35) {
      if (_instructionIndex + 1 >= _instructions.length) {
        setState(() {
          _navigationActive = false;
          _message = 'Вы прибыли в пункт назначения.';
        });
        _tts.speak('Вы прибыли в пункт назначения.');
        return;
      }
      setState(() => _instructionIndex++);
      _speakCurrentInstruction();
    }
  }

  void _stopNavigation() {
    setState(() {
      _navigationActive = false;
      _message = 'Навигация остановлена.';
    });
    _tts.stop();
  }


  double _distanceToRouteMeters(LatLng position) {
    if (_routePoints.length < 2) return double.infinity;
    final latScale = 110540.0;
    final lonScale = 111320.0 * math.cos(position.latitude * math.pi / 180);
    final px = position.longitude * lonScale;
    final py = position.latitude * latScale;
    var best = double.infinity;
    for (var i = 0; i < _routePoints.length - 1; i++) {
      final a = _routePoints[i];
      final b = _routePoints[i + 1];
      final ax = a.longitude * lonScale;
      final ay = a.latitude * latScale;
      final bx = b.longitude * lonScale;
      final by = b.latitude * latScale;
      final dx = bx - ax;
      final dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared == 0
          ? 0.0
          : (((px - ax) * dx + (py - ay) * dy) / lengthSquared)
              .clamp(0.0, 1.0);
      final nearestX = ax + t * dx;
      final nearestY = ay + t * dy;
      final distance = math.sqrt(
        (px - nearestX) * (px - nearestX) +
            (py - nearestY) * (py - nearestY),
      );
      if (distance < best) best = distance;
    }
    return best;
  }

  void _checkForOffRoute(Position position) {
    if (!_navigationActive || _isBuildingRoute || _destination == null) return;
    // Ignore poor fixes; a bad GPS point must not trigger a false reroute.
    if (position.accuracy > 45 || _routePoints.length < 2) return;
    final now = DateTime.now();
    if (_lastAutomaticReroute != null &&
        now.difference(_lastAutomaticReroute!) < const Duration(seconds: 25)) {
      return;
    }
    final distance = _distanceToRouteMeters(
      LatLng(position.latitude, position.longitude),
    );
    final offRouteLimit = math.max(55.0, position.accuracy * 2.0);
    if (distance > offRouteLimit) {
      _offRouteSamples++;
    } else {
      _offRouteSamples = 0;
    }
    if (_offRouteSamples >= 3) {
      _offRouteSamples = 0;
      _lastAutomaticReroute = now;
      _buildRoute(automaticReroute: true);
    }
  }

  Future<void> _buildRoute({bool automaticReroute = false}) async {
    if (_destination == null) {
      setState(() => _message = 'Сначала удерживайте нужное место на карте.');
      return;
    }

    if (_currentLocation == null) {
      await _locateMe();
    }
    if (_currentLocation == null || _destination == null) return;

    final resumeNavigation = automaticReroute && _navigationActive;
    setState(() {
      _isBuildingRoute = true;
      _message = automaticReroute ? 'Вы отклонились от маршрута. Перестраиваем…' : 'Строим маршрут…';
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
      final instructions = _readInstructions(route);
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
        _instructions = instructions;
        _navigationActive = resumeNavigation;
        _instructionIndex = resumeNavigation && instructions.length > 1 ? 1 : 0;
        _offRouteSamples = 0;
        _routeDistanceMeters = (route['distance'] as num).toDouble();
        _routeDurationSeconds = (route['duration'] as num).toDouble();
        _message = automaticReroute
            ? 'Маршрут перестроен. Продолжаем навигацию.'
            : 'Маршрут построен. Это предварительный расчёт для тестирования.';
      });

      if (points.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: points,
            padding: const EdgeInsets.fromLTRB(36, 100, 36, 250),
          ),
        );
      }

      if (automaticReroute && resumeNavigation) {
        await _tts.speak('Вы отклонились от маршрута. Маршрут перестроен.');
        await _speakCurrentInstruction();
      } else {
        final distanceKm = (_routeDistanceMeters! / 1000).toStringAsFixed(1);
        final minutes = (_routeDurationSeconds! / 60).round();
        await _tts.speak('Маршрут построен. Расстояние $distanceKm километра. '
            'Примерное время в пути $minutes минут.');
      }
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
      _instructions = [];
      _navigationActive = false;
      _instructionIndex = 0;
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
        actions: [
          IconButton(
            tooltip: 'Настройки навигатора',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
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
              if (_offlineTileProvider == null)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'kz.bake.bake_navigator',
                )
              else
                TileLayer(tileProvider: _offlineTileProvider!),
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
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _searchAddress(),
                              decoration: const InputDecoration(
                                hintText: 'Улица, номер дома, город',
                                prefixIcon: Icon(Icons.search),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.all(Radius.circular(14)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _isSearching ? null : _searchAddress,
                            icon: _isSearching
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.search),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _message,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                      ),
                      const SizedBox(height: 8),
                      if (_gpsAccuracyMeters != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Точность GPS: ±${_gpsAccuracyMeters!.round()} м',
                          style: const TextStyle(fontSize: 11, color: Colors.black54),
                        ),
                      ],
                      Text(
                        _routeSummary(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_instructions.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          _navigationActive &&
                                  _instructionIndex < _instructions.length
                              ? _instructions[_instructionIndex].text
                              : 'Подсказок: ${_instructions.length}. Нажмите «Начать навигацию».',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1769AA),
                          ),
                        ),
                      ],
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
                              label: const Text('Маршрут'),
                            ),
                          ),
                          if (_instructions.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _navigationActive
                                    ? _stopNavigation
                                    : _startNavigation,
                                icon: Icon(_navigationActive
                                    ? Icons.stop
                                    : Icons.navigation),
                                label: Text(_navigationActive
                                    ? 'Стоп'
                                    : 'Старт'),
                              ),
                            ),
                          ],
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
                        'Можно искать улицу и номер дома. Подъезд найдётся, если его вход отмечен в OpenStreetMap; иначе выберите точку на карте.',
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


class _PermissionEntry {
  const _PermissionEntry({
    required this.title,
    required this.description,
    required this.icon,
    required this.permissions,
  });
  final String title;
  final String description;
  final IconData icon;
  final List<Permission> permissions;
}

class NavigatorSettingsScreen extends StatefulWidget {
  const NavigatorSettingsScreen({super.key});

  @override
  State<NavigatorSettingsScreen> createState() => _NavigatorSettingsScreenState();
}

class _NavigatorSettingsScreenState extends State<NavigatorSettingsScreen> with WidgetsBindingObserver {
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleColor = TextEditingController();
  final _vehiclePlate = TextEditingController();
  bool _loading = true;
  String? _offlineMapPath;
  bool _importingOfflineMap = false;
  final Map<String, List<PermissionStatus>> _statuses = {};

  static const _entries = <_PermissionEntry>[
    _PermissionEntry(
      title: 'Местоположение',
      description: 'GPS для положения на карте, маршрута и навигации.',
      icon: Icons.location_on_outlined,
      permissions: [Permission.locationWhenInUse],
    ),
    _PermissionEntry(
      title: 'Микрофон',
      description: 'Для будущего голосового управления и голосового поиска.',
      icon: Icons.mic_none,
      permissions: [Permission.microphone],
    ),
    _PermissionEntry(
      title: 'Уведомления',
      description: 'Предупреждения навигации и сообщения приложения.',
      icon: Icons.notifications_none,
      permissions: [Permission.notification],
    ),
    _PermissionEntry(
      title: 'Физическая активность',
      description: 'Определение движения и режима поездки, если функция будет включена.',
      icon: Icons.directions_walk,
      permissions: [Permission.activityRecognition],
    ),
    _PermissionEntry(
      title: 'Камера',
      description: 'Для будущего сканирования документов или фото автомобиля по запросу.',
      icon: Icons.camera_alt_outlined,
      permissions: [Permission.camera],
    ),
    _PermissionEntry(
      title: 'Контакты',
      description: 'Для выбора контакта при отправке местоположения, только по запросу.',
      icon: Icons.contacts_outlined,
      permissions: [Permission.contacts],
    ),
    _PermissionEntry(
      title: 'Телефон',
      description: 'Для сведений о состоянии телефона; доступ к журналу звонков не запрашивается.',
      icon: Icons.phone_outlined,
      permissions: [Permission.phone],
    ),
    _PermissionEntry(
      title: 'Устройства поблизости',
      description: 'Bluetooth для будущего подключения к автомобильным устройствам.',
      icon: Icons.bluetooth,
      permissions: [Permission.bluetoothScan, Permission.bluetoothConnect],
    ),
    _PermissionEntry(
      title: 'Фото и видео',
      description: 'Для выбора фото профиля или изображения автомобиля.',
      icon: Icons.photo_library_outlined,
      permissions: [Permission.photos, Permission.videos],
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshStatuses();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _vehicleMake.text = prefs.getString('vehicle_make') ?? '';
    _vehicleModel.text = prefs.getString('vehicle_model') ?? '';
    _vehicleColor.text = prefs.getString('vehicle_color') ?? '';
    _vehiclePlate.text = prefs.getString('vehicle_plate') ?? '';
    _offlineMapPath = prefs.getString('offline_map_path');
    await _refreshStatuses();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshStatuses() async {
    final next = <String, List<PermissionStatus>>{};
    for (final entry in _entries) {
      next[entry.title] = await Future.wait(
        entry.permissions.map((permission) => permission.status),
      );
    }
    if (mounted) setState(() => _statuses
      ..clear()
      ..addAll(next));
  }

  String _statusLabel(_PermissionEntry entry) {
    final values = _statuses[entry.title] ?? const <PermissionStatus>[];
    if (values.isEmpty) return 'Проверяем…';
    if (values.every((status) => status.isGranted || status.isLimited)) {
      return values.any((status) => status.isLimited) ? 'Разрешено частично' : 'Разрешено';
    }
    if (values.any((status) => status.isPermanentlyDenied)) {
      return 'Запрещено в настройках телефона';
    }
    if (values.any((status) => status.isRestricted)) return 'Ограничено системой';
    return 'Не разрешено';
  }

  Future<void> _requestEntry(_PermissionEntry entry) async {
    for (final permission in entry.permissions) {
      final status = await permission.status;
      if (status.isPermanentlyDenied || status.isRestricted) {
        await openAppSettings();
        break;
      }
      if (!status.isGranted && !status.isLimited) {
        await permission.request();
      }
    }
    await _refreshStatuses();
  }


  Future<void> _importOfflineMap() async {
    if (_importingOfflineMap) return;
    setState(() => _importingOfflineMap = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mbtiles'],
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final sourcePath = result.files.single.path;
      if (sourcePath == null) {
        throw Exception('Сначала сохраните файл карты в память телефона, затем выберите его.');
      }
      final source = File(sourcePath);
      final directory = await getApplicationSupportDirectory();
      final destination = File('${directory.path}/bake_offline_map.mbtiles');
      if (source.absolute.path != destination.absolute.path) {
        if (await destination.exists()) await destination.delete();
        await source.copy(destination.path);
      }
      final validationProvider = MbTilesTileProvider.fromPath(path: destination.path);
      validationProvider.dispose();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_map_path', destination.path);
      if (!mounted) return;
      setState(() => _offlineMapPath = destination.path);
      Navigator.of(context).pop(destination.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _importingOfflineMap = false);
    }
  }

  Future<void> _removeOfflineMap() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('offline_map_path');
    if (!mounted) return;
    setState(() => _offlineMapPath = null);
    Navigator.of(context).pop('__use_online_map__');
  }

  Future<void> _saveVehicle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vehicle_make', _vehicleMake.text.trim());
    await prefs.setString('vehicle_model', _vehicleModel.text.trim());
    await prefs.setString('vehicle_color', _vehicleColor.text.trim());
    await prefs.setString('vehicle_plate', _vehiclePlate.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Данные автомобиля сохранены на этом телефоне.')),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _vehicleColor.dispose();
    _vehiclePlate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки навигатора')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Разрешения телефона',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Каждое разрешение включается отдельно. Навигатор не получает доступ к данным без вашего согласия.',
                  style: TextStyle(color: Colors.black54),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _refreshStatuses,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Обновить статусы'),
                  ),
                ),
                const SizedBox(height: 8),
                for (final entry in _entries)
                  Card(
                    child: ListTile(
                      leading: Icon(entry.icon, color: const Color(0xFF1769AA)),
                      title: Text(entry.title),
                      subtitle: Text('${_statusLabel(entry)}\n${entry.description}'),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: 'Изменить разрешение',
                        icon: const Icon(Icons.tune),
                        onPressed: () => _requestEntry(entry),
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                const Text(
                  'Данные автомобиля',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Эти сведения сохраняются локально. Пока они не отправляются на сервер.',
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _vehicleMake,
                  decoration: const InputDecoration(labelText: 'Марка автомобиля'),
                ),
                TextField(
                  controller: _vehicleModel,
                  decoration: const InputDecoration(labelText: 'Модель'),
                ),
                TextField(
                  controller: _vehicleColor,
                  decoration: const InputDecoration(labelText: 'Цвет'),
                ),
                TextField(
                  controller: _vehiclePlate,
                  decoration: const InputDecoration(labelText: 'Государственный номер'),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _saveVehicle,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Сохранить данные автомобиля'),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Офлайн-карты',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.map_outlined),
                          title: const Text('Офлайн-карта'),
                          subtitle: Text(
                            _offlineMapPath == null
                                ? 'Карта ещё не импортирована. Выберите готовый MBTiles-файл для работы карты без интернета.'
                                : 'Офлайн-карта подключена на этом устройстве.',
                          ),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _importingOfflineMap ? null : _importOfflineMap,
                            icon: _importingOfflineMap
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.file_open_outlined),
                            label: Text(_importingOfflineMap
                                ? 'Импортируем…'
                                : 'Импортировать MBTiles-карту'),
                          ),
                        ),
                        if (_offlineMapPath != null)
                          TextButton.icon(
                            onPressed: _removeOfflineMap,
                            icon: const Icon(Icons.cloud_outlined),
                            label: const Text('Отключить офлайн-карту'),
                          ),
                        const SizedBox(height: 4),
                        const Text(
                          'Файл карты нужно заранее получить из источника, разрешающего офлайн-использование. Обычные публичные тайлы OpenStreetMap массово скачивать нельзя.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

