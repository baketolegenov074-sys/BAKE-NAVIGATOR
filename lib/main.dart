import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
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
  double? _gpsHeadingDegrees;
  int _offRouteSamples = 0;
  DateTime? _lastAutomaticReroute;
  String _message = 'Нажмите «Моё местоположение» или удерживайте точку на карте';

  @override
  void initState() {
    super.initState();
    _configureVoice();
    _loadSavedOfflineMap();
    // Ask for location after the first frame so the permission dialog has a valid context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_locateMe());
    });
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
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 20),
        ),
      );

      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _currentLocation = point;
        _gpsAccuracyMeters = position.accuracy;
        if (position.speed >= 0.8 && position.heading.isFinite) {
          _gpsHeadingDegrees = position.heading;
        }
        _message = 'GPS определён. Положение будет обновляться в реальном времени.';
      });
      _mapController.move(point, 15);
      await _startLiveLocationUpdates();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }


  Future<void> _startLiveLocationUpdates({bool backgroundNavigation = false}) async {
    await _positionSubscription?.cancel();
    if (!mounted) return;

    final LocationSettings locationSettings;
    if (backgroundNavigation && defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 3),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'BAKE Navigator — навигация активна',
          notificationText: 'GPS и голосовые подсказки продолжают работать в фоне.',
          notificationChannelName: 'Фоновая навигация',
          setOngoing: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      );
    }

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        if (!mounted) return;
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _gpsAccuracyMeters = position.accuracy;
          // Ignore unstable compass headings while stopped or moving very slowly.
          if (position.speed >= 0.8 && position.heading.isFinite) {
            _gpsHeadingDegrees = position.heading;
          }
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


  double _distanceKm(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude, a.longitude, b.latitude, b.longitude,
    ) / 1000;
  }

  Future<void> _searchAddress() async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;
    setState(() {
      _isSearching = true;
      _message = 'Ищем рядом с вами…';
    });
    try {
      // Prefer the live GPS position; use Shymkent only before GPS is available.
      final anchor = _currentLocation ?? _shymkent;
      final west = (anchor.longitude - 0.45).toStringAsFixed(6);
      final north = (anchor.latitude + 0.45).toStringAsFixed(6);
      final east = (anchor.longitude + 0.45).toStringAsFixed(6);
      final south = (anchor.latitude - 0.45).toStringAsFixed(6);

      Future<List<dynamic>> requestSearch({required bool bounded}) async {
        final params = <String, String>{
          'q': query,
          'format': 'jsonv2',
          'limit': '12',
          'countrycodes': 'kz',
          'accept-language': 'ru,kk',
          'addressdetails': '1',
          'viewbox': '$west,$north,$east,$south',
          if (bounded) 'bounded': '1',
        };
        final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
        final response = await http.get(
          uri,
          headers: const {
            'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)',
          },
        ).timeout(const Duration(seconds: 20));
        if (response.statusCode == 429) {
          throw Exception('Сервис поиска просит подождать. Повторите через минуту.');
        }
        if (response.statusCode != 200) {
          throw Exception('Поиск адресов временно недоступен.');
        }
        return jsonDecode(response.body) as List<dynamic>;
      }

      // First search strictly around the driver to prevent distant-city matches.
      var results = await requestSearch(bounded: true);
      // If the local box has no match, broaden to Kazakhstan but keep nearest first.
      if (results.isEmpty) results = await requestSearch(bounded: false);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _message = 'В Казахстане такой объект не найден. Проверьте название или выберите точку на карте.');
        return;
      }

      final valid = results.whereType<Map<String, dynamic>>().where((item) {
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        return lat != null && lon != null &&
            lat >= 40.0 && lat <= 56.0 && lon >= 46.0 && lon <= 88.0;
      }).toList();

      valid.sort((a, b) {
        final aPoint = LatLng(
          double.parse(a['lat'].toString()),
          double.parse(a['lon'].toString()),
        );
        final bPoint = LatLng(
          double.parse(b['lat'].toString()),
          double.parse(b['lon'].toString()),
        );
        return _distanceKm(anchor, aPoint).compareTo(_distanceKm(anchor, bPoint));
      });

      if (valid.isEmpty) {
        setState(() => _message = 'Поиск вернул некорректные координаты. Попробуйте другое название.');
        return;
      }

      final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ближайшие результаты'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: valid.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = valid[index];
                final point = LatLng(
                  double.parse(item['lat'].toString()),
                  double.parse(item['lon'].toString()),
                );
                final distance = _distanceKm(anchor, point);
                final distanceLabel = distance < 1
                    ? '${(distance * 1000).round()} м от вас'
                    : '${distance.toStringAsFixed(1)} км от вас';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined, color: Color(0xFF2468A0)),
                  title: Text(
                    item['name']?.toString().isNotEmpty == true
                        ? item['name'].toString()
                        : (item['display_name']?.toString() ?? 'Адрес'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${item['display_name'] ?? ''}\n$distanceLabel',
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
      if (lat == null || lon == null || lat < 40 || lat > 56 || lon < 46 || lon > 88) {
        setState(() => _message = 'Координаты результата не относятся к Казахстану.');
        return;
      }
      final point = LatLng(lat, lon);
      _selectDestination(point);
      _mapController.move(point, 16);
      setState(() => _message = 'Точка выбрана. Проверьте её на карте и постройте маршрут.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _selectDestination(LatLng point) {
    final wasNavigating = _navigationActive;
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
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
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
      _message = 'Включаем фоновый GPS и голосовые подсказки…';
    });
    try {
      await _startLiveLocationUpdates(backgroundNavigation: true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _navigationActive = false;
        _message = 'Не удалось включить фоновый GPS: $error';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _message = 'Навигация началась. GPS продолжит работать при свёрнутом приложении.';
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
        unawaited(_startLiveLocationUpdates());
        return;
      }
      setState(() => _instructionIndex++);
      _speakCurrentInstruction();
    }
  }

  Future<void> _stopNavigation() async {
    setState(() {
      _navigationActive = false;
      _message = 'Навигация остановлена.';
    });
    await _tts.stop();
    await _startLiveLocationUpdates();
  }


  double _distanceToRouteMeters(LatLng position) {
    if (_routePoints.length < 2) return double.infinity;
    const latScale = 110540.0;
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
    final wasNavigating = _navigationActive;
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
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
  }

  String _gpsQualityLabel(double accuracyMeters) {
    if (accuracyMeters <= 10) return 'отличный сигнал';
    if (accuracyMeters <= 20) return 'хороший сигнал';
    if (accuracyMeters <= 50) return 'слабый сигнал';
    return 'неточный сигнал';
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
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final markers = <Marker>[
      if (_currentLocation != null)
        Marker(
          point: _currentLocation!,
          width: 44,
          height: 44,
          child: Transform.rotate(
            angle: (_gpsHeadingDegrees ?? 0) * math.pi / 180,
            child: const Icon(Icons.navigation, color: Color(0xFF1769AA), size: 36),
          ),
        ),
      if (_destination != null)
        Marker(
          point: _destination!,
          width: 48,
          height: 48,
          child: const Icon(Icons.location_pin, color: Colors.red, size: 42),
        ),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF3F6FA),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _shymkent,
              initialZoom: 13,
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
                      strokeWidth: 7,
                      color: const Color(0xFF2378C8),
                    ),
                  ],
                ),
              MarkerLayer(markers: markers),
              const RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
              ),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 12, offset: Offset(0, 3))],
                          ),
                          child: const Text(
                            'BAKE NAVIGATOR',
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, letterSpacing: 0.2),
                          ),
                        ),
                        const Spacer(),
                        _MapActionButton(
                          icon: Icons.settings_outlined,
                          tooltip: 'Настройки',
                          onPressed: _openSettings,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Material(
                      color: Colors.white,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
                        child: Row(
                          children: [
                            const Icon(Icons.search, color: Color(0xFF2468A0), size: 25),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                textInputAction: TextInputAction.search,
                                onSubmitted: (_) => _searchAddress(),
                                decoration: const InputDecoration(
                                  hintText: 'Куда едем? Адрес или место',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            IconButton.filled(
                              tooltip: 'Найти',
                              onPressed: _isSearching ? null : _searchAddress,
                              icon: _isSearching
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.arrow_forward),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 142,
            right: 14,
            child: _MapActionButton(
              icon: Icons.my_location,
              tooltip: 'Моё местоположение',
              onPressed: _isLocating ? null : _locateMe,
              loading: _isLocating,
            ),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            left: 12,
            right: 12,
            bottom: keyboardInset > 0 ? keyboardInset + 8 : 12,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                elevation: 8,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: _navigationActive ? const Color(0xFF1E9B63) : const Color(0xFF2468A0),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _navigationActive ? 'НАВИГАЦИЯ АКТИВНА' : (_destination == null ? 'ГОТОВ К ПОИСКУ МАРШРУТА' : 'ТОЧКА НАЗНАЧЕНИЯ ВЫБРАНА'),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.7, color: Color(0xFF526273)),
                            ),
                          ),
                          if (_destination != null)
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Очистить маршрут',
                              onPressed: _clearDestination,
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                      Text(
                        _routeSummary(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF17212B)),
                      ),
                      if (_gpsAccuracyMeters != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          'GPS ±${_gpsAccuracyMeters!.round()} м · ${_gpsQualityLabel(_gpsAccuracyMeters!)}',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF687786)),
                        ),
                      ],
                      if (_message.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          _message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF526273)),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _isBuildingRoute ? null : _buildRoute,
                              icon: _isBuildingRoute
                                  ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.alt_route),
                              label: Text(_isBuildingRoute ? 'Строим…' : 'Маршрут'),
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                            ),
                          ),
                          if (_instructions.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: _navigationActive ? _stopNavigation : _startNavigation,
                                icon: Icon(_navigationActive ? Icons.stop : Icons.navigation),
                                label: Text(_navigationActive ? 'Стоп' : 'Поехали'),
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 46), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                              ),
                            ),
                          ],
                        ],
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

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.loading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 5,
      borderRadius: BorderRadius.circular(16),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: loading
            ? const SizedBox(width: 19, height: 19, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icon, color: const Color(0xFF2468A0)),
      ),
    );
  }
}

