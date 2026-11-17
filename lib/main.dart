import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  AppLocale.language = prefs.getString('app_language') ?? 'ru';
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
          seedColor: const Color(0xFFFFCC00),
          brightness: Brightness.light,
        ).copyWith(
          primary: const Color(0xFFFFCC00),
          onPrimary: const Color(0xFF171717),
          secondary: const Color(0xFF171717),
          surface: const Color(0xFFFFFFFF),
        ),
        scaffoldBackgroundColor: const Color(0xFFFFFFFF),
      ),
      home: const NavigatorScreen(),
    );
  }
}



class AppLocale {
  static String language = 'ru';

  static const Map<String, Map<String, String>> _translations = {
    'kk': {
      'Настройки': 'Баптаулар',
      'Голосовые подсказки': 'Дауыстық нұсқаулар',
      'Предпочтения маршрута': 'Маршрут параметрлері',
      'Быстрый': 'Жылдам',
      'Избегать платных дорог': 'Ақылы жолдардан аулақ болу',
      'Единицы измерения': 'Өлшем бірліктері',
      'км, м': 'км, м',
      'Язык приложения': 'Қолданба тілі',
      'Профиль': 'Профиль',
      'О приложении': 'Қолданба туралы',
      'Автомобиль': 'Автокөлік',
      'Эти сведения сохраняются только на этом телефоне.': 'Бұл мәліметтер тек осы телефонда сақталады.',
      'Марка автомобиля': 'Көлік маркасы',
      'Модель': 'Моделі',
      'Цвет': 'Түсі',
      'Государственный номер': 'Мемлекеттік нөмірі',
      'Сохранить': 'Сақтау',
      'Параметры маршрута': 'Маршрут параметрлері',
      'Избегать грунтовых дорог': 'Топырақ жолдардан аулақ болу',
      'Офлайн-карты': 'Офлайн карталар',
      'Офлайн-карта': 'Офлайн карта',
      'Импортируем…': 'Импортталуда…',
      'Импортировать MBTiles-карту': 'MBTiles картасын импорттау',
      'Отключить офлайн-карту': 'Офлайн картаны өшіру',
      'Карта': 'Карта',
      'Поиск': 'Іздеу',
      'Маршрут': 'Маршрут',
      'Избранное': 'Таңдаулылар',
      'Завершить маршрут': 'Маршрутты аяқтау',
      'Построить маршрут': 'Маршрут құру',
      'Поехали': 'Жолға шығу',
      'Отмена': 'Болдырмау',
      'Готово': 'Дайын',
      'Закрыть': 'Жабу',
      'Понятно': 'Түсінікті',
      'Добавить место': 'Орын қосу',
      'Мои места': 'Менің орындарым',
      'Дом': 'Үй',
      'Работа': 'Жұмыс',
      'Добавьте домашний адрес': 'Үй мекенжайын қосыңыз',
      'Добавьте адрес работы': 'Жұмыс мекенжайын қосыңыз',
      'Закладки': 'Бетбелгілер',
      'Сохранённая точка': 'Сақталған нүкте',
      'Сохранить в закладки': 'Бетбелгілерге сақтау',
      'Добавить остановку на карте': 'Картаға аялдама қосу',
      'Промежуточные остановки': 'Аралық аялдамалар',
      'Время выезда': 'Жолға шығу уақыты',
      'Сейчас': 'Қазір',
      'Изменить': 'Өзгерту',
      'Сбросить': 'Қалпына келтіру',
      'Сбросить время': 'Уақытты қалпына келтіру',
      'Время отправления': 'Жөнелу уақыты',
      'Дата': 'Күні',
      'Время': 'Уақыты',
      'ОТКУДА': 'ҚАЙДАН',
      'Добавить точку маршрута': 'Маршрут нүктесін қосу',
      'Скопировать ссылку на точку': 'Нүкте сілтемесін көшіру',
      'Тип события': 'Оқиға түрі',
      'Сообщить о событии': 'Оқиға туралы хабарлау',
      'События на дороге': 'Жолдағы оқиғалар',
      'Слои и офлайн-карты': 'Қабаттар және офлайн карталар',
      'Пробки': 'Кептелістер',
      'Дорожные события': 'Жол оқиғалары',
      'Парковки': 'Тұрақ орындары',
      'Спутниковая карта': 'Спутниктік карта',
      'Карта Казахстана': 'Қазақстан картасы',
      'Шымкент и область': 'Шымкент және облыс',
      'Выбрать MBTiles-файл': 'MBTiles файлын таңдау',
      'Язык голосовых подсказок': 'Дауыстық нұсқаулар тілі',
      'Голос телефона': 'Телефон дауысы',
      'Название': 'Атауы',
      'Адрес': 'Мекенжай',
      'Найти адрес отправления': 'Бастапқы мекенжайды табу',
      'Марка автомобиля': 'Көлік маркасы',
      'Модель': 'Моделі',
      'Цвет': 'Түсі',
      'Государственный номер': 'Мемлекеттік нөмірі',
      'Пока нет сохранённых точек. Удерживайте место на карте и выберите «Сохранить в закладки».': 'Әзірге сақталған нүктелер жоқ. Картадағы орынды басып тұрып, «Бетбелгілерге сақтау» таңдаңыз.',
      'Добавьте остановку долгим нажатием на нужное место карты.': 'Картадағы қажетті орынды ұзақ басып, аялдама қосыңыз.',
      'Прослушать голос': 'Дауысты тыңдау',
      'Системный голос по умолчанию': 'Әдепкі жүйелік дауыс',
      'Громкость': 'Дыбыс деңгейі',
      'Скорость речи': 'Сөйлеу жылдамдығы',
      'Для выбранного языка голоса не найдены. Установите голосовые данные в настройках преобразования текста в речь Android.': 'Таңдалған тілге арналған дауыс табылмады. Android мәтінді сөйлеуге түрлендіру баптауларынан дауыс деректерін орнатыңыз.',
      'Изменить точки': 'Нүктелерді өзгерту',
      'Промежуточные остановки: ': 'Аралық аялдамалар: ',
      'Вариант ': 'Нұсқа ',
      'Куда едем?': 'Қайда барамыз?',
      'Найти': 'Іздеу',
      'Опишите, что не так': 'Мәселені сипаттаңыз',
      'Поддержка BAKE': 'BAKE қолдауы',
      'Разместить объект': 'Нысанды орналастыру',
      'Бронирования и история': 'Брондаулар және тарих',
      'Отзывы и исправления': 'Пікірлер және түзетулер',
      'Музыка BAKE': 'BAKE музыкасы',
      'Добавьте описание (необязательно)': 'Сипаттама қосыңыз (міндетті емес)',
      'Введите адрес': 'Мекенжайды енгізіңіз',
      'Адрес дома': 'Үй мекенжайы',
      'Адрес работы': 'Жұмыс мекенжайы',
      'Удалить место': 'Орынды жою',
      'Например, спортзал': 'Мысалы, спортзал',
      'Улица, дом или место': 'Көше, үй немесе орын',
      'Куда': 'Қайда',
      'Введите адрес или место': 'Мекенжайды немесе орынды енгізіңіз',
      'Найти место': 'Орынды табу',
      'Точка на карте: ': 'Картадағы нүкте: ',
      'Удалить остановку': 'Аялдаманы жою',
      'Завершить навигацию': 'Навигацияны аяқтау',
      'Слои карты': 'Карта қабаттары',
      'На север': 'Солтүстікке',
      'Моё местоположение': 'Менің орналасқан жерім',
      'Координаты: ': 'Координаттар: ',
      'Голос телефона': 'Телефон дауысы',
    },
    'en': {
      'Настройки': 'Settings',
      'Голосовые подсказки': 'Voice guidance',
      'Предпочтения маршрута': 'Route preferences',
      'Быстрый': 'Fastest',
      'Избегать платных дорог': 'Avoid toll roads',
      'Единицы измерения': 'Units of measurement',
      'км, м': 'km, m',
      'Язык приложения': 'App language',
      'Профиль': 'Profile',
      'О приложении': 'About',
      'Автомобиль': 'Vehicle',
      'Эти сведения сохраняются только на этом телефоне.': 'This information is stored only on this phone.',
      'Марка автомобиля': 'Vehicle make',
      'Модель': 'Model',
      'Цвет': 'Color',
      'Государственный номер': 'License plate',
      'Сохранить': 'Save',
      'Параметры маршрута': 'Route settings',
      'Избегать грунтовых дорог': 'Avoid unpaved roads',
      'Офлайн-карты': 'Offline maps',
      'Офлайн-карта': 'Offline map',
      'Импортируем…': 'Importing…',
      'Импортировать MBTiles-карту': 'Import MBTiles map',
      'Отключить офлайн-карту': 'Disable offline map',
      'Карта': 'Map',
      'Поиск': 'Search',
      'Маршрут': 'Route',
      'Избранное': 'Favorites',
      'Завершить маршрут': 'End navigation',
      'Построить маршрут': 'Build route',
      'Поехали': 'Go',
      'Отмена': 'Cancel',
      'Готово': 'Done',
      'Закрыть': 'Close',
      'Понятно': 'Got it',
      'Добавить место': 'Add place',
      'Мои места': 'My places',
      'Дом': 'Home',
      'Работа': 'Work',
      'Добавьте домашний адрес': 'Add your home address',
      'Добавьте адрес работы': 'Add your work address',
      'Закладки': 'Bookmarks',
      'Сохранённая точка': 'Saved point',
      'Сохранить в закладки': 'Save to bookmarks',
      'Добавить остановку на карте': 'Add stop on map',
      'Промежуточные остановки': 'Intermediate stops',
      'Время выезда': 'Departure time',
      'Сейчас': 'Now',
      'Изменить': 'Change',
      'Сбросить': 'Reset',
      'Сбросить время': 'Reset time',
      'Время отправления': 'Departure time',
      'Дата': 'Date',
      'Время': 'Time',
      'ОТКУДА': 'FROM',
      'Добавить точку маршрута': 'Add route point',
      'Скопировать ссылку на точку': 'Copy point link',
      'Тип события': 'Event type',
      'Сообщить о событии': 'Report an event',
      'События на дороге': 'Road events',
      'Слои и офлайн-карты': 'Layers and offline maps',
      'Пробки': 'Traffic',
      'Дорожные события': 'Road incidents',
      'Парковки': 'Parking',
      'Спутниковая карта': 'Satellite map',
      'Карта Казахстана': 'Map of Kazakhstan',
      'Шымкент и область': 'Shymkent and region',
      'Выбрать MBTiles-файл': 'Choose MBTiles file',
      'Язык голосовых подсказок': 'Voice guidance language',
      'Голос телефона': 'Device voice',
      'Название': 'Name',
      'Адрес': 'Address',
      'Найти адрес отправления': 'Find starting address',
      'Марка автомобиля': 'Vehicle make',
      'Модель': 'Model',
      'Цвет': 'Color',
      'Государственный номер': 'License plate',
      'Пока нет сохранённых точек. Удерживайте место на карте и выберите «Сохранить в закладки».': 'No saved points yet. Long-press a place on the map and choose “Save to bookmarks”.',
      'Добавьте остановку долгим нажатием на нужное место карты.': 'Long-press the desired place on the map to add a stop.',
      'Прослушать голос': 'Preview voice',
      'Системный голос по умолчанию': 'System default voice',
      'Громкость': 'Volume',
      'Скорость речи': 'Speech rate',
      'Для выбранного языка голоса не найдены. Установите голосовые данные в настройках преобразования текста в речь Android.': 'No voices found for the selected language. Install voice data in Android text-to-speech settings.',
      'Изменить точки': 'Edit stops',
      'Промежуточные остановки: ': 'Intermediate stops: ',
      'Вариант ': 'Option ',
      'Куда едем?': 'Where to?',
      'Найти': 'Search',
      'Опишите, что не так': 'Describe the issue',
      'Поддержка BAKE': 'BAKE Support',
      'Разместить объект': 'Add a place',
      'Бронирования и история': 'Bookings and history',
      'Отзывы и исправления': 'Reviews and corrections',
      'Музыка BAKE': 'BAKE Music',
      'Добавьте описание (необязательно)': 'Add a description (optional)',
      'Введите адрес': 'Enter an address',
      'Адрес дома': 'Home address',
      'Адрес работы': 'Work address',
      'Удалить место': 'Delete place',
      'Например, спортзал': 'For example, gym',
      'Улица, дом или место': 'Street, building or place',
      'Куда': 'To',
      'Введите адрес или место': 'Enter an address or place',
      'Найти место': 'Find place',
      'Точка на карте: ': 'Map point: ',
      'Удалить остановку': 'Remove stop',
      'Завершить навигацию': 'End navigation',
      'Слои карты': 'Map layers',
      'На север': 'North up',
      'Моё местоположение': 'My location',
      'Координаты: ': 'Coordinates: ',
      'Голос телефона': 'Device voice',
    },
  };