class NavigatorSettingsScreen extends StatefulWidget {
  const NavigatorSettingsScreen({super.key});

  @override
  State<NavigatorSettingsScreen> createState() => _NavigatorSettingsScreenState();
}

class _NavigatorSettingsScreenState extends State<NavigatorSettingsScreen> {
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleColor = TextEditingController();
  final _vehiclePlate = TextEditingController();
  bool _loading = true;
  String? _offlineMapPath;
  bool _importingOfflineMap = false;

  static const _entries = <_PermissionEntry>[
    _PermissionEntry(
      title: 'Местоположение',
      description: 'GPS для карты и маршрута. Во время навигации Android показывает постоянное уведомление о работе GPS в фоне.',
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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _vehicleMake.text = prefs.getString('vehicle_make') ?? '';
    _vehicleModel.text = prefs.getString('vehicle_model') ?? '';
    _vehicleColor.text = prefs.getString('vehicle_color') ?? '';
    _vehiclePlate.text = prefs.getString('vehicle_plate') ?? '';
    _offlineMapPath = prefs.getString('offline_map_path');
    if (mounted) setState(() => _loading = false);
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
    _vehicleMake.dispose();
    _vehicleModel.dispose();
    _vehicleColor.dispose();
    _vehiclePlate.dispose();
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки BAKE Navigator')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.security_outlined, color: Color(0xFF2468A0)),
                    title: const Text('Разрешения телефона'),
                    subtitle: const Text('Откроются системные настройки Android. Разрешения включаются только по необходимости.'),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: openAppSettings,
                  ),
                ),
                const SizedBox(height: 20),
                const Text('Автомобиль', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('Эти сведения сохраняются только на этом телефоне.'),
                const SizedBox(height: 10),
                TextField(controller: _vehicleMake, decoration: const InputDecoration(labelText: 'Марка автомобиля')),
                TextField(controller: _vehicleModel, decoration: const InputDecoration(labelText: 'Модель')),
                TextField(controller: _vehicleColor, decoration: const InputDecoration(labelText: 'Цвет')),
                TextField(controller: _vehiclePlate, decoration: const InputDecoration(labelText: 'Государственный номер')),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _saveVehicle, icon: const Icon(Icons.save_outlined), label: const Text('Сохранить')),
                const SizedBox(height: 20),
                const Text('Офлайн-карты', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
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
                          subtitle: Text(_offlineMapPath == null
                              ? 'Готовый MBTiles-файл пока не подключён.'
                              : 'Офлайн-карта подключена на этом устройстве.'),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _importingOfflineMap ? null : _importOfflineMap,
                            icon: _importingOfflineMap
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.file_open_outlined),
                            label: Text(_importingOfflineMap ? 'Импортируем…' : 'Импортировать MBTiles-карту'),
                          ),
                        ),
                        if (_offlineMapPath != null)
                          TextButton.icon(
                            onPressed: _removeOfflineMap,
                            icon: const Icon(Icons.cloud_outlined),
                            label: const Text('Отключить офлайн-карту'),
                          ),
                        const Text(
                          'Исходный OSM PBF не является готовой MBTiles-картой. Для офлайн-режима нужны отдельно подготовленные тайлы.',
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