  static String tr(String russian) => _translations[language]?[russian] ?? russian;
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
  final FocusNode _searchFocusNode = FocusNode();
  MbTilesTileProvider? _offlineTileProvider;

  LatLng? _currentLocation;
  LatLng? _destination;
  LatLng? _routeOrigin;
  final List<LatLng> _routeStops = <LatLng>[];
  List<Map<String, dynamic>> _routeAlternatives = <Map<String, dynamic>>[];
  int _selectedRouteIndex = 0;
  List<LatLng> _routePoints = [];
  List<RouteInstruction> _instructions = [];
  int _instructionIndex = 0;
  bool _navigationActive = false;
  double _currentSpeedKmh = 0;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  StreamSubscription<Position>? _positionSubscription;
  bool _isLocating = false;
  bool _isSearching = false;
  bool _isBuildingRoute = false;
  int _voiceMode = 3;
  double? _gpsHeadingDegrees;
  int _offRouteSamples = 0;
  DateTime? _lastAutomaticReroute;
  DateTime? _plannedDeparture;
  String _message = 'Нажмите «Моё местоположение» или удерживайте точку на карте';

  @override
  void initState() {
    super.initState();
    _configureVoice();
    _loadSavedOfflineMap();
    _loadSavedRoutePoints();
    // Ask for location after the first frame so the permission dialog has a valid context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_locateMe());
    });
  }

  static const String _savedRouteOriginKey = 'saved_route_origin_v1';
  static const String _savedRouteDestinationKey = 'saved_route_destination_v1';

  String _encodePoint(LatLng point) =>
      jsonEncode({'lat': point.latitude, 'lon': point.longitude});

  LatLng? _decodePoint(String? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(value) as Map<String, dynamic>;
      final lat = (decoded['lat'] as num).toDouble();
      final lon = (decoded['lon'] as num).toDouble();
      if (lat < 40 || lat > 56 || lon < 46 || lon > 88) return null;
      return LatLng(lat, lon);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadSavedRoutePoints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // A saved start point may be stale after the user has moved.
      // Always use the fresh GPS fix as the default route origin on app launch.
      await prefs.remove(_savedRouteOriginKey);
      final destination = _decodePoint(prefs.getString(_savedRouteDestinationKey));
      if (!mounted || destination == null) return;
      setState(() {
        _routeOrigin = null;
        _destination = destination;
        _message = 'Последний пункт назначения восстановлен. Начальная точка будет определена по GPS.';
      });
    } catch (_) {
      // Route planning remains usable if local preferences are unavailable.
    }
  }

  Future<void> _saveRoutePoint(String key, LatLng point) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, _encodePoint(point));
    } catch (_) {
      if (mounted) setState(() => _message = 'Не удалось сохранить точку маршрута на телефоне.');
    }
  }

  Future<void> _removeSavedRoutePoint(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      if (mounted) setState(() => _message = 'Не удалось удалить сохранённую точку маршрута.');
    }
  }

  String _navigationLanguage = 'ru-RU';
  String? _selectedVoiceName;
  String? _selectedVoiceLocale;
  List<Map<String, String>> _availableVoices = <Map<String, String>>[];

  Future<void> _configureVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final volume = prefs.getDouble('voice_volume') ?? 1.0;
      final rate = prefs.getDouble('voice_rate') ?? 0.48;
      _voiceMode = prefs.getInt('voice_mode') ?? 3;
      _navigationLanguage = prefs.getString('navigation_language') ?? 'ru-RU';
      _selectedVoiceName = prefs.getString('voice_name');
      _selectedVoiceLocale = prefs.getString('voice_locale');
      await _tts.setLanguage(_navigationLanguage);
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(volume);
      await _refreshAvailableVoices();
      await _applySelectedVoice();
    } catch (_) {
      // Voice support depends on the speech engine installed on the phone.
    }
  }

  Future<void> _refreshAvailableVoices() async {
    try {
      final raw = await _tts.getVoices;
      final parsed = <Map<String, String>>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final name = item['name']?.toString() ?? '';
          final locale = (item['locale'] ?? item['language'] ?? '').toString();
          if (name.isEmpty || locale.isEmpty) continue;
          parsed.add(<String, String>{'name': name, 'locale': locale});
        }
      }
      _availableVoices = parsed;
    } catch (_) {
      _availableVoices = <Map<String, String>>[];
    }
  }

  Future<void> _applySelectedVoice() async {
    final name = _selectedVoiceName;
    final locale = _selectedVoiceLocale;
    if (name != null && locale != null) {
      await _tts.setVoice(<String, String>{'name': name, 'locale': locale});
    } else {
      await _tts.setLanguage(_navigationLanguage);
    }
  }

  String _localized(String ru, String kk, String en) {
    if (_navigationLanguage == 'kk-KZ') return kk;
    if (_navigationLanguage == 'en-US') return en;
    return ru;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _offlineTileProvider?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
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
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NavigatorPreferencesScreen(
          onOpenSoundSettings: _openSoundSettings,
          onOpenRoutePreferences: _openRoutePreferences,
          onOpenProfile: _openProfileMenu,
          onVoiceChanged: (enabled) {
            setState(() => _voiceMode = enabled ? 3 : 0);
            if (!enabled) unawaited(_tts.stop());
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openOfflineAndVehicleSettings() async {
    final selectedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const NavigatorSettingsScreen()),
    );
    if (!mounted || selectedPath == null) return;
    if (selectedPath == '__use_online_map__') {
      _offlineTileProvider?.dispose();
      setState(() { _offlineTileProvider = null; _message = 'Включена онлайн-карта.'; });
      return;
    }
    try {
      final provider = MbTilesTileProvider.fromPath(path: selectedPath);
      _offlineTileProvider?.dispose();
      setState(() { _offlineTileProvider = provider; _message = 'Офлайн-карта подключена. Для построения маршрута пока нужен интернет.'; });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Не удалось открыть офлайн-карту: $error');
    }
  }

  Future<void> _openSoundSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    await _refreshAvailableVoices();
    var mode = prefs.getInt('voice_mode') ?? _voiceMode;
    var volume = prefs.getDouble('voice_volume') ?? 1.0;
    var rate = prefs.getDouble('voice_rate') ?? 0.48;
    var language = prefs.getString('navigation_language') ?? _navigationLanguage;
    var selectedKey = (_selectedVoiceName == null || _selectedVoiceLocale == null)
        ? ''
        : '$_selectedVoiceName|$_selectedVoiceLocale';
    const languages = <String, String>{
      'ru-RU': 'Русский',
      'kk-KZ': 'Қазақша',
      'en-US': 'English',
    };
    const modes = <String>['Выкл.', 'Важные', 'Подсказки', 'Все'];
    List<Map<String, String>> voicesFor(String lang) => _availableVoices
        .where((v) => (v['locale'] ?? '').toLowerCase().replaceAll('_', '-').startsWith(lang.substring(0, 2).toLowerCase()))
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) {
          final voices = voicesFor(language);
          final selectedExists = voices.any((v) => '${v['name']}|${v['locale']}' == selectedKey);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(AppLocale.tr('Звуковое сопровождение'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 14),
                  Text(AppLocale.tr('Язык голосовых подсказок'), style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: language,
                    isExpanded: true,
                    items: languages.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (value) async {
                      if (value == null) return;
                      language = value;
                      _navigationLanguage = value;
                      _selectedVoiceName = null;
                      _selectedVoiceLocale = null;
                      selectedKey = '';
                      await prefs.setString('navigation_language', value);
                      await prefs.remove('voice_name');
                      await prefs.remove('voice_locale');
                      await _tts.setLanguage(value);
                      refresh(() {});
                    },
                  ),
                  const SizedBox(height: 12),
                  Text(AppLocale.tr('Голос телефона'), style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (voices.isEmpty)
                    Text(AppLocale.tr('Для выбранного языка голоса не найдены. Установите голосовые данные в настройках преобразования текста в речь Android.', style: TextStyle(color: Color(0xFF9A5B00)))
                  else
                    DropdownButtonFormField<String>(
                      value: selectedExists ? selectedKey : '',
                      isExpanded: true,
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: '', child: Text(AppLocale.tr('Системный голос по умолчанию'))),
                        ...voices.map((v) {
                          final key = '${v['name']}|${v['locale']}';
                          return DropdownMenuItem(value: key, child: Text(AppLocale.tr('${v[')name']} · ${v['locale']}', overflow: TextOverflow.ellipsis));
                        }),
                      ],
                      onChanged: (value) async {
                        selectedKey = value ?? '';
                        if (selectedKey.isEmpty) {
                          _selectedVoiceName = null;
                          _selectedVoiceLocale = null;
                          await prefs.remove('voice_name');
                          await prefs.remove('voice_locale');
                          await _tts.setLanguage(language);
                        } else {
                          final voice = voices.firstWhere((v) => '${v['name']}|${v['locale']}' == selectedKey);
                          _selectedVoiceName = voice['name'];
                          _selectedVoiceLocale = voice['locale'];
                          await prefs.setString('voice_name', _selectedVoiceName!);
                          await prefs.setString('voice_locale', _selectedVoiceLocale!);
                          await _tts.setVoice(<String, String>{'name': _selectedVoiceName!, 'locale': _selectedVoiceLocale!});
                        }
                        refresh(() {});
                      },
                    ),
                  if (voices.isNotEmpty)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          await _applySelectedVoice();
                          await _tts.speak(language == 'kk-KZ'
                              ? 'Дауысты тексеру. Бағыт бойынша жүре беріңіз.'
                              : language == 'en-US'
                                  ? 'Voice test. Continue on the route.'
                                  : 'Проверка голоса. Продолжайте движение по маршруту.');
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: Text(AppLocale.tr('Прослушать голос')),
                      ),
                    ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List<Widget>.generate(modes.length, (index) => ChoiceChip(
                      label: Text(modes[index]),
                      selected: mode == index,
                      onSelected: (_) async {
                        mode = index;
                        _voiceMode = index;
                        refresh(() {});
                        await prefs.setInt('voice_mode', index);
                        if (index == 0) await _tts.stop();
                      },
                    )),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    mode == 0 ? 'Голосовые подсказки выключены.'
                      : mode == 1 ? 'Озвучиваются прибытие и важные предупреждения.'
                      : mode == 2 ? 'Озвучиваются дорожные манёвры и предупреждения.'
                      : 'Озвучиваются манёвры, предупреждения и информация о маршруте.',
                    style: const TextStyle(color: Color(0xFF555B63)),
                  ),
                  const Divider(height: 28),
                  Text('${AppLocale.tr('Громкость')} · ${(volume * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Slider(value: volume, min: 0, max: 1, divisions: 10, onChanged: (value) async {
                    volume = value; refresh(() {});
                    await prefs.setDouble('voice_volume', value); await _tts.setVolume(value);
                  }),
                  Text('${AppLocale.tr('Скорость речи')} · ${rate.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  Slider(value: rate, min: 0.25, max: 0.75, divisions: 10, onChanged: (value) async {
                    rate = value; refresh(() {});
                    await prefs.setDouble('voice_rate', value); await _tts.setSpeechRate(value);
                  }),
                  const SizedBox(height: 12),
                  Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: Text(AppLocale.tr('Готово')))),
                ],
              ),
            ),
          );
        },
      ),
    );
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
        _currentSpeedKmh = math.max(0, position.speed * 3.6).toDouble();
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
          _currentSpeedKmh = math.max(0, position.speed * 3.6).toDouble();
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

  Future<void> _searchAddress({bool selectAsOrigin = false}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? <String>[];
    history.remove(query);
    history.insert(0, query);
    await prefs.setStringList('search_history', history.take(20).toList());
    setState(() {
      _isSearching = true;
      _message = selectAsOrigin ? 'Ищем начальную точку…' : 'Ищем пункт назначения…';
    });
    var shouldBuildRoute = false;
    try {
      // Prefer the live GPS position; use Shymkent only before GPS is available.
      final anchor = selectAsOrigin
          ? (_currentLocation ?? _routeOrigin ?? _shymkent)
          : (_routeOrigin ?? _currentLocation ?? _shymkent);
      final west = (anchor.longitude - 0.45).toStringAsFixed(6);
      final north = (anchor.latitude + 0.45).toStringAsFixed(6);
      final east = (anchor.longitude + 0.45).toStringAsFixed(6);
      final south = (anchor.latitude - 0.45).toStringAsFixed(6);

      Future<List<dynamic>> requestSearch({required bool bounded, String limit = '12'}) async {
        final params = <String, String>{
          'q': query,
          'format': 'jsonv2',
          'limit': limit,
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
      if (!mounted) return;
      if (results.isEmpty) {
        final searchNationwide = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(AppLocale.tr('Рядом не найдено')),
            content: Text(AppLocale.tr('Поблизости такого объекта нет в карте. Искать его по всему Казахстану?')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(AppLocale.tr('Не сейчас')),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(AppLocale.tr('По всему Казахстану')),
              ),
            ],
          ),
        );
        if (searchNationwide != true || !mounted) {
          setState(() => _message = 'Рядом объект не найден. Попробуйте уточнить название или выбрать точку на карте.');
          return;
        }
        results = await requestSearch(bounded: false, limit: '40');
        if (!mounted) return;
      }
      if (results.isEmpty) {
        setState(() => _message = 'Такой объект не найден в Казахстане. Проверьте название.');
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
          title: Text(selectAsOrigin ? 'Выберите начальную точку' : 'Выберите пункт назначения'),
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
                    ? '${(distance * 1000).round()} м от точки поиска'
                    : '${distance.toStringAsFixed(1)} км от точки поиска';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined, color: Color(0xFF343434)),
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
              child: Text(AppLocale.tr('Отмена')),
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
      if (selectAsOrigin) {
        _selectRouteOrigin(point);
      } else {
        _selectDestination(point);
        shouldBuildRoute = true;
      }
      _mapController.move(point, 16);
      setState(() => _message = selectAsOrigin
          ? 'Начальная точка выбрана. Теперь введите пункт назначения.'
          : 'Адрес найден. Автоматически строим маршрут от вашего GPS-положения…');
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
    // Once a destination is selected, calculate the route automatically.
    // The user only needs to review it and tap «Поехали».
    if (shouldBuildRoute && mounted) {
      await _buildRoute();
    }
  }

  void _selectRouteOrigin(LatLng point) {
    final wasNavigating = _navigationActive;
    setState(() {
      _routeOrigin = point;
      _routePoints = [];
      _instructions = [];
      _navigationActive = false;
      _instructionIndex = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = 'Начальная точка выбрана на карте. Выберите пункт назначения.';
    });
    unawaited(_saveRoutePoint(_savedRouteOriginKey, point));
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
  }

  void _resetRouteOrigin() {
    setState(() {
      _routeOrigin = null;
      _routePoints = [];
      _instructions = [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = 'Начальная точка снова определяется по GPS.';
    });
    unawaited(_removeSavedRoutePoint(_savedRouteOriginKey));
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
    unawaited(_saveRoutePoint(_savedRouteDestinationKey, point));
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
  }


  String _instructionText(Map<String, dynamic> step) {
    final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
    final type = maneuver['type']?.toString() ?? '';
    final modifier = maneuver['modifier']?.toString() ?? '';
    final name = (step['name']?.toString() ?? '').trim();
    final road = name.isEmpty
        ? ''
        : _localized(' на $name', ' $name жолымен', ' on $name');
    if (type == 'depart') return _localized('Начинайте движение$road', 'Қозғалысты бастаңыз$road', 'Start driving$road');
    if (type == 'arrive') return _localized('Вы прибыли в пункт назначения', 'Межелі жерге жеттіңіз', 'You have arrived at your destination');
    if (type == 'roundabout' || type == 'rotary') {
      return _localized('На круговом движении продолжайте$road', 'Айналма жолмен жүре беріңіз$road', 'Continue around the roundabout$road');
    }
    final actions = <String, String>{
      'left': _localized('Поверните налево', 'Солға бұрылыңыз', 'Turn left'),
      'slight left': _localized('Плавно поверните налево', 'Солға қарай жайлап бұрылыңыз', 'Slight left'),
      'sharp left': _localized('Резко поверните налево', 'Солға күрт бұрылыңыз', 'Sharp left'),
      'right': _localized('Поверните направо', 'Оңға бұрылыңыз', 'Turn right'),
      'slight right': _localized('Плавно поверните направо', 'Оңға қарай жайлап бұрылыңыз', 'Slight right'),
      'sharp right': _localized('Резко поверните направо', 'Оңға күрт бұрылыңыз', 'Sharp right'),
      'uturn': _localized('Развернитесь', 'Кері бұрылыңыз', 'Make a U-turn'),
      'straight': _localized('Продолжайте прямо', 'Тура жүре беріңіз', 'Continue straight'),
    };
    final action = actions[modifier] ??
        (type == 'new name'
            ? _localized('Продолжайте движение', 'Қозғалысты жалғастырыңыз', 'Continue driving')
            : _localized('Продолжайте по маршруту', 'Бағыт бойынша жүре беріңіз', 'Continue on the route'));
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
        ? _localized('${(meters / 1000).toStringAsFixed(1)} километра', '${(meters / 1000).toStringAsFixed(1)} километр', '${(meters / 1000).toStringAsFixed(1)} kilometers')
        : _localized('${meters.round()} метров', '${meters.round()} метр', '${meters.round()} meters');
    if (_voiceMode >= 2) {
      await _tts.speak(_localized('${instruction.text} через $distanceText.', '${instruction.text} $distanceText кейін.', '${instruction.text} in $distanceText.'));
    }
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
          _message = _localized('Вы прибыли в пункт назначения.', 'Межелі жерге жеттіңіз.', 'You have arrived at your destination.');
        });
        if (_voiceMode >= 1) _tts.speak(_localized('Вы прибыли в пункт назначения.', 'Межелі жерге жеттіңіз.', 'You have arrived at your destination.'));
        unawaited(_startLiveLocationUpdates());
        return;
      }
      setState(() => _instructionIndex++);
      _speakCurrentInstruction();
    }
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
      setState(() => _message = 'Сначала выберите конечную точку на карте.');
      return;
    }
    if (_routeOrigin == null && _currentLocation == null) await _locateMe();
    final routeOrigin = _routeOrigin ?? _currentLocation;
    if (routeOrigin == null || _destination == null) {
      if (mounted) setState(() => _message = 'Не удалось определить начальную точку. Выберите её на карте или включите GPS.');
      return;
    }

    final resumeNavigation = automaticReroute && _navigationActive;
    setState(() {
      _isBuildingRoute = true;
      _message = automaticReroute ? 'Вы отклонились от маршрута. Перестраиваем…' : 'Строим варианты маршрута…';
    });

    try {
      final coordinates = <LatLng>[routeOrigin, ..._routeStops, _destination!]
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/$coordinates'
        '?overview=full&geometries=geojson&steps=true&alternatives=true',
      );
      // Public OSRM demo endpoint is for testing, not production traffic.
      final response = await http.get(uri).timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) throw Exception('Сервис маршрутов временно недоступен.');

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = (data['routes'] as List?) ?? const [];
      if (data['code'] != 'Ok' || routes.isEmpty) {
        throw Exception('Маршрут не найден. Попробуйте изменить выбранные точки.');
      }

      final validRoutes = routes.cast<Map<String, dynamic>>().where((route) {
        final distance = (route['distance'] as num).toDouble();
        final directDistance = Geolocator.distanceBetween(
          routeOrigin.latitude, routeOrigin.longitude,
          _destination!.latitude, _destination!.longitude,
        );
        return distance <= math.max(5000.0, directDistance * 8.0);
      }).toList();
      if (validRoutes.isEmpty) {
        throw Exception('Сервис вернул слишком длинный маршрут. Проверьте выбранные точки.');
      }

      final first = validRoutes.first;
      final geometry = first['geometry'] as Map<String, dynamic>;
      final coordinatesList = geometry['coordinates'] as List<dynamic>;
      final points = coordinatesList.map((coordinate) {
        final pair = coordinate as List<dynamic>;
        return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
      }).toList();
      final instructions = _readInstructions(first);
      final distance = (first['distance'] as num).toDouble();
      final duration = (first['duration'] as num).toDouble();

      if (!mounted) return;
      setState(() {
        _routeAlternatives = validRoutes;
        _selectedRouteIndex = 0;
        _routePoints = points;
        _instructions = instructions;
        _navigationActive = resumeNavigation;
        _instructionIndex = resumeNavigation && instructions.length > 1 ? 1 : 0;
        _offRouteSamples = 0;
        _routeDistanceMeters = distance;
        _routeDurationSeconds = duration;
        _message = automaticReroute
            ? 'Маршрут перестроен. Продолжаем навигацию.'
            : 'Найдено вариантов: ${validRoutes.length}. Выберите подходящий маршрут.';
      });
      if (points.isNotEmpty) {
        _mapController.fitCamera(CameraFit.coordinates(
          coordinates: points,
          padding: const EdgeInsets.fromLTRB(36, 100, 36, 250),
        ));
      }
      if (automaticReroute && resumeNavigation) {
        if (_voiceMode >= 1) await _tts.speak(_localized('Вы отклонились от маршрута. Маршрут перестроен.', 'Бағыттан ауытқыдыңыз. Маршрут қайта құрылды.', 'You left the route. The route has been recalculated.'));
        await _speakCurrentInstruction();
      } else {
        final distanceKm = (distance / 1000).toStringAsFixed(1);
        final minutes = (duration / 60).round();
        if (_voiceMode >= 3) await _tts.speak(_localized('Маршрут построен. Расстояние $distanceKm километра. Примерное время в пути $minutes минут.', 'Маршрут құрылды. Қашықтық $distanceKm километр. Жол уақыты шамамен $minutes минут.', 'Route built. Distance $distanceKm kilometers. Estimated travel time $minutes minutes.'));
        // Always show the route summary, including the «Поехали» action,
        // even when the routing service returns only one valid route.
        unawaited(_openRouteAlternatives());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isBuildingRoute = false);
    }
  }

  void _selectRouteAlternative(int index) {
    if (index < 0 || index >= _routeAlternatives.length) return;
    final route = _routeAlternatives[index];
    final geometry = route['geometry'] as Map<String, dynamic>;
    final coordinates = geometry['coordinates'] as List<dynamic>;
    final points = coordinates.map((coordinate) {
      final pair = coordinate as List<dynamic>;
      return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
    }).toList();
    final instructions = _readInstructions(route);
    setState(() {
      _selectedRouteIndex = index;
      _routePoints = points;
      _instructions = instructions;
      _instructionIndex = 0;
      _routeDistanceMeters = (route['distance'] as num).toDouble();
      _routeDurationSeconds = (route['duration'] as num).toDouble();
      _message = 'Выбран вариант маршрута ${index + 1}.';
    });
    if (points.isNotEmpty) {
      _mapController.fitCamera(CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(36, 100, 36, 250),
      ));
    }
  }

  Future<void> _openRouteAlternatives() async {
    if (_routeAlternatives.isEmpty) {
      await _openRoutePlanner();
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, refreshPage) => Scaffold(
          backgroundColor: const Color(0xFFF7F8FA),
          appBar: AppBar(
            title: Text(AppLocale.tr('Построение маршрута')),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            actions: [
              IconButton(
                tooltip: AppLocale.tr('Изменить точки'),
                onPressed: () {
                  Navigator.pop(pageContext);
                  _openRoutePlanner();
                },
                icon: const Icon(Icons.edit_location_alt_outlined),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      Card(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.trip_origin, color: Color(0xFF269B68)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _routeOrigin == null
                                          ? (_currentLocation == null ? 'Моё местоположение' : 'Текущее местоположение')
                                          : '${_routeOrigin!.latitude.toStringAsFixed(5)}, ${_routeOrigin!.longitude.toStringAsFixed(5)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              const Padding(
                                padding: EdgeInsets.only(left: 11),
                                child: SizedBox(height: 18, child: VerticalDivider(width: 1, thickness: 1)),
                              ),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Color(0xFFE45D52)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _destination == null
                                          ? 'Пункт назначения не выбран'
                                          : '${_destination!.latitude.toStringAsFixed(5)}, ${_destination!.longitude.toStringAsFixed(5)}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              if (_routeStops.isNotEmpty) ...[
                                const Divider(height: 22),
                                Text('${AppLocale.tr('Промежуточные остановки: ')}${_routeStops.length}'),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Варианты маршрута',
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ...List.generate(_routeAlternatives.length, (index) {
                        final route = _routeAlternatives[index];
                        final km = ((route['distance'] as num).toDouble() / 1000).toStringAsFixed(1);
                        final minutes = (((route['duration'] as num).toDouble()) / 60).round();
                        final selected = index == _selectedRouteIndex;
                        return Card(
                          color: selected ? const Color(0xFFFFF4CC) : Colors.white,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            leading: Icon(
                              selected ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: const Color(0xFF343434),
                            ),
                            title: Text(
                              '$minutes мин · $km км',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text('${AppLocale.tr('Вариант ')}${index + 1}'),
                            trailing: selected ? const Icon(Icons.check_circle, color: Color(0xFF269B68)) : null,
                            onTap: () {
                              _selectRouteAlternative(index);
                              refreshPage(() {});
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: SafeArea(
                    top: false,
                    child: SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFFCC00),
                          foregroundColor: const Color(0xFF171717),
                        ),
                        onPressed: _navigationActive ? null : () {
                          Navigator.pop(pageContext);
                          _startNavigation();
                        },
                        child: Text(AppLocale.tr('Поехали'), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }

  Future<void> _addRouteStop(LatLng point) async {
    if (_routeStops.length >= 5) {
      setState(() => _message = 'Можно добавить не более пяти промежуточных остановок.');
      return;
    }
    setState(() {
      _routeStops.add(point);
      _message = 'Промежуточная остановка добавлена. Перестройте маршрут.';
    });
  }



  Future<void> _openSearchPanel() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? <String>[];
    if (!mounted) return;
    const categories = <Map<String, Object>>[
      {'name': 'АЗС', 'query': 'АЗС', 'icon': Icons.local_gas_station},
      {'name': 'Рестораны', 'query': 'ресторан', 'icon': Icons.restaurant},
      {'name': 'Магазины', 'query': 'магазин', 'icon': Icons.store},
      {'name': 'Гостиницы', 'query': 'гостиница', 'icon': Icons.hotel},
      {'name': 'Аптеки', 'query': 'аптека', 'icon': Icons.local_pharmacy},
      {'name': 'Ещё', 'query': '', 'icon': Icons.apps},
    ];

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(AppLocale.tr('Поиск')),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) {
                    Navigator.pop(pageContext);
                    _searchAddress();
                  },
                  decoration: InputDecoration(
                    hintText: AppLocale.tr('Куда едем?'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      tooltip: AppLocale.tr('Найти'),
                      onPressed: _isSearching
                          ? null
                          : () {
                              Navigator.pop(pageContext);
                              _searchAddress();
                            },
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Недавние запросы',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (history.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      'Здесь появятся адреса и места, которые вы искали.',
                      style: TextStyle(color: Color(0xFF7B8792)),
                    ),
                  )
                else
                  ...history.take(4).map((query) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history, color: Color(0xFF69737D)),
                    title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.north_west, size: 18),
                    onTap: () {
                      Navigator.pop(pageContext);
                      _searchController.text = query;
                      _searchAddress();
                    },
                  )),
                const Divider(height: 24),
                const Text(
                  'Категории',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  crossAxisCount: 3,
                  childAspectRatio: 1.05,
                  children: categories.map((category) {
                    final name = category['name']! as String;
                    final query = category['query']! as String;
                    final icon = category['icon']! as IconData;
                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.pop(pageContext);
                        if (name == 'Ещё') {
                          _openMoreSearchCategories();
                        } else if (name == 'АЗС') {
                          _openStationNetworks();
                        } else {
                          _searchController.text = query;
                          _searchAddress();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              radius: 27,
                              backgroundColor: const Color(0xFFF1F3F5),
                              child: Icon(icon, color: const Color(0xFF343434)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              name,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openMoreSearchCategories() async {
    const categories = <Map<String, Object>>[
      {'name': 'Кафе', 'query': 'кафе', 'icon': Icons.local_cafe},
      {'name': 'Банкоматы', 'query': 'банкомат', 'icon': Icons.atm},
      {'name': 'Автомойки', 'query': 'автомойка', 'icon': Icons.local_car_wash},
      {'name': 'Автосервисы', 'query': 'автосервис', 'icon': Icons.car_repair},
      {'name': 'Больницы', 'query': 'больница', 'icon': Icons.local_hospital},
      {'name': 'Кинотеатры', 'query': 'кинотеатр', 'icon': Icons.movie},
    ];
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(AppLocale.tr('Ещё категории')),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
          ),
          body: GridView.count(
            padding: const EdgeInsets.all(14),
            crossAxisCount: 3,
            childAspectRatio: 1.05,
            children: categories.map((category) {
              final name = category['name']! as String;
              final query = category['query']! as String;
              final icon = category['icon']! as IconData;
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.pop(pageContext);
                  _searchController.text = query;
                  _searchAddress();
                },
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 27,
                        backgroundColor: const Color(0xFFF1F3F5),
                        child: Icon(icon, color: const Color(0xFF343434)),
                      ),
                      const SizedBox(height: 8),
                      Text(name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _showUnavailableFeature(String title, String detail) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(detail),
        actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocale.tr('Понятно')))],
      ),
    );
  }

  Future<void> _shareCurrentLocation() async {
    final point = _currentLocation;
    if (point == null) {
      await _showUnavailableFeature('Геопозиция', 'Сначала дождитесь определения GPS.');
      return;
    }
    final value = 'Моя геопозиция BAKE: https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=17/${point.latitude}/${point.longitude}';
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) setState(() => _message = 'Ссылка на геопозицию скопирована.');
  }

  Future<void> _shareRoute() async {
    if (_destination == null || _routePoints.isEmpty) {
      await _showUnavailableFeature('Поделиться маршрутом', 'Сначала постройте маршрут.');
      return;
    }
    final origin = _routeOrigin ?? _currentLocation;
    final value = 'Маршрут BAKE Navigator\\n'
        'Откуда: ${origin == null ? 'текущее местоположение' : '${origin.latitude}, ${origin.longitude}'}\\n'
        'Куда: ${_destination!.latitude}, ${_destination!.longitude}\\n'
        '${_routeSummary()}\\n'
        'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${origin?.latitude}%2C${origin?.longitude}%3B${_destination!.latitude}%2C${_destination!.longitude}';
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) setState(() => _message = 'Описание маршрута скопировано для отправки.');
  }

  Future<void> _reportRouteIssue() async {
    final controller = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.tr('Сообщить об ошибке маршрута')),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: InputDecoration(hintText: AppLocale.tr('Опишите, что не так'), border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocale.tr('Отмена'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(AppLocale.tr('Скопировать отчёт'))),
        ],
      ),
    );
    if (accepted != true || !mounted) { controller.dispose(); return; }
    final report = 'Ошибка маршрута BAKE Navigator\\n${controller.text.trim()}\\n${_routeSummary()}';
    await Clipboard.setData(ClipboardData(text: report));
    controller.dispose();
    if (mounted) setState(() => _message = 'Отчёт скопирован. Отправка на сервер пока не подключена.');
  }

  Future<void> _openRoutePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var avoidTolls = prefs.getBool('avoid_tolls') ?? false;
    var avoidUnpaved = prefs.getBool('avoid_unpaved') ?? false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: StatefulBuilder(
            builder: (sheetContext, refresh) => Column(mainAxisSize: MainAxisSize.min, children: [
              Align(alignment: Alignment.centerLeft, child: Text(AppLocale.tr('Параметры маршрута'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: avoidTolls,
                title: Text(AppLocale.tr('Избегать платных дорог')),
                onChanged: (value) async { avoidTolls = value; refresh(() {}); await prefs.setBool('avoid_tolls', value); },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: avoidUnpaved,
                title: Text(AppLocale.tr('Избегать плохих и грунтовых дорог')),
                onChanged: (value) async { avoidUnpaved = value; refresh(() {}); await prefs.setBool('avoid_unpaved', value); },
              ),
              Text(AppLocale.tr('Эти параметры сохраняются на телефоне. Текущий тестовый сервис OSRM пока не применяет их при расчёте.'), style: TextStyle(fontSize: 12, color: Colors.black54)),
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.pop(sheetContext), child: Text(AppLocale.tr('Готово')))),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openMapLayers() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    var traffic = prefs.getBool('layer_traffic') ?? false;
    var roadEvents = prefs.getBool('layer_road_events') ?? true;
    var parking = prefs.getBool('layer_parking') ?? false;
    var satellite = prefs.getBool('layer_satellite') ?? false;

    Future<void> saveLayer(String key, bool value) async {
      await prefs.setBool(key, value);
      if (!mounted) return;
      setState(() {
        _message = 'Настройка сохранена. Для отображения этого слоя нужен подключённый источник данных.';
      });
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, refresh) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: Text(AppLocale.tr('Слои и офлайн-карты')),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                const Text(
                  'Слои карты',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.traffic_outlined),
                  title: Text(AppLocale.tr('Пробки')),
                  value: traffic,
                  onChanged: (value) async {
                    refresh(() => traffic = value);
                    await saveLayer('layer_traffic', value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.warning_amber_outlined),
                  title: Text(AppLocale.tr('Дорожные события')),
                  value: roadEvents,
                  onChanged: (value) async {
                    refresh(() => roadEvents = value);
                    await saveLayer('layer_road_events', value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.local_parking_outlined),
                  title: Text(AppLocale.tr('Парковки')),
                  value: parking,
                  onChanged: (value) async {
                    refresh(() => parking = value);
                    await saveLayer('layer_parking', value);
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.satellite_alt_outlined),
                  title: Text(AppLocale.tr('Спутниковая карта')),
                  value: satellite,
                  onChanged: (value) async {
                    refresh(() => satellite = value);
                    await saveLayer('layer_satellite', value);
                  },
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 18),
                  child: Text(
                    'Переключатели пока сохраняют выбор. Пробки, парковки, спутниковые снимки и общий слой дорожных событий ещё не подключены к источникам данных и не отображаются на карте.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                const Divider(),
                const SizedBox(height: 10),
                const Text(
                  'Офлайн-карты',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.map_outlined),
                  title: Text(AppLocale.tr('Карта Казахстана')),
                  subtitle: Text(AppLocale.tr('Импортировать MBTiles-файл с телефона')),
                  trailing: const Icon(Icons.download_for_offline_outlined),
                  onTap: () {
                    Navigator.pop(pageContext);
                    _openOfflineAndVehicleSettings();
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_city_outlined),
                  title: Text(AppLocale.tr('Шымкент и область')),
                  subtitle: Text(AppLocale.tr('Импортировать MBTiles-файл с телефона')),
                  trailing: const Icon(Icons.download_for_offline_outlined),
                  onTap: () {
                    Navigator.pop(pageContext);
                    _openOfflineAndVehicleSettings();
                  },
                ),
                const SizedBox(height: 10),
                Text(
                  _offlineTileProvider == null
                      ? 'Офлайн-карта не подключена. Размер и покрытие файла проверяются после выбора; готовые пакеты для скачивания пока не предоставляются.'
                      : 'Офлайн-карта подключена. Для построения маршрута пока нужен интернет.',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(pageContext);
                    _openOfflineAndVehicleSettings();
                  },
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(AppLocale.tr('Выбрать MBTiles-файл')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openProfileMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD6D9DE), borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 18),
            Row(children: [
              const CircleAvatar(radius: 27, backgroundColor: Color(0xFFFFF5D6), child: Icon(Icons.person_outline, size: 31, color: Color(0xFF343434))),
              const SizedBox(width: 14),
              Expanded(child: Text(AppLocale.tr('Профиль BAKE'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
              IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
            ]),
            const SizedBox(height: 10),
            _menuTile(sheetContext, Icons.download_for_offline_outlined, 'Загрузка карт', () { Navigator.pop(sheetContext); _openOfflineAndVehicleSettings(); }),
            _menuTile(sheetContext, Icons.support_agent_outlined, 'Поддержка', () { Navigator.pop(sheetContext); _openSupportPage(); }),
            _menuTile(sheetContext, Icons.map_outlined, 'Изменить карту и слои', () { Navigator.pop(sheetContext); _openMapLayers(); }),
            _menuTile(sheetContext, Icons.add_location_alt_outlined, 'Разместить объект', () { Navigator.pop(sheetContext); _openPlaceSubmissionPage(); }),
            _menuTile(sheetContext, Icons.share_location_outlined, 'Поделиться геопозицией', () { Navigator.pop(sheetContext); _shareCurrentLocation(); }),
            _menuTile(sheetContext, Icons.bookmark_border, 'Закладки', () { Navigator.pop(sheetContext); _openBookmarks(); }),
            _menuTile(sheetContext, Icons.place_outlined, 'Мои места', () { Navigator.pop(sheetContext); _openMyPlaces(); }),
            _menuTile(sheetContext, Icons.warning_amber_outlined, 'События на дороге', () { Navigator.pop(sheetContext); _openRoadEvents(); }),
            _menuTile(sheetContext, Icons.local_gas_station_outlined, 'Заправки', () { Navigator.pop(sheetContext); _openStationNetworks(); }),
            _menuTile(sheetContext, Icons.local_parking_outlined, 'Парковки', () { Navigator.pop(sheetContext); _searchController.text = 'парковка'; _searchAddress(); }),
            _menuTile(sheetContext, Icons.settings_outlined, 'Настройки', () { Navigator.pop(sheetContext); _openSettings(); }),
            _menuTile(sheetContext, Icons.history, 'Бронирования и история заказов', () { Navigator.pop(sheetContext); _openBookingsPage(); }),
            _menuTile(sheetContext, Icons.rate_review_outlined, 'Лента отзывов и исправлений', () { Navigator.pop(sheetContext); _openFeedbackPage(); }),
            _menuTile(sheetContext, Icons.workspace_premium_outlined, 'BAKE Plus', () { Navigator.pop(sheetContext); _openBakePlusPage(); }),
            _menuTile(sheetContext, Icons.music_note_outlined, 'Музыка', () { Navigator.pop(sheetContext); _openMusicPage(); }),
          ]),
        ),
      ),
    );
  }

  Future<void> _openFeaturePage({
    required String title,
    required IconData icon,
    required String description,
    required String status,
    String? actionLabel,
    Future<void> Function()? onAction,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: const Color(0xFFFFFFFF),
          appBar: AppBar(
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            backgroundColor: const Color(0xFFFFFFFF),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: const Color(0xFFFFF5D6),
                        child: Icon(icon, size: 30, color: const Color(0xFF343434)),
                      ),
                      const SizedBox(height: 18),
                      Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Text(description, style: const TextStyle(fontSize: 16, height: 1.45)),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F4F7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(status, style: const TextStyle(fontSize: 14, color: Color(0xFF555B63))),
                      ),
                    ],
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      await onAction();
                      if (pageContext.mounted) Navigator.pop(pageContext);
                    },
                    icon: const Icon(Icons.copy),
                    label: Text(actionLabel),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openSupportPage() => _openFeaturePage(
    title: 'Поддержка BAKE',
    icon: Icons.support_agent_outlined,
    description: 'Здесь будет раздел помощи по поиску, маршрутам, GPS и офлайн-картам. Можно подготовить обращение и скопировать его, чтобы отправить удобным способом.',
    status: 'Канал отправки обращений на сервер ещё не подключён. Эта страница не отправляет сообщения автоматически.',
    actionLabel: 'Подготовить обращение',
    onAction: () async {
      await Clipboard.setData(const ClipboardData(text: 'Обращение в поддержку BAKE Navigator. Опишите проблему и приложите скриншот.'));
      if (mounted) setState(() => _message = 'Шаблон обращения скопирован.');
    },
  );

  Future<void> _openPlaceSubmissionPage() => _openFeaturePage(
    title: 'Разместить объект',
    icon: Icons.add_location_alt_outlined,
    description: 'Раздел предназначен для подготовки карточки нового места: название, категория, адрес и координаты. Для добавления объекта на общую карту потребуется серверная проверка.',
    status: 'Публикация объектов пока не подключена. Ничего не будет отправлено без сервера.',
  );

  Future<void> _openBookingsPage() => _openFeaturePage(
    title: 'Бронирования и история',
    icon: Icons.history,
    description: 'Здесь будет история поездок и сохранённые бронирования BAKE, когда приложение получит соответствующий сервис.',
    status: 'История пока пуста: сервис бронирований и учёт поездок ещё не подключены.',
  );

  Future<void> _openFeedbackPage() => _openFeaturePage(
    title: 'Отзывы и исправления',
    icon: Icons.rate_review_outlined,
    description: 'Раздел для просмотра сообщений об ошибках карты и предложенных исправлений.',
    status: 'Лента пока недоступна: серверный источник отзывов и модерация ещё не подключены.',
  );

  Future<void> _openMusicPage() => _openFeaturePage(
    title: 'Музыка BAKE',
    icon: Icons.music_note_outlined,
    description: 'Отдельная музыкальная панель должна показывать только реально доступное управление воспроизведением на телефоне или подключённом музыкальном сервисе. В ней будут текущий трек и доступные системные действия, если Android предоставит их.',
    status: 'Музыкальный провайдер и управление медиасессией пока не подключены. BAKE не показывает вымышленные треки, исполнителей и обложки.',
  );

  Future<void> _openBakePlusPage() => _openFeaturePage(
    title: 'BAKE Plus',
    icon: Icons.workspace_premium_outlined,
    description: 'Будущий раздел дополнительных возможностей BAKE Navigator. Здесь будут описаны условия, если будет создана собственная подписка.',
    status: 'Подписка BAKE Plus пока не создана. Оплата и платные функции не включены.',
  );

  Future<void> _openPointMenu(LatLng point) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(AppLocale.tr('Что здесь')),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_showPointDetails(point));
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_location_alt_outlined),
              title: Text(AppLocale.tr('Добавить точку маршрута')),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_addRouteStop(point));
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(AppLocale.tr('Скопировать ссылку на точку')),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_sharePoint(point));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPointDetails(LatLng point) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'jsonv2',
        'zoom': '18',
        'accept-language': 'ru,kk',
      });
      final response = await http.get(uri, headers: const {'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)'}).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) throw Exception('Сервис адресов временно недоступен.');
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['display_name']?.toString() ?? 'Адрес не найден в OpenStreetMap.';
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocale.tr('Что здесь')),
          content: Text('$address\\n\\n${AppLocale.tr('Координаты: ')}${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
          actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text(AppLocale.tr('Закрыть')))],
        ),
      );
    } catch (error) {
      if (mounted) setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _sharePoint(LatLng point) async {
    final url = 'https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=17/${point.latitude}/${point.longitude}';
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) setState(() => _message = 'Ссылка на точку скопирована.');
  }

  Future<void> _reportMapItem(LatLng point, String title) async {
    final controller = TextEditingController();
    const eventTypes = ['ДТП', 'Ремонт дороги', 'Камера', 'Опасность', 'Другое'];
    var selectedType = eventTypes.first;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title == 'Дорожное событие') ...[
                Text(AppLocale.tr('Тип события')),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedType,
                  items: eventTypes.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
                  onChanged: (value) { if (value != null) refreshDialog(() => selectedType = value); },
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: controller,
                maxLines: 4,
                decoration: InputDecoration(hintText: AppLocale.tr('Добавьте описание (необязательно)'), border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocale.tr('Отмена'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(AppLocale.tr('Сохранить'))),
          ],
        ),
      ),
    );
    if (accepted != true || !mounted) { controller.dispose(); return; }
    final detail = controller.text.trim();
    final eventTitle = title == 'Дорожное событие' ? selectedType : title;
    final report = '$eventTitle\nКоординаты: ${point.latitude}, ${point.longitude}\n$detail';
    if (title == 'Дорожное событие') {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('road_event_reports') ?? <String>[];
      saved.add(jsonEncode({'kind': selectedType, 'detail': detail, 'lat': point.latitude, 'lon': point.longitude, 'date': DateTime.now().toLocal().toString().substring(0, 16)}));
      await prefs.setStringList('road_event_reports', saved);
    }
    await Clipboard.setData(ClipboardData(text: report));
    controller.dispose();
    if (mounted) {
      setState(() => _message = title == 'Дорожное событие'
        ? 'Событие сохранено на устройстве. Отправка другим водителям пока не подключена.'
        : 'Отчёт скопирован. Отправка на сервер пока не подключена.');
    }
  }

  Future<void> _openMyPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    var home = prefs.getString('my_place_home') ?? '';
    var work = prefs.getString('my_place_work') ?? '';
    var customPlaces = prefs.getStringList('my_custom_places') ?? <String>[];
    if (!mounted) return;

    Future<void> editAddress({
      required String title,
      required String currentValue,
      required Future<void> Function(String) onSave,
    }) async {
      final controller = TextEditingController(text: currentValue);
      final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: AppLocale.tr('Введите адрес'),
              border: OutlineInputBorder(),
            ),
            onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(AppLocale.tr('Отмена')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(AppLocale.tr('Сохранить')),
            ),
          ],
        ),
      );
      controller.dispose();
      if (value == null) return;
      await onSave(value);
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, refresh) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: Text(AppLocale.tr('Мои места')),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3C4),
                    child: Icon(Icons.home_outlined, color: Color(0xFF343434)),
                  ),
                  title: Text(AppLocale.tr('Дом'), style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(home.isEmpty ? 'Добавьте домашний адрес' : home),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    await editAddress(
                      title: 'Адрес дома',
                      currentValue: home,
                      onSave: (value) async {
                        home = value;
                        await prefs.setString('my_place_home', value);
                        refresh(() {});
                      },
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFEAF4FF),
                    child: Icon(Icons.work_outline, color: Color(0xFF343434)),
                  ),
                  title: Text(AppLocale.tr('Работа'), style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(work.isEmpty ? 'Добавьте адрес работы' : work),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    await editAddress(
                      title: 'Адрес работы',
                      currentValue: work,
                      onSave: (value) async {
                        work = value;
                        await prefs.setString('my_place_work', value);
                        refresh(() {});
                      },
                    );
                  },
                ),
                const SizedBox(height: 18),
                const Text(
                  'Избранное',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (customPlaces.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Text(AppLocale.tr('Сохранённых пользовательских мест пока нет.')),
                  )
                else
                  ...customPlaces.asMap().entries.map((entry) {
                    final index = entry.key;
                    final parts = entry.value.split('|');
                    final name = parts.isNotEmpty ? parts.first : 'Место';
                    final address = parts.length > 1 ? parts.sublist(1).join('|') : '';
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.favorite_outline, color: Color(0xFFE45D52)),
                      title: Text(name),
                      subtitle: Text(address),
                      onTap: address.isEmpty
                          ? null
                          : () {
                              Navigator.pop(pageContext);
                              _searchController.text = address;
                              _searchAddress();
                            },
                      trailing: IconButton(
                        tooltip: AppLocale.tr('Удалить место'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          customPlaces.removeAt(index);
                          await prefs.setStringList('my_custom_places', customPlaces);
                          refresh(() {});
                        },
                      ),
                    );
                  }),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    final nameController = TextEditingController();
                    final addressController = TextEditingController();
                    final accepted = await showDialog<bool>(
                      context: pageContext,
                      builder: (dialogContext) => AlertDialog(
                        title: Text(AppLocale.tr('Добавить место')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameController,
                              decoration: const InputDecoration(
                                labelText: AppLocale.tr('Название'),
                                hintText: AppLocale.tr('Например, спортзал'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: addressController,
                              decoration: const InputDecoration(
                                labelText: AppLocale.tr('Адрес'),
                                hintText: AppLocale.tr('Улица, дом или место'),
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext, false),
                            child: Text(AppLocale.tr('Отмена')),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(
                              dialogContext,
                              nameController.text.trim().isNotEmpty &&
                                  addressController.text.trim().isNotEmpty,
                            ),
                            child: Text(AppLocale.tr('Сохранить')),
                          ),
                        ],
                      ),
                    );
                    final name = nameController.text.trim();
                    final address = addressController.text.trim();
                    nameController.dispose();
                    addressController.dispose();
                    if (accepted != true || name.isEmpty || address.isEmpty) return;
                    customPlaces = [...customPlaces, '$name|$address'];
                    await prefs.setStringList('my_custom_places', customPlaces);
                    refresh(() {});
                  },
                  icon: const Icon(Icons.add),
                  label: Text(AppLocale.tr('Добавить место')),
                ),
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.bookmark_border),
                  title: Text(AppLocale.tr('Точки, сохранённые на карте')),
                  subtitle: Text(AppLocale.tr('Открыть закладки с координатами')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(pageContext);
                    _openBookmarks();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRoadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final reports = prefs.getStringList('road_event_reports') ?? <String>[];
    if (!mounted) return;

    IconData iconFor(String kind) {
      switch (kind) {
        case 'ДТП':
          return Icons.warning_rounded;
        case 'Ремонт дороги':
          return Icons.construction_rounded;
        case 'Камера':
          return Icons.camera_alt_rounded;
        case 'Опасность':
          return Icons.error_rounded;
        default:
          return Icons.report_problem_outlined;
      }
    }

    Color colorFor(String kind) {
      switch (kind) {
        case 'ДТП':
          return const Color(0xFFE53935);
        case 'Ремонт дороги':
          return const Color(0xFFFFC107);
        case 'Камера':
          return const Color(0xFF1976D2);
        case 'Опасность':
          return const Color(0xFFFF8A00);
        default:
          return const Color(0xFF777777);
      }
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            title: Text(AppLocale.tr('События на дороге')),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
          ),
          body: reports.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Пока нет сохранённых сообщений о дорожных событиях.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: reports.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = jsonDecode(reports[reports.length - 1 - index])
                        as Map<String, dynamic>;
                    final kind = item['kind']?.toString() ?? 'Дорожное событие';
                    final detail = item['detail']?.toString() ?? '';
                    final date = item['date']?.toString() ?? '';
                    final lat = item['lat'];
                    final lon = item['lon'];
                    final hasPoint = lat is num && lon is num;
                    final coordinateText = hasPoint
                        ? 'Координаты: ${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}'
                        : '';
                    final subtitle = [detail, coordinateText, date]
                        .where((value) => value.isNotEmpty)
                        .join(' · ');
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      leading: Icon(
                        iconFor(kind),
                        color: colorFor(kind),
                        size: 30,
                      ),
                      title: Text(
                        kind,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: subtitle.isEmpty ? null : Text(subtitle),
                    );
                  },
                ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: () {
                Navigator.pop(pageContext);
                final point = _currentLocation;
                if (point == null) {
                  _showUnavailableFeature(
                    'Геопозиция',
                    'Сначала дождитесь определения GPS или выберите точку долгим нажатием на карте.',
                  );
                } else {
                  _reportMapItem(point, 'Дорожное событие');
                }
              },
              icon: const Icon(Icons.campaign_outlined),
              label: Text(AppLocale.tr('Сообщить о событии')),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('map_bookmarks') ?? <String>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text(AppLocale.tr('Закладки'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            if (saved.isEmpty)
              Padding(padding: const EdgeInsets.all(22), child: Text(AppLocale.tr('Пока нет сохранённых точек. Удерживайте место на карте и выберите «Сохранить в закладки».')))
            else
              ...saved.map((raw) {
                final item = jsonDecode(raw) as Map<String, dynamic>;
                final lat = (item['lat'] as num).toDouble();
                final lon = (item['lon'] as num).toDouble();
                return ListTile(
                  leading: const Icon(Icons.bookmark),
                  title: Text(item['label']?.toString() ?? 'Сохранённая точка'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final point = LatLng(lat, lon);
                    _selectDestination(point);
                    _mapController.move(point, 16);
                  },
                );
              }),
          ]),
        ),
      ),
    );
  }

  String _formatDeparture(DateTime value) {
    final date = '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
    final time = '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  Future<void> _openDepartureTime(StateSetter refreshPlanner) async {
    var selected = _plannedDeparture ?? DateTime.now();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(child: Text(AppLocale.tr('Время отправления'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
                TextButton(onPressed: () { setState(() => _plannedDeparture = null); refreshPlanner(() {}); Navigator.pop(sheetContext); }, child: Text(AppLocale.tr('Сбросить'))),
              ]),
              const SizedBox(height: 10),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined),
                title: Text(AppLocale.tr('Дата')),
                subtitle: Text('${selected.day.toString().padLeft(2, '0')}.${selected.month.toString().padLeft(2, '0')}.${selected.year}'),
                onTap: () async {
                  final now = DateTime.now();
                  final date = await showDatePicker(
                    context: sheetContext,
                    initialDate: selected.isBefore(DateTime(now.year, now.month, now.day)) ? now : selected,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: DateTime(now.year + 2),
                    helpText: 'Дата отправления',
                  );
                  if (date != null) { selected = DateTime(date.year, date.month, date.day, selected.hour, selected.minute); refresh(() {}); }
                },
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: Text(AppLocale.tr('Время')),
                subtitle: Text('${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}'),
                onTap: () async {
                  final time = await showTimePicker(context: sheetContext, initialTime: TimeOfDay.fromDateTime(selected), helpText: 'Время отправления');
                  if (time != null) { selected = DateTime(selected.year, selected.month, selected.day, time.hour, time.minute); refresh(() {}); }
                },
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () { setState(() => _plannedDeparture = selected); refreshPlanner(() {}); Navigator.pop(sheetContext); }, child: Text(AppLocale.tr('Готово')))),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openRoutePlanner() async {
    final destinationController = TextEditingController();
    final originController = TextEditingController();
    var searchAfterClose = false;
    var searchOriginAfterClose = false;
    var buildRouteAfterClose = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refreshSheet) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(18, 12, 18, 18 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD6D9DE), borderRadius: BorderRadius.circular(8)))),
                  const SizedBox(height: 14),
                  Text(AppLocale.tr('Планирование маршрута'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 16),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Padding(padding: EdgeInsets.only(top: 12), child: Icon(Icons.my_location, color: Color(0xFF269B68))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(AppLocale.tr('ОТКУДА'), style: TextStyle(fontSize: 10, color: Color(0xFF78838D), fontWeight: FontWeight.w800, letterSpacing: 0.8)),
                      const SizedBox(height: 3),
                      Text(_routeOrigin != null
                          ? '${_routeOrigin!.latitude.toStringAsFixed(5)}, ${_routeOrigin!.longitude.toStringAsFixed(5)}'
                          : (_currentLocation == null ? 'Моё местоположение (ожидаем GPS)' : '${_currentLocation!.latitude.toStringAsFixed(5)}, ${_currentLocation!.longitude.toStringAsFixed(5)}'),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      Text(_routeOrigin == null ? 'Начальная точка определяется по GPS' : 'Начальная точка выбрана вручную', style: const TextStyle(fontSize: 11, color: Color(0xFF7B8792))),
                      const SizedBox(height: 8),
                      TextField(
                        controller: originController,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) { searchOriginAfterClose = originController.text.trim().isNotEmpty; Navigator.pop(sheetContext); },
                        decoration: const InputDecoration(
                          labelText: AppLocale.tr('Найти адрес отправления'),
                          hintText: AppLocale.tr('Улица, дом или место'),
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ])),
                    if (_routeOrigin != null)
                      TextButton(onPressed: () { _resetRouteOrigin(); refreshSheet(() {}); }, child: Text(AppLocale.tr('Сбросить'))),
                    TextButton(onPressed: () { Navigator.pop(sheetContext); unawaited(_locateMe()); }, child: Text(AppLocale.tr('GPS'))),
                  ]),
                  const Divider(height: 22),
                  Row(children: [
                    const Icon(Icons.location_on, color: Color(0xFFE45D52)),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(
                      controller: destinationController,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) { searchAfterClose = true; Navigator.pop(sheetContext); },
                      decoration: InputDecoration(labelText: AppLocale.tr('Куда'), hintText: AppLocale.tr('Введите адрес или место'), border: InputBorder.none),
                    )),
                    IconButton(
                      tooltip: AppLocale.tr('Найти место'),
                      onPressed: () { searchAfterClose = destinationController.text.trim().isNotEmpty; Navigator.pop(sheetContext); },
                      icon: const Icon(Icons.search, color: Color(0xFF343434)),
                    ),
                  ]),
                  if (_destination != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 36, bottom: 8),
                      child: Text('${AppLocale.tr('Точка на карте: ')}${_destination!.latitude.toStringAsFixed(5)}, ${_destination!.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 11, color: Color(0xFF6D7882))),
                    ),
                  const Divider(height: 18),
                  Row(children: [
                    const Icon(Icons.more_horiz, color: Color(0xFF343434)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(AppLocale.tr('Промежуточные остановки'), style: TextStyle(fontWeight: FontWeight.w700))),
                    Text('${_routeStops.length}/5', style: const TextStyle(color: Color(0xFF687786))),
                  ]),
                  if (_routeStops.isEmpty)
                    Padding(padding: const EdgeInsets.fromLTRB(36, 6, 0, 8), child: Text(AppLocale.tr('Добавьте остановку долгим нажатием на нужное место карты.'), style: TextStyle(fontSize: 12, color: Color(0xFF7B8792))))
                  else
                    ..._routeStops.asMap().entries.map((entry) => ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 30),
                      leading: CircleAvatar(radius: 12, child: Text('${entry.key + 1}', style: const TextStyle(fontSize: 11))),
                      title: Text('${entry.value.latitude.toStringAsFixed(5)}, ${entry.value.longitude.toStringAsFixed(5)}', style: const TextStyle(fontSize: 13)),
                      trailing: IconButton(
                        tooltip: AppLocale.tr('Удалить остановку'),
                        icon: const Icon(Icons.close, size: 19),
                        onPressed: () { setState(() { _routeStops.removeAt(entry.key); _routePoints = []; _instructions = []; }); refreshSheet(() {}); },
                      ),
                    )),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _routeStops.length >= 5 ? null : () { Navigator.pop(sheetContext); setState(() => _message = 'Удерживайте нужную точку карты и выберите «Добавить как промежуточную остановку».'); },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: Text(AppLocale.tr('Добавить остановку на карте')),
                  ),
                  const Divider(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule, color: Color(0xFF343434)),
                    title: Text(AppLocale.tr('Время выезда'), style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_plannedDeparture == null ? 'Сейчас' : _formatDeparture(_plannedDeparture!)),
                    trailing: TextButton(
                      onPressed: () => _openDepartureTime(refreshSheet),
                      child: Text(AppLocale.tr('Изменить')),
                    ),
                  ),
                  if (_plannedDeparture != null)
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () { setState(() => _plannedDeparture = null); refreshSheet(() {}); }, child: Text(AppLocale.tr('Сбросить время')))),
                  Text(AppLocale.tr('Выбранное время сохраняется как план. Оно пока не учитывается тестовым сервисом расчёта маршрута и пробок.'), style: TextStyle(fontSize: 11, color: Color(0xFF7B8792))),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFCC00),
                      foregroundColor: const Color(0xFF171717),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _isBuildingRoute || (_destination == null && destinationController.text.trim().isEmpty)
                        ? null
                        : () {
                            buildRouteAfterClose = true;
                            Navigator.pop(sheetContext);
                          },
                    icon: _isBuildingRoute
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.alt_route),
                    label: Text(AppLocale.tr('Построить маршрут'), style: TextStyle(fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    child: Text(AppLocale.tr('Готово без построения')),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final destinationQuery = destinationController.text.trim();
    final originQuery = originController.text.trim();
    destinationController.dispose();
    originController.dispose();
    if (searchOriginAfterClose && originQuery.isNotEmpty && mounted) {
      _searchController.text = originQuery;
      await _searchAddress(selectAsOrigin: true);
    } else if (searchAfterClose && destinationQuery.isNotEmpty && mounted) {
      _searchController.text = destinationQuery;
      await _searchAddress();
    }
    if (buildRouteAfterClose && mounted) {
      if (destinationQuery.isNotEmpty) {
        _searchController.text = destinationQuery;
        await _searchAddress();
      }
      if (mounted) await _buildRoute();
    }
  }

  Future<void> _openRouteMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD6D9DE), borderRadius: BorderRadius.circular(8))),
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: Text(AppLocale.tr('Маршрут'), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
            _menuTile(sheetContext, Icons.edit_road_outlined, 'Планирование маршрута', () { Navigator.pop(sheetContext); _openRoutePlanner(); }),
            _menuTile(sheetContext, Icons.edit_location_alt_outlined, 'Изменить маршрут', () { Navigator.pop(sheetContext); _openRoutePlanner(); }),
            _menuTile(sheetContext, Icons.add_location_alt_outlined, 'Добавить точку', () { Navigator.pop(sheetContext); _openRoutePlanner(); }),
            _menuTile(sheetContext, Icons.alt_route, 'Варианты маршрута', () { Navigator.pop(sheetContext); _openRouteAlternatives(); }),
            _menuTile(sheetContext, Icons.tune, 'Параметры маршрута', () { Navigator.pop(sheetContext); _openRoutePreferences(); }),
            _menuTile(sheetContext, Icons.share_outlined, 'Поделиться маршрутом', () { Navigator.pop(sheetContext); _shareRoute(); }),
            _menuTile(sheetContext, Icons.flag_outlined, 'Сообщить об ошибке', () { Navigator.pop(sheetContext); _reportRouteIssue(); }),
            const Divider(height: 18),
            _menuTile(sheetContext, Icons.place_outlined, 'Мои места', () { Navigator.pop(sheetContext); _openMyPlaces(); }),
            _menuTile(sheetContext, Icons.layers_outlined, 'Слои и офлайн-карты', () { Navigator.pop(sheetContext); _openMapLayers(); }),
            _menuTile(sheetContext, Icons.warning_amber_outlined, 'События на дороге', () { Navigator.pop(sheetContext); _openRoadEvents(); }),
            _menuTile(sheetContext, Icons.settings_outlined, 'Настройки', () { Navigator.pop(sheetContext); _openSettings(); }),
          ]),
        ),
      ),
    );
  }

  Widget _menuTile(BuildContext sheetContext, IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: const Color(0xFF555B63), size: 25),
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      onTap: onTap,
    );
  }

  String _routeSummary() {
    if (_routeDistanceMeters == null || _routeDurationSeconds == null) {
      return 'Маршрут ещё не построен';
    }
    final km = (_routeDistanceMeters! / 1000).toStringAsFixed(1);
    final minutes = (_routeDurationSeconds! / 60).round();
    return '$km км · около $minutes мин';
  }
 
  Future<void> _openStationNetworks() async {
    const networks = <String>[
      'Газпромнефть Казахстан',
      'Sinooil',
      'Qazaq Oil',
      'Gasenergy',
      'Helios',
      'TS',
      'Royal Petrol',
      'Compass',
      'Другие АЗС',
    ];
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('selected_station_networks');
    final initial = saved == null ? networks.toSet() : saved.toSet();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, refresh) => Scaffold(
            backgroundColor: const Color(0xFFFFFFFF),
            appBar: AppBar(
              title: Text(AppLocale.tr('Сети АЗС')),
              backgroundColor: const Color(0xFFFFFFFF),
              actions: [
                TextButton(
                  onPressed: () async {
                    await prefs.setStringList('selected_station_networks', initial.toList());
                    if (!pageContext.mounted) return;
                    Navigator.pop(pageContext);
                    final query = initial.isEmpty || initial.length == networks.length
                        ? 'АЗС'
                        : initial.where((name) => name != 'Другие АЗС').join(' OR ');
                    _searchController.text = query.isEmpty ? 'АЗС' : query;
                    _searchAddress();
                  },
                  child: Text(AppLocale.tr('Готово')),
                ),
              ],
            ),
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                const Text(
                  'Выбери сети, которые нужно учитывать при поиске заправок.',
                  style: TextStyle(color: Color(0xFF65717D), fontSize: 14),
                ),
                const SizedBox(height: 12),
                ...networks.map((network) => Card(
                  margin: const EdgeInsets.only(bottom: 7),
                  color: Colors.white,
                  child: CheckboxListTile(
                    value: initial.contains(network),
                    controlAffinity: ListTileControlAffinity.leading,
                    secondary: const Icon(Icons.local_gas_station_outlined, color: Color(0xFF343434)),
                    title: Text(network),
                    onChanged: (checked) => refresh(() {
                      if (checked == true) {
                        initial.add(network);
                      } else {
                        initial.remove(network);
                      }
                    }),
                  ),
                )),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => refresh(() {
                    if (initial.length == networks.length) {
                      initial.clear();
                    } else {
                      initial
                        ..clear()
                        ..addAll(networks);
                    }
                  }),
                  child: Text(initial.length == networks.length ? 'Снять все отметки' : 'Выбрать все сети'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Примечание: поиск использует названия сетей в OpenStreetMap. Если бренд не указан в данных карты, заправка может не попасть в отфильтрованный список.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7B8792)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundMapButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    Color iconColor = const Color(0xFF45484C),
  }) {
    return Material(
      color: Colors.white,
      elevation: 4,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: iconColor, size: 28),
      ),
    );
  }

  Widget _mapBottomItem(IconData icon, String label, VoidCallback onTap, {bool selected = false}) {
    final color = selected ? const Color(0xFFB88A00) : const Color(0xFF4B4E52);
    return Expanded(
      child: Tooltip(
        message: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: 58,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 23, color: color),
                const SizedBox(height: 3),
                Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      if (_routeOrigin != null)
        Marker(
          point: _routeOrigin!,
          width: 46,
          height: 46,
          child: const Icon(Icons.trip_origin, color: Color(0xFF269B68), size: 34),
        ),
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
      ..._routeStops.asMap().entries.map((entry) => Marker(
        point: entry.value,
        width: 38,
        height: 38,
        child: CircleAvatar(
          backgroundColor: const Color(0xFF343434),
          child: Text('${entry.key + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      )),
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
              onLongPress: (_, point) => _openPointMenu(point),
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(children: [
                  Expanded(
                    child: Material(
                      color: Colors.white,
                      elevation: 5,
                      borderRadius: BorderRadius.circular(22),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 3, 5, 3),
                        child: Row(children: [
                          const Icon(Icons.search, color: Color(0xFF343434), size: 24),
                          const SizedBox(width: 8),
                          Expanded(child: TextField(
                            controller: _searchController,
                            textInputAction: TextInputAction.search,
                            onSubmitted: (_) => _searchAddress(),
                            decoration: InputDecoration(hintText: AppLocale.tr('Куда едем?'), border: InputBorder.none, isDense: true),
                          )),
                          IconButton(
                            tooltip: AppLocale.tr('Найти'),
                            onPressed: _isSearching ? null : _searchAddress,
                            icon: _isSearching
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.arrow_forward, color: Color(0xFF343434)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          if (_navigationActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 74, 14, 0),
                  child: Material(
                    color: Colors.white,
                    elevation: 5,
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          const Icon(Icons.turn_right, size: 34, color: Color(0xFF343434)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _instructionIndex < _instructions.length
                                      ? _instructions[_instructionIndex].text
                                      : 'Продолжайте по маршруту',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                                ),
                                if (_instructionIndex < _instructions.length)
                                  Text(
                                    'Следующий манёвр · ${_instructions[_instructionIndex].distanceMeters.round()} м',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF626A73)),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: AppLocale.tr('Завершить навигацию'),
                            onPressed: () async {
                              setState(() {
                                _navigationActive = false;
                                _message = 'Навигация завершена.';
                              });
                              await _tts.stop();
                              await _startLiveLocationUpdates();
                            },
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_navigationActive)
            Positioned(
              left: 14,
              bottom: 100,
              child: Material(
                color: Colors.white,
                elevation: 5,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentSpeedKmh.round().toString(),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                      ),
                      Text(AppLocale.tr('км/ч'), style: TextStyle(fontSize: 11)),
                      const Divider(height: 10),
                      Text(AppLocale.tr('60'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(AppLocale.tr('лимит'), style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              ),
            ),
          if (_navigationActive)
            Positioned(
              left: 14,
              right: 14,
              bottom: 44,
              child: SafeArea(
                top: false,
                child: Material(
                  color: Colors.white,
                  elevation: 7,
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _routeDurationSeconds == null
                                    ? '—'
                                    : '${(_routeDurationSeconds! / 60).round()} мин',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                              ),
                              Text(
                                _routeDistanceMeters == null
                                    ? 'Расстояние неизвестно'
                                    : '${(_routeDistanceMeters! / 1000).toStringAsFixed(1)} км · осталось по расчёту',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF626A73)),
                              ),
                            ],
                          ),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFFFCC00),
                            foregroundColor: const Color(0xFF171717),
                          ),
                          onPressed: () async {
                            setState(() {
                              _navigationActive = false;
                              _message = 'Навигация завершена.';
                            });
                            await _tts.stop();
                            await _startLiveLocationUpdates();
                          },
                          child: Text(AppLocale.tr('Завершить маршрут')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 112,
            right: 14,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _roundMapButton(
                  icon: Icons.layers_outlined,
                  tooltip: AppLocale.tr('Слои карты'),
                  onPressed: _openMapLayers,
                ),
                const SizedBox(height: 10),
                _roundMapButton(
                  icon: Icons.explore_outlined,
                  tooltip: AppLocale.tr('На север'),
                  onPressed: () => _mapController.rotate(0),
                ),
              ],
            ),
          ),
          Positioned(
            left: 14,
            bottom: 86,
            child: _roundMapButton(
              icon: Icons.my_location,
              tooltip: AppLocale.tr('Моё местоположение'),
              iconColor: const Color(0xFF343434),
              onPressed: _isLocating ? null : () => unawaited(_locateMe()),
            ),
          ),
          if (_message.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 82,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: Material(
                      color: const Color(0xEEFFFFFF),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        child: Text(_message, maxLines: 2, overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Material(
                color: Colors.white,
                elevation: 7,
                borderRadius: BorderRadius.circular(24),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: Row(children: [
                    _mapBottomItem(Icons.map_outlined, AppLocale.tr('Карта'), () {
                      final camera = _mapController.camera;
                      _mapController.move(camera.center, camera.zoom);
                    }, selected: true),
                    _mapBottomItem(Icons.search, AppLocale.tr('Поиск'), _openSearchPanel),
                    _mapBottomItem(Icons.alt_route, AppLocale.tr('Маршрут'), _openRouteMenu),
                    _mapBottomItem(Icons.bookmark_border, AppLocale.tr('Избранное'), _openBookmarks),
                    _mapBottomItem(Icons.person_outline, AppLocale.tr('Профиль'), _openProfileMenu),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NavigatorPreferencesScreen extends StatefulWidget {
  const NavigatorPreferencesScreen({
    super.key,
    required this.onOpenSoundSettings,
    required this.onOpenRoutePreferences,
    required this.onOpenProfile,
    required this.onVoiceChanged,
  });

  final Future<void> Function() onOpenSoundSettings;
  final Future<void> Function() onOpenRoutePreferences;
  final Future<void> Function() onOpenProfile;
  final ValueChanged<bool> onVoiceChanged;

  @override
  State<NavigatorPreferencesScreen> createState() => _NavigatorPreferencesScreenState();
}

class _NavigatorPreferencesScreenState extends State<NavigatorPreferencesScreen> {
  bool _voiceEnabled = true;
  bool _avoidTolls = false;
  bool _loading = true;
  String _appLanguage = 'ru';

  String get _appLanguageLabel => const {'ru': 'Русский', 'kk': 'Қазақша', 'en': 'English'}[_appLanguage] ?? 'Русский';

  Future<void> _chooseAppLanguage() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppLocale.tr('Язык приложения')),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'ru'), child: Text(AppLocale.tr('Русский'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'kk'), child: Text(AppLocale.tr('Қазақша'))),
          SimpleDialogOption(onPressed: () => Navigator.pop(context, 'en'), child: Text(AppLocale.language == 'en' ? 'English' : 'English')),
        ],
      ),
    );
    if (selected == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', selected);
    AppLocale.language = selected;
    if (mounted) setState(() => _appLanguage = selected);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _voiceEnabled = (prefs.getInt('voice_mode') ?? 3) != 0;
      _avoidTolls = prefs.getBool('avoid_tolls') ?? false;
      _appLanguage = prefs.getString('app_language') ?? 'ru';
      _loading = false;
    });
  }

  Future<void> _setVoice(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    final mode = value ? 3 : 0;
    await prefs.setInt('voice_mode', mode);
    if (!mounted) return;
    setState(() => _voiceEnabled = value);
    widget.onVoiceChanged(value);
  }

  Future<void> _setAvoidTolls(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('avoid_tolls', value);
    if (!mounted) return;
    setState(() => _avoidTolls = value);
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'BAKE Navigator',
      applicationLegalese: 'Навигационное приложение BAKE.',
      children: const [
        Text(AppLocale.tr('Часть функций зависит от подключённых источников картографических и дорожных данных.')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(AppLocale.tr('Настройки')),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.volume_up_outlined),
                  title: Text(AppLocale.tr('Голосовые подсказки')),
                  value: _voiceEnabled,
                  onChanged: _setVoice,
                ),
                ListTile(
                  leading: const Icon(Icons.alt_route),
                  title: Text(AppLocale.tr('Предпочтения маршрута')),
                  subtitle: Text(AppLocale.tr('Быстрый')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenRoutePreferences,
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.toll_outlined),
                  title: Text(AppLocale.tr('Избегать платных дорог')),
                  value: _avoidTolls,
                  onChanged: _setAvoidTolls,
                ),
                ListTile(
                  leading: const Icon(Icons.straighten_outlined),
                  title: Text(AppLocale.tr('Единицы измерения')),
                  subtitle: Text(AppLocale.tr('км, м')),
                ),
                ListTile(
                  leading: const Icon(Icons.language_outlined),
                  title: Text(AppLocale.tr('Язык приложения')),
                  subtitle: Text(_appLanguageLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _chooseAppLanguage,
                ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(AppLocale.tr('Профиль')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenProfile,
                ),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(AppLocale.tr('О приложении')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _showAbout,
                ),
                const SizedBox(height: 12),
              ],
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
  double _voiceVolume = 1.0;
  double _voiceRate = 0.48;
  bool _avoidTolls = false;
  bool _avoidUnpaved = false;


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
    _voiceVolume = prefs.getDouble('voice_volume') ?? 1.0;
    _voiceRate = prefs.getDouble('voice_rate') ?? 0.48;
    _avoidTolls = prefs.getBool('avoid_tolls') ?? false;
    _avoidUnpaved = prefs.getBool('avoid_unpaved') ?? false;
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

  Future<void> _saveNavigationPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('voice_volume', _voiceVolume);
    await prefs.setDouble('voice_rate', _voiceRate);
    await prefs.setBool('avoid_tolls', _avoidTolls);
    await prefs.setBool('avoid_unpaved', _avoidUnpaved);
  }

  Future<void> _saveVehicle() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('vehicle_make', _vehicleMake.text.trim());
    await prefs.setString('vehicle_model', _vehicleModel.text.trim());
    await prefs.setString('vehicle_color', _vehicleColor.text.trim());
    await prefs.setString('vehicle_plate', _vehiclePlate.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocale.tr('Данные автомобиля сохранены на этом телефоне.'))),
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
      appBar: AppBar(title: Text(AppLocale.tr('Настройки BAKE Navigator'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 4),
                Text(AppLocale.tr('Автомобиль'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(AppLocale.tr('Эти сведения сохраняются только на этом телефоне.')),
                const SizedBox(height: 10),
                TextField(controller: _vehicleMake, decoration: InputDecoration(labelText: AppLocale.tr('Марка автомобиля'))),
                TextField(controller: _vehicleModel, decoration: InputDecoration(labelText: AppLocale.tr('Модель'))),
                TextField(controller: _vehicleColor, decoration: InputDecoration(labelText: AppLocale.tr('Цвет'))),
                TextField(controller: _vehiclePlate, decoration: InputDecoration(labelText: AppLocale.tr('Государственный номер'))),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _saveVehicle, icon: const Icon(Icons.save_outlined), label: Text(AppLocale.tr('Сохранить'))),
                const SizedBox(height: 22),
                Text(AppLocale.tr('Голосовые подсказки'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${AppLocale.tr('Громкость')} · ${(_voiceVolume * 100).round()}%'),
                      Slider(
                        value: _voiceVolume,
                        min: 0,
                        max: 1,
                        divisions: 10,
                        label: '${(_voiceVolume * 100).round()}%',
                        onChanged: (value) {
                          setState(() => _voiceVolume = value);
                          unawaited(_saveNavigationPreferences());
                        },
                      ),
                      Text('${AppLocale.tr('Скорость речи')} · ${_voiceRate.toStringAsFixed(2)}'),
                      Slider(
                        value: _voiceRate,
                        min: 0.25,
                        max: 0.75,
                        divisions: 10,
                        label: _voiceRate.toStringAsFixed(2),
                        onChanged: (value) {
                          setState(() => _voiceRate = value);
                          _saveNavigationPreferences();
                        },
                      ),
                      Text(AppLocale.tr('Изменения сохраняются на этом телефоне и применяются при следующем запуске навигатора.'), style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),
                Text(AppLocale.tr('Параметры маршрута'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                Card(
                  child: Column(children: [
                    SwitchListTile(
                      value: _avoidTolls,
                      title: Text(AppLocale.tr('Избегать платных дорог')),
                      onChanged: (value) {
                        setState(() => _avoidTolls = value);
                        _saveNavigationPreferences();
                      },
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _avoidUnpaved,
                      title: Text(AppLocale.tr('Избегать грунтовых дорог')),
                      onChanged: (value) {
                        setState(() => _avoidUnpaved = value);
                        _saveNavigationPreferences();
                      },
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Text(AppLocale.tr('Фильтры сохраняются, но текущий тестовый сервис маршрутов OSRM пока не применяет их при расчёте.'), style: TextStyle(fontSize: 12, color: Colors.black54)),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                Text(AppLocale.tr('Офлайн-карты'), style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
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
                          title: Text(AppLocale.tr('Офлайн-карта')),
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
                            label: Text(AppLocale.tr('Отключить офлайн-карту')),
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

