import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:mbtiles/mbtiles.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_map_tiles_mbtiles/vector_map_tiles_mbtiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'kazakh_voice_service.dart';
import 'services/road_alert_service.dart';
import 'services/offline_address_search.dart';
import 'screens/road_report_center.dart';
import 'screens/openfreemap_experiment.dart';
import 'services/road_report_sync_service.dart';
import 'services/valhalla_archive_validator.dart';


// Offline label layers for the OpenMapTiles schema in shymkent.mbtiles.
// This renderer paints text with Flutter's local/system fonts; PBF
// glyph URLs are not used by vector_tile_renderer.
vtr.Theme _buildBakeOfflineVectorTheme() {
  final base = vtr.ProvidedThemes.lightTheme();
  final roads = vtr.ThemeReader().read({
    'id': 'bake-shymkent-road-widths', 'metadata': {'version': '1'},
    'sources': {'openmaptiles': {'type': 'vector'}},
    'layers': [
      {'id': 'bake_transportation_casing', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'transportation', 'minzoom': 13,
       'filter': ['in', 'class', 'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'residential', 'unclassified', 'service', 'living_street'],
       'layout': {'line-cap': 'round', 'line-join': 'round'},
       'paint': {'line-color': '#FFFFFF', 'line-width': ['interpolate', ['linear'], ['zoom'], 13, 9.0, 14, 10.8, 15, 13.0, 16, 16.0, 17, 19.0, 18, 22.0]}},
      {'id': 'bake_transportation_wide', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'transportation', 'minzoom': 13,
       'filter': ['in', 'class', 'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'minor', 'residential', 'unclassified', 'service', 'living_street'],
       'layout': {'line-cap': 'round', 'line-join': 'round'},
       'paint': {'line-color': '#B7C2CE', 'line-width': ['interpolate', ['linear'], ['zoom'], 13, 5.4, 14, 6.8, 15, 8.8, 16, 10.8, 17, 13.5, 18, 16.0]}},
    ],
  });
  final labels = vtr.ThemeReader().read({
    'id': 'bake-shymkent-offline-labels',
    'metadata': {'version': '1'},
    'sources': {
      'openmaptiles': {'type': 'vector'},
    },
    'layers': [
      {
        'id': 'bake_transportation_name',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'transportation_name',
        'minzoom': 10,
        'layout': {
          'symbol-placement': 'line',
          'text-anchor': 'center',
          // OpenMapTiles stores the local OSM language in its canonical name
          // field. This offline renderer uses local Flutter fonts, not PBF glyphs.
          'text-field': [
          'coalesce',
          ['get', 'name:latin'],
          ['get', 'name:nonlatin'],
          ['get', 'name:ru'],
          ['get', 'name'],
          ['get', 'name:kk'],
          ['get', 'name_ru'],
          ['get', 'name_kk'],
        ],
          'text-font': ['Roboto'],
          'text-size': 14,
          'text-max-width': 12,
          'text-offset': [0, 0.15],
          'text-allow-overlap': false,
        },
        'paint': {
          'text-color': '#111111',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2.5,
        },
      },
      {
        'id': 'bake_transportation_fallback_name',
        'type': 'symbol',
        'source': 'openmaptiles',
        // Some regional OpenMapTiles exports keep road names directly in
        // transportation instead of transportation_name.
        'source-layer': 'transportation',
        'minzoom': 12,
        'layout': {
          'symbol-placement': 'line',
          'text-anchor': 'center',
          'text-field': [
            'coalesce',
            ['get', 'name'],
            ['get', 'name:latin'],
            ['get', 'name:nonlatin'],
            ['get', 'name:ru'],
            ['get', 'name:kk'],
            ['get', 'name_ru'],
            ['get', 'name_kk'],
          ],
          'text-font': ['Roboto'],
          'text-size': 13,
          'text-max-width': 12,
          'text-allow-overlap': false,
        },
        'paint': {
          'text-color': '#111111',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2.5,
        },
      },
      {
        'id': 'bake_place_labels',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'place',
        'minzoom': 11,
        'layout': {
          'symbol-placement': 'point',
          'text-anchor': 'center',
          'text-field': [
          'coalesce',
          ['get', 'name:latin'],
          ['get', 'name:nonlatin'],
          ['get', 'name:ru'],
          ['get', 'name'],
          ['get', 'name:kk'],
          ['get', 'name_ru'],
          ['get', 'name_kk'],
        ],
          'text-font': ['Roboto'],
          'text-size': 14,
          'text-max-width': 10,
          'text-offset': [0, 0.1],
          'text-allow-overlap': false,
        },
        'paint': {
          'text-color': '#111111',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2.5,
        },
      },
      {
        'id': 'bake_boundary_labels',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'boundary',
        'minzoom': 7,
        'layout': {
          'symbol-placement': 'line',
          'text-anchor': 'center',
          'text-field': [
          'coalesce',
          ['get', 'name:latin'],
          ['get', 'name:nonlatin'],
          ['get', 'name:ru'],
          ['get', 'name'],
          ['get', 'name:kk'],
          ['get', 'name_ru'],
          ['get', 'name_kk'],
        ],
          'text-font': ['Roboto'],
          'text-size': 12,
          'text-max-width': 12,
        },
        'paint': {
          'text-color': '#697386',
          'text-halo-color': '#ffffff',
          'text-halo-width': 2,
        },
      },
      {
        'id': 'bake_transportation_name_direct_fallback',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'transportation_name',
        // The inspected BBBike MBTiles schema exposes street names as
        // "name:latin" in transportation_name (not as plain "name").
        // Read that exact field directly as a fallback label layer.
        'minzoom': 8,
        'filter': ['has', 'name:latin'],
        'layout': {
          'symbol-placement': 'line',
          'text-anchor': 'center',
          'text-field': '{name:latin}',
          'text-font': ['Roboto'],
          'text-size': 13,
          'text-max-width': 12,
          'text-offset': [0, 0.15],
          'text-allow-overlap': false,
        },
        'paint': {
          'text-color': '#111111',
          'text-halo-color': '#FFFFFF',
          'text-halo-width': 2.5,
        },
      },
      {
        'id': 'bake_house_numbers',
        'type': 'symbol',
        'source': 'openmaptiles',
        'source-layer': 'housenumber',
        'minzoom': 14,
        'layout': {
          'symbol-placement': 'point',
          'text-anchor': 'center',
          'text-field': '{housenumber}',
          'text-font': ['Roboto'],
          'text-size': 11,
          'text-offset': [0, 0],
        },
        'paint': {
          'text-color': '#4b4b4b',
          'text-halo-color': '#ffffff',
          'text-halo-width': 2,
        },
      },
    ],
  });

  // Remove the default light-theme road strokes: they are drawn above
  // BAKE's custom strokes and contain the orange casing/fill colors.
  // Keep railways, one-way arrows, shields, buildings and symbol layers.
  final baseWithoutDefaultRoadStrokes = base.layers.where((layer) {
    final isDefaultRoadGeometry = layer.id.startsWith('road_') ||
        layer.id.startsWith('bridge_') ||
        layer.id.startsWith('tunnel_');
    final isRailOrArrow = layer.id.contains('rail') ||
        layer.id.contains('one_way_arrow');
    // Remove road line AND fill/casing/pattern layers. The orange
    // road_area_pattern is a fill layer, not a line layer.
    // Keep every symbol layer, including road_label and road_shield.
    return !isDefaultRoadGeometry ||
        isRailOrArrow ||
        layer.type == vtr.ThemeLayerType.symbol;
  }).toList(growable: false);

  // Built-in road labels and BAKE's regional name:* fallback labels stay
  // above all road geometry.
  final firstSymbolIndex = baseWithoutDefaultRoadStrokes.indexWhere(
    (layer) => layer.type == vtr.ThemeLayerType.symbol,
  );
  final orderedLayers = firstSymbolIndex < 0
      ? <vtr.ThemeLayer>[
          ...baseWithoutDefaultRoadStrokes,
          ...roads.layers,
          ...labels.layers,
        ]
      : <vtr.ThemeLayer>[
          ...baseWithoutDefaultRoadStrokes.take(firstSymbolIndex),
          ...roads.layers,
          ...baseWithoutDefaultRoadStrokes.skip(firstSymbolIndex),
          ...labels.layers,
        ];
  return vtr.Theme(
    id: 'bake-shymkent-offline',
    version: '5',
    layers: orderedLayers,
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release builds normally replace failed widgets with an uninformative grey
  // screen. Keep the actual exception visible so device-only map failures can
  // be diagnosed instead of appearing as a blank screen.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('BAKE RELEASE WIDGET ERROR: ${details.exceptionAsString()}');
    debugPrintStack(stackTrace: details.stack);
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: const Color(0xFFFFFFFF),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: SelectableText(
              'BAKE ERROR\\n\\n${details.exceptionAsString()}',
              style: const TextStyle(
                color: Color(0xFFB00020),
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  };
  final startupWatch = Stopwatch()..start();
  // Start local preferences loading alongside cloud SDK initialization so
  // independent startup work does not run sequentially.
  final prefsFuture = SharedPreferences.getInstance();
  try {
    final cloudInitWatch = Stopwatch()..start();
    await RoadReportSyncService.initialize();
    debugPrint('BAKE STARTUP phase=supabase_init duration_ms=${cloudInitWatch.elapsedMilliseconds}');
  } catch (error) {
    debugPrint('BAKE road report cloud sync is unavailable: $error');
    debugPrint(
      'BAKE Supabase config: ${RoadReportSyncService.configurationSummary}; '
      'problem=${RoadReportSyncService.configurationProblem ?? 'none'}',
    );
  }
  final prefs = await prefsFuture;
  debugPrint('BAKE STARTUP phase=before_run_app duration_ms=${startupWatch.elapsedMilliseconds}');
  // One-time migration: make Kazakh the default app and navigation language.
  if (!(prefs.getBool('kazakh_primary_language_v1') ?? false)) {
    await prefs.setString('app_language', 'kk');
    await prefs.setString('navigation_language', 'kk-KZ');
    await prefs.remove('voice_name');
    await prefs.remove('voice_locale');
    await prefs.setBool('kazakh_primary_language_v1', true);
  }
  AppLocale.language = prefs.getString('app_language') ?? 'kk';
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
  static String language = 'kk';

  static const Map<String, Map<String, String>> _translations = {
    'kk': {
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
      'Сохранить': 'Сақтау',
      'Избегать грунтовых дорог': 'Топырақ жолдардан аулақ болу',
      'Офлайн-карта': 'Офлайн карта',
      'Отключить офлайн-карту': 'Офлайн картаны өшіру',
      'Карта': 'Карта',
      'Поиск': 'Іздеу',
      'Маршрут': 'Маршрут',
      'Завершить маршрут': 'Маршрутты аяқтау',
      'Построить маршрут': 'Маршрут құру',
      'Поехали': 'Жолға шығу',
      'Отмена': 'Болдырмау',
      'Готово': 'Дайын',
      'Закрыть': 'Жабу',
      'Понятно': 'Түсінікті',
      'Добавить место': 'Орын қосу',
      'Дом': 'Үй',
      'Работа': 'Жұмыс',
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
      'Пробки': 'Кептелістер',
      'Дорожные события': 'Жол оқиғалары',
      'Спутниковая карта': 'Спутниктік карта',
      'Карта Казахстана': 'Қазақстан картасы',
      'Шымкент и область': 'Шымкент және облыс',
      'Выбрать MBTiles-файл': 'MBTiles файлын таңдау',
      'Язык голосовых подсказок': 'Дауыстық нұсқаулар тілі',
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
      'Навигационное приложение BAKE.': 'BAKE навигациялық қолданбасы.',
      'Часть функций зависит от подключённых источников картографических и дорожных данных.': 'Кейбір функциялар карта және жол деректерінің қосылған көздеріне байланысты.',
      'Здесь будет раздел помощи по поиску, маршрутам, GPS и офлайн-картам. Можно подготовить обращение и скопировать его, чтобы отправить удобным способом.': 'Мұнда іздеу, маршруттар, GPS және офлайн карталар бойынша көмек бөлімі болады. Өтініш дайындап, оны жіберу үшін көшіруге болады.',
      'Канал отправки обращений на сервер ещё не подключён. Эта страница не отправляет сообщения автоматически.': 'Өтініштерді серверге жіберу арнасы әлі қосылмаған. Бұл бет хабарламаларды автоматты түрде жібермейді.',
      'Подготовить обращение': 'Өтініш дайындау',
      'Обращение в поддержку BAKE Navigator. Опишите проблему и приложите скриншот.': 'BAKE Navigator қолдау қызметіне өтініш. Мәселені сипаттап, скриншот тіркеңіз.',
      'Шаблон обращения скопирован.': 'Өтініш үлгісі көшірілді.',
      'Раздел предназначен для подготовки карточки нового места: название, категория, адрес и координаты. Для добавления объекта на общую карту потребуется серверная проверка.': 'Бұл бөлім жаңа орын карточкасын дайындауға арналған: атауы, санаты, мекенжайы және координаттары. Нысанды ортақ картаға қосу үшін серверлік тексеру қажет.',
      'Публикация объектов пока не подключена. Ничего не будет отправлено без сервера.': 'Нысандарды жариялау әлі қосылмаған. Серверсіз ештеңе жіберілмейді.',
      'Здесь будет история поездок и сохранённые бронирования BAKE, когда приложение получит соответствующий сервис.': 'Қолданба тиісті қызметке қосылған кезде мұнда сапарлар тарихы мен BAKE брондаулары сақталады.',
      'История пока пуста: сервис бронирований и учёт поездок ещё не подключены.': 'Тарих әзірге бос: брондау қызметі мен сапарларды есепке алу қосылмаған.',
      'Раздел для просмотра сообщений об ошибках карты и предложенных исправлений.': 'Карта қателері туралы хабарламалар мен ұсынылған түзетулерді көруге арналған бөлім.',
      'Лента пока недоступна: серверный источник отзывов и модерация ещё не подключены.': 'Таспа әзірге қолжетімсіз: пікірлердің серверлік көзі мен модерация қосылмаған.',
      'Отдельная музыкальная панель должна показывать только реально доступное управление воспроизведением на телефоне или подключённом музыкальном сервисе. В ней будут текущий трек и доступные системные действия, если Android предоставит их.': 'Музыка панелі телефондағы немесе қосылған музыкалық қызметтегі қолжетімді ойнату басқаруын ғана көрсетеді. Android ұсынса, онда ағымдағы трек пен жүйелік әрекеттер көрсетіледі.',
      'Музыкальный провайдер и управление медиасессией пока не подключены. BAKE не показывает вымышленные треки, исполнителей и обложки.': 'Музыкалық провайдер мен медиа сеансын басқару әлі қосылмаған. BAKE ойдан шығарылған тректерді, орындаушыларды немесе мұқабаларды көрсетпейді.',
      'Будущий раздел дополнительных возможностей BAKE Navigator. Здесь будут описаны условия, если будет создана собственная подписка.': 'BAKE Navigator қосымша мүмкіндіктерінің болашақ бөлімі. Жеке жазылым жасалған жағдайда шарттары осында көрсетіледі.',
      'Подписка BAKE Plus пока не создана. Оплата и платные функции не включены.': 'BAKE Plus жазылымы әлі жасалмаған. Төлем және ақылы функциялар қосылмаған.',
      'Добавьте домашний адрес': 'Үй мекенжайын қосыңыз',
      'Добавьте адрес работы': 'Жұмыс мекенжайын қосыңыз',
      'Начальная точка определяется по GPS': 'Бастапқы нүкте GPS арқылы анықталады',
      'Начальная точка выбрана вручную': 'Бастапқы нүкте қолмен таңдалды',
      'Моё местоположение (ожидаем GPS)': 'Менің орналасқан жерім (GPS күтілуде)',
      'Удерживайте нужную точку карты и выберите «Добавить как промежуточную остановку».': 'Картадағы қажетті нүктені басып тұрып, «Аралық аялдама ретінде қосу» таңдаңыз.',
      'Выбранное время сохраняется как план. Оно пока не учитывается тестовым сервисом расчёта маршрута и пробок.': 'Таңдалған уақыт жоспар ретінде сақталады. Әзірге ол маршрут пен кептелісті есептейтін сынақ қызметінде ескерілмейді.',
      'Импортируем…': 'Импортталуда…',
      'Импортировать MBTiles-карту': 'MBTiles картасын импорттау',
      'Настройки': 'Баптаулар',
      'Закладки': 'Бетбелгілер',
      'Мои места': 'Менің орындарым',
      'События на дороге': 'Жол оқиғалары',
      'BAKE Plus': 'BAKE Plus',
      'Выкл.': 'Өшірулі',
      'Важные': 'Маңызды',
      'Подсказки': 'Нұсқаулар',
      'Все': 'Барлығы',
      'ДТП': 'ЖКО',
      'Ремонт дороги': 'Жол жөндеу',
      'Камера': 'Камера',
      'Опасность': 'Қауіп',
      'Другое': 'Басқа',
      'Выберите начальную точку': 'Бастапқы нүктені таңдаңыз',
      'Выберите пункт назначения': 'Межелі орынды таңдаңыз',
      'Пункт назначения не выбран': 'Межелі орын таңдалмаған',
      'Текущее местоположение': 'Ағымдағы орналасқан жер',
      'Текущая геопозиция': 'Ағымдағы геопозиция',
      'Можно добавить не более пяти промежуточных остановок.': 'Бес аралық аялдамадан артық қосуға болмайды.',
      'Промежуточная остановка добавлена. Перестройте маршрут.': 'Аралық аялдама қосылды. Маршрутты қайта құрыңыз.',
      'АЗС': 'ЖҚС',
      'Рестораны': 'Мейрамханалар',
      'Магазины': 'Дүкендер',
      'Гостиницы': 'Қонақүйлер',
      'Аптеки': 'Дәріханалар',
      'Ещё': 'Тағы',
      'Кафе': 'Кафелер',
      'Банкоматы': 'Банкоматтар',
      'Автомойки': 'Автожуу орындары',
      'Автосервисы': 'Автосервистер',
      'Больницы': 'Ауруханалар',
      'Кинотеатры': 'Кинотеатрлар',
      'Пока нет сохранённых сообщений о дорожных событиях.': 'Әзірге жол оқиғалары туралы сақталған хабарламалар жоқ.',
      'Дорожное событие': 'Жол оқиғасы',
      'Геопозиция': 'Геолокация',
      'Планирование маршрута': 'Маршрутты жоспарлау',
      'Откуда': 'Қайдан',
      'Изменить маршрут': 'Маршрутты өзгерту',
      'Добавить точку': 'Нүкте қосу',
      'Параметры маршрута': 'Маршрут параметрлері',
      'Поделиться маршрутом': 'Маршрутпен бөлісу',
      'Сообщить об ошибке': 'Қате туралы хабарлау',
      'Слои и офлайн-карты': 'Қабаттар және офлайн карталар',
      'Заправки': 'Жанармай құю станциялары',
      'Поддержка': 'Қолдау',
      'Загрузка карт': 'Карталарды жүктеу',
      'Изменить карту и слои': 'Карта мен қабаттарды өзгерту',
      'Поделиться геопозицией': 'Геолокациямен бөлісу',
      'Парковки': 'Тұрақ орындары',
      'Бронирования и история заказов': 'Брондаулар және тапсырыстар тарихы',
      'Лента отзывов и исправлений': 'Пікірлер мен түзетулер таспасы',
      'Музыка': 'Музыка',
      'Маршрут ещё не построен': 'Маршрут әлі құрылмаған',
      'Следующий манёвр': 'Келесі маневр',
      'Навигация завершена.': 'Навигация аяқталды.',      'Расстояние неизвестно': 'Қашықтық белгісіз',
      'Снять все отметки': 'Барлық белгіні алып тастау',
      'Выбрать все сети': 'Барлық желіні таңдау',
      'Для выбранного языка голоса не найдены. Установите голосовые данные в настройках преобразования текста в речь Android.': 'Таңдалған тілге арналған дауыс табылмады. Android мәтінді сөйлеуге түрлендіру баптауларынан дауыс деректерін орнатыңыз.',
      'Изменить точки': 'Нүктелерді өзгерту',
      'Промежуточные остановки: ': 'Аралық аялдамалар: ',
      'Вариант ': 'Нұсқа ',
      'Куда едем?': 'Қайда барамыз?',
      'Найти': 'Іздеу',
      'Опишите, что не так': 'Мәселені сипаттаңыз',
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
      'На север': 'Солтүстікке',
      'Моё местоположение': 'Менің орналасқан жерім',
      'Координаты: ': 'Координаттар: ',
      'Варианты маршрута': 'Маршрут нұсқалары',
      'Недавние запросы': 'Соңғы іздеулер',
      'Здесь появятся адреса и места, которые вы искали.': 'Мұнда іздеген мекенжайлар мен орындар көрсетіледі.',
      'Категории': 'Санаттар',
      'Слои карты': 'Карта қабаттары',
      'Избранное': 'Таңдаулылар',
      'Выбери сети, которые нужно учитывать при поиске заправок.': 'Жанармай іздеу кезінде ескерілетін желілерді таңдаңыз.',
      'Примечание: поиск использует названия сетей в OpenStreetMap. Если бренд не указан в данных карты, заправка может не попасть в отфильтрованный список.': 'Ескерту: іздеу OpenStreetMap картасындағы желі атауларын пайдаланады. Егер бренд карта деректерінде көрсетілмесе, жанармай құю станциясы сүзілген тізімге кірмеуі мүмкін.',
      'Сохранённых пользовательских мест пока нет.': 'Әзірге сақталған жеке орындар жоқ.',
      'Сначала постройте маршрут.': 'Алдымен маршрут құрыңыз.',
      'Поддержка BAKE': 'BAKE қолдауы',
      'Разместить объект': 'Нысанды орналастыру',
      'Бронирования и история': 'Брондаулар және тарих',
      'Отзывы и исправления': 'Пікірлер және түзетулер',
      'Музыка BAKE': 'BAKE музыкасы',
      'Готовый MBTiles-файл пока не подключён.': 'Дайын MBTiles файлы әлі қосылмаған.',
      'Офлайн-карта подключена на этом устройстве.': 'Офлайн карта осы құрылғыда қосылған.',
      'Офлайн-карты': 'Офлайн карталар',
      'Исходный OSM PBF не является готовой MBTiles-картой. Для офлайн-режима нужны отдельно подготовленные тайлы.': 'Бастапқы OSM PBF дайын MBTiles картасы емес. Офлайн режим үшін алдын ала дайындалған тайлдар қажет.',
      'Импортировать MBTiles-файл с телефона': 'Телефоннан MBTiles файлын импорттау',
      'Звуковое сопровождение': 'Дыбыстық сүйемелдеу',
      'Изменения сохраняются на этом телефоне и применяются при следующем запуске навигатора.': 'Өзгерістер осы телефонда сақталып, навигатор келесі іске қосылғанда қолданылады.',
      'Фильтры сохраняются, но текущий тестовый сервис маршрутов OSRM пока не применяет их при расчёте.': 'Сүзгілер сақталады, бірақ OSRM сынақ қызметі оларды әзірге маршрут есебінде қолданбайды.',
      'Сначала сохраните файл карты в память телефона, затем выберите его.': 'Алдымен карта файлын телефон жадына сақтап, содан кейін таңдаңыз.',
      'Голос телефона': 'Телефон дауысы',
    },
    'en': {
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
      'Сохранить': 'Save',
      'Избегать грунтовых дорог': 'Avoid unpaved roads',
      'Офлайн-карта': 'Offline map',
      'Отключить офлайн-карту': 'Disable offline map',
      'Карта': 'Map',
      'Поиск': 'Search',
      'Маршрут': 'Route',
      'Завершить маршрут': 'End navigation',
      'Построить маршрут': 'Build route',
      'Поехали': 'Go',
      'Отмена': 'Cancel',
      'Готово': 'Done',
      'Закрыть': 'Close',
      'Понятно': 'Got it',
      'Добавить место': 'Add place',
      'Дом': 'Home',
      'Работа': 'Work',
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
      'Пробки': 'Traffic',
      'Дорожные события': 'Road incidents',
      'Спутниковая карта': 'Satellite map',
      'Карта Казахстана': 'Map of Kazakhstan',
      'Шымкент и область': 'Shymkent and region',
      'Выбрать MBTiles-файл': 'Choose MBTiles file',
      'Язык голосовых подсказок': 'Voice guidance language',
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
      'Навигационное приложение BAKE.': 'BAKE navigation app.',
      'Часть функций зависит от подключённых источников картографических и дорожных данных.': 'Some features depend on connected map and road data sources.',
      'Здесь будет раздел помощи по поиску, маршрутам, GPS и офлайн-картам. Можно подготовить обращение и скопировать его, чтобы отправить удобным способом.': 'This section will provide help with search, routes, GPS, and offline maps. You can prepare and copy a support request to send it yourself.',
      'Канал отправки обращений на сервер ещё не подключён. Эта страница не отправляет сообщения автоматически.': 'The server support channel is not connected yet. This page does not send messages automatically.',
      'Подготовить обращение': 'Prepare a request',
      'Обращение в поддержку BAKE Navigator. Опишите проблему и приложите скриншот.': 'BAKE Navigator support request. Describe the issue and attach a screenshot.',
      'Шаблон обращения скопирован.': 'Request template copied.',
      'Раздел предназначен для подготовки карточки нового места: название, категория, адрес и координаты. Для добавления объекта на общую карту потребуется серверная проверка.': 'This section is for preparing a new place listing: name, category, address, and coordinates. Server review will be required to add it to the shared map.',
      'Публикация объектов пока не подключена. Ничего не будет отправлено без сервера.': 'Place publishing is not connected yet. Nothing will be submitted without a server.',
      'Здесь будет история поездок и сохранённые бронирования BAKE, когда приложение получит соответствующий сервис.': 'Your trip history and saved BAKE bookings will appear here when the relevant service is connected.',
      'История пока пуста: сервис бронирований и учёт поездок ещё не подключены.': 'History is empty: bookings and trip tracking are not connected yet.',
      'Раздел для просмотра сообщений об ошибках карты и предложенных исправлений.': 'View map error reports and suggested corrections here.',
      'Лента пока недоступна: серверный источник отзывов и модерация ещё не подключены.': 'The feed is unavailable: server reviews and moderation are not connected yet.',
      'Отдельная музыкальная панель должна показывать только реально доступное управление воспроизведением на телефоне или подключённом музыкальном сервисе. В ней будут текущий трек и доступные системные действия, если Android предоставит их.': 'The music panel will show only playback controls actually available on your phone or connected music service. It will show the current track and system actions if Android provides them.',
      'Музыкальный провайдер и управление медиасессией пока не подключены. BAKE не показывает вымышленные треки, исполнителей и обложки.': 'The music provider and media session controls are not connected yet. BAKE does not display fictional tracks, artists, or cover art.',
      'Будущий раздел дополнительных возможностей BAKE Navigator. Здесь будут описаны условия, если будет создана собственная подписка.': 'A future section for additional BAKE Navigator features. Terms will appear here if a subscription is created.',
      'Подписка BAKE Plus пока не создана. Оплата и платные функции не включены.': 'BAKE Plus subscription has not been created. Payments and paid features are not enabled.',
      'Добавьте домашний адрес': 'Add your home address',
      'Добавьте адрес работы': 'Add your work address',
      'Начальная точка определяется по GPS': 'Starting point is detected by GPS',
      'Начальная точка выбрана вручную': 'Starting point selected manually',
      'Моё местоположение (ожидаем GPS)': 'My location (waiting for GPS)',
      'Удерживайте нужную точку карты и выберите «Добавить как промежуточную остановку».': 'Long-press the desired map point and choose “Add as an intermediate stop”.',
      'Выбранное время сохраняется как план. Оно пока не учитывается тестовым сервисом расчёта маршрута и пробок.': 'The selected time is saved as a plan. It is not yet used by the test route and traffic service.',
      'Импортируем…': 'Importing…',
      'Импортировать MBTiles-карту': 'Import MBTiles map',
      'Настройки': 'Settings',
      'Закладки': 'Bookmarks',
      'Мои места': 'My places',
      'События на дороге': 'Road events',
      'BAKE Plus': 'BAKE Plus',
      'Выкл.': 'Off',
      'Важные': 'Important',
      'Подсказки': 'Guidance',
      'Все': 'All',
      'ДТП': 'Accident',
      'Ремонт дороги': 'Roadworks',
      'Камера': 'Camera',
      'Опасность': 'Hazard',
      'Другое': 'Other',
      'Выберите начальную точку': 'Select starting point',
      'Выберите пункт назначения': 'Select destination',
      'Пункт назначения не выбран': 'No destination selected',
      'Текущее местоположение': 'Current location',
      'Текущая геопозиция': 'Current location',
      'Можно добавить не более пяти промежуточных остановок.': 'You can add up to five intermediate stops.',
      'Промежуточная остановка добавлена. Перестройте маршрут.': 'Intermediate stop added. Recalculate the route.',
      'АЗС': 'Gas stations',
      'Рестораны': 'Restaurants',
      'Магазины': 'Shops',
      'Гостиницы': 'Hotels',
      'Аптеки': 'Pharmacies',
      'Ещё': 'More',
      'Кафе': 'Cafes',
      'Банкоматы': 'ATMs',
      'Автомойки': 'Car washes',
      'Автосервисы': 'Auto services',
      'Больницы': 'Hospitals',
      'Кинотеатры': 'Cinemas',
      'Пока нет сохранённых сообщений о дорожных событиях.': 'No saved road event reports yet.',
      'Дорожное событие': 'Road event',
      'Геопозиция': 'Location',
      'Планирование маршрута': 'Route planning',
      'Изменить маршрут': 'Edit route',
      'Добавить точку': 'Add point',
      'Параметры маршрута': 'Route settings',
      'Поделиться маршрутом': 'Share route',
      'Сообщить об ошибке': 'Report an issue',
      'Слои и офлайн-карты': 'Layers and offline maps',
      'Заправки': 'Gas stations',
      'Поддержка': 'Support',
      'Загрузка карт': 'Download maps',
      'Изменить карту и слои': 'Change map and layers',
      'Поделиться геопозицией': 'Share location',
      'Парковки': 'Parking',
      'Бронирования и история заказов': 'Bookings and order history',
      'Лента отзывов и исправлений': 'Feedback and corrections feed',
      'Музыка': 'Music',
      'Маршрут ещё не построен': 'Route has not been built yet',
      'Следующий манёвр': 'Next maneuver',
      'Навигация завершена.': 'Navigation ended.',
      'Расстояние неизвестно': 'Distance unknown',
      'Снять все отметки': 'Clear all selections',
      'Выбрать все сети': 'Select all networks',
      'Для выбранного языка голоса не найдены. Установите голосовые данные в настройках преобразования текста в речь Android.': 'No voices found for the selected language. Install voice data in Android text-to-speech settings.',
      'Изменить точки': 'Edit stops',
      'Промежуточные остановки: ': 'Intermediate stops: ',
      'Вариант ': 'Option ',
      'Куда едем?': 'Where to?',
      'Найти': 'Search',
      'Опишите, что не так': 'Describe the issue',
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
      'На север': 'North up',
      'Моё местоположение': 'My location',
      'Координаты: ': 'Coordinates: ',
      'Варианты маршрута': 'Route options',
      'Недавние запросы': 'Recent searches',
      'Здесь появятся адреса и места, которые вы искали.': 'Addresses and places you search for will appear here.',
      'Категории': 'Categories',
      'Слои карты': 'Map layers',
      'Избранное': 'Favorites',
      'Выбери сети, которые нужно учитывать при поиске заправок.': 'Choose which fuel station networks to include in search.',
      'Примечание: поиск использует названия сетей в OpenStreetMap. Если бренд не указан в данных карты, заправка может не попасть в отфильтрованный список.': 'Note: search uses network names in OpenStreetMap. If a brand is not listed in the map data, a station may not appear in the filtered results.',
      'Сохранённых пользовательских мест пока нет.': 'There are no saved custom places yet.',
      'Сначала постройте маршрут.': 'Build a route first.',
      'Поддержка BAKE': 'BAKE Support',
      'Разместить объект': 'Add a place',
      'Бронирования и история': 'Bookings and history',
      'Отзывы и исправления': 'Reviews and corrections',
      'Музыка BAKE': 'BAKE Music',
      'Звуковое сопровождение': 'Sound settings',
      'Готовый MBTiles-файл пока не подключён.': 'No ready-to-use MBTiles file is connected yet.',
      'Офлайн-карта подключена на этом устройстве.': 'Offline map is connected on this device.',
      'Офлайн-карты': 'Offline maps',
      'Исходный OSM PBF не является готовой MBTiles-картой. Для офлайн-режима нужны отдельно подготовленные тайлы.': 'An OSM PBF source file is not a ready-to-use MBTiles map. Offline mode requires separately prepared tiles.',
      'Импортировать MBTiles-файл с телефона': 'Import an MBTiles file from your phone',
      'Фильтры сохраняются, но текущий тестовый сервис маршрутов OSRM пока не применяет их при расчёте.': 'Filters are saved, but the current OSRM test routing service does not yet apply them when calculating routes.',
      'Изменения сохраняются на этом телефоне и применяются при следующем запуске навигатора.': 'Changes are saved on this phone and applied the next time the navigator starts.',
      'Сначала сохраните файл карты в память телефона, затем выберите его.': 'Save the map file to your phone first, then select it.',
      'Голос телефона': 'Device voice',
    },
  };

  static String pick(String ru, String kk, String en) {
    if (language == 'kk') return kk;
    if (language == 'en') return en;
    return ru;
  }

  static String tr(String russian) => _translations[language]?[russian] ?? russian;
}

class RouteInstruction {
  const RouteInstruction({
    required this.location,
    required this.text,
    required this.distanceMeters,
    required this.maneuverType,
    required this.maneuverModifier,
    this.laneGuidance = const <bool>[],
  });
  final LatLng location;
  final String text;
  final double distanceMeters;
  final String maneuverType;
  final String maneuverModifier;
  final List<bool> laneGuidance;
}

String _valhallaErrorForUser(Object error, {bool duringImport = false}) {
  final details = error.toString().toLowerCase();
  if (details.contains('not initialized')) {
    return AppLocale.pick(
      'Офлайн-маршрутизатор не запустился. Проверьте архив дорожных данных.',
      'Офлайн маршруттау құралы іске қосылмады. Жол деректерінің архивін тексеріңіз.',
      'Offline routing did not start. Check the road-data archive.',
    );
  }
  if (details.contains('not found') ||
      details.contains('no such file') ||
      details.contains('tile extract') ||
      details.contains('archive')) {
    return AppLocale.pick(
      'Не удалось открыть архив дорожных данных. Проверьте файл Valhalla .tar.',
      'Жол деректерінің архивін ашу мүмкін болмады. Valhalla .tar файлын тексеріңіз.',
      'Could not open the road-data archive. Check the Valhalla .tar file.',
    );
  }
  if (details.contains('no route') ||
      details.contains('route not found') ||
      details.contains('no suitable')) {
    return AppLocale.pick(
      'Архив открылся, но тестовый маршрут по нему не построен.',
      'Архив ашылды, бірақ сынақ маршруты құрылмады.',
      'The archive opened, but the test route could not be built.',
    );
  }
  return duringImport
      ? AppLocale.pick(
          'Не удалось проверить офлайн-маршрутизатор. Проверьте архив Valhalla и попробуйте ещё раз.',
          'Офлайн маршруттау құралын тексеру мүмкін болмады. Valhalla архивін тексеріп, қайталап көріңіз.',
          'Could not verify offline routing. Check the Valhalla archive and try again.',
        )
      : AppLocale.pick(
          'Не удалось построить маршрут по офлайн-дорожным данным.',
          'Офлайн жол деректері бойынша маршрут құру мүмкін болмады.',
          'Could not build a route using offline road data.',
        );
}

Map<String, dynamic> _decodeValhallaRouteResponseInBackground(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw const FormatException('Valhalla returned a non-object response.');
  }
  final data = Map<String, dynamic>.from(decoded);
  final rawRoutes = data['routes'];
  if (rawRoutes is! List) return data;

  data['routes'] = rawRoutes.map((rawRoute) {
    if (rawRoute is! Map) return rawRoute;
    final route = Map<String, dynamic>.from(rawRoute);
    final rawGeometry = route['geometry'];
    if (rawGeometry is! Map) return route;
    final geometry = Map<String, dynamic>.from(rawGeometry);
    final rawCoordinates = geometry['coordinates'];
    if (rawCoordinates is List) {
      final decodedCoordinates = <List<double>>[];
      for (final coordinate in rawCoordinates) {
        if (coordinate is! List || coordinate.length < 2 ||
            coordinate[0] is! num || coordinate[1] is! num) {
          continue;
        }
        decodedCoordinates.add(<double>[
          (coordinate[0] as num).toDouble(),
          (coordinate[1] as num).toDouble(),
        ]);
      }
      // Keep GeoJSON intact for the existing route/alternative renderer,
      // while caching validated points produced on the background isolate.
      route['_bakeDecodedCoordinates'] = decodedCoordinates;
    }
    return route;
  }).toList(growable: false);
  return data;
}

List<LatLng> _routePointsFromDecodedRoute(Map<String, dynamic> route) {
  final cached = route['_bakeDecodedCoordinates'];
  final geometry = route['geometry'];
  final coordinates = cached is List
      ? cached
      : (geometry is Map ? geometry['coordinates'] : null);
  if (coordinates is! List) return <LatLng>[];
  return coordinates.whereType<List>().where((pair) => pair.length >= 2 &&
      pair[0] is num && pair[1] is num).map((pair) {
    return LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble());
  }).toList(growable: false);
}

class NavigatorScreen extends StatefulWidget {
  const NavigatorScreen({super.key});

  @override
  State<NavigatorScreen> createState() => _NavigatorScreenState();
}

class _NavigatorScreenState extends State<NavigatorScreen> with WidgetsBindingObserver {
  static const LatLng _shymkent = LatLng(42.3154, 69.5869);
  static const MethodChannel _valhallaChannel =
      MethodChannel('bake.navigator/valhalla');
  bool _valhallaReady = false;
  Future<bool>? _valhallaReadyFuture;
  String? _valhallaExtractPath;
  String _valhallaStatus = 'Дорожный граф проверяется автоматически';


  final MapController _mapController = MapController();
  // flutter_map controllers are unusable until MapOptions.onMapReady fires.
  bool _offlineMapReady = false;
  // FlutterMap is the default online 2D renderer; offline MBTiles stays separate.
  bool _flutterMapExperimentEnabled = true;
  bool _flutterMapExperimentLoading = false;
  Style? _flutterMapOnlineStyle;
  bool get _isFlutterMapDisplayed => true;

  LatLng? _lastRouteLineSyncPoint;

  final FlutterTts _tts = FlutterTts();
  final KazakhVoiceService _kazakhVoiceService = KazakhVoiceService();
  final RoadAlertService _roadAlertService = RoadAlertService();
  List<RoadFeature> _roadFeatures = <RoadFeature>[];
  DateTime? _lastRoadFeatureLookup;
  LatLng? _lastRoadFeatureLookupPoint;
  bool _roadFeatureLookupInProgress = false;
  final Map<String, int> _announcedRoadFeatureStages = <String, int>{};
  Timer? _roadReportRetryTimer;
  bool _roadReportRetryInProgress = false;
  bool _confirmedRoadReportsLoadInProgress = false;
  final OfflineAddressSearch _offlineAddressSearch = OfflineAddressSearch();
  List<RoadAlert> _roadAlerts = <RoadAlert>[];
  List<RoadAlert> _bundledRoadAlerts = <RoadAlert>[];
  List<Map<String, dynamic>> _confirmedRoadReports = <Map<String, dynamic>>[];
  final Map<String, int> _announcedRoadAlertStages = <String, int>{};
  DateTime? _lastRoadAlertLookup;
  LatLng? _lastRoadAlertLookupPoint;
  bool _roadAlertLookupInProgress = false;
  bool _showShymkentCamerasOnMap = true;
  int _kazakhVoiceId = 0;
  bool _kazakhVoiceEnabled = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  MbTilesTileProvider? _offlineTileProvider;
  MbTiles? _offlineVectorMbtiles;
  MbTilesVectorTileProvider? _offlineVectorTileProvider;
  final vtr.Theme _offlineVectorTheme = _buildBakeOfflineVectorTheme();

  bool get _isOfflineMapActive =>
      _offlineTileProvider != null || _offlineVectorTileProvider != null;

  void _disposeOfflineMap() {
    // The FlutterMap widget remains mounted when its tile source changes.
    // Keep controller readiness; onMapReady will not fire again for provider swaps.
    _offlineTileProvider?.dispose();
    _offlineTileProvider = null;
    _offlineVectorMbtiles?.dispose();
    _offlineVectorMbtiles = null;
    _offlineVectorTileProvider = null;
  }

  LatLng? _currentLocation;
  // Smoothed marker/camera position for free-drive mode; raw GPS remains in _currentLocation.
  LatLng? _freeDriveDisplayLocation;
  DateTime? _freeDriveFixTimestamp;
  LatLng? _freeDriveJumpCandidate;
  int _freeDriveJumpCandidateCount = 0;
  LatLng? _destination;
  String _selectedMapPointAddress = 'Адрес определяется…';
  int _routeRequestGeneration = 0;
  DateTime? _mapPointerDownAt;
  Offset? _mapPointerDownPosition;
  bool _mapPointerMoved = false;
  Duration _lastMapPointerHoldDuration = Duration.zero;
  LatLng? _pendingMapLongPressPoint;
  LatLng? _routeOrigin;
  final List<LatLng> _routeStops = <LatLng>[];
  List<Map<String, dynamic>> _routeAlternatives = <Map<String, dynamic>>[];
  int _selectedRouteIndex = 0;
  List<LatLng> _routePoints = [];
  int _routeProgressSegmentIndex = 0;
  LatLng? _navigationMatchedLocation;
  LatLng? _navigationFixMatchedLocation;
  DateTime? _navigationFixTimestamp;
  double _navigationFixSpeedMetersPerSecond = 0;
  int _navigationFixSegmentIndex = 0;
  double _navigationFixSegmentT = 0;
  Timer? _navigationPredictionTimer;
  List<double> _routeCumulativeMeters = <double>[];
  List<double> _instructionProgressMeters = <double>[];
  double _navigationFixProgressMeters = 0;
  double _navigationProgressMeters = 0;
  List<RouteInstruction> _instructions = [];
  int _instructionIndex = 0;
  bool _navigationActive = false;
  bool _walkingMode = false;
  bool _routeReady = false;
  bool _routeActionDismissed = false;
  double _currentSpeedKmh = 0;
  String? _speedLimitKmh;
  DateTime? _lastSpeedLimitLookup;
  LatLng? _lastSpeedLimitLookupPoint;
  bool _speedLimitLookupInProgress = false;  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  StreamSubscription<Position>? _positionSubscription;
  Future<void> _gpsStreamQueue = Future<void>.value();
  bool _gpsStopPending = false;
  bool _gpsDiagnosticsEnabled = false;
  Future<void> _gpsDiagnosticWriteQueue = Future<void>.value();
  DateTime? _lastGpsDiagnosticCallbackAt;
  DateTime? _lastGpsDiagnosticFixAt;
  LatLng? _lastGpsDiagnosticRawPoint;
  bool _appInForeground = true;
  DateTime? _lastCameraUpdateAt;
  DateTime? _lastMapAnnotationUpdateAt;
  bool _speedingVoiceActive = false;
  bool _trafficLayerEnabled = false;
  bool _roadEventsLayerEnabled = true;
  String _tomtomTrafficApiKey = '';
  String? _activeConfirmedCameraId;
  double? _activeConfirmedCameraDistance;
  final Set<String> _passedConfirmedCameraIds = <String>{};
  final Map<String, int> _confirmedCameraStages = <String, int>{};
  bool _isLocating = false;
  bool _gpsAvailable = false;
  bool _isSearching = false;
  bool _nominatimTestMode = false;
  DateTime? _lastNominatimTestRequestAt;
  bool _isBuildingRoute = false;
  int _voiceMode = 3;
  double? _gpsHeadingDegrees;
  double? _lastCameraHeadingDegrees;
  bool _northUpLocked = false;
  bool _mapFollowEnabled = true;
  bool _headingUpGestureActive = false;
  Timer? _headingUpResumeTimer;
  int _announcedManeuverStage = 0;
  int _offRouteSamples = 0;
  DateTime? _lastAutomaticReroute;
  DateTime? _plannedDeparture;  String _message = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadFlutterMapOnlineStyle());
    unawaited(_loadGpsDiagnosticsSetting());
    _roadReportRetryTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_retryPendingRoadReports()),
    );
    _configureVoice();
    unawaited(_loadBundledRoadAlerts());
    unawaited(_loadConfirmedRoadReports());
    RoadReportSyncService.subscribeToChanges(() {
      if (mounted) unawaited(_loadConfirmedRoadReports());
    });
    unawaited(_offlineAddressSearch.initialize());
    _loadSavedOfflineMap();
    _loadSavedRoutePoints();
    unawaited(_loadTrafficLayerPreference());
    unawaited(_loadNominatimTestMode());
    // Ask for location after the first frame so the permission dialog has a valid context.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_ensureValhallaReady());
      unawaited(_locateMe());
    });
  }

  Future<void> _loadBundledRoadAlerts() async {
    final bundled = <RoadAlert>[];
    // Restore the full Kazakhstan database first. The APK workflow downloads
    // this CSV before packaging, so it is available offline after installation.
    try {
      bundled.addAll(await _roadAlertService.loadBundledCameras());
    } catch (error) {
      debugPrint('Не удалось загрузить общую базу камер Казахстана: $error');
    }
    // Keep the dedicated Shymkent dataset as an additional source, not a
    // replacement for the national camera database.
    try {
      bundled.addAll(await _roadAlertService.loadBundledShymkentCameraCandidates());
      bundled.addAll(await _roadAlertService.loadShymkentOsmCameras());
    } catch (error) {
      debugPrint('Не удалось загрузить слой камер Шымкента: $error');
    }
    if (!mounted || bundled.isEmpty) return;
    setState(() {
      _bundledRoadAlerts = bundled;
      _roadAlerts = _mergeRoadAlerts(bundled, _roadAlerts);
    });
  }

  List<RoadAlert> _mergeRoadAlerts(List<RoadAlert> bundled, List<RoadAlert> live) {
    final byId = <String, RoadAlert>{};
    for (final alert in bundled) {
      byId[alert.id] = alert;
    }
    for (final alert in live) {
      if (byId.containsKey(alert.id)) {
        byId[alert.id] = alert;
        continue;
      }
      // Deduplicate only across the bundled Shymkent layer and live lookup.
      // Nearby cameras within the same source are retained: some are genuinely
      // mapped as separate devices only a few metres apart.
      final isShymkentRecord = alert.id.startsWith('shymkent/');
      final duplicate = byId.values.any((existing) {
        if (existing.kind != alert.kind ||
            existing.id.startsWith('shymkent/') == isShymkentRecord) {
          return false;
        }
        final meters = const Distance().as(
          LengthUnit.Meter, existing.location, alert.location,
        );
        return meters <= 18;
      });
      if (!duplicate) byId[alert.id] = alert;
    }
    return byId.values.toList();
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
  Future<void> _loadNominatimTestMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('nominatim_test_mode') ?? false;
      if (!mounted || _nominatimTestMode == enabled) return;
      setState(() => _nominatimTestMode = enabled);
    } catch (error) {
      debugPrint('BAKE Nominatim test setting load failed: $error');
    }
  }

  Future<void> _loadTrafficLayerPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('layer_traffic') ?? false;
      final roadEventsEnabled = prefs.getBool('layer_road_events') ?? true;
      final trafficKey = (prefs.getString('tomtom_traffic_api_key') ?? '').trim();
      if (!mounted) return;
      if (_trafficLayerEnabled == enabled &&
          _roadEventsLayerEnabled == roadEventsEnabled &&
          _tomtomTrafficApiKey == trafficKey) return;
      setState(() {
        _trafficLayerEnabled = enabled;
        _roadEventsLayerEnabled = roadEventsEnabled;
        _tomtomTrafficApiKey = trafficKey;
      });
    } catch (error) {
      debugPrint('BAKE traffic layer preference load failed: $error');
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
        _message = AppLocale.pick('Последний пункт назначения восстановлен. Начальная точка будет определена по GPS.', 'Соңғы межелі орын қалпына келтірілді. Бастапқы нүкте GPS арқылы анықталады.', 'Last destination restored. The starting point will be detected by GPS.');
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
      if (mounted) setState(() => _message = AppLocale.pick('Не удалось сохранить точку маршрута на телефоне.', 'Маршрут нүктесін телефонға сақтау мүмкін болмады.', 'Could not save the route point on this phone.'));
    }
  }

  Future<void> _removeSavedRoutePoint(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {
      if (mounted) setState(() => _message = AppLocale.pick('Не удалось удалить сохранённую точку маршрута.', 'Сақталған маршрут нүктесін жою мүмкін болмады.', 'Could not delete the saved route point.'));
    }
  }

  String _navigationLanguage = 'kk-KZ';
  String? _selectedVoiceName;
  String? _selectedVoiceLocale;
  List<Map<String, String>> _availableVoices = <Map<String, String>>[];

  Future<void> _configureVoice() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final volume = prefs.getDouble('voice_volume') ?? 1.0;
      final rate = prefs.getDouble('voice_rate') ?? 0.48;
      _voiceMode = prefs.getInt('voice_mode') ?? 3;
      _navigationLanguage = _normalizeNavigationLanguage(prefs.getString('navigation_language') ?? 'kk-KZ');
      _selectedVoiceName = prefs.getString('voice_name');
      _selectedVoiceLocale = prefs.getString('voice_locale');
      _kazakhVoiceId = (prefs.getInt('kazakh_voice_sid') ?? 0).clamp(0, 5).toInt();
      _kazakhVoiceEnabled = prefs.getBool('kazakh_voice_enabled') ?? false;
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

  String _voiceLanguageCode(String locale) =>
      locale.toLowerCase().replaceAll('_', '-').split('-').first;

  Future<bool> _prepareSpeechVoice() async {
    // Voice enumeration is not reliable on every Android TTS engine. In
    // particular, some engines can synthesize a locale even when getVoices
    // returns an empty list. Check locale support, then set the locale directly.
    final languageAvailable = await _tts.isLanguageAvailable(_navigationLanguage);
    if (languageAvailable != true) return false;

    await _tts.setLanguage(_navigationLanguage);
    final requiredLanguage = _voiceLanguageCode(_navigationLanguage);
    final matchingVoices = _availableVoices
        .where((voice) => _voiceLanguageCode(voice['locale'] ?? '') == requiredLanguage)
        .toList();

    // No enumerated voices is not a reason to silence navigation. Keep the
    // requested locale and let Android's TTS engine use its locale default.
    if (matchingVoices.isEmpty) {
      _selectedVoiceName = null;
      _selectedVoiceLocale = null;
      return true;
    }

    final selected = matchingVoices.where((voice) =>
      voice['name'] == _selectedVoiceName &&
      voice['locale'] == _selectedVoiceLocale
    );
    final voice = selected.isNotEmpty ? selected.first : matchingVoices.first;
    _selectedVoiceName = voice['name'];
    _selectedVoiceLocale = voice['locale'];
    await _tts.setVoice(<String, String>{
      'name': voice['name']!,
      'locale': voice['locale']!,
    });
    return true;
  }

  Future<void> _applySelectedVoice() async {
    await _prepareSpeechVoice();
  }

  Future<void> _speakText(String text) async {
    // The global voice switch must silence every navigation language,
    // including the bundled Kazakh ISSAI voice.
    if (_voiceMode == 0) return;
    try {
      // Kazakh navigation speech is provided by BAKE's bundled ISSAI engine.
      // It must never depend on a Kazakh voice installed in Android.
      if (_navigationLanguage == 'kk-KZ') {
        if (!_kazakhVoiceEnabled) return;
        await _kazakhVoiceService.speak(
          text: text,
          speakerId: _kazakhVoiceId,
          speed: 1.0,
        );
        return;
      }
      if (!await _prepareSpeechVoice()) return;
      await _tts.speak(text);
    } catch (error) {
      if (mounted) {
        setState(() => _message = _navigationLanguage == 'kk-KZ'
            ? AppLocale.pick(
                'Қазақша дауыс пакетін жүктеу немесе іске қосу мүмкін болмады. Интернетті тексеріп, дыбыс баптауларынан «Қазақша офлайн дауысы» батырмасын басыңыз.',
                'Қазақша дауыс пакетін жүктеу немесе іске қосу мүмкін болмады. Интернетті тексеріп, дыбыс баптауларынан «Қазақша офлайн дауысы» батырмасын басыңыз.',
                'Could not download or start the built-in Kazakh voice. Check the internet and use the Kazakh offline voice button in sound settings.',
              )
            : AppLocale.pick(
                'Не удалось запустить выбранный голос навигации.',
                'Таңдалған навигация дауысын іске қосу мүмкін болмады.',
                'Could not start the selected navigation voice.',              ));
      }
    }
  }

  String _normalizeNavigationLanguage(String value) {
    final code = value.toLowerCase().replaceAll('_', '-');
    if (code == 'kk' || code.startsWith('kk-')) return 'kk-KZ';
    if (code == 'en' || code.startsWith('en-')) return 'en-US';
    return 'ru-RU';
  }

  String _localized(String ru, String kk, String en) {
    final code = _normalizeNavigationLanguage(_navigationLanguage);
    if (code == 'kk-KZ') return kk;
    if (code == 'en-US') return en;
    return ru;
  }

  String _localizedStepRoadName(Map<String, dynamic> step) {
    final keys = _normalizeNavigationLanguage(_navigationLanguage) == 'kk-KZ'
        ? const ['name:kk', 'name_kk', 'name:kk-KZ', 'name_kk_KZ', 'street_name:kk']
        : _normalizeNavigationLanguage(_navigationLanguage) == 'en-US'
            ? const ['name:en', 'name_en', 'street_name:en']
            : const ['name:ru', 'name_ru', 'street_name:ru'];
    for (final key in keys) {
      final value = step[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    // A generic OSM "name" is not language-tagged. In Kazakh mode it may
    // contain Russian-only text, so omit it rather than mixing languages.
    if (_normalizeNavigationLanguage(_navigationLanguage) == 'kk-KZ') return '';
    return (step['name']?.toString() ?? '').trim();
  }

  // One vehicle marker is used in both map renderers. During navigation
  // prefer the road-matched/predicted position; keep raw GPS for routing,
  // alerts and off-route detection.
  LatLng? get _vehicleDisplayLocation {
    if (_navigationActive) {
      final matched = _navigationMatchedLocation;
      final raw = _currentLocation;
      if (matched != null && raw != null &&
          _routePoints.length > 1 &&
          _distanceToRouteMeters(raw) <= 100) {
        return matched;
      }
      return raw;
    }
    return _freeDriveDisplayLocation ?? _currentLocation;
  }

  double get _vehicleDisplayBearing {
    if (_navigationActive && _vehicleDisplayLocation != null &&
        _routePoints.length > 1 &&
        _currentLocation != null &&
        _distanceToRouteMeters(_currentLocation!) <= 100) {
      return _routeBearingAt(_vehicleDisplayLocation!);
    }
    return (_gpsHeadingDegrees ?? _lastCameraHeadingDegrees ?? 0.0) *
        math.pi / 180.0;
  }

  // Reject stale/inaccurate fixes and impossible jumps only for free-drive display.
  // Raw coordinates remain untouched for reports, cameras, speed limits and routing.
  LatLng _updateFreeDriveDisplayPosition(Position fix, LatLng rawPoint) {
    final now = DateTime.now();
    final fixAge = now.difference(fix.timestamp);
    if (fixAge.isNegative || fixAge > const Duration(seconds: 10) ||
        !fix.accuracy.isFinite || fix.accuracy > 60) {
      return _freeDriveDisplayLocation ?? rawPoint;
    }

    final previous = _freeDriveDisplayLocation;
    if (previous == null) {
      _freeDriveDisplayLocation = rawPoint;
      _freeDriveFixTimestamp = fix.timestamp;
      _freeDriveJumpCandidate = null;
      _freeDriveJumpCandidateCount = 0;
      return rawPoint;
    }

    final previousTimestamp = _freeDriveFixTimestamp;
    final elapsed = previousTimestamp == null
        ? 1.0
        : (fix.timestamp.difference(previousTimestamp).inMilliseconds / 1000)
            .clamp(0.25, 5.0).toDouble();
    final distance = Geolocator.distanceBetween(
      previous.latitude, previous.longitude,
      rawPoint.latitude, rawPoint.longitude,
    );
    final reportedSpeed = fix.speed.isFinite && fix.speed > 0
        ? fix.speed.clamp(0.0, 45.0).toDouble()
        : 0.0;
    final plausibleTravel = reportedSpeed * elapsed;
    final jumpLimit = math.max(25.0, plausibleTravel * 2.0 +
        math.min(fix.accuracy, 35.0) * 0.8);
    if (distance > jumpLimit) {
      final candidate = _freeDriveJumpCandidate;
      final candidateDistance = candidate == null ? double.infinity :
          Geolocator.distanceBetween(candidate.latitude, candidate.longitude,
              rawPoint.latitude, rawPoint.longitude);
      if (candidateDistance <= math.max(20.0, fix.accuracy)) {
        _freeDriveJumpCandidateCount++;
      } else {
        _freeDriveJumpCandidate = rawPoint;
        _freeDriveJumpCandidateCount = 1;
      }
      // Reacquire after three consecutive fixes agree on the new position;
      // a single GPS teleport cannot move the displayed vehicle.
      if (_freeDriveJumpCandidateCount >= 3) {
        _freeDriveDisplayLocation = rawPoint;
        _freeDriveFixTimestamp = fix.timestamp;
        _freeDriveJumpCandidate = null;
        _freeDriveJumpCandidateCount = 0;
        return rawPoint;
      }
      return previous;
    }
    _freeDriveJumpCandidate = null;
    _freeDriveJumpCandidateCount = 0;

    // Follow accepted fixes promptly while softening small coordinate jitter.
    final factor = distance < 5 ? 0.75 : 0.60;
    final smoothed = LatLng(
      previous.latitude + (rawPoint.latitude - previous.latitude) * factor,
      previous.longitude + (rawPoint.longitude - previous.longitude) * factor,
    );
    _freeDriveDisplayLocation = smoothed;
    _freeDriveFixTimestamp = fix.timestamp;
    return smoothed;
  }

  LatLng get _mapCameraCenter {
    return _offlineMapReady ? _mapController.camera.center : (_currentLocation ?? _shymkent);
  }
  double get _mapCameraZoom => _offlineMapReady ? _mapController.camera.zoom : 13;
  // Manual panning disables camera-follow only; GPS, route progress and voice guidance keep running.
  void _scheduleHeadingUpReturn() {
    _headingUpGestureActive = false;
    _headingUpResumeTimer?.cancel();
  }

  void _moveMapCamera(LatLng point, double zoom) {
    if (!_offlineMapReady) return;
    _mapController.move(point, zoom);
  }

  void _updateNavigationCamera(LatLng point, double zoom, double heading) {
    _lastCameraHeadingDegrees = heading;
    if (!_appInForeground || !_offlineMapReady) return;
    _mapController.move(point, zoom);
    _mapController.rotate(-heading);
  }

  void _rotateMapCamera(double rotation) {
    if (!_offlineMapReady) return;
    _mapController.rotate(rotation);
  }

  void _fitMapCamera(List<LatLng> points) {
    if (points.isEmpty || !_offlineMapReady) return;
    _mapController.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(36, 100, 36, 250),
    ));
  }

  void _zoomMapBy(double delta) {
    _moveMapCamera(_mapCameraCenter, (_mapCameraZoom + delta).clamp(3.0, 20.0).toDouble());
  }

  void _onOfflineMapReady() {
    if (!mounted || !_isFlutterMapDisplayed) return;
    _offlineMapReady = true;
    final point = _currentLocation;
    if (point == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_offlineMapReady || !_isFlutterMapDisplayed) return;
      _updateNavigationCamera(
        point,
        math.max(_mapCameraZoom, _navigationActive ? 16.0 : 13.0).toDouble(),
        _gpsHeadingDegrees ?? 0.0,
      );
    });
  }
  // Diagnostic build: verify the satellite toggle and Esri raster tiles on device.
  List<LatLng> _simplifyRouteForDisplay(List<LatLng> points) {
    if (points.length <= 2) return points;
    final latitudeRadians = points.first.latitude * math.pi / 180;
    final xScale = 111320.0 * math.cos(latitudeRadians);
    const yScale = 110540.0;
    double distanceToSegment(LatLng point, LatLng start, LatLng end) {
      final px = point.longitude * xScale;
      final py = point.latitude * yScale;
      final ax = start.longitude * xScale;
      final ay = start.latitude * yScale;
      final bx = end.longitude * xScale;
      final by = end.latitude * yScale;
      final dx = bx - ax;
      final dy = by - ay;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared == 0
          ? 0.0
          : (((px - ax) * dx + (py - ay) * dy) / lengthSquared)
              .clamp(0.0, 1.0);
      final nearestX = ax + t * dx;
      final nearestY = ay + t * dy;
      return math.sqrt(
        (px - nearestX) * (px - nearestX) +
        (py - nearestY) * (py - nearestY),
      );
    }

    final keep = List<bool>.filled(points.length, false);
    keep[0] = true;
    keep[points.length - 1] = true;
    final pending = <(int, int)>[(0, points.length - 1)];
    while (pending.isNotEmpty) {
      final range = pending.removeLast();
      final start = range.$1;
      final end = range.$2;
      var farthestDistance = 5.0;
      var farthestIndex = -1;
      for (var i = start + 1; i < end; i++) {
        final distance = distanceToSegment(points[i], points[start], points[end]);
        if (distance > farthestDistance) {
          farthestDistance = distance;
          farthestIndex = i;
        }
      }
      if (farthestIndex >= 0) {
        keep[farthestIndex] = true;
        pending.add((start, farthestIndex));
        pending.add((farthestIndex, end));
      }
    }
    return <LatLng>[
      for (var i = 0; i < points.length; i++)
        if (keep[i]) points[i],
    ];
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _roadReportRetryTimer?.cancel();
    unawaited(_stopLiveLocationUpdates(reason: 'widget_disposed'));
    _headingUpResumeTimer?.cancel();
    _navigationPredictionTimer?.cancel();
    _disposeOfflineMap();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tts.stop();
    unawaited(_kazakhVoiceService.dispose());
    _roadAlertService.dispose();
    super.dispose();
  }


  Future<void> _loadSavedOfflineMap() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString('offline_map_path');
    if (path == null || !await File(path).exists()) return;
    try {
      final database = MbTiles(mbtilesPath: path);
      final format = database.getMetadata().format?.toLowerCase();
      if (format == 'pbf' || format == 'mvt') {
        final vectorProvider = MbTilesVectorTileProvider(mbtiles: database);
        if (!mounted) {
          database.dispose();
          return;
        }
        setState(() {
          _offlineTileProvider = null;
          _offlineVectorMbtiles = database;
          _offlineVectorTileProvider = vectorProvider;
        });
      } else {
        database.dispose();
        final provider = MbTilesTileProvider.fromPath(path: path);
        if (!mounted) {
          provider.dispose();
          return;
        }
        setState(() {
          _offlineVectorMbtiles = null;
          _offlineVectorTileProvider = null;
          _offlineTileProvider = provider;
        });
      }
    } catch (_) {
      // Keep the online map available if an offline archive cannot be opened.
    }
  }

  Future<bool> _ensureValhallaReady() {
    if (_valhallaReady) return Future<bool>.value(true);
    final pending = _valhallaReadyFuture;
    if (pending != null) return pending;
    final future = _prepareValhallaAutomatically();
    _valhallaReadyFuture = future;
    return future.whenComplete(() {
      if (identical(_valhallaReadyFuture, future)) {
        _valhallaReadyFuture = null;
      }
    });
  }

  Future<bool> _prepareValhallaAutomatically() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString('valhalla_tile_extract_path');
    File? archiveFile;
    var isManagedArchive = false;

    try {
      if (savedPath != null && savedPath.isNotEmpty) {
        final savedFile = File(savedPath);
        final savedExists = await savedFile.exists().timeout(
          const Duration(seconds: 2), onTimeout: () => false,
        );
        final savedLength = savedExists
            ? await savedFile.length().timeout(
                const Duration(seconds: 2), onTimeout: () => 0,
              )
            : 0;
        if (savedExists && savedLength > 100000) {
          archiveFile = savedFile;
          isManagedArchive = savedFile.path.endsWith('/shymkent-valhalla.tar');
        }
      }

      if (archiveFile == null) {
        if (mounted) {
          setState(() => _valhallaStatus = 'Загружаем дорожный граф Шымкента…');
        }
        final directory = await getApplicationSupportDirectory();
        archiveFile = File('${directory.path}/shymkent-valhalla.tar');
        isManagedArchive = true;
        final managedExists = await archiveFile.exists().timeout(
          const Duration(seconds: 2), onTimeout: () => false,
        );
        final managedLength = managedExists
            ? await archiveFile.length().timeout(
                const Duration(seconds: 2), onTimeout: () => 0,
              )
            : 0;
        if (!managedExists || managedLength < 100000) {
          final temporary = File('${archiveFile.path}.download');
          final response = await http
              .get(Uri.parse(
                'https://github.com/baketolegenov074-sys/BAKE-NAVIGATOR/releases/download/shymkent-valhalla-latest/shymkent-valhalla.tar',
              ))
              .timeout(const Duration(minutes: 5));
          if (response.statusCode != 200 || response.bodyBytes.length < 100000) {
            throw Exception('Не удалось скачать дорожный граф Шымкента (HTTP ${response.statusCode}).');
          }
          await temporary.writeAsBytes(response.bodyBytes, flush: true);
          if (await archiveFile.exists()) await archiveFile.delete();
          await temporary.rename(archiveFile.path);
        }
      }

      final archiveValid = await hasValidShymkentValhallaSha256(archiveFile)
          .timeout(const Duration(seconds: 2), onTimeout: () => false);
      if (!archiveValid) {
        throw Exception(
          'Контрольная сумма дорожного графа Шымкента не совпадает. Архив отклонён.',
        );
      }

      if (mounted) {
        setState(() => _valhallaStatus = 'Подключаем офлайн-маршрутизатор…');
      }      final initialized = await _valhallaChannel.invokeMapMethod<String, dynamic>(
        'initialize',
        <String, dynamic>{'tileExtractPath': archiveFile.path},
      );
      if (initialized?['ready'] != true) {
        throw Exception('Valhalla не подтвердила готовность дорожного графа.');
      }

      final diagnosticRaw = await _valhallaChannel.invokeMethod<String>(
        'route',
        <String, dynamic>{
          'startLat': 42.3640,
          'startLon': 69.4780,
          'endLat': 42.3154,
          'endLon': 69.5869,
        },
      );
      if (diagnosticRaw == null || diagnosticRaw.isEmpty) {
        throw Exception('Пустой ответ на контрольный офлайн-маршрут.');
      }
      final diagnosticData = await compute(
        _decodeValhallaRouteResponseInBackground,
        diagnosticRaw,
      );
      final routes = (diagnosticData['routes'] as List?) ?? const [];
      final route = routes.isNotEmpty ? routes.first : null;
      final geometry = route is Map<String, dynamic> ? route['geometry'] : null;
      final coordinates = geometry is Map<String, dynamic>
          ? geometry['coordinates']
          : null;
      if (diagnosticData['code'] != 'Ok' ||
          route is! Map<String, dynamic> ||
          route['distance'] is! num ||
          route['duration'] is! num ||
          coordinates is! List ||
          coordinates.length < 2) {
        throw Exception('Контрольный маршрут по графу Шымкента не построен.');
      }

      await prefs.setString('valhalla_tile_extract_path', archiveFile.path);
      _valhallaExtractPath = archiveFile.path;
      _valhallaReady = true;
      if (mounted) {
        setState(() {
          _valhallaStatus = 'Офлайн-маршрутизация Шымкента готова';
        });
      }
      debugPrint('BAKE Valhalla ready: ${archiveFile.path}');
      return true;
    } catch (error) {
      _valhallaReady = false;
      if (isManagedArchive && archiveFile != null) {
        if (await archiveFile.exists()) await archiveFile.delete();
        await prefs.remove('valhalla_tile_extract_path');
      }
      if (mounted) {
        setState(() {
          _valhallaStatus = 'Офлайн-граф не подключён; при наличии сети доступен онлайн-маршрут';
        });
      }
      debugPrint('BAKE automatic Valhalla setup failed: $error');
      return false;
    }
  }

  Future<void> _loadFlutterMapOnlineStyle() async {
    if (_flutterMapExperimentLoading || _flutterMapOnlineStyle != null) return;
    setState(() => _flutterMapExperimentLoading = true);
    try {
      final style = await StyleReader(
        uri: 'https://tiles.openfreemap.org/styles/liberty',
      ).read();
      if (!mounted) return;
      setState(() {
        _flutterMapOnlineStyle = style;
        _flutterMapExperimentEnabled = true;
      });
    } catch (error) {
      debugPrint('BAKE FlutterMap online style failed to load: $error');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Онлайн-карта не загрузилась: $error'),
          duration: const Duration(seconds: 4),
        ));
      }
    } finally {
      if (mounted) setState(() => _flutterMapExperimentLoading = false);
    }
  }

  Future<void> _toggleOfflineMapFromMap() async {
    if (_isOfflineMapActive) {
      _disposeOfflineMap();
      if (mounted) {
        setState(() => _message = '');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocale.pick(
            'Включена онлайн-карта.',
            'Онлайн карта қосылды.',
            'Online map enabled.',
          )),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    await _loadSavedOfflineMap();
    if (!mounted) return;
    final notice = _isOfflineMapActive
        ? AppLocale.pick(
            'Включена офлайн-карта Шымкента.',
            'Шымкенттің офлайн картасы қосылды.',
            'Shymkent offline map enabled.',
          )
        : AppLocale.pick(
            'Сначала импортируйте MBTiles-карту в настройках.',
            'Алдымен баптаулардан MBTiles картасын импорттаңыз.',
            'Import an MBTiles map in settings first.',
          );
    setState(() => _message = '');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(notice),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NavigatorPreferencesScreen(
          onOpenSoundSettings: _openSoundSettings,
          onOpenRoutePreferences: _openRoutePreferences,
          onOpenProfile: _openProfileMenu,
          onOpenGpsDiagnostics: _openGpsDiagnostics,
          onVoiceChanged: (enabled) {
            setState(() => _voiceMode = enabled ? 3 : 0);
            if (!enabled) {
              unawaited(_tts.stop());
              unawaited(_kazakhVoiceService.stopAndUnload().catchError((Object error) {
                debugPrint('BAKE ISSAI unload after voice switch failed: $error');
              }));
            }
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openOfflineAndVehicleSettings() async {
    final selectedPath = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => NavigatorSettingsScreen(onRetryValhalla: _ensureValhallaReady),
      ),
    );
    if (!mounted || selectedPath == null) return;
    if (selectedPath == '__use_online_map__') {
      _disposeOfflineMap();
      setState(() => _message = '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocale.pick('Включена онлайн-карта.', 'Онлайн карта қосылды.', 'Online map enabled.')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    try {
      final database = MbTiles(mbtilesPath: selectedPath);
      final format = database.getMetadata().format?.toLowerCase();
      if (format == 'pbf' || format == 'mvt') {
        final vectorProvider = MbTilesVectorTileProvider(mbtiles: database);
        _disposeOfflineMap();
        setState(() {
          _offlineVectorMbtiles = database;
          _offlineVectorTileProvider = vectorProvider;
          _message = '';
        });
      } else {
        database.dispose();
        final provider = MbTilesTileProvider.fromPath(path: selectedPath);
        _disposeOfflineMap();
        setState(() {
          _offlineTileProvider = provider;
          _message = '';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = AppLocale.pick('Не удалось открыть офлайн-карту: $error', 'Офлайн картаны ашу мүмкін болмады: $error', 'Could not open offline map: $error'));
    }
    if (mounted && _isOfflineMapActive) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocale.pick('Офлайн-карта Шымкента включена.', 'Шымкенттің офлайн картасы қосылды.', 'Shymkent offline map enabled.')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
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
    var kazakhVoiceId = (prefs.getInt('kazakh_voice_sid') ?? _kazakhVoiceId).clamp(0, 5).toInt();
    var kazakhVoiceEnabled = prefs.getBool('kazakh_voice_enabled') ?? false;
    var offlineVoiceBusy = false;
    var offlineVoiceReady = await _kazakhVoiceService.isInstalled;
    var offlineVoiceStatus = offlineVoiceReady ? 'Голос Иса уже скачан и доступен без интернета.' : '';
    var offlineVoiceFailed = false;
    var progressReceived = 0;
    var progressTotal = -1;
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
    StateSetter refreshSheet = (_) {};

    Future<void> loadAndPreviewVoice() async {
      if (offlineVoiceBusy) return;
      offlineVoiceBusy = true;
      offlineVoiceFailed = false;
      offlineVoiceStatus = AppLocale.pick(
        'Қазақша дауыс дайындалып жатыр…',
        'Қазақша дауыс дайындалып жатыр…',
        'Preparing Kazakh voice…',
      );
      progressReceived = 0;
      progressTotal = -1;
      refreshSheet(() {});
      try {
        // Previewing ISSAI must not silently enable navigation voice.
        refreshSheet(() {});
        await _kazakhVoiceService.speak(
          text: 'Сәлем, мен Иса, жолға дайынмын!',
          speakerId: kazakhVoiceId,
          speed: 1.0,
          onDownloadProgress: (received, total) {
            progressReceived = received;
            progressTotal = total;
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(0);
            if (total > 0) {
              final totalMb = (total / (1024 * 1024)).toStringAsFixed(0);
              final percent = (received * 100 / total).clamp(0, 100).round();
              offlineVoiceStatus = 'Жүктелуде: $percent% ($receivedMb / $totalMb МБ)';
            } else {
              offlineVoiceStatus = 'Жүктелуде: $receivedMb МБ';
            }
            refreshSheet(() {});
          },
          onStage: (stage) {
            offlineVoiceStatus = stage == 'extracting'
                ? 'Архив распаковывается…'
                : 'Қазақша дауыс қозғалтқышы іске қосылуда…';
            refreshSheet(() {});
          },
        );
        offlineVoiceReady = true;
        offlineVoiceFailed = false;
        offlineVoiceStatus = AppLocale.pick(
          'Қазақша офлайн дауыс дайын.',
          'Қазақша офлайн дауыс дайын.',
          'Kazakh offline voice is ready.',
        );
      } catch (error) {
        offlineVoiceFailed = true;
        final detail = error.toString().replaceFirst('Exception: ', '').trim();
        offlineVoiceStatus = detail.isEmpty
            ? 'Қазақша дауыс іске қосылмады.'
            : (detail.length > 220 ? '${detail.substring(0, 220)}…' : detail);
      } finally {
        await _kazakhVoiceService.stopAndUnload();
        offlineVoiceBusy = false;
        refreshSheet(() {});
      }
    }

    Future<void> importVoiceArchive() async {
      if (offlineVoiceBusy) return;
      offlineVoiceBusy = true;
      offlineVoiceFailed = false;
      offlineVoiceStatus = 'Архив тексеріліп, орнатылуда…';
      refreshSheet(() {});
      try {
        final directory = await _kazakhVoiceService.importModelArchive();
        if (directory == null) {
          offlineVoiceStatus = '';
        } else {
          await _kazakhVoiceService.speak(
            text: 'Сәлем, мен Иса, жолға дайынмын!',
            speakerId: kazakhVoiceId,
            speed: 1.0,
          );
          offlineVoiceReady = true;
          offlineVoiceStatus = 'Қазақша офлайн дауыс дайын.';
        }
      } catch (error) {
        offlineVoiceFailed = true;
        // Keep the real failure visible: import, extraction and TTS startup
        // are different stages and must not all be reported as a bad archive.
        final detail = error.toString().replaceFirst('Exception: ', '').trim();
        offlineVoiceStatus = detail.isEmpty
            ? 'Архивті өңдеу кезінде қате болды. Файлды қайта таңдаңыз.'
            : (detail.length > 220 ? '${detail.substring(0, 220)}…' : detail);
      } finally {
        await _kazakhVoiceService.stopAndUnload();
        offlineVoiceBusy = false;
        refreshSheet(() {});
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) {
          refreshSheet = refresh;
          final voices = voicesFor(language);
          final selectedExists = voices.any((v) => '${v['name']}|${v['locale']}' == selectedKey);
          return SafeArea(
            top: true,
            bottom: true,
            minimum: const EdgeInsets.only(bottom: 24),
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
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: languages.entries.map((entry) => ChoiceChip(
                      label: Text(entry.value),
                      selected: language == entry.key,
                      onSelected: (_) async {
                        final value = entry.key;
                        // Apply language immediately; native ISSAI shutdown is
                        // independent and must not block Russian/English selection.
                        language = value;
                        _navigationLanguage = value;
                        _selectedVoiceName = null;
                        _selectedVoiceLocale = null;
                        selectedKey = '';
                        if (value != 'kk-KZ') {
                          kazakhVoiceEnabled = false;
                          _kazakhVoiceEnabled = false;
                        }
                        refresh(() {});
                        await prefs.setString('navigation_language', value);
                        if (value != 'kk-KZ') {
                          await prefs.setBool('kazakh_voice_enabled', false);
                          unawaited(_kazakhVoiceService.stopAndUnload().catchError((Object error) {
                            debugPrint('BAKE ISSAI unload after language change failed: $error');
                          }));
                        }
                        await prefs.remove('voice_name');
                        await prefs.remove('voice_locale');
                        await _tts.setLanguage(value);
                        await _refreshAvailableVoices();
                        await _prepareSpeechVoice();
                        refresh(() {});
                      },
                    )).toList(),
                  ),
                  if (language == 'kk-KZ') ...[
                    const SizedBox(height: 14),
                    Text('Қазақша офлайн дауысы · ISSAI', style: const TextStyle(fontWeight: FontWeight.w700)),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Использовать голос Исай'),
                      subtitle: const Text('Выключено — модель не загружается и не запускается автоматически.'),
                      value: kazakhVoiceEnabled,
                      onChanged: (value) async {
                        kazakhVoiceEnabled = value;
                        _kazakhVoiceEnabled = value;
                        await prefs.setBool('kazakh_voice_enabled', value);
                        if (!value) {
                          await _kazakhVoiceService.stopAndUnload();
                          offlineVoiceStatus = 'Голос Исай выключен. Файл модели сохранён на телефоне.';
                        } else {
                          offlineVoiceStatus = 'Голос Исай включён. Загрузка начнётся при проверке голоса или навигационной подсказке.';
                        }
                        refresh(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      value: kazakhVoiceId,
                      isExpanded: true,
                      items: KazakhVoiceService.voices.map((voice) =>
                        DropdownMenuItem<int>(
                          value: voice.id,
                          child: Text(voice.label, overflow: TextOverflow.ellipsis),
                        ),
                      ).toList(),
                      onChanged: (value) async {
                        if (value == null) return;
                        kazakhVoiceId = value;
                        _kazakhVoiceId = value;
                        await prefs.setInt('kazakh_voice_sid', value);
                        refresh(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      AppLocale.pick('В пакете 2 мужских и 4 женских голоса. Первая загрузка — около 129 МБ, дальше работает без интернета.', 'Бір пакетте 2 ер және 4 әйел дауысы бар. Алғашқы жүктеу шамамен 129 МБ, кейін интернетсіз жұмыс істейді.', 'One package includes 2 male and 4 female voices. First download is about 129 MB; after that it works offline.'),
                      style: const TextStyle(fontSize: 12, color: Color(0xFF62666D)),
                    ),
                    const SizedBox(height: 8),                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: offlineVoiceBusy ? null : loadAndPreviewVoice,
                            icon: offlineVoiceBusy
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : Icon(offlineVoiceReady ? Icons.check_circle_outline : Icons.download_for_offline_outlined),
                            label: Text(offlineVoiceBusy
                                ? AppLocale.pick('Загрузка голоса…', 'Дауыс жүктелуде…', 'Downloading voice…')
                                : offlineVoiceReady
                                    ? AppLocale.pick('Голос Иса скачан · Проверить', 'Иса дауысы жүктелген · Тексеру', 'Issai voice downloaded · Test')
                                    : AppLocale.pick('Скачать голос Иса', 'Иса дауысын жүктеу', 'Download Issai voice')),
                          ),
                        ),
                      ],
                    ),
                    if (offlineVoiceBusy) ...[
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: progressTotal > 0
                            ? (progressReceived / progressTotal).clamp(0.0, 1.0)
                            : null,
                        minHeight: 5,
                      ),
                    ],
                    OutlinedButton.icon(
                      onPressed: offlineVoiceBusy ? null : importVoiceArchive,
                      icon: const Icon(Icons.folder_open_outlined),
                      label: const Text('Файлдан таңдау (Выбрать архив с телефона)'),
                    ),
                    if (offlineVoiceFailed)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: offlineVoiceBusy ? null : loadAndPreviewVoice,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Қайталау'),
                        ),
                      ),
                    if (offlineVoiceStatus.isNotEmpty)
                      Text(offlineVoiceStatus, style: const TextStyle(fontSize: 12, color: Color(0xFF62666D))),
                  ],
                  const SizedBox(height: 12),
                  Text(AppLocale.tr('Голос телефона'), style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  if (voices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        AppLocale.tr('Список голосов Android пуст. Для казахского языка можно загрузить встроенный офлайн-пакет ISSAI выше.'),
                        style: const TextStyle(color: Color(0xFF9A5B00)),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: selectedExists ? selectedKey : '',
                      isExpanded: true,
                      items: <DropdownMenuItem<String>>[
                        DropdownMenuItem(value: '', child: Text(AppLocale.tr('Системный голос по умолчанию'))),
                        ...voices.map((v) {
                          final key = '${v['name']}|${v['locale']}';
                          return DropdownMenuItem(value: key, child: Text('${v['name']} · ${v['locale']}', overflow: TextOverflow.ellipsis));
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await _applySelectedVoice();
                        await _speakText(language == 'kk-KZ'
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
                      label: Text(AppLocale.tr(modes[index])),
                      selected: mode == index,
                      onSelected: (_) async {
                        mode = index;
                        _voiceMode = index;
                        refresh(() {});
                        await prefs.setInt('voice_mode', index);
                        if (index == 0) {
                          await _tts.stop();
                          await _kazakhVoiceService.stopAndUnload();
                        }
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
                  Slider(value: rate, min: 0.25, max: 0.75, divisions: 10, onChanged: (value) async {                    rate = value; refresh(() {});
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
      _gpsAvailable = false;
      _message = AppLocale.pick('Определяем GPS-положение…', 'GPS орналасқан жерді анықтауда…', 'Detecting GPS location…');
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception(AppLocale.pick('Включите геолокацию (GPS) на телефоне.', 'Телефонда геолокацияны (GPS) қосыңыз.', 'Turn on location services (GPS) on your phone.'));
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw Exception(AppLocale.pick('Разрешите приложению доступ к местоположению.', 'Қолданбаға орналасқан жерге кіруге рұқсат беріңіз.', 'Allow the app to access your location.'));
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception(AppLocale.pick('Доступ к GPS запрещён в настройках телефона.', 'Телефон баптауларында GPS қолжетімділігіне тыйым салынған.', 'GPS access is denied in your phone settings.'));
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          timeLimit: Duration(seconds: 20),
        ),
      );

      final point = LatLng(position.latitude, position.longitude);
      _recordGpsDiagnostic(event: 'LOCATE_FIX', position: position, rawPoint: point, displayPoint: point);
      if (!mounted) return;
      _freeDriveDisplayLocation = point;
      _freeDriveFixTimestamp = position.timestamp;
      _mapFollowEnabled = true;
      setState(() {
        _currentLocation = point;
        _gpsAvailable = true;
        _currentSpeedKmh = math.max(0, position.speed * 3.6).toDouble();
        if (position.speed >= 0.8 && position.heading.isFinite) {
          _gpsHeadingDegrees = position.heading;
        }
        _message = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocale.pick('GPS определён.', 'GPS анықталды.', 'GPS located.')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
      // Refresh the live position without interrupting the active navigation stream.
      // In particular, keep the Android foreground GPS subscription alive while
      // navigating; replacing it with a foreground-only stream can break tracking.
      if (_navigationActive) {
        final heading = _gpsHeadingDegrees;
        _updateNavigationCamera(
          point,
          17,
          heading != null && _currentSpeedKmh >= 5.4 ? heading : 0.0,
        );
        // Navigation already owns a background location stream. Do not cancel
        // and replace it just because the user tapped the GPS recenter button.
        if (_positionSubscription == null) {
          await _startLiveLocationUpdates(backgroundNavigation: true);
        }
      } else {
        _updateNavigationCamera(point, 16, _gpsHeadingDegrees ?? 0.0);
        await _startLiveLocationUpdates();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _gpsAvailable = false;
        _message = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }


  Future<void> _loadGpsDiagnosticsSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _gpsDiagnosticsEnabled = prefs.getBool('gps_diagnostics_enabled') ?? false;
    } catch (error) {
      debugPrint('BAKE GPS diagnostics preference unavailable: $error');
    }
  }

  Future<File> _gpsDiagnosticsFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/bake_gps_diagnostics.log');
  }

  void _recordGpsDiagnostic({
    required String event,
    Position? position,
    LatLng? rawPoint,
    LatLng? displayPoint,
    String? detail,
  }) {
    if (!_gpsDiagnosticsEnabled) return;
    final now = DateTime.now();
    final callbackGapMs = position == null || _lastGpsDiagnosticCallbackAt == null
        ? null
        : now.difference(_lastGpsDiagnosticCallbackAt!).inMilliseconds;
    final fixGapMs = position == null || _lastGpsDiagnosticFixAt == null
        ? null
        : position.timestamp.difference(_lastGpsDiagnosticFixAt!).inMilliseconds;
    final rawJumpMeters = rawPoint == null || _lastGpsDiagnosticRawPoint == null
        ? null
        : Geolocator.distanceBetween(
            _lastGpsDiagnosticRawPoint!.latitude,
            _lastGpsDiagnosticRawPoint!.longitude,
            rawPoint.latitude,
            rawPoint.longitude,
          );
    if (position != null) {
      _lastGpsDiagnosticCallbackAt = now;
      _lastGpsDiagnosticFixAt = position.timestamp;
      if (rawPoint != null) _lastGpsDiagnosticRawPoint = rawPoint;
    }
    final record = <String, Object?>{
      'event': event,
      'app_time': now.toIso8601String(),
      'detail': detail,
      'stream_active': _positionSubscription != null,
      'foreground': _appInForeground,
      'navigation_active': _navigationActive,
      'callback_gap_ms': callbackGapMs,
      'fix_gap_ms': fixGapMs,
      'raw_jump_m': rawJumpMeters,
      'fix_time': position?.timestamp.toIso8601String(),
      'fix_age_ms': position == null
          ? null
          : now.difference(position.timestamp).inMilliseconds,
      'accuracy_m': position?.accuracy,
      'speed_mps': position?.speed,
      'heading_deg': position?.heading,
      'mocked': position?.isMocked,
      'raw_lat': rawPoint?.latitude,
      'raw_lon': rawPoint?.longitude,
      'display_lat': displayPoint?.latitude,
      'display_lon': displayPoint?.longitude,
    };
    final line = jsonEncode(record);
    _gpsDiagnosticWriteQueue = _gpsDiagnosticWriteQueue.then<void>((_) async {
      final file = await _gpsDiagnosticsFile();
      await file.writeAsString('$line\n', mode: FileMode.append, flush: false);
    }).catchError((Object error) {
      debugPrint('BAKE GPS diagnostic write failed: $error');
    });
  }

  Future<void> _openGpsDiagnostics() async {
    final prefs = await SharedPreferences.getInstance();
    var enabled = prefs.getBool('gps_diagnostics_enabled') ?? false;
    _gpsDiagnosticsEnabled = enabled;
    final file = await _gpsDiagnosticsFile();
    var logText = await file.exists() ? await file.readAsString() : '';
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, refreshDialog) => AlertDialog(
          title: const Text('Диагностика GPS'),
          content: SizedBox(
            width: 520,
            height: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(enabled
                    ? 'Запись включена. Проедьте обычным маршрутом 10–15 минут.'
                    : 'Запись выключена. Включите её перед поездкой.'),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    color: const Color(0xFFF3F4F6),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        logText.isEmpty ? 'Записей пока нет.' : logText,
                        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                if (enabled) {
                  _recordGpsDiagnostic(event: 'DIAGNOSTICS_STOP');
                  enabled = false;
                  _gpsDiagnosticsEnabled = false;
                  await prefs.setBool('gps_diagnostics_enabled', false);
                } else {
                  await file.writeAsString('');
                  _lastGpsDiagnosticCallbackAt = null;
                  _lastGpsDiagnosticFixAt = null;
                  _lastGpsDiagnosticRawPoint = null;
                  enabled = true;
                  _gpsDiagnosticsEnabled = true;
                  await prefs.setBool('gps_diagnostics_enabled', true);
                  _recordGpsDiagnostic(event: 'DIAGNOSTICS_START');
                }
                await _gpsDiagnosticWriteQueue;
                logText = await file.exists() ? await file.readAsString() : '';
                refreshDialog(() {});
              },
              child: Text(enabled ? 'Остановить запись' : 'Начать запись'),
            ),
            TextButton(
              onPressed: () async {
                await _gpsDiagnosticWriteQueue;
                await _gpsDiagnosticWriteQueue;
                logText = await file.exists() ? await file.readAsString() : '';
                refreshDialog(() {});
              },
              child: const Text('Обновить'),
            ),
            TextButton(
              onPressed: () async {
                await _gpsDiagnosticWriteQueue;
                logText = await file.exists() ? await file.readAsString() : '';
                await Clipboard.setData(ClipboardData(text: logText));
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('GPS-журнал скопирован')),
                  );
                }
              },
              child: const Text('Копировать журнал'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startLiveLocationUpdates({
    bool backgroundNavigation = false,
    bool waitForFirstFix = false,
  }) {
    final previousOperation = _gpsStreamQueue;
    final operationCompleter = Completer<void>();
    _gpsStreamQueue = operationCompleter.future;
    return () async {
      try {
        await previousOperation;
        await _startLiveLocationUpdatesInternal(
          backgroundNavigation: backgroundNavigation,
          waitForFirstFix: waitForFirstFix,
        );
      } finally {
        if (!operationCompleter.isCompleted) operationCompleter.complete();
      }
    }();
  }

  /// Stop GPS through the same queue as starts so lifecycle callbacks cannot
  /// overlap cancellation with creation of a replacement subscription.
  Future<void> _stopLiveLocationUpdates({String reason = 'requested'}) {
    _gpsStopPending = true;
    final previousOperation = _gpsStreamQueue;
    final operationCompleter = Completer<void>();
    _gpsStreamQueue = operationCompleter.future;
    return () async {
      try {
        await previousOperation;
        final subscription = _positionSubscription;
        _positionSubscription = null;
        if (subscription != null) {
          _recordGpsDiagnostic(event: 'STREAM_CANCEL_REQUEST', detail: reason);
          await subscription.cancel();
          _recordGpsDiagnostic(event: 'STREAM_CANCEL_COMPLETE', detail: reason);
        }
      } finally {
        _gpsStopPending = false;
        if (!operationCompleter.isCompleted) operationCompleter.complete();
      }
    }();
  }

  Future<void> _startLiveLocationUpdatesInternal({
    bool backgroundNavigation = false,
    bool waitForFirstFix = false,
  }) async {
    final previousSubscription = _positionSubscription;
    if (previousSubscription != null) {
      _recordGpsDiagnostic(event: 'STREAM_CANCEL', detail: 'Subscription replaced or stopped');
    }
    _positionSubscription = null;
    await previousSubscription?.cancel();
    if (!mounted) return;

    final firstFix = Completer<void>();
    final LocationSettings locationSettings;
    if (backgroundNavigation && defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(seconds: 1),
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
        distanceFilter: 1,
      );
    }

    _recordGpsDiagnostic(
      event: 'STREAM_START',
      detail: backgroundNavigation && defaultTargetPlatform == TargetPlatform.android
          ? 'AndroidSettings; interval=1000ms; distanceFilter=1m; bestForNavigation'
          : 'LocationSettings; interval=not-explicit; distanceFilter=1m; bestForNavigation',
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (position) {
        if (!mounted) return;
        final wasWaitingForNavigationFix =
            _navigationActive && _currentLocation == null;
        final point = LatLng(position.latitude, position.longitude);
        final displayPoint = _navigationActive
            ? point
            : _updateFreeDriveDisplayPosition(position, point);
        _recordGpsDiagnostic(
          event: 'GPS_FIX',
          position: position,
          rawPoint: point,
          displayPoint: displayPoint,
        );
        final navigationPoint = _navigationActive
            ? _matchNavigationPosition(position, point)
            : point;
        _navigationMatchedLocation = _navigationActive ? navigationPoint : null;
        setState(() {
          _currentLocation = point;
          _gpsAvailable = true;
          _currentSpeedKmh = math.max(0, position.speed * 3.6).toDouble();
          // Ignore unstable compass headings while stopped or moving very slowly.
          if (position.speed >= 0.8 && position.heading.isFinite) {
            _gpsHeadingDegrees = position.heading;
          }
        });
        final lastRouteLineSyncPoint = _lastRouteLineSyncPoint;
        final routeDisplayPoint = _navigationActive ? navigationPoint : point;
        final shouldRefreshRouteLine = _navigationActive &&
            (lastRouteLineSyncPoint == null ||
                Geolocator.distanceBetween(
                  lastRouteLineSyncPoint.latitude,
                  lastRouteLineSyncPoint.longitude,
                  routeDisplayPoint.latitude,
                  routeDisplayPoint.longitude,
                ) >= 20);
        final annotationNow = DateTime.now();
        final shouldRefreshAnnotations = shouldRefreshRouteLine ||
            _lastMapAnnotationUpdateAt == null ||
            annotationNow.difference(_lastMapAnnotationUpdateAt!) >=
                const Duration(milliseconds: 350);
        if (shouldRefreshAnnotations) {
          _lastMapAnnotationUpdateAt = annotationNow;
        }
        _checkSpeedingWarning();
        _updateConfirmedCameraWarning(
          point,
          position.heading.isFinite && position.speed >= 0.8
              ? position.heading
              : null,
        );
        unawaited(_refreshRoadSpeedLimit(point));
        // Load and display nearby speed cameras whenever GPS is available,
        // including normal map browsing without an active route.
        unawaited(_updateRoadAlerts(
          point,
          position.heading.isFinite && position.speed >= 0.8
              ? position.heading
              : null,
        ));
        unawaited(_updateRoadFeatureWarnings(
          point,
          position.heading.isFinite && position.speed >= 0.8
              ? position.heading
              : null,
        ));

        // The first GPS fix may arrive after navigation has already started.
        // Initialize the camera and speak the current instruction exactly once.
        if (wasWaitingForNavigationFix && _navigationActive) {
          unawaited(_speakCurrentInstruction());
        }

        // Follow GPS with one coordinated camera update instead of competing
        // position and bearing animations.
        if (position.speed >= 1.5 && _headingUpGestureActive) {
          _headingUpResumeTimer?.cancel();
          _headingUpGestureActive = false;
        }
        final cameraNow = DateTime.now();
        final cameraUpdateInterval = _isFlutterMapDisplayed
            ? const Duration(milliseconds: 300)
            : const Duration(milliseconds: 450);
        final cameraUpdateDue = _lastCameraUpdateAt == null ||
            cameraNow.difference(_lastCameraUpdateAt!) >= cameraUpdateInterval;
        if (_appInForeground && cameraUpdateDue && _mapFollowEnabled && !_headingUpGestureActive) {
          _lastCameraUpdateAt = cameraNow;
          final cameraCenter = _mapCameraCenter;
          final cameraTarget = _navigationActive ? navigationPoint : displayPoint;
          final shouldRecenter = Geolocator.distanceBetween(
                cameraCenter.latitude, cameraCenter.longitude,
                cameraTarget.latitude, cameraTarget.longitude,
              ) > (_isFlutterMapDisplayed ? 3 : 5);
          final routeHeading = _navigationActive && _routePoints.length > 1
              ? _routeBearingAt(cameraTarget)
              : null;
          final heading = _navigationActive
              ? (routeHeading ?? _gpsHeadingDegrees ?? _lastCameraHeadingDegrees ?? 0.0)
              : (_northUpLocked ? 0.0 : (_gpsHeadingDegrees ?? _lastCameraHeadingDegrees ?? 0.0));
          final normalizedHeading = (heading % 360 + 360) % 360;
          final previousHeading = _lastCameraHeadingDegrees;
          final difference = previousHeading == null
              ? 360.0
              : ((normalizedHeading - previousHeading + 540) % 360) - 180;
          final shouldRotate = difference.abs() >= (_isFlutterMapDisplayed ? 4 : 6);
          if (shouldRecenter || shouldRotate || wasWaitingForNavigationFix) {
            _updateNavigationCamera(
              cameraTarget,
              math.max(_mapCameraZoom, _navigationActive ? 17.0 : 16.0).toDouble(),
              normalizedHeading,
            );
          }
        }

        if (!firstFix.isCompleted) firstFix.complete();
        _updateNavigationProgress(navigationPoint);
        _checkForOffRoute(position);
      },
      onError: (Object error) {
        _recordGpsDiagnostic(event: 'STREAM_ERROR', detail: error.toString());
        if (waitForFirstFix && !firstFix.isCompleted) {
          firstFix.completeError(error, StackTrace.current);
        }
        if (!mounted) return;
        setState(() {
          _gpsAvailable = false;
          _message = AppLocale.pick('Потеряна связь с GPS. Проверьте геолокацию телефона.', 'GPS байланысы жоғалды. Телефон геолокациясын тексеріңіз.', 'GPS signal lost. Check your phone location settings.');
        });
      },
      onDone: () {
        _recordGpsDiagnostic(event: 'STREAM_DONE', detail: 'Geolocator position stream closed');
      },
    );

    if (waitForFirstFix) {
      await firstFix.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException(
          AppLocale.pick(
            'GPS не передал координаты за 15 секунд. Проверьте сигнал и разрешение на геолокацию.',
            'GPS 15 секунд ішінде координаттарды жібермеді. Сигнал мен геолокация рұқсатын тексеріңіз.',
            'GPS did not provide a location within 15 seconds. Check the signal and location permission.',
          ),
        ),
      );
    }
  }


  double _distanceKm(LatLng a, LatLng b) {
    return Geolocator.distanceBetween(
      a.latitude, a.longitude, b.latitude, b.longitude,
    ) / 1000;
  }

  String _photonQuery(String value) => value.trim();

  bool _isLikelyCityQuery(String value) {
    final query = value.trim().toLowerCase().replaceAll('ё', 'е');
    if (query.length < 2 || query.length > 48) return false;
    if (RegExp(r'^(?:г\.?\s*|город\s+|қала\s+)', caseSensitive: false).hasMatch(query)) {
      return true;
    }
    const kazakhstanCities = <String>{
      'шымкент', 'алматы', 'астана', 'нур-султан', 'тараз', 'туркестан',
      'сарыагаш', 'кызылорда', 'караганда', 'актобе', 'актау', 'атырау',
      'павлодар', 'семей', 'усть-каменогорск', 'оскемен', 'костанай',
      'петропавловск', 'кокшетау', 'жезказган', 'темиртау', 'талдыкорган',
      'экибастуз', 'рудный', 'жанаозен', 'конаев', 'байконур',
    };
    return kazakhstanCities.contains(query);
  }

  bool _isPhotonCityFeature(Map<String, dynamic> feature) {
    final raw = feature['properties'];
    final properties = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    // Photon returns GeoJSON GeocodeJSON properties: place type is stored
    // in osm_key/osm_value, not reliably in a generic "type" property.
    final osmKey = properties['osm_key']?.toString().toLowerCase();
    final osmValue = properties['osm_value']?.toString().toLowerCase();
    final legacyType = properties['type']?.toString().toLowerCase();
    const settlementTypes = <String>{
      'city', 'town', 'village', 'hamlet', 'locality',
    };
    return (osmKey == 'place' && settlementTypes.contains(osmValue)) ||
        settlementTypes.contains(legacyType);
  }

  String valueForPhotonFeature(Map<String, dynamic> feature) {
    final address = _photonFeatureAddress(feature);
    return address.isEmpty ? 'Шымкент' : address;
  }

  String _photonFeatureAddress(Map<String, dynamic> feature) {
    final raw = feature['properties'];
    final properties = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final displayLabel = properties['display_label']?.toString().trim() ?? '';
    if (displayLabel.isNotEmpty) return displayLabel;
    final parts = <String>[];
    final name = properties['name']?.toString().trim() ?? '';
    final street = properties['street']?.toString().trim() ?? '';
    final house = properties['housenumber']?.toString().trim() ?? '';
    final district = (properties['district'] ?? properties['suburb'])?.toString().trim() ?? '';
    final city = properties['city']?.toString().trim() ?? '';
    if (name.isNotEmpty && name != street) parts.add(name);
    if (street.isNotEmpty) parts.add(street);
    if (house.isNotEmpty) parts.add(house);
    if (district.isNotEmpty && !parts.contains(district)) parts.add(district);
    if (city.isNotEmpty && !parts.contains(city)) parts.add(city);
    if (parts.isEmpty) {
      final label = properties['label']?.toString().trim() ?? '';
      if (label.isNotEmpty) parts.add(label);
    }
    return parts.join(', ');
  }

  String _photonFeatureStreetAddress(Map<String, dynamic> feature) {
    final raw = feature['properties'];
    final p = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final direct = p['address']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final street = p['street']?.toString().trim() ?? '';
    final house = p['housenumber']?.toString().trim() ?? '';
    final district = (p['district'] ?? p['suburb'])?.toString().trim() ?? '';
    return [if (street.isNotEmpty) street, if (house.isNotEmpty) house,
      if (district.isNotEmpty) district].join(', ');
  }

  String? _requestedHouseNumber(String query) {
    final normalized = query.trim().toLowerCase().replaceAll('ё', 'е');
    final match = RegExp(
      r'(?:^|[\s,])(?:дом\s*|д\.?\s*|№\s*)?(\d+[0-9a-zа-я]?(?:/\d+[0-9a-zа-я]?)?)\s*$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return null;
    final streetPart = normalized.substring(0, match.start).trim();
    if (streetPart.isEmpty ||
        RegExp(r'\b(?:школа|мектеп|микрорайон|мкр|район|№|mega|мега|центр|торговый|плаза|plaza|mall|базар|рынок|аэропорт|вокзал)\b', caseSensitive: false).hasMatch(streetPart) ||
        streetPart.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).length < 2) {
      return null;
    }
    return _normalizeHouseNumber(match.group(1)!);
  }

  String _normalizeHouseNumber(String value) => value
      .toLowerCase()
      .replaceAll('ё', 'е')
      .replaceAll(RegExp(r'[^0-9a-zа-я/]'), '');

  bool _matchesRequestedHouseNumber(Map<String, dynamic> feature, String query) {
    final requested = _requestedHouseNumber(query);
    if (requested == null) return true;
    final raw = feature['properties'];
    final properties = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final actual = properties['housenumber'] ?? properties['house_number'] ?? properties['house'];
    if (actual == null || actual.toString().trim().isEmpty) return false;
    return _normalizeHouseNumber(actual.toString()) == requested;
  }

  List<Map<String, dynamic>> _keepExactHouseNumber(
    List<Map<String, dynamic>> features,
    String query,
  ) {
    if (_requestedHouseNumber(query) == null) return features;
    return features
        .where((feature) => _matchesRequestedHouseNumber(feature, query))
        .toList(growable: false);
  }

  String _photonDestinationAddress(Map<String, dynamic> feature) {
    final raw = feature['properties'];
    final p = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    String value(String key) => (p[key] ?? '').toString().trim();
    final name = value('name');
    final street = value('street');
    final house = value('housenumber');
    final district = value('district').isNotEmpty ? value('district') : value('suburb');
    final city = value('city');
    final address = value('address');
    final display = value('display_label').isNotEmpty
        ? value('display_label')
        : value('label');

    // Keep a POI/landmark name and its street address together. The old
    // implementation returned the street first and discarded the POI name.
    final streetParts = <String>[
      if (street.isNotEmpty) street,
      if (house.isNotEmpty && house != street) house,
    ];
    final streetLine = streetParts.join(', ');
    final result = <String>[];
    if (name.isNotEmpty && name != street && name != house) result.add(name);
    if (streetLine.isNotEmpty) result.add(streetLine);
    if (streetLine.isEmpty && address.isNotEmpty && !result.contains(address)) {
      result.add(address);
    }
    if (district.isNotEmpty && !result.contains(district)) result.add(district);
    if (city.isNotEmpty && !result.contains(city)) result.add(city);
    if (result.isNotEmpty) {
      final ordered = <String>[
        if (district.isNotEmpty) district,
        if (name.isNotEmpty && name != street && name != house) name,
        if (street.isNotEmpty) street,
        if (house.isNotEmpty && house != street) 'дом $house',
        if (city.isNotEmpty && city != district) city,
      ];
      final unique = <String>[];
      for (final part in ordered) {
        if (part.isNotEmpty && !unique.any((item) => item.toLowerCase() == part.toLowerCase())) {
          unique.add(part);
        }
      }
      return unique.join(', ');
    }

    // Photon may return only a formatted label for a road/house feature.
    if (display.isNotEmpty) return display;
    return _photonFeatureAddress(feature);
  }

  double? _photonFeatureDistanceMeters(Map<String, dynamic> feature) {
    final origin = _currentLocation;
    final geometry = feature['geometry'];
    final coordinates = geometry is Map ? geometry['coordinates'] : null;
    if (origin == null || coordinates is! List || coordinates.length < 2) return null;
    final lon = double.tryParse(coordinates[0].toString());
    final lat = double.tryParse(coordinates[1].toString());
    if (lat == null || lon == null || !lat.isFinite || !lon.isFinite) return null;
    return Geolocator.distanceBetween(origin.latitude, origin.longitude, lat, lon);
  }

  int _searchFeatureRelevanceScore(
    Map<String, dynamic> feature,
    String query,
  ) {
    final needle = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (needle.isEmpty) return 0;
    final raw = feature['properties'];
    final properties = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    String value(String key) =>
        (properties[key] ?? '').toString().trim().toLowerCase();
    String normalize(String value) => value
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[^0-9a-zа-яәғқңөұүһі]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final normalizedNeedle = normalize(needle);
    final name = normalize(value('name'));
    final label = normalize([
      value('display_label'),
      value('label'),
      value('address'),
      value('street'),
      value('housenumber'),
      value('house_number'),
      value('district'),
      value('suburb'),
      value('city'),
      value('name'),
    ].where((part) => part.isNotEmpty).join(' '));
    var score = 0;
    if (name == normalizedNeedle) {
      score += 1200;
    } else if (name.startsWith(normalizedNeedle)) {
      score += 800;
    } else if (name.contains(normalizedNeedle)) {
      score += 500;
    }
    if (label == normalizedNeedle) {
      score += 600;
    } else if (label.contains(normalizedNeedle)) {
      score += 350;
    }
    final queryTokens = normalizedNeedle.split(' ').where((token) => token.isNotEmpty);
    if (queryTokens.isNotEmpty && queryTokens.every(label.contains)) {
      score += 300;
    }
    if (_isLikelyCityQuery(query) && _isPhotonCityFeature(feature)) {
      // A countrywide settlement match must outrank nearby Shymkent POIs
      // returned by the local index for the same short city-name query.
      score += 1000;
    }
    return score;
  }

  void _sortSearchFeatures(
    List<Map<String, dynamic>> features,
    String query,
  ) {
    features.sort((left, right) {
      final relevance = _searchFeatureRelevanceScore(right, query)
          .compareTo(_searchFeatureRelevanceScore(left, query));
      if (relevance != 0) return relevance;
      return (_photonFeatureDistanceMeters(left) ?? double.infinity)
          .compareTo(_photonFeatureDistanceMeters(right) ?? double.infinity);
    });
  }

  String _formatSearchDistance(Map<String, dynamic> feature) {
    final distance = _photonFeatureDistanceMeters(feature);
    if (distance == null) return '—';
    return distance < 1000 ? '${distance.round()} м' : '${(distance / 1000).toStringAsFixed(1)} км';
  }

  static DateTime? _lastNominatimCityRequestAt;

  Future<List<Map<String, dynamic>>> _fetchNominatimCityFeatures(String query) async {
    final previous = _lastNominatimCityRequestAt;
    if (previous != null) {
      final elapsed = DateTime.now().difference(previous).inMilliseconds;
      final waitMs = 1000 - elapsed;
      if (waitMs > 0) await Future<void>.delayed(Duration(milliseconds: waitMs));
    }
    _lastNominatimCityRequestAt = DateTime.now();

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query.trim(),
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '20',
      'countrycodes': 'kz',
      'featureType': 'city',
    });
    try {
      final response = await http.get(uri, headers: const {
        'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)',
        'Accept': 'application/json',
        'Accept-Language': 'ru,kk,en',
      }).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        debugPrint('BAKE Nominatim city search: HTTP ${response.statusCode}; query="${query.trim()}"; bytes=${response.bodyBytes.length}');
        return <Map<String, dynamic>>[];
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        debugPrint('BAKE Nominatim city search: unexpected JSON type ${decoded.runtimeType}');
        return <Map<String, dynamic>>[];
      }
      final features = decoded.whereType<Map>().map((item) {
      final result = Map<String, dynamic>.from(item);
      final addressRaw = result['address'];
      final address = addressRaw is Map
          ? Map<String, dynamic>.from(addressRaw)
          : <String, dynamic>{};
      final lat = double.tryParse(result['lat']?.toString() ?? '');
      final lon = double.tryParse(result['lon']?.toString() ?? '');
      if (lat == null || lon == null) return <String, dynamic>{};
      final name = (result['name'] ?? address['city'] ?? address['town'] ??
          address['village'] ?? result['display_name'] ?? query).toString();
      final placeType = (result['addresstype'] ?? result['type'] ?? 'city').toString();
      return <String, dynamic>{
        'type': 'Feature',
        'properties': <String, dynamic>{
          'name': name,
          'display_label': (result['display_name'] ?? name).toString(),
          'city': (address['city'] ?? address['town'] ?? address['village'] ?? name).toString(),
          'osm_key': 'place',
          'osm_value': placeType == 'town' || placeType == 'village' || placeType == 'hamlet'
              ? placeType
              : 'city',
          'osm_type': result['osm_type'],
          'osm_id': result['osm_id'],
          'source': 'nominatim',
        },
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[lon, lat],
        },
      };
      }).where((feature) => feature.isNotEmpty).toList();
      debugPrint('BAKE Nominatim city search: HTTP 200; query="${query.trim()}"; results=${features.length}');
      return features;
    } catch (error) {
      debugPrint('BAKE Nominatim city search failed: query="${query.trim()}"; error=$error');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchNominatimTestFeatures(String query) async {
    final now = DateTime.now();
    final previous = _lastNominatimTestRequestAt;
    if (previous != null) {
      final elapsed = now.difference(previous);
      if (elapsed < const Duration(seconds: 1)) {
        await Future<void>.delayed(const Duration(seconds: 1) - elapsed);
      }
    }
    _lastNominatimTestRequestAt = DateTime.now();
    return _fetchNominatimAddressFeatures(query);
  }

  Future<List<Map<String, dynamic>>> _fetchNominatimAddressFeatures(String query) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query.trim(),
      'format': 'jsonv2',
      'addressdetails': '1',
      'namedetails': '1',
      'limit': '20',
      'countrycodes': 'kz',
    });
    try {
      final response = await http.get(uri, headers: const {
        'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)',
        'Accept': 'application/json',
        'Accept-Language': 'ru,kk,en',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('BAKE Nominatim address search: HTTP ${response.statusCode}');
        return <Map<String, dynamic>>[];
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((item) {
        final result = Map<String, dynamic>.from(item);
        final lat = double.tryParse(result['lat']?.toString() ?? '');
        final lon = double.tryParse(result['lon']?.toString() ?? '');
        if (lat == null || lon == null) return <String, dynamic>{};
        final rawAddress = result['address'];
        final address = rawAddress is Map
            ? Map<String, dynamic>.from(rawAddress)
            : <String, dynamic>{};
        final name = (result['name'] ??
            (result['namedetails'] is Map ? (result['namedetails'] as Map)['name'] : null) ??
            address['road'] ?? result['display_name'] ?? query).toString();
        return <String, dynamic>{
          'type': 'Feature',
          'properties': <String, dynamic>{
            'name': name,
            'street': address['road'] ?? address['pedestrian'] ?? address['residential'] ?? '',
            'housenumber': address['house_number'] ?? '',
            'district': address['suburb'] ?? address['city_district'] ?? address['neighbourhood'] ?? '',
            'city': address['city'] ?? address['town'] ?? address['village'] ?? '',
            'display_label': result['display_name'] ?? name,
            'osm_type': result['osm_type'],
            'osm_id': result['osm_id'],
            'source': 'nominatim',
          },
          'geometry': <String, dynamic>{
            'type': 'Point',
            'coordinates': <double>[lon, lat],
          },
        };
      }).where((feature) => feature.isNotEmpty).toList(growable: false);
    } catch (error) {
      debugPrint('BAKE Nominatim address search failed: $error');
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchPhotonFeatures(String query, {bool includeCitySearch = false, bool includeNominatimCitySearch = true, bool includeNominatimAddressFallback = true, int resultLimit = 50}) async {
    Future<List<Map<String, dynamic>>> request(Uri uri) async {
      try {
        final response = await http.get(uri, headers: const {
          'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)',
          'Accept': 'application/geo+json, application/json',
        }).timeout(const Duration(seconds: 7));
        if (response.statusCode != 200) {
          debugPrint('BAKE Photon search: HTTP ${response.statusCode}; path=${uri.path}');
          return <Map<String, dynamic>>[];
        }
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map) return <Map<String, dynamic>>[];
        final rawFeatures = decoded['features'];
        if (rawFeatures is! List) return <Map<String, dynamic>>[];
        return rawFeatures.whereType<Map>().map(
          (item) => Map<String, dynamic>.from(item),
        ).where((feature) {
          final geometry = feature['geometry'];
          final coordinates = geometry is Map ? geometry['coordinates'] : null;
          return coordinates is List && coordinates.length >= 2 &&
              double.tryParse(coordinates[0].toString()) != null &&
              double.tryParse(coordinates[1].toString()) != null;
        }).toList();
      } catch (error) {
        debugPrint('BAKE Photon search failed: path=${uri.path}; error=$error');
        return <Map<String, dynamic>>[];
      }
    }

    final trimmed = query.trim();
    if (trimmed.isEmpty) return <Map<String, dynamic>>[];

    final apiQueries = <String>{_photonQuery(trimmed)};
    final schoolMatch = RegExp(
      r'(?:школа\s*№?\s*(\d+)|№\s*(\d+)\s*школа|(\d+)\s*школа)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final schoolNumber = schoolMatch?.group(1) ??
        schoolMatch?.group(2) ??
        schoolMatch?.group(3);
    if (schoolNumber != null) {
      apiQueries
        ..add('Школа №$schoolNumber')
        ..add('$schoolNumber школа')
        ..add('Мектеп $schoolNumber');
    } else if (includeCitySearch && !_isLikelyCityQuery(trimmed) &&
        !trimmed.toLowerCase().contains('шымкент')) {
      apiQueries.add('$trimmed Шымкент');
      // OSM/Photon often stores large shopping centres under an English
      // brand name rather than the Russian generic "мегацентр".
      if (RegExp(r'мега\s*центр|мегацентр', caseSensitive: false).hasMatch(trimmed)) {
        apiQueries
          ..add('MEGA Planet Шымкент')
          ..add('Mega Center Шымкент');
      }
    }

    final addressMatch = RegExp(
      r'^(.*?)\s*(?:,|\s)\s*(?:дом\s*|д\.?\s*|№\s*)?(\d+[0-9а-яa-z]*(?:/\d+[0-9а-яa-z]*)?)$',
      caseSensitive: false,
    ).firstMatch(trimmed);
    final requestUris = <Uri>[];
    // Start the city lookup alongside Photon so a slow Nominatim response
    // cannot consume the entire online-search timeout before Photon starts.
    final nominatimCityFuture = includeCitySearch && includeNominatimCitySearch && _isLikelyCityQuery(trimmed)
        ? _fetchNominatimCityFeatures(trimmed)
        : Future<List<Map<String, dynamic>>>.value(<Map<String, dynamic>>[]);
    for (final apiQuery in apiQueries.take(4)) {
      requestUris.add(Uri.https('photon.komoot.io', '/api/', {
        'q': apiQuery,
        'lang': 'ru',
        'limit': resultLimit.toString(),
        'countrycode': 'KZ',
      }));
    }

    // Address-shaped input also gets a structured street + house-number lookup.
    if (addressMatch != null && schoolNumber == null &&
        !RegExp(r'школа|мектеп|мега|центр|базар|рынок|плаза|plaza|mall|аэропорт|вокзал', caseSensitive: false)
            .hasMatch(addressMatch.group(1)!)) {
      final street = addressMatch.group(1)!.trim();
      final house = addressMatch.group(2)!.trim();
      // Use the street field for a street name. The previous implementation
      // incorrectly sent the street text as a district, wasting a Photon request.
      requestUris.add(Uri.https('photon.komoot.io', '/structured', {
        'street': street,
        'housenumber': house,
        'city': 'Шымкент',
        'lang': 'ru',
        'limit': resultLimit.toString(),
      }));
    }
    final groups = await Future.wait(
      requestUris.toSet().take(6).map(request),
    );
    final nominatimCityResults = await nominatimCityFuture;
    final merged = <Map<String, dynamic>>[...nominatimCityResults];
    final seen = <String>{};
    for (final group in groups) {
      for (final feature in group) {
        final properties = feature['properties'] is Map
            ? Map<String, dynamic>.from(feature['properties'] as Map)
            : <String, dynamic>{};
        final geometry = feature['geometry'] as Map;
        final coordinates = geometry['coordinates'] as List;
        final identity = properties['osm_id'] != null
            ? '${properties['osm_type'] ?? ''}:${properties['osm_id']}'
            : '${properties['name'] ?? ''}:${coordinates[0]}:${coordinates[1]}';
        if (seen.add(identity)) merged.add(feature);
      }
    }
    if (!_isLikelyCityQuery(trimmed)) {
      final queryTokens = trimmed.toLowerCase()
          .replaceAll('ё', 'е')
          .replaceAll(RegExp(r'[^0-9a-zа-яәғқңөұүһі]+'), ' ')
          .split(RegExp(r'\s+'))
          .where((token) => token.length > 1 &&
              token != 'шымкент' && token != 'город' && token != 'г')
          .toList();
      final hasStrongMatch = merged.any((feature) {
        final raw = feature['properties'];
        final properties = raw is Map
            ? Map<String, dynamic>.from(raw)
            : <String, dynamic>{};
        final searchable = [
          properties['name'],
          properties['display_label'],
          properties['label'],
          properties['address'],
          properties['street'],
          properties['housenumber'],
          properties['house_number'],
          properties['district'],
          properties['suburb'],
          properties['city'],
        ].whereType<Object>().join(' ').toLowerCase()
            .replaceAll('ё', 'е')
            .replaceAll(RegExp(r'[^0-9a-zа-яәғқңөұүһі]+'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        return queryTokens.isNotEmpty &&
            queryTokens.every((token) => searchable.contains(token));
      });
      if (includeNominatimAddressFallback && (merged.isEmpty || !hasStrongMatch)) {
        // Photon can return nearby but unrelated objects and suppress a valid
        // OSM match. Retry the full place/street phrase through Nominatim.
        final fallbackQuery = includeCitySearch &&
                !trimmed.toLowerCase().contains('шымкент')
            ? '$trimmed Шымкент'
            : trimmed;
        merged.addAll(await _fetchNominatimAddressFeatures(fallbackQuery));
      }
    }
    return merged.take(150).toList();
  }
  Future<List<Map<String, dynamic>>> _fetchAddressFeatures(String query, {LatLng? near, bool includeNominatimCitySearch = true, bool includeNominatimAddressFallback = true, bool includeExpandedPhotonQueries = true}) async {
    if (_nominatimTestMode) {
      try {
        // Isolated provider test: no Photon, local index, saved places, or road reports.
        final results = await _fetchNominatimTestFeatures(query);
        _sortSearchFeatures(results, query);
        return results;
      } catch (error) {
        debugPrint('BAKE Nominatim isolated search failed: $error');
        return <Map<String, dynamic>>[];
      }
    }
    final needle = query.trim().toLowerCase();
    final reportFeatures = <Map<String, dynamic>>[];
    final seenReports = <String>{};
    Map<String, dynamic> toFeature(Map<String, dynamic> report) {
      final lat = (report['latitude'] as num).toDouble();
      final lon = (report['longitude'] as num).toDouble();
      final title = (report['title'] ?? report['type'] ?? 'Дорожная отметка').toString();
      final address = (report['address'] ?? '').toString();
      return <String, dynamic>{
        'type': 'Feature', '_roadReport': true,
        'properties': {'name': title, 'display_label': address.isEmpty ? title : '$title · $address',
          'address': address, 'comment': report['comment'] ?? '', 'source': 'road_reports',
          'report_id': report['id']?.toString()},
        'geometry': {'type': 'Point', 'coordinates': <double>[lon, lat]},
      };
    }
    bool matches(Map<String, dynamic> row) {
      final status = row['status']?.toString();
      if (status != 'Подтверждено' && status != 'approved') return false;
      return [row['title'], row['address'], row['comment'], row['type']]
          .whereType<Object>().any((value) => value.toString().toLowerCase().contains(needle));
    }
    for (final row in _confirmedRoadReports) {
      final id = row['id']?.toString() ?? '';
      if (matches(row) && seenReports.add(id)) reportFeatures.add(toFeature(row));
    }
    if (RoadReportSyncService.isInitialized) {
      try {
        for (final row in await RoadReportSyncService.searchConfirmedReports(query)) {
          final id = row['id']?.toString() ?? '';
          if (matches(row) && seenReports.add(id)) reportFeatures.add(toFeature(row));
        }
      } catch (error) {
        debugPrint('BAKE confirmed address search from Supabase unavailable: $error');
      }
    }
    // Places created by the user in "Мои места" must be routable from search too.
    final savedPlaceFeatures = <Map<String, dynamic>>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPlaces = prefs.getStringList('my_custom_places') ?? <String>[];
      final savedPoints = prefs.getStringList('my_custom_place_points_v1') ?? <String>[];
      final normalizedNeedle = needle.replaceAll('ё', 'е')
          .replaceAll(RegExp(r'[^0-9a-zа-яәғқңөұүһі]+'), ' ').trim();
      final queryTokens = normalizedNeedle.split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty).toList();
      for (var index = 0; index < savedPlaces.length; index++) {
        final parts = savedPlaces[index].split('|');
        final name = parts.isEmpty ? '' : parts.first.trim();
        final address = parts.length > 1 ? parts.sublist(1).join('|').trim() : '';
        final searchable = '$name $address'.toLowerCase().replaceAll('ё', 'е')
            .replaceAll(RegExp(r'[^0-9a-zа-яәғқңөұүһі]+'), ' ').trim();
        if (name.isEmpty || queryTokens.isEmpty ||
            !queryTokens.every((token) => searchable.contains(token))) continue;
        if (index >= savedPoints.length || savedPoints[index].trim().isEmpty) continue;
        final coordinates = savedPoints[index].split(',');
        if (coordinates.length < 2) continue;
        final lat = double.tryParse(coordinates[0].trim());
        final lon = double.tryParse(coordinates[1].trim());
        if (lat == null || lon == null || !lat.isFinite || !lon.isFinite ||
            lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
        savedPlaceFeatures.add(<String, dynamic>{
          'type': 'Feature',
          '_savedPlace': true,
          'properties': <String, dynamic>{
            'name': name,
            'display_label': address.isEmpty ? name : '$name · $address',
            'address': address,
            'source': 'BAKE saved places',
          },
          'geometry': <String, dynamic>{
            'type': 'Point',
            'coordinates': <double>[lon, lat],
          },
        });
      }
    } catch (error) {
      debugPrint('BAKE saved places address search unavailable: $error');
    }

    // Map-selected reverse-geocoded addresses retain exact coordinates and
    // are searchable later without relying on a fresh geocoder response.
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = prefs.getStringList('map_address_history_v1') ?? <String>[];
      final normalizedNeedle = needle.toLowerCase().replaceAll('ё', 'е')
          .replaceAll(RegExp(r'[^0-9a-zа-яәғқңөұүһі]+'), ' ').trim();
      final tokens = normalizedNeedle.split(RegExp(r'\s+')).where((v) => v.isNotEmpty).toList();
      for (final rawRecord in records) {
        try {
          final record = jsonDecode(rawRecord);
          if (record is! Map) continue;
          final address = (record['address'] ?? '').toString().trim();
          final lat = double.tryParse(record['lat']?.toString() ?? '');
          final lon = double.tryParse(record['lon']?.toString() ?? '');
          final searchable = address.toLowerCase().replaceAll('ё', 'е')
              .replaceAll(RegExp(r'[^0-9a-zа-яәғқңөұүһі]+'), ' ').trim();
          if (address.isEmpty || lat == null || lon == null || tokens.isEmpty ||
              !tokens.every(searchable.contains)) continue;
          savedPlaceFeatures.add(<String, dynamic>{
            'type': 'Feature',
            '_mapAddressHistory': true,
            'properties': <String, dynamic>{
              'name': address,
              'display_label': address,
              'address': address,
              'source': 'BAKE map address history',
            },
            'geometry': <String, dynamic>{
              'type': 'Point',
              'coordinates': <double>[lon, lat],
            },
          });
        } catch (_) {
          continue;
        }
      }
    } catch (error) {
      debugPrint('BAKE map address history search unavailable: $error');
    }

    final localResults = await _offlineAddressSearch.search(query, near: near ?? _currentLocation ?? _shymkent);

    // The experimental online FlutterMap search must query Photon even when
    // the Shymkent-only local index has partial matches. Keep the offline-only
    // search path unchanged when the experimental online map is not active.
    if (!_isOfflineMapActive) {
      try {
        final onlineResults = await _fetchPhotonFeatures(
          query,
          includeCitySearch: includeExpandedPhotonQueries,
          includeNominatimCitySearch: includeNominatimCitySearch,
          includeNominatimAddressFallback: includeNominatimAddressFallback,
        ).timeout(const Duration(seconds: 18));
        final merged = <Map<String, dynamic>>[];
        final seen = <String>{};
        // Keep exact city matches ahead of the Shymkent local index so a
        // request such as "Тараз" cannot be buried under nearby local hits.
        final orderedResults = <Map<String, dynamic>>[
          ...onlineResults,
          ...localResults,
        ];
        _sortSearchFeatures(orderedResults, query);
        for (final feature in orderedResults) {
          final rawProperties = feature['properties'];
          final properties = rawProperties is Map
              ? Map<String, dynamic>.from(rawProperties)
              : <String, dynamic>{};
          final rawGeometry = feature['geometry'];
          final coordinates = rawGeometry is Map ? rawGeometry['coordinates'] : null;
          final identity = properties['osm_id'] != null
              ? '${properties['osm_type'] ?? ''}:${properties['osm_id']}'
              : '${properties['name'] ?? ''}:${coordinates is List && coordinates.length >= 2 ? coordinates[0] : ''}:${coordinates is List && coordinates.length >= 2 ? coordinates[1] : ''}';
          if (seen.add(identity)) merged.add(feature);
        }
        final combined = <Map<String, dynamic>>[...reportFeatures, ...savedPlaceFeatures, ...merged];
        final exactAddressResults = _keepExactHouseNumber(combined, query);
        _sortSearchFeatures(exactAddressResults, query);
        return exactAddressResults;
      } catch (error) {
        debugPrint('BAKE Photon address search unavailable: $error');
        return _keepExactHouseNumber(
          <Map<String, dynamic>>[...reportFeatures, ...savedPlaceFeatures, ...localResults],
          query,
        );
      }
    }

    // Preserve the established offline behavior: use the local Shymkent
    // index first and contact Photon only when the local index has no match.
    var otherResults = localResults;
    if (otherResults.isEmpty) {
      try {
        otherResults = await _fetchPhotonFeatures(
          query,
          includeNominatimCitySearch: includeNominatimCitySearch,
          includeNominatimAddressFallback: includeNominatimAddressFallback,
        ).timeout(const Duration(seconds: 18));
      } catch (error) {
        debugPrint('BAKE Photon address search unavailable: $error');
        otherResults = <Map<String, dynamic>>[];
      }
    }
    return _keepExactHouseNumber(
      <Map<String, dynamic>>[...reportFeatures, ...savedPlaceFeatures, ...otherResults],
      query,
    );
  }

  Future<void> _searchAddress({bool selectAsOrigin = false}) async {
    final query = _searchController.text.trim();
    if (query.isEmpty || _isSearching) return;    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList('search_history') ?? <String>[];
    history.remove(query);
    history.insert(0, query);
    await prefs.setStringList('search_history', history.take(20).toList());
    setState(() {
      _isSearching = true;
      _message = selectAsOrigin
          ? AppLocale.pick('Ищем начальную точку…', 'Бастапқы нүкте ізделуде…', 'Searching for starting point…')
          : AppLocale.pick('Ищем пункт назначения…', 'Межелі орын ізделуде…', 'Searching for destination…');
    });
    var shouldBuildRoute = false;
    try {
      final anchor = selectAsOrigin
          ? (_currentLocation ?? _routeOrigin ?? _shymkent)
          : (_routeOrigin ?? _currentLocation ?? _shymkent);      final results = await _fetchAddressFeatures(query, near: anchor);
      if (_flutterMapExperimentEnabled && !_isOfflineMapActive) {
        _sortSearchFeatures(results, query);
      }
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _message = AppLocale.pick(
          'Адрес не найден. Попробуйте уточнить название улицы или дома.',
          'Мекенжай табылмады. Көше немесе үй атауын нақтылап көріңіз.',
          'Address not found. Try a more specific street or house name.',
        ));
        return;
      }
      final selected = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.84,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: Container(
                  width: 42, height: 5,
                  decoration: BoxDecoration(color: const Color(0xFFD6D9DE), borderRadius: BorderRadius.circular(8)),
                )),
                const SizedBox(height: 14),
                Text(
                  selectAsOrigin ? AppLocale.tr('Выберите начальную точку') : AppLocale.tr('Выберите пункт назначения'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final feature = results[index];
                      final address = _photonFeatureAddress(feature);
                      final geometry = feature['geometry'] as Map;
                      final coordinates = geometry['coordinates'] as List;
                      final point = LatLng(
                        double.parse(coordinates[1].toString()),
                        double.parse(coordinates[0].toString()),
                      );
                      final distance = _distanceKm(anchor, point);
                      final distanceLabel = distance < 1
                          ? '${(distance * 1000).round()} м от точки поиска'
                          : '${distance.toStringAsFixed(1)} км от точки поиска';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.location_on_outlined, color: Color(0xFF343434)),
                        title: Text(address.isEmpty ? 'Адрес' : address, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(distanceLabel),
                        onTap: () => Navigator.of(sheetContext).pop(feature),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(onPressed: () => Navigator.of(sheetContext).pop(), child: Text(AppLocale.tr('Отмена'))),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final geometry = selected['geometry'];
      final coordinates = geometry is Map ? geometry['coordinates'] : null;
      if (coordinates is! List || coordinates.length < 2) {
        setState(() => _message = AppLocale.tr('Поиск вернул некорректные координаты.'));
        return;
      }
      final lon = double.tryParse(coordinates[0].toString());
      final lat = double.tryParse(coordinates[1].toString());
      if (lat == null || lon == null || lat < 40 || lat > 56 || lon < 46 || lon > 88) {
        setState(() => _message = AppLocale.tr('Координаты результата не относятся к Казахстану.'));
        return;
      }
      final point = LatLng(lat, lon);
      if (selectAsOrigin) {
        _selectRouteOrigin(point);
      } else {
        _selectDestination(point);
        shouldBuildRoute = true;
      }
      _moveMapCamera(point, 16);
      final address = _photonDestinationAddress(selected);
      setState(() {
        if (!selectAsOrigin) {
          // Keep the exact resolved destination address visible for the
          // entire route lifecycle, including active navigation.
          _selectedMapPointAddress = address.isEmpty ? query : address;
        }
        _message = address.isEmpty
            ? AppLocale.pick('Адрес найден.', 'Мекенжай табылды.', 'Address found.')
            : address;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
    if (shouldBuildRoute && mounted) await _buildRoute();
  }

  void _selectRouteOrigin(LatLng point) {
    final wasNavigating = _navigationActive;
    setState(() {
      _routeOrigin = point;
      _routeProgressSegmentIndex = 0;
      _navigationMatchedLocation = null;
      _routePoints = [];
      _routeReady = false;
      _instructions = [];
      _navigationActive = false;
      _instructionIndex = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = '';
    });
    unawaited(_saveRoutePoint(_savedRouteOriginKey, point));
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
  }

  void _resetRouteOrigin() {
    setState(() {
      _routeOrigin = null;
      _routeProgressSegmentIndex = 0;
_navigationMatchedLocation = null;
      _routePoints = [];
      _routeReady = false;
      _instructions = [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = AppLocale.pick('Начальная точка снова определяется по GPS.', 'Бастапқы нүкте қайтадан GPS арқылы анықталады.', 'Starting point will be detected by GPS again.');
    });
    unawaited(_removeSavedRoutePoint(_savedRouteOriginKey));
  }

  void _selectDestination(LatLng point) {
    final wasNavigating = _navigationActive;
    // Invalidate every in-flight route request for the previous destination.
    _routeRequestGeneration++;
    setState(() {
      _destination = point;
      _selectedMapPointAddress = 'Адрес определяется…';
      _routeAlternatives = <Map<String, dynamic>>[];
      _selectedRouteIndex = 0;
      _routeProgressSegmentIndex = 0;
_navigationMatchedLocation = null;
      _routePoints = [];
      _routeReady = false;
      _instructions = [];
      _navigationActive = false;
      _instructionIndex = 0;
      _announcedManeuverStage = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = '';
    });
    unawaited(_saveRoutePoint(_savedRouteDestinationKey, point));
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
  }
  LatLng _offsetAlongRoute(
    LatLng point,
    double bearingDegrees,
    double distanceMeters,
  ) {
    final radians = bearingDegrees * math.pi / 180;
    final east = math.sin(radians) * distanceMeters;
    final north = math.cos(radians) * distanceMeters;
    final latitude = point.latitude + north / 111320.0;
    final longitudeScale =
        111320.0 * math.cos(point.latitude * math.pi / 180);
    final longitude =
        point.longitude + east / math.max(1.0, longitudeScale);
    return LatLng(latitude, longitude);
  }

  LatLng _offsetRouteCue(LatLng point, double bearingDegrees, double sideMeters) {
    final radians = bearingDegrees * math.pi / 180;
    // Place the cue consistently on the right-hand side of the route.
    final east = math.cos(radians) * sideMeters;
    final north = -math.sin(radians) * sideMeters;
    final latitude = point.latitude + north / 111320.0;
    final longitudeScale =
        111320.0 * math.cos(point.latitude * math.pi / 180);
    final longitude = point.longitude + east / math.max(1.0, longitudeScale);
    return LatLng(latitude, longitude);
  }

  // Build a map-native triangular arrow from geographic coordinates. This does
  // not depend on glyphs in the online map style, so it remains visible offline/online.
  double _routeBearingAt(LatLng point) {
    if (_routePoints.length < 2) return _gpsHeadingDegrees ?? 0.0;
    var nearestDistance = double.infinity;
    // Restrict heading lookup to the active progress window. A nearby parallel
    // leg elsewhere on the route must not rotate the map ahead of the vehicle.
    final anchorIndex = _navigationActive ? _navigationFixSegmentIndex : 0;
    final firstSegment = math.max(0, anchorIndex - 2);
    final lastSegment = math.min(_routePoints.length - 2, anchorIndex + 12);
    const latScale = 110540.0;
    final lonScale = 111320.0 * math.cos(point.latitude * math.pi / 180);
    final px = point.longitude * lonScale;
    final py = point.latitude * latScale;
    var segmentIndex = firstSegment;
    for (var i = firstSegment; i <= lastSegment; i++) {
      final a = _routePoints[i];
      final b = _routePoints[i + 1];
      final ax = a.longitude * lonScale;
      final ay = a.latitude * latScale;
      final dx = (b.longitude - a.longitude) * lonScale;
      final dy = (b.latitude - a.latitude) * latScale;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared < 0.01
          ? 0.0
          : (((px - ax) * dx + (py - ay) * dy) / lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
      final ex = px - (ax + t * dx);
      final ey = py - (ay + t * dy);
      final distance = math.sqrt(ex * ex + ey * ey);
      if (distance < nearestDistance) {
        nearestDistance = distance;
        segmentIndex = i;
      }
    }
    return Geolocator.bearingBetween(
      _routePoints[segmentIndex].latitude,
      _routePoints[segmentIndex].longitude,
      _routePoints[segmentIndex + 1].latitude,
      _routePoints[segmentIndex + 1].longitude,
    );
  }

  bool _isRouteManeuverMarker(RouteInstruction instruction) {
    const maneuverTypes = <String>{
      'turn',
      'fork',
      'merge',
      'on ramp',
      'off ramp',
      'end of road',
      'roundabout',
      'rotary',
      'roundabout turn',
      'exit roundabout',
      'exit rotary',
    };
    return maneuverTypes.contains(instruction.maneuverType.trim().toLowerCase());
  }

  String _maneuverArrowGlyph(RouteInstruction instruction) {
    final type = instruction.maneuverType.trim().toLowerCase();
    final modifier = instruction.maneuverModifier.trim().toLowerCase();
    if (type.contains('roundabout') || type == 'rotary') return '↻';
    switch (modifier) {
      case 'slight left':
        return '↖';
      case 'left':
        return '↰';
      case 'sharp left':
      case 'uturn':
      case 'uturn left':
        return '↶';
      case 'slight right':
        return '↗';
      case 'right':
        return '↱';
      case 'sharp right':
      case 'uturn right':
        return '↷';
      case 'straight':
        return '↑';
      default:
        return '➤';
    }
  }

  IconData _maneuverIcon(RouteInstruction? instruction) {
    if (instruction == null) return Icons.navigation;
    final modifier = instruction.maneuverModifier.trim().toLowerCase();
    switch (modifier) {
      case 'left':
      case 'slight left':
      case 'sharp left':
        return Icons.turn_left;
      case 'right':
      case 'slight right':
      case 'sharp right':
        return Icons.turn_right;
      case 'uturn':
      case 'uturn left':
        return Icons.u_turn_left;
      case 'uturn right':
        return Icons.u_turn_right;
      case 'straight':
        return Icons.straight;
    }
    if (instruction.maneuverType == 'roundabout' ||
        instruction.maneuverType == 'rotary') {
      return Icons.roundabout_left;
    }
    if (instruction.maneuverType == 'arrive') return Icons.flag_outlined;
    return Icons.navigation;
  }

  String _instructionText(Map<String, dynamic> step) {
    final maneuver = step['maneuver'] as Map<String, dynamic>? ?? {};
    final type = maneuver['type']?.toString() ?? '';
    final modifier = maneuver['modifier']?.toString() ?? '';
    final name = _localizedStepRoadName(step);
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

  List<double> _buildRouteCumulativeMeters(List<LatLng> points) {
    if (points.isEmpty) return <double>[];
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + Geolocator.distanceBetween(
        points[i - 1].latitude, points[i - 1].longitude,
        points[i].latitude, points[i].longitude,
      ));
    }
    return cumulative;
  }

  double _projectRouteProgress(
    List<LatLng> points, List<double> cumulative, LatLng location, {
    int fromSegment = 0,
  }) {
    if (points.length < 2 || cumulative.length != points.length) return 0;
    const latScale = 110540.0;
    final lonScale = 111320.0 * math.cos(location.latitude * math.pi / 180);
    final px = location.longitude * lonScale, py = location.latitude * latScale;
    final first = fromSegment.clamp(0, points.length - 2).toInt();
    var bestDistance = double.infinity;
    var bestProgress = cumulative[first];
    for (var i = first; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final ax = a.longitude * lonScale, ay = a.latitude * latScale;
      final dx = (b.longitude - a.longitude) * lonScale;
      final dy = (b.latitude - a.latitude) * latScale;
      final lengthSquared = dx * dx + dy * dy;
      if (lengthSquared < 0.01) continue;
      final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared)
          .clamp(0.0, 1.0).toDouble();
      final ex = px - (ax + t * dx), ey = py - (ay + t * dy);
      final distance = math.sqrt(ex * ex + ey * ey);
      if (distance < bestDistance) {
        bestDistance = distance;
        bestProgress = cumulative[i] + (cumulative[i + 1] - cumulative[i]) * t;
      }
    }
    return bestProgress;
  }

  List<double> _buildInstructionProgressMeters(
    List<LatLng> points, List<RouteInstruction> instructions,
  ) {
    final cumulative = _buildRouteCumulativeMeters(points);
    if (points.length < 2 || instructions.isEmpty) return <double>[];
    final result = <double>[];
    var fromSegment = 0;
    var previousProgress = 0.0;
    for (final instruction in instructions) {
      final progress = _projectRouteProgress(
        points, cumulative, instruction.location, fromSegment: fromSegment,
      ).clamp(previousProgress, cumulative.last).toDouble();
      result.add(progress);
      previousProgress = progress;
      while (fromSegment < points.length - 2 && cumulative[fromSegment + 1] < progress) {
        fromSegment++;
      }
    }
    return result;
  }

  void _setNavigationProgressAnchor(double progress) {
    if (_routeCumulativeMeters.length != _routePoints.length || _routePoints.length < 2) return;
    final bounded = progress.clamp(0.0, _routeCumulativeMeters.last).toDouble();
    var index = 0;
    while (index < _routePoints.length - 2 && _routeCumulativeMeters[index + 1] < bounded) {
      index++;
    }
    final segmentLength = _routeCumulativeMeters[index + 1] - _routeCumulativeMeters[index];
    final t = segmentLength <= 0 ? 0.0 : ((bounded - _routeCumulativeMeters[index]) / segmentLength).clamp(0.0, 1.0).toDouble();
    _routeProgressSegmentIndex = index;
    _navigationFixSegmentIndex = index;
    _navigationFixSegmentT = t;
    _navigationFixProgressMeters = bounded;
    _navigationProgressMeters = bounded;
  }

  void _prepareNavigationProgress(List<LatLng> points, List<RouteInstruction> instructions) {
    _routeCumulativeMeters = _buildRouteCumulativeMeters(points);
    _instructionProgressMeters = _buildInstructionProgressMeters(points, instructions);
    _navigationFixMatchedLocation = null;
    _navigationFixTimestamp = null;
    _navigationFixSpeedMetersPerSecond = 0;
    _navigationFixSegmentIndex = 0;
    _navigationFixSegmentT = 0;
    _navigationFixProgressMeters = 0;
    _navigationProgressMeters = 0;
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
        final intersections = step['intersections'] as List<dynamic>? ?? const [];
        List<bool> laneGuidance = <bool>[];
        for (final intersection in intersections) {
          if (intersection is! Map<String, dynamic>) continue;
          final lanes = intersection['lanes'];
          if (lanes is! List || lanes.isEmpty) continue;
          laneGuidance = lanes.map((lane) =>
              lane is Map && (lane['valid'] == true || lane['valid_indication'] == true)
          ).toList();
          break;
        }
        result.add(RouteInstruction(
          location: LatLng(
            (location[1] as num).toDouble(),
            (location[0] as num).toDouble(),
          ),
          text: _instructionText(step),
          distanceMeters: (step['distance'] as num?)?.toDouble() ?? 0,
          maneuverType: maneuver['type']?.toString() ?? '',
          maneuverModifier: maneuver['modifier']?.toString() ?? '',
          laneGuidance: laneGuidance,
        ));
      }
    }
    return result;
  }

  Future<bool> _ensureBackgroundLocationPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (!mounted) return false;

    if (permission == LocationPermission.always) return true;

    // Both a foreground-only grant and deniedForever require the user to
    // visit Android app settings to enable "Allow all the time".

    final openSettings = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.pick(
          'Разрешите GPS в фоне',
          'Фондық GPS-ке рұқсат беріңіз',
          'Allow background GPS',        )),
        content: Text(AppLocale.pick(
          'Сейчас доступ к GPS разрешён только при открытом приложении. Откройте настройки приложения, выберите «Местоположение» и установите «Разрешить всегда». Затем вернитесь в BAKE Navigator и снова нажмите «Поехали».',
          'Қазір GPS тек қолданба ашық кезде қолжетімді. Қолданба баптауларын ашып, «Орналасқан жер» бөлімінен «Әрқашан рұқсат ету» таңдаңыз. Содан кейін BAKE Navigator-ға оралып, «Жолға шығу» түймесін қайта басыңыз.',
          'GPS is currently allowed only while the app is open. Open app settings, choose Location, and set it to Allow all the time. Then return to BAKE Navigator and tap Go again.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocale.pick('Отмена', 'Бас тарту', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocale.pick('Открыть настройки', 'Баптауларды ашу', 'Open settings')),
          ),
        ],
      ),
    );

    if (openSettings != true) return false;
    await Geolocator.openAppSettings();
    if (mounted) {
      setState(() => _message = AppLocale.pick(
        'Включите «Разрешить всегда» для местоположения, вернитесь в приложение и снова нажмите «Поехали».',
        'Орналасқан жер үшін «Әрқашан рұқсат ету» параметрін қосып, қолданбаға оралып, «Жолға шығу» түймесін қайта басыңыз.',
        'Enable Allow all the time for Location, return to the app, and tap Go again.',
      ));
    }
    return false;
  }

  Future<void> _startNavigation() async {
    if (_routePoints.length < 2 || _destination == null) {
      if (mounted) setState(() => _message = AppLocale.pick('Сначала постройте маршрут до пункта назначения.', 'Алдымен межелі орынға маршрут құрыңыз.', 'Build a route to the destination first.'));
      return;
    }

    // Android requires an explicit background location grant for reliable
    // navigation while the app is minimized.
    final backgroundPermissionGranted = await _ensureBackgroundLocationPermission();
    if (!backgroundPermissionGranted || !mounted) return;

    // GPS can take time to acquire a fix, especially indoors or after launch.
    // Try a one-shot fix, but do not discard a valid planned route on timeout.
    if (_currentLocation == null) {
      try { await _locateMe(); } catch (_) { /* Stream below keeps waiting. */ }
    }
    if (!mounted) return;

    _mapFollowEnabled = true;
    setState(() {
      _navigationActive = true;
      _announcedManeuverStage = 0;
      _instructionIndex = _instructions.isNotEmpty && _instructions.length > 1 ? 1 : 0;
      _message = _currentLocation == null
          ? AppLocale.pick('Маршрут запущен. Ожидаем сигнал GPS — движение и подсказки начнутся после получения координат.', 'Маршрут басталды. GPS сигналы күтілуде — координат алынған соң қозғалыс пен нұсқаулар басталады.', 'Route started. Waiting for GPS; tracking and guidance will begin when a location fix arrives.')
          : AppLocale.pick('Включаем фоновый GPS и голосовые подсказки…', 'Фондық GPS пен дауыстық нұсқаулар қосылуда…', 'Enabling background GPS and voice guidance…');
    });
    try {
      _navigationFixMatchedLocation = null;
      _navigationFixTimestamp = null;
      _navigationFixSpeedMetersPerSecond = 0;
      _startNavigationPredictionTicker();
      // Keep the location stream active without blocking route start on first fix.
      await _startLiveLocationUpdates(
        backgroundNavigation: true,
        waitForFirstFix: false,
      );
    } catch (error) {
      await _stopLiveLocationUpdates(reason: 'navigation_start_failed');
      if (!mounted) return;
      setState(() {
        _navigationActive = false;
        _message = AppLocale.pick('Не удалось включить фоновый GPS: $error', 'Фондық GPS қосылмады: $error', 'Could not enable background GPS: $error');
      });
      unawaited(_startLiveLocationUpdates());
      return;
    }
    if (!mounted) return;
    final livePoint = _currentLocation;
    if (livePoint != null) {
      final initialHeading = _gpsHeadingDegrees != null && _currentSpeedKmh >= 5.4
          ? _gpsHeadingDegrees!
          : 0.0;
      _updateNavigationCamera(livePoint, 17, initialHeading);
      if (_gpsHeadingDegrees != null && _currentSpeedKmh >= 5.4) {
        _lastCameraHeadingDegrees = initialHeading;
      }
      await _speakCurrentInstruction();
    }
  }

  Future<void> _resetRoutePreview() async {
    if (!mounted) return;
    setState(() {
      _routeReady = false;
      _routeActionDismissed = true;
      _selectedMapPointAddress = '';
      _routeProgressSegmentIndex = 0;
_navigationMatchedLocation = null;
      _routePoints = <LatLng>[];
      _routeOrigin = null;
      _destination = null;
      _routeStops.clear();
      _routeAlternatives = <Map<String, dynamic>>[];
      _selectedRouteIndex = 0;
      _instructions = <RouteInstruction>[];
      _instructionIndex = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _announcedManeuverStage = 0;
      _offRouteSamples = 0;
      _message = '';
      _searchController.clear();
    });
    await _tts.stop();
    await _kazakhVoiceService.stop();
    await _removeSavedRoutePoint(_savedRouteDestinationKey);
    // Clear the rendered map route and destination annotation immediately.
  }

  Future<void> _finishNavigation() async {
    if (!mounted) return;
    setState(() {
      _navigationActive = false;
      _routeActionDismissed = true;
      _routeReady = false;
      _selectedMapPointAddress = '';
      _routeProgressSegmentIndex = 0;
_navigationMatchedLocation = null;
      _routePoints = <LatLng>[];
      _routeOrigin = null;
      _destination = null;
      _routeStops.clear();
      _routeAlternatives = <Map<String, dynamic>>[];
      _selectedRouteIndex = 0;
      _instructions = <RouteInstruction>[];
      _instructionIndex = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _announcedManeuverStage = 0;
      _offRouteSamples = 0;
      _message = AppLocale.tr('Навигация завершена.');
      _searchController.clear();
      _activeConfirmedCameraId = null;
      _activeConfirmedCameraDistance = null;
      _passedConfirmedCameraIds.clear();
      _confirmedCameraStages.clear();
    });
    await _tts.stop();
    await _removeSavedRoutePoint(_savedRouteDestinationKey);
    _lastCameraHeadingDegrees = null;
    _rotateMapCamera(0);
    // Force map renderer to remove the old blue line and route markers.
    await _startLiveLocationUpdates();
  }

  Future<void> _speakCurrentInstruction() async {
    if (!_navigationActive || _instructionIndex >= _instructions.length) return;
    final instruction = _instructions[_instructionIndex];
    final currentLocation = _currentLocation;
    if (currentLocation == null) {
      if (mounted) {
        setState(() => _message = AppLocale.pick(
          'Ожидаем координаты GPS перед голосовой подсказкой.',
          'Дауыстық нұсқауға дейін GPS координаттары күтілуде.',
          'Waiting for a GPS fix before speaking the instruction.',
        ));
      }
      return;
    }
    final meters = _distanceToNextManeuverMeters ?? Geolocator.distanceBetween(
      currentLocation.latitude, currentLocation.longitude,
      instruction.location.latitude, instruction.location.longitude,
    );
    final distanceText = meters >= 1000
        ? _localized('${(meters / 1000).toStringAsFixed(1)} километра', '${(meters / 1000).toStringAsFixed(1)} километр', '${(meters / 1000).toStringAsFixed(1)} kilometers')
        : _localized('${meters.round()} метров', '${meters.round()} метр', '${meters.round()} meters');
    if (_voiceMode >= 2) {
      await _speakText(_localized('${instruction.text} через $distanceText.', '${instruction.text} $distanceText кейін.', '${instruction.text} in $distanceText.'));
    }
  }

  double? get _distanceToNextManeuverMeters {
    if (_instructionIndex >= _instructions.length) return null;
    if (_instructionProgressMeters.length == _instructions.length && _routeCumulativeMeters.isNotEmpty) {
      return math.max(0.0, _instructionProgressMeters[_instructionIndex] - _navigationProgressMeters).toDouble();
    }
    final point = _navigationMatchedLocation ?? _currentLocation;
    if (point == null) return null;
    final target = _instructions[_instructionIndex].location;
    return Geolocator.distanceBetween(point.latitude, point.longitude, target.latitude, target.longitude);
  }

  int get _effectiveSpeedLimitKmh {
    final point = _currentLocation;
    if (point != null) {
      for (final report in _confirmedRoadReports) {
        final status = report['status']?.toString();
        if (status != 'Подтверждено' && status != 'approved') continue;
        final type = (report['type'] ?? '').toString().toLowerCase();
        final details = [
          report['type'], report['title'], report['address'], report['comment'],
        ].whereType<Object>().join(' ').toLowerCase();
        final distance = Geolocator.distanceBetween(
          point.latitude,
          point.longitude,
          (report['latitude'] as num).toDouble(),
          (report['longitude'] as num).toDouble(),
        );
        if (distance <= 500 &&
            (type.contains('школ') ||
                (type.contains('знак') && RegExp(r'\b40\b').hasMatch(details)))) {
          return 40;
        }
      }
    }
    return int.tryParse(_speedLimitKmh ?? '') ?? 60;
  }

  bool get _isSpeeding => _currentSpeedKmh > _effectiveSpeedLimitKmh;

  void _checkSpeedingWarning() {
    if (_isSpeeding && !_speedingVoiceActive) {
      _speedingVoiceActive = true;
      if (_voiceMode > 0) {
        unawaited(_speakText(_localized(
          'Превышение скорости',
          'Жылдамдықты асыру',
          'Speed limit exceeded',
        )));
      }
    } else if (!_isSpeeding) {
      _speedingVoiceActive = false;
    }
  }

  void _updateConfirmedCameraWarning(LatLng point, double? heading) {
    if (!_navigationActive) {
      _activeConfirmedCameraId = null;
      _activeConfirmedCameraDistance = null;
      return;
    }

    Map<String, dynamic>? nearest;
    var nearestDistance = double.infinity;
    for (final report in _confirmedRoadReports) {
      final status = report['status']?.toString();
      if (status != 'Подтверждено' && status != 'approved') continue;
      final type = (report['type'] ?? '').toString().toLowerCase();
      if (!type.contains('камер')) continue;
      final id = report['id']?.toString() ?? '';
      if (id.isEmpty || _passedConfirmedCameraIds.contains(id)) continue;
      final cameraPoint = LatLng(
        (report['latitude'] as num).toDouble(),
        (report['longitude'] as num).toDouble(),
      );
      final distance = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        cameraPoint.latitude, cameraPoint.longitude,
      );
      final previousDistance = id == _activeConfirmedCameraId
          ? _activeConfirmedCameraDistance
          : null;
      if (previousDistance != null &&
          previousDistance <= 50 &&
          distance > previousDistance + 3) {
        _passedConfirmedCameraIds.add(id);
        continue;
      }
      if (distance < 15) {
        _passedConfirmedCameraIds.add(id);
        continue;
      }
      if (distance > 300 || distance >= nearestDistance) continue;
      if (heading != null) {
        final bearing = Geolocator.bearingBetween(
          point.latitude, point.longitude,
          cameraPoint.latitude, cameraPoint.longitude,
        );
        if (_bearingDifference(heading, bearing) > 70) continue;
      }
      nearest = report;
      nearestDistance = distance;
    }

    final nextId = nearest?['id']?.toString();
    if (nextId == null) {
      _activeConfirmedCameraId = null;
      _activeConfirmedCameraDistance = null;
      return;
    }

    final stage = nearestDistance <= 50 ? 3 : nearestDistance <= 100 ? 2 : 1;
    final previousStage = _confirmedCameraStages[nextId] ?? 0;
    if (stage > previousStage) {
      _confirmedCameraStages[nextId] = stage;
      if (_voiceMode > 0) {
        final spoken = stage == 1
            ? 'Впереди камера'
            : stage == 2
                ? 'Камера через 100 метров'
                : 'Камера через 50 метров';
        unawaited(_speakText(_localized(
          spoken,
          stage == 1 ? 'Алда камера' : stage == 2 ? '100 метрден кейін камера' : '50 метрден кейін камера',
          stage == 1 ? 'Camera ahead' : stage == 2 ? 'Camera in 100 meters' : 'Camera in 50 meters',
        )));
      }
    }
    _activeConfirmedCameraId = nextId;
    _activeConfirmedCameraDistance = nearestDistance;
  }

  bool _isTrafficIncidentReport(Map<String, dynamic> report) {
    final status = report['status']?.toString();
    if (status != 'Подтверждено' && status != 'approved') return false;
    final text = [
      report['type'], report['title'], report['comment'], report['address'],
    ].whereType<Object>().join(' ').toLowerCase();
    return RegExp(r'пробк|дтп|авари|перекры|закрыт|ремонт|опасн|затрудн|свободн').hasMatch(text);
  }

  List<Map<String, dynamic>> get _trafficReports =>
      _confirmedRoadReports.where(_isTrafficIncidentReport).toList();

  Color _trafficReportColor(Map<String, dynamic> report) {
    final text = [
      report['type'], report['title'], report['comment'],
    ].whereType<Object>().join(' ').toLowerCase();
    if (RegExp(r'перекры|закрыт|ремонт|авари|дтп').hasMatch(text)) {
      return const Color(0xFFE53935);
    }
    if (RegExp(r'свободн|без пробк').hasMatch(text)) {
      return const Color(0xFF2EAD63);
    }
    return const Color(0xFFFFB300);
  }

  List<bool> _laneGuidanceForCurrentManeuver() {
    if (_instructionIndex >= _instructions.length) {
      return const <bool>[false, true, false];
    }
    final instruction = _instructions[_instructionIndex];
    if (instruction.laneGuidance.isNotEmpty) {
      final lanes = List<bool>.filled(3, false);
      final source = instruction.laneGuidance;
      final start = source.length > 3 ? source.length - 3 : 0;
      final visible = source.skip(start).take(3).toList();
      for (var i = 0; i < visible.length; i++) {
        lanes[i] = visible[i];
      }
      if (lanes.every((value) => !value)) lanes[1] = true;
      return lanes;
    }
    final modifier = instruction.maneuverModifier.toLowerCase();
    if (modifier.contains('left')) return const <bool>[true, false, false];
    if (modifier.contains('right')) return const <bool>[false, false, true];
    return const <bool>[false, true, false];
  }

  Widget _buildManeuverDistanceCue() {
    final distance = _distanceToNextManeuverMeters;
    if (distance == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF169B55), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 5)],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _maneuverIcon(_instructionIndex < _instructions.length
                ? _instructions[_instructionIndex]
                : null),
            size: 17,
            color: const Color(0xFF169B55),
          ),
          const SizedBox(width: 4),
          Text('${distance.round()} м',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  Future<void> _refreshRoadSpeedLimit(LatLng point, {bool force = false}) async {
    if (_speedLimitLookupInProgress) return;
    final now = DateTime.now();
    final lastPoint = _lastSpeedLimitLookupPoint;
    final movedMeters = lastPoint == null
        ? double.infinity
        : Geolocator.distanceBetween(
            lastPoint.latitude, lastPoint.longitude,
            point.latitude, point.longitude,
          );
    if (!force &&
        _lastSpeedLimitLookup != null &&
        now.difference(_lastSpeedLimitLookup!) < const Duration(seconds: 30) &&
        movedMeters < 100) {      return;
    }

    _speedLimitLookupInProgress = true;
    _lastSpeedLimitLookup = now;
    _lastSpeedLimitLookupPoint = point;
    try {
      final query = '[out:json][timeout:10];way(around:40,'
          '${point.latitude},${point.longitude})[highway];out tags center;';
      final response = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'User-Agent': 'BAKE-Navigator/1.0',
        },
        body: {'data': query},
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = decoded['elements'] as List<dynamic>? ?? const [];
      double? nearestDistance;
      String? foundLimit;
      for (final item in elements) {
        if (item is! Map<String, dynamic>) continue;
        final tags = item['tags'] as Map<String, dynamic>? ?? const {};
        final raw = tags['maxspeed']?.toString().trim();
        if (raw == null || raw.isEmpty || raw == 'signals' ||
            raw == 'none' || raw == 'variable') {
          continue;
        }

        final center = item['center'] as Map<String, dynamic>?;
        if (center == null) continue;
        final lat = (center['lat'] as num?)?.toDouble();
        final lon = (center['lon'] as num?)?.toDouble();
        if (lat == null || lon == null) continue;
        final distance = Geolocator.distanceBetween(
          point.latitude, point.longitude, lat, lon,
        );
        if (nearestDistance != null && distance >= nearestDistance) continue;

        final match = RegExp(
          r'^(\d+(?:\.\d+)?)\s*(mph|km/h)?$',
          caseSensitive: false,
        ).firstMatch(raw);
        if (match == null) continue;
        var value = double.parse(match.group(1)!);
        if ((match.group(2) ?? '').toLowerCase() == 'mph') {
          value *= 1.60934;
        }
        nearestDistance = distance;
        foundLimit = value.round().toString();
      }

      if (!mounted) return;
      setState(() => _speedLimitKmh = foundLimit);
      _checkSpeedingWarning();
    } catch (_) {
      // Keep the last known value when road data is temporarily unavailable.
    } finally {
      _speedLimitLookupInProgress = false;
    }
  }

  double _bearingDifference(double a, double b) {
    final difference = (a - b).abs() % 360;
    return difference > 180 ? 360 - difference : difference;
  }

  double _mapMarkerCollisionDistanceMeters() {
    // Marker dimensions are measured in screen pixels. Convert a 44 px
    // collision margin to ground distance for the current map zoom.
    final latitude = (_currentLocation ?? _shymkent).latitude;
    final metersPerPixel = 156543.03392 *
        math.cos(latitude * math.pi / 180) /
        math.pow(2, _mapCameraZoom);
    return (metersPerPixel * 44).clamp(25.0, 600.0).toDouble();
  }

  Color _roadAlertColor(RoadAlert alert) => switch (alert.kind) {
        RoadAlertKind.speedCamera => const Color(0xFFB42318),
        RoadAlertKind.trafficSignalCamera => const Color(0xFFB54708),
        RoadAlertKind.surveillanceCamera => const Color(0xFF175CD3),
        RoadAlertKind.sergekCamera => const Color(0xFF7A3E9D),
        RoadAlertKind.unknownCamera => const Color(0xFF475467),
      };

  String _roadAlertGlyph(RoadAlert alert) => switch (alert.kind) {
        RoadAlertKind.speedCamera => '📷',
        RoadAlertKind.trafficSignalCamera => '🚦',
        RoadAlertKind.surveillanceCamera => '🎥',
        RoadAlertKind.sergekCamera => '📹',
        RoadAlertKind.unknownCamera => '📷',
      };

  Widget _buildRoadAlertMapMarker(RoadAlert alert) {
    final color = _roadAlertColor(alert);
    final details = [      alert.name ?? 'Камера',
      if (alert.isApproximate) 'Примерное место — камера здесь не подтверждена',
      if (alert.verificationStatus != null) 'Статус: ${alert.verificationStatus}',
      if (alert.source != null) 'Источник: ${alert.source}',
    ].join('\n');
    return Tooltip(
      message: details,
      child: SizedBox(
        width: 28,
        height: 30,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: color, width: 2.2),
                boxShadow: const [
                  BoxShadow(color: Color(0x44000000), blurRadius: 5, offset: Offset(0, 2)),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                _roadAlertGlyph(alert),
                style: const TextStyle(fontSize: 24, height: 1),
                textAlign: TextAlign.center,
              ),
            ),
            if (alert.isApproximate)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: const BoxDecoration(color: Color(0xFFFFD54F), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Text('≈', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF332400))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _recordGpsDiagnostic(event: 'APP_LIFECYCLE', detail: state.name);
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      _lastCameraUpdateAt = null;
      _lastMapAnnotationUpdateAt = null;
      _headingUpGestureActive = false;
      _headingUpResumeTimer?.cancel();
      _roadReportRetryTimer ??= Timer.periodic(
        const Duration(seconds: 45),
        (_) => unawaited(_retryPendingRoadReports()),
      );
      unawaited(_retryPendingRoadReports());
      unawaited(_loadConfirmedRoadReports());
      if (_positionSubscription == null || _gpsStopPending) {
        unawaited(_startLiveLocationUpdates(
          backgroundNavigation: _navigationActive,
        ));
      }
      return;
    }

    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      _headingUpResumeTimer?.cancel();
      _headingUpResumeTimer = null;
      _roadReportRetryTimer?.cancel();
      _roadReportRetryTimer = null;
      if (!_navigationActive) {
        unawaited(_stopLiveLocationUpdates(reason: 'app_${state.name}'));
      }
    }
  }

  /// Re-send locally stored reports that have not reached Supabase yet.
  /// This runs on app resume and every 45 seconds while the app is open.
  Future<void> _retryPendingRoadReports() async {
    if (_roadReportRetryInProgress) return;
    _roadReportRetryInProgress = true;
    try {
      if (!RoadReportSyncService.isConfigured) return;
      if (!RoadReportSyncService.isInitialized) {
        await RoadReportSyncService.initialize();
      }
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList('bake_road_reports_v1') ?? <String>[];
      var changed = false;
      for (var index = 0; index < rows.length; index++) {
        try {
          final record = Map<String, dynamic>.from(jsonDecode(rows[index]) as Map);
          if (record['status'] != 'На проверке' ||
              record['syncStatus'] == 'Синхронизировано') {
            continue;
          }
          await RoadReportSyncService.uploadReport(record);
          record['syncStatus'] = 'Синхронизировано';
          rows[index] = jsonEncode(record);
          changed = true;
        } catch (error) {
          debugPrint('BAKE pending report retry failed: ${error.runtimeType}');
        }
      }
      if (changed) await prefs.setStringList('bake_road_reports_v1', rows);
    } catch (error) {
      debugPrint('BAKE pending report retry unavailable: ${error.runtimeType}');
    } finally {
      _roadReportRetryInProgress = false;
    }
  }

  Future<void> _loadConfirmedRoadReports() async {
    if (_confirmedRoadReportsLoadInProgress) return;
    _confirmedRoadReportsLoadInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList('bake_road_reports_v1') ?? <String>[];
      final reportsById = <String, Map<String, dynamic>>{};
      final updatedLocalRows = <String>[];
      var localRowsChanged = false;

      for (final raw in rows) {
        try {
          final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          final status = record['status']?.toString();
          if (status == 'Подтверждено') {
            reportsById[record['id']?.toString() ?? raw] = record;
          } else if (status == 'На проверке' &&
              RoadReportSyncService.isInitialized &&
              record['syncStatus']?.toString() != 'Синхронизировано') {
            try {
              await RoadReportSyncService.uploadReport(record);
              record['syncStatus'] = 'Синхронизировано';
              localRowsChanged = true;
            } catch (error) {
              debugPrint('BAKE report upload will retry later: $error');
            }
          }
          updatedLocalRows.add(jsonEncode(record));
        } catch (_) {
          updatedLocalRows.add(raw);
        }
      }

      if (localRowsChanged) {
        await prefs.setStringList('bake_road_reports_v1', updatedLocalRows);
      }

      if (RoadReportSyncService.isInitialized) {
        try {
          final remoteReports = await RoadReportSyncService.fetchConfirmedReports();
          for (final report in remoteReports) {
            reportsById[report['id']?.toString() ?? ''] = report;
          }
        } catch (error) {
          debugPrint('BAKE shared road reports could not be loaded: $error');
        }
      }

      final reports = reportsById.values.where((record) {
        final lat = (record['latitude'] as num?)?.toDouble();
        final lon = (record['longitude'] as num?)?.toDouble();
        return lat != null && lon != null &&
            lat.isFinite && lon.isFinite &&
            lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
      }).toList();

      if (!mounted) return;
      setState(() => _confirmedRoadReports = reports);
    } catch (error) {
      debugPrint('Не удалось загрузить подтверждённые дорожные отметки: $error');
    } finally {
      _confirmedRoadReportsLoadInProgress = false;
    }
  }

  bool _isRoadWarningReport(Map<String, dynamic> report) {
    final type = (report['type'] ?? '').toString().trim().toLowerCase();
    return type.contains('камера') || type.contains('светофор') ||
        type.contains('лежач') || type.contains('полиц') ||
        type.contains('перекрыт') || type.contains('яма') ||
        type.contains('переход') || type.contains('скорост') ||
        type.contains('знак') || type.contains('опасн') ||
        type.contains('переезд') || type.contains('поворот') ||
        type.contains('односторон') || type.contains('ремонт');
  }

  bool _isStreetNameReport(Map<String, dynamic> report) {
    final type = (report['type'] ?? '').toString().trim().toLowerCase();
    return type.contains('улиц') || type.contains('дорог') ||
        type.contains('переимен') || type.contains('street') ||
        type.contains('road');
  }

  String _roadReportStreetLabel(Map<String, dynamic> report) {
    for (final key in ['title', 'address']) {
      final value = report[key]?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _roadReportGlyph(Map<String, dynamic> report) {
    final type = report['type']?.toString() ?? '';
    if (type.contains('Камера')) return '📷';
    if (type.contains('знак')) return '🚸';
    if (type.contains('Светофор')) return '🚦';
    if (type.contains('переход')) return '🚶';
    if (type.contains('полицейский') || type.contains('Опасный')) return '⚠';
    if (type.contains('переезд')) return '🚆';
    if (type.contains('поворот')) return '↩';
    if (type.contains('Односторон')) return '➡';
    if (type.contains('Ремонт')) return '🚧';
    if (type.contains('Школа')) return '🏫';
    return '📍';
  }

  Widget _buildConfirmedRoadReportMarker(Map<String, dynamic> report) {
    final type = report['type']?.toString() ?? 'Дорожный объект';
    final date = report['createdAt']?.toString() ?? '';
    return Tooltip(
      message: '$type\nПодтверждено${date.isNotEmpty ? '\n$date' : ''}',
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFD54F),
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFF202020), width: 2),
          boxShadow: const [BoxShadow(color: Color(0x44000000), blurRadius: 5, offset: Offset(0, 2))],
        ),
        alignment: Alignment.center,
        child: Text(_roadReportGlyph(report), style: const TextStyle(fontSize: 14)),
      ),
    );
  }

  bool _isShymkentCamera(RoadAlert alert) {
    if (alert.id.startsWith('shymkent/')) return true;
    final distanceFromCityCenter = const Distance().as(
      LengthUnit.Meter, _shymkent, alert.location,
    );
    return distanceFromCityCenter <= 25000;
  }

  List<RoadAlert> _shymkentCameraAlerts() =>
      _bundledRoadAlerts.where(_isShymkentCamera).toList()
        ..sort((a, b) => (a.name ?? '').compareTo(b.name ?? ''));

  List<RoadAlert> _roadAlertsVisibleOnMap() {
    final visible = _showShymkentCamerasOnMap
        ? _roadAlerts
        : _roadAlerts.where((alert) => !_isShymkentCamera(alert)).toList();
    return List<RoadAlert>.unmodifiable(visible);
  }

  Future<void> _updateRoadAlerts(LatLng position, double? gpsHeading) async {
    // Camera lookup and map markers work outside navigation too.
    // Voice announcements remain gated by _navigationActive below.
    if (_roadAlertLookupInProgress) return;

    var alertsWereRefreshed = false;
    final now = DateTime.now();
    final lastPoint = _lastRoadAlertLookupPoint;
    final movedMeters = lastPoint == null
        ? double.infinity
        : Geolocator.distanceBetween(
            lastPoint.latitude,
            lastPoint.longitude,
            position.latitude,
            position.longitude,
          );
    if (_lastRoadAlertLookup != null &&
        now.difference(_lastRoadAlertLookup!) < const Duration(seconds: 20) &&
        movedMeters < 150) {
      // Existing alerts are still checked against the latest GPS position below.
    } else {
      _roadAlertLookupInProgress = true;
      try {
        final loadedAlerts = await _roadAlertService.fetchNearby(
          position,
          radiusMeters: 3000,
        );
        _roadAlerts = _mergeRoadAlerts(_bundledRoadAlerts, loadedAlerts);
        // Start the cooldown only after a successful server response. A failed
        // request must not suppress the next retry for 45 seconds.
        _lastRoadAlertLookup = DateTime.now();
        _lastRoadAlertLookupPoint = position;
        alertsWereRefreshed = true;
      } catch (_) {
        // Keep the last successful result and allow the next GPS update to retry.
      } finally {
        _roadAlertLookupInProgress = false;
      }
    }

    if (!mounted) return;

    // Rebuild both map renderers whenever the camera data changes.
    if (alertsWereRefreshed) {
      setState(() {});
    }

    // Never speak camera warnings while browsing the map without navigation.
    if (!_navigationActive) return;

    // Prefer the live GPS course; when nearly stopped, use the next route step.
    double? travelBearing = gpsHeading;
    if (travelBearing == null && _instructionIndex < _instructions.length) {
      final target = _instructions[_instructionIndex].location;
      travelBearing = Geolocator.bearingBetween(
        position.latitude,
        position.longitude,
        target.latitude,
        target.longitude,
      );
    }
    if (travelBearing == null || !travelBearing.isFinite) return;

    final candidates = <({RoadAlert alert, double distance})>[];
    for (final alert in _roadAlerts) {
      // Only confirmed speed-enforcement coordinates may trigger speech.
      if (alert.kind != RoadAlertKind.speedCamera || alert.isApproximate) continue;
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        alert.location.latitude,
        alert.location.longitude,
      );
      if (distance > 1200 || distance < 0) continue;

      final bearingToAlert = Geolocator.bearingBetween(
        position.latitude,
        position.longitude,
        alert.location.latitude,
        alert.location.longitude,
      );
      // Avoid announcing objects behind the vehicle or on a distant parallel road.
      if (_bearingDifference(travelBearing, bearingToAlert) > 65) continue;
      final enforcedBearing = alert.bearingDegrees;
      if (enforcedBearing != null &&
          _bearingDifference(travelBearing, enforcedBearing) > 65) continue;
      candidates.add((alert: alert, distance: distance));
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));

    for (final candidate in candidates) {
      final alert = candidate.alert;
      final distance = candidate.distance;
      final stage = distance <= 200 ? 3 : distance <= 500 ? 2 : distance <= 1000 ? 1 : 0;
      if (_voiceMode == 0 || stage == 0 ||
          stage <= (_announcedRoadAlertStages[alert.id] ?? 0)) {
        continue;
      }
      _announcedRoadAlertStages[alert.id] = stage;

      final distanceText = distance >= 1000
          ? '${(distance / 1000).toStringAsFixed(1)} километра'
          : '${(distance / 50).round() * 50} метров';
      final message = _localized(
        'Впереди камера контроля скорости. Расстояние $distanceText.',
        'Алда жылдамдықты бақылау камерасы бар. Қашықтық $distanceText.',
        'Speed camera ahead. Distance $distanceText.',
      );
      await _speakText(message);
      if (!mounted || !_navigationActive || _voiceMode == 0) return;
    }
  }


  Future<void> _updateRoadFeatureWarnings(
    LatLng position,
    double? gpsHeading,
  ) async {
    if (_roadFeatureLookupInProgress) return;
    final now = DateTime.now();
    final lastPoint = _lastRoadFeatureLookupPoint;
    final movedMeters = lastPoint == null
        ? double.infinity
        : Geolocator.distanceBetween(
            lastPoint.latitude, lastPoint.longitude,
            position.latitude, position.longitude,
          );
    final shouldRefresh = _lastRoadFeatureLookup == null ||
        now.difference(_lastRoadFeatureLookup!) >= const Duration(minutes: 2) ||
        movedMeters >= 250;
    if (shouldRefresh) {
      _roadFeatureLookupInProgress = true;
      try {
        final loaded = await _roadAlertService.fetchNearbyFeatures(
          position,
          radiusMeters: 1800,
        );
        _roadFeatures = loaded;
        _lastRoadFeatureLookup = DateTime.now();
        _lastRoadFeatureLookupPoint = position;
      } catch (error) {
        debugPrint('Не удалось обновить школы и переходы: $error');
      } finally {
        _roadFeatureLookupInProgress = false;
      }
    }

    if (!mounted || !_navigationActive || _voiceMode == 0) return;
    double? heading = gpsHeading;
    if (heading == null && _instructionIndex < _instructions.length) {
      final next = _instructions[_instructionIndex].location;
      heading = Geolocator.bearingBetween(
        position.latitude, position.longitude,
        next.latitude, next.longitude,
      );
    }
    if (heading == null || !heading.isFinite) return;

    final candidates = <({RoadFeature feature, double distance})>[];
    for (final feature in _roadFeatures) {
      final distance = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        feature.location.latitude, feature.location.longitude,
      );
      final announceRadius = feature.kind == RoadFeatureKind.school ? 450.0 : 260.0;
      if (distance > announceRadius || distance < 25) continue;
      final bearing = Geolocator.bearingBetween(
        position.latitude, position.longitude,
        feature.location.latitude, feature.location.longitude,
      );
      if (_bearingDifference(heading, bearing) > 60) continue;
      candidates.add((feature: feature, distance: distance));
    }
    candidates.sort((a, b) => a.distance.compareTo(b.distance));

    for (final candidate in candidates.take(2)) {
      final feature = candidate.feature;
      final distance = candidate.distance;
      final isSchool = feature.kind == RoadFeatureKind.school;
      final stage = isSchool
          ? (distance <= 130 ? 2 : 1)
          : (distance <= 70 ? 2 : 1);
      if (stage <= (_announcedRoadFeatureStages[feature.id] ?? 0)) continue;
      _announcedRoadFeatureStages[feature.id] = stage;
      final distanceText = distance >= 1000
          ? '${(distance / 1000).toStringAsFixed(1)} километра'
          : '${(distance / 50).round() * 50} метров';
      final message = isSchool
          ? _localized(
              stage == 1 ? 'Впереди школа. $distanceText.' : 'Школа через $distanceText. Снизьте скорость.',
              stage == 1 ? 'Алда мектеп. $distanceText.' : 'Мектеп $distanceText кейін. Жылдамдықты азайтыңыз.',
              stage == 1 ? 'School ahead. $distanceText.' : 'School in $distanceText. Slow down.',
            )
          : _localized(
              stage == 1 ? 'Впереди пешеходный переход. $distanceText.' : 'Пешеходный переход через $distanceText.',
              stage == 1 ? 'Алда жаяу жүргіншілер өткелі. $distanceText.' : 'Жаяу жүргіншілер өткелі $distanceText кейін.',
              stage == 1 ? 'Pedestrian crossing ahead. $distanceText.' : 'Pedestrian crossing in $distanceText.',
            );
      await _speakText(message);
      if (!mounted || !_navigationActive || _voiceMode == 0) return;
    }
  }

  // Advance the last accepted route match between GPS callbacks. This is a
  // short-horizon dead-reckoning estimate, not a replacement for raw GPS.
  void _startNavigationPredictionTicker() {
    _navigationPredictionTimer?.cancel();
    _navigationPredictionTimer = Timer.periodic(
      const Duration(milliseconds: 400),
      (_) {
        if (!mounted) return;
        if (!_navigationActive) {
          _navigationPredictionTimer?.cancel();
          _navigationPredictionTimer = null;
          return;
        }
        if (!_appInForeground) return;
        final predicted = _predictNavigationPosition();
        if (predicted == null) return;
        _navigationMatchedLocation = predicted;
        if (_routeCumulativeMeters.length == _routePoints.length && _navigationFixTimestamp != null) {
          final ageSeconds = DateTime.now().difference(_navigationFixTimestamp!).inMilliseconds / 1000.0;
          final predictedProgress = _navigationFixProgressMeters +
              _navigationFixSpeedMetersPerSecond.clamp(0.0, 40.0) * ageSeconds.clamp(0.0, 1.0).toDouble();
          _navigationProgressMeters = math.max(
            _navigationProgressMeters,
            predictedProgress.clamp(0.0, _routeCumulativeMeters.last).toDouble(),
          ).toDouble();
        }

        if (_mapFollowEnabled && !_headingUpGestureActive) {
          final center = _mapCameraCenter;
          final cameraDistance = Geolocator.distanceBetween(
            center.latitude, center.longitude,
            predicted.latitude, predicted.longitude,
          );
          if (cameraDistance >= 3.0) {
            final heading = _routeBearingAt(predicted) ??
                _gpsHeadingDegrees ?? _lastCameraHeadingDegrees ?? 0.0;
            _updateNavigationCamera(
              predicted,
              math.max(_mapCameraZoom, 17.0).toDouble(),
              heading,
            );
          }
        }

        final lastRouteSync = _lastRouteLineSyncPoint;
        final refreshRoute = lastRouteSync == null ||
            Geolocator.distanceBetween(
              lastRouteSync.latitude, lastRouteSync.longitude,
              predicted.latitude, predicted.longitude,
            ) >= 20;
        final now = DateTime.now();
        if (refreshRoute || _lastMapAnnotationUpdateAt == null ||
            now.difference(_lastMapAnnotationUpdateAt!) >=
                const Duration(milliseconds: 750)) {
          _lastMapAnnotationUpdateAt = now;
        }
        _updateNavigationProgress(predicted);
      },
    );
  }

  LatLng? _predictNavigationPosition() {
    final anchor = _navigationFixMatchedLocation;
    final timestamp = _navigationFixTimestamp;
    if (!_navigationActive || anchor == null || timestamp == null ||
        _routePoints.length < 2) {
      return _navigationMatchedLocation ?? anchor;
    }
    final ageSeconds = DateTime.now().difference(timestamp).inMilliseconds /
        1000.0;
    final predictionSeconds = ageSeconds.clamp(0.0, 1.0).toDouble();
    final speed = _navigationFixSpeedMetersPerSecond.clamp(0.0, 40.0).toDouble();
    var remainingMeters = speed * predictionSeconds;
    if (remainingMeters < 0.5) return anchor;

    var index = _navigationFixSegmentIndex
        .clamp(0, _routePoints.length - 2).toInt();
    var t = _navigationFixSegmentT.clamp(0.0, 1.0).toDouble();
    while (index < _routePoints.length - 1) {
      final a = _routePoints[index];
      final b = _routePoints[index + 1];
      final segmentMeters = Geolocator.distanceBetween(
        a.latitude, a.longitude, b.latitude, b.longitude,
      );
      if (segmentMeters < 0.1) {
        index++;
        t = 0;
        continue;
      }
      final availableMeters = segmentMeters * (1.0 - t);
      if (remainingMeters <= availableMeters) {
        final predictedT = t + remainingMeters / segmentMeters;
        return LatLng(
          a.latitude + (b.latitude - a.latitude) * predictedT,
          a.longitude + (b.longitude - a.longitude) * predictedT,
        );
      }
      remainingMeters -= availableMeters;
      index++;
      t = 0;
    }
    return _routePoints.last;
  }

  // Snap accepted GPS fixes to the active route. Raw GPS remains untouched
  // for road alerts and off-route detection; only guidance and map-follow use
  // this road-matched position.
  LatLng _matchNavigationPosition(Position fix, LatLng rawPoint) {
    if (!_navigationActive || _routePoints.length < 2) return rawPoint;
    if (!fix.accuracy.isFinite || fix.accuracy > 60) {
      return _navigationMatchedLocation ?? rawPoint;
    }
    if (DateTime.now().difference(fix.timestamp).inSeconds > 8) {
      return _navigationMatchedLocation ?? rawPoint;
    }

    const latScale = 110540.0;
    final lonScale = 111320.0 * math.cos(rawPoint.latitude * math.pi / 180);
    final px = rawPoint.longitude * lonScale;
    final py = rawPoint.latitude * latScale;
    final first = math.max(_routeProgressSegmentIndex, _navigationFixSegmentIndex)
        .clamp(0, _routePoints.length - 2).toInt();
    final last = math.min(_routePoints.length - 2, first + 80).toInt();
    var bestScore = double.infinity;
    var bestDistance = double.infinity;
    var bestIndex = -1;
    var bestT = 0.0;
    final hasCourse = fix.speed >= 1.5 &&
        fix.heading.isFinite &&
        fix.heading >= 0 &&
        fix.heading <= 360;

    for (var i = first; i <= last; i++) {
      final a = _routePoints[i];
      final b = _routePoints[i + 1];
      final ax = a.longitude * lonScale;
      final ay = a.latitude * latScale;
      final dx = (b.longitude - a.longitude) * lonScale;
      final dy = (b.latitude - a.latitude) * latScale;
      final lengthSquared = dx * dx + dy * dy;
      if (lengthSquared < 0.01) continue;
      final t = (((px - ax) * dx + (py - ay) * dy) / lengthSquared)
          .clamp(0.0, 1.0)
          .toDouble();
      final ex = px - (ax + t * dx);
      final ey = py - (ay + t * dy);
      final distance = math.sqrt(ex * ex + ey * ey);
      final segmentBearing = Geolocator.bearingBetween(
        a.latitude, a.longitude, b.latitude, b.longitude,
      );
      final headingDifference = hasCourse
          ? _bearingDifference(fix.heading, segmentBearing)
          : 0.0;
      if (hasCourse && headingDifference > 105) continue;
      if (i == _navigationFixSegmentIndex && t + 0.02 < _navigationFixSegmentT) continue;
      final score = distance + headingDifference * 0.22;
      if (score < bestScore) {
        bestScore = score;
        bestDistance = distance;
        bestIndex = i;
        bestT = t;
      }
    }

    final snapLimit = math.max(55.0, fix.accuracy * 1.8);
    if (bestIndex < 0 || bestDistance > snapLimit) {
      return _navigationMatchedLocation ?? rawPoint;
    }
    if (bestIndex > _routeProgressSegmentIndex) {
      _routeProgressSegmentIndex = bestIndex;
    }
    final a = _routePoints[bestIndex];
    final b = _routePoints[bestIndex + 1];
    final matched = LatLng(
      a.latitude + (b.latitude - a.latitude) * bestT,
      a.longitude + (b.longitude - a.longitude) * bestT,
    );
    _navigationFixMatchedLocation = matched;
    _navigationFixTimestamp = fix.timestamp;
    _navigationFixSpeedMetersPerSecond =
        fix.speed.isFinite ? math.max(0.0, fix.speed).toDouble() : 0.0;
    _navigationFixSegmentIndex = bestIndex;
    _navigationFixSegmentT = bestT;
    if (_routeCumulativeMeters.length == _routePoints.length) {
      _navigationFixProgressMeters = _routeCumulativeMeters[bestIndex] +
          (_routeCumulativeMeters[bestIndex + 1] - _routeCumulativeMeters[bestIndex]) * bestT;
      _navigationProgressMeters = math.max(_navigationProgressMeters, _navigationFixProgressMeters).toDouble();
    }
    return matched;
  }

  void _updateNavigationProgress(LatLng position) {
    if (!_navigationActive || _instructionIndex >= _instructions.length) return;

    final target = _instructions[_instructionIndex];
    final hasRouteProgress = _instructionProgressMeters.length == _instructions.length &&
        _routeCumulativeMeters.length == _routePoints.length && _routeCumulativeMeters.isNotEmpty;
    final meters = hasRouteProgress
        ? math.max(0.0, _instructionProgressMeters[_instructionIndex] - _navigationProgressMeters)
        : Geolocator.distanceBetween(position.latitude, position.longitude,
            target.location.latitude, target.location.longitude);

    // HUD, voice prompts and maneuver switching share one monotonic route distance.
    final isArrivalInstruction = _instructionIndex + 1 >= _instructions.length;
    final stage = isArrivalInstruction
        ? (meters <= 150 ? 2 : meters <= 500 ? 1 : 0)
        : (meters <= 35 ? 3 : meters <= 150 ? 2 : meters <= 500 ? 1 : 0);
    if (stage > _announcedManeuverStage) {
      _announcedManeuverStage = stage;
      if (_voiceMode >= 2) {
        final announcement = stage == 1
            ? _localized('Через 500 метров: ${target.text}', '500 метрден кейін: ${target.text}', 'In 500 meters: ${target.text}')
            : stage == 2
                ? _localized('Через 150 метров: ${target.text}', '150 метрден кейін: ${target.text}', 'In 150 meters: ${target.text}')
                : target.text;        unawaited(_speakText(announcement));
      }
    }

    final maneuverPassed = hasRouteProgress
        ? _navigationProgressMeters >= _instructionProgressMeters[_instructionIndex] + 5
        : meters <= 35;
    if (maneuverPassed) {
      if (_instructionIndex + 1 >= _instructions.length) {
        setState(() {
          _navigationActive = false;
          _routeActionDismissed = true;
          _message = AppLocale.pick('Вы прибыли в пункт назначения.', 'Межелі жерге жеттіңіз.', 'You have arrived at your destination.');
          _searchController.clear();
        });
        if (_voiceMode >= 1) {
          _speakText(_localized('Вы прибыли в пункт назначения.', 'Межелі жерге жеттіңіз.', 'You have arrived at your destination.'));
        }
        unawaited(_startLiveLocationUpdates());
        return;
      }
      setState(() {
        _instructionIndex++;
        _announcedManeuverStage = 0;
      });
      unawaited(_speakCurrentInstruction());
    }
  }

  // Keep full route geometry for rerouting; clip only the line rendered during navigation.
  List<LatLng> _remainingRoutePoints() {
    if (!_navigationActive || _currentLocation == null || _routePoints.length < 2) return _routePoints;
    final p = _navigationMatchedLocation ?? _currentLocation!;
    const latScale = 110540.0;
    final lonScale = 111320.0 * math.cos(p.latitude * math.pi / 180);
    final px = p.longitude * lonScale, py = p.latitude * latScale;
    final first = _routeProgressSegmentIndex.clamp(0, _routePoints.length - 2).toInt();
    var bestD2 = double.infinity, bestI = first, bestT = 0.0;
    for (var i = first; i < _routePoints.length - 1; i++) {
      final a = _routePoints[i], b = _routePoints[i + 1];
      final ax = a.longitude * lonScale, ay = a.latitude * latScale;
      final dx = (b.longitude - a.longitude) * lonScale;
      final dy = (b.latitude - a.latitude) * latScale;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0).toDouble();
      final ex = px - (ax + t * dx), ey = py - (ay + t * dy);
      final d2 = ex * ex + ey * ey;
      if (d2 < bestD2) { bestD2 = d2; bestI = i; bestT = t; }
    }
    if (bestD2 > 10000) return _routePoints;
    if (bestI > _routeProgressSegmentIndex) _routeProgressSegmentIndex = bestI;
    final a = _routePoints[bestI], b = _routePoints[bestI + 1];
    final projected = LatLng(a.latitude + (b.latitude-a.latitude)*bestT, a.longitude + (b.longitude-a.longitude)*bestT);
    final result = <LatLng>[projected]..addAll(_routePoints.skip(bestI + 1));
    return result.length > 1 ? result : <LatLng>[projected, _routePoints.last];
  }

  String _routeDirectionCueText() {
    if (_instructionIndex >= _instructions.length) return '‹   ▲   ›';
    final m = _instructions[_instructionIndex].maneuverModifier.toLowerCase();
    if (m.contains('left') || m.contains('uturn')) return '◀   ↑   ›';
    if (m.contains('right')) return '‹   ↑   ▶';
    return '‹   ▲   ›';
  }

  Widget _buildRouteDirectionCue() {
    final m = _instructionIndex < _instructions.length ? _instructions[_instructionIndex].maneuverModifier.toLowerCase() : 'straight';
    final left = m.contains('left') || m.contains('uturn'), right = m.contains('right');
    const faded = Color(0x8877A98A), active = Color(0xFF16864A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(color: const Color(0xAAFFFFFF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0x6673A987))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.arrow_left, size: 20, color: left ? active : faded),
        const SizedBox(width: 3),
        Icon(Icons.arrow_upward, size: 20, color: (!left && !right) ? active : faded),
        const SizedBox(width: 3),
        Icon(Icons.arrow_right, size: 20, color: right ? active : faded),
        const SizedBox(width: 5),
        Text(_distanceToNextManeuverMeters == null ? '—' : (_distanceToNextManeuverMeters! >= 1000 ? '${(_distanceToNextManeuverMeters! / 1000).toStringAsFixed(1)} км' : '${_distanceToNextManeuverMeters!.round()} м'),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF263238))),
      ]),
    );
  }

  List<Marker> _buildOfflineRouteArrowMarkers(List<LatLng> points) {
    if (points.length < 2 || _instructions.isEmpty) return <Marker>[];
    final result = <Marker>[];
    for (var i = 0; i < _instructions.length; i++) {
      final instruction = _instructions[i];
      if (!_isRouteManeuverMarker(instruction)) continue;
      if (_navigationActive && i <= _instructionIndex) continue;
      result.add(Marker(
        point: instruction.location,
        width: 34,
        height: 34,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF2378C8), width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 1)),
            ],
          ),
          child: Icon(_maneuverIcon(instruction), color: const Color(0xFF2378C8), size: 21),
        ),
      ));
    }
    return result;
  }

  double _distanceToRouteMeters(LatLng position) {
    if (_routePoints.length < 2) return double.infinity;
    const latScale = 110540.0;
    final lonScale = 111320.0 * math.cos(position.latitude * math.pi / 180);
    final px = position.longitude * lonScale;
    final py = position.latitude * latScale;
    // Only compare against the route still ahead of the vehicle. Including
    // already-driven segments can hide a missed turn on a nearby parallel road.
    final firstSegment = math.max(
      _routeProgressSegmentIndex,
      _navigationFixSegmentIndex,
    ).clamp(0, _routePoints.length - 2).toInt();
    var best = double.infinity;
    for (var i = firstSegment; i < _routePoints.length - 1; i++) {
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
    // Allow normal urban GPS variation, but reject stale/very inaccurate fixes.
    // Two consecutive off-route fixes are still required to avoid false reroutes.
    if (!position.accuracy.isFinite ||
        position.accuracy <= 0 ||
        position.accuracy > 60 ||
        _routePoints.length < 2) return;
    final now = DateTime.now();
    if (_lastAutomaticReroute != null &&
        now.difference(_lastAutomaticReroute!) < const Duration(seconds: 4)) {
      return;
    }
    final distance = _distanceToRouteMeters(
      LatLng(position.latitude, position.longitude),
    );
    final offRouteLimit = math.max(25.0, position.accuracy * 1.25);
    if (distance > offRouteLimit) {
      _offRouteSamples++;
    } else {
      _offRouteSamples = 0;
    }
    if (_offRouteSamples >= 2) {
      _offRouteSamples = 0;
      _lastAutomaticReroute = now;
      _buildRoute(automaticReroute: true);
    }
  }

  Future<void> _buildRoute({bool automaticReroute = false}) async {
    final requestGeneration = ++_routeRequestGeneration;
    if (_destination == null) {
      setState(() => _message = AppLocale.pick('Сначала выберите конечную точку на карте.', 'Алдымен картадан соңғы нүктені таңдаңыз.', 'First select the destination point on the map.'));
      return;
    }
    if (_routeOrigin == null && _currentLocation == null) await _locateMe();
    // During an automatic reroute, always start from the latest live GPS fix;
    // a manually saved/planned origin must never pull the driver backwards.
    final routeOrigin = automaticReroute
        ? _currentLocation
        : (_routeOrigin ?? _currentLocation);
    if (routeOrigin == null || _destination == null) {
      if (mounted) setState(() => _message = AppLocale.pick('Не удалось определить начальную точку. Выберите её на карте или включите GPS.', 'Бастапқы нүктені анықтау мүмкін болмады. Оны картадан таңдаңыз немесе GPS қосыңыз.', 'Could not determine the starting point. Select it on the map or enable GPS.'));
      return;
    }

    final resumeNavigation = automaticReroute && _navigationActive;
    setState(() {
      _isBuildingRoute = true;
      _message = automaticReroute ? AppLocale.pick('Вы отклонились от маршрута. Перестраиваем…', 'Маршруттан ауытқыдыңыз. Қайта құрудамыз…', 'You left the route. Recalculating…') : AppLocale.pick('Строим варианты маршрута…', 'Маршрут нұсқалары құрылуда…', 'Building route options…');
    });

    String? routingNotice;
    try {
      final coordinates = <LatLng>[routeOrigin, ..._routeStops, _destination!]
          .map((point) => '${point.longitude},${point.latitude}')
          .join(';');
      Map<String, dynamic>? routeData;

      // Valhalla handles direct Shymkent routes for both car and pedestrian
      // costing. OSRM remains the fallback and handles intermediate stops.
      final destination = _destination!;
      final directDistanceMeters = Geolocator.distanceBetween(
        routeOrigin.latitude, routeOrigin.longitude,
        destination.latitude, destination.longitude,
      );
      // Keep the proven in-city alternatives request unchanged. Longer car
      // trips ask OSRM for up to three alternative routes explicitly.
      final isIntercityDriving = !_walkingMode && directDistanceMeters >= 50000;
      final isInsideShymkentGraph =
          routeOrigin.latitude >= 42.12 &&
          routeOrigin.latitude <= 42.53 &&
          routeOrigin.longitude >= 69.35 &&
          routeOrigin.longitude <= 69.90 &&
          destination.latitude >= 42.12 &&
          destination.latitude <= 42.53 &&          destination.longitude >= 69.35 &&
          destination.longitude <= 69.90;
      if (_routeStops.isEmpty && isInsideShymkentGraph) {
        if (!_valhallaReady) {
          // Never block route calculation on downloading or initializing the graph.
          // It continues in the background for the next route.
          unawaited(_ensureValhallaReady());
          routingNotice = AppLocale.pick(
            'Офлайн-граф подключается в фоне. Используем интернет-маршрут.',
            'Офлайн графы фонда қосылуда. Интернет маршрутын қолданамыз.',
            'Offline graph is preparing in the background. Using online routing.',
          );
        } else {
          try {
            final raw = await _valhallaChannel.invokeMethod<String>(
              'route',
              <String, dynamic>{
                'startLat': routeOrigin.latitude,
                'startLon': routeOrigin.longitude,
                'endLat': destination.latitude,
                'endLon': destination.longitude,
                'costing': _walkingMode ? 'pedestrian' : 'auto',
              },
            ).timeout(const Duration(seconds: 2));
            if (raw == null || raw.isEmpty) {
              throw Exception('Пустой ответ офлайн-маршрутизатора.');
            }
            // Native Valhalla routing already runs on its dedicated Kotlin
            // worker. Decode the potentially large GeoJSON response off the UI
            // isolate as well, so map gestures and GPS rendering stay responsive.
            final localData = await compute(
              _decodeValhallaRouteResponseInBackground,
              raw,
            );
            final localRoutes = (localData['routes'] as List?) ?? const [];
            // The shared route renderer expects OSRM-compatible GeoJSON geometry.
            // Reject malformed Valhalla responses here so the online fallback runs
            // instead of failing later while drawing the route.
            final usableLocalRoutes = localRoutes.where((route) {
              if (route is! Map<String, dynamic>) return false;
              final geometry = route['geometry'];
              if (geometry is! Map<String, dynamic>) return false;
              final coordinates = geometry['coordinates'];
              return route['distance'] is num &&
                  route['duration'] is num &&
                  coordinates is List &&
                  coordinates.length >= 2 &&
                  coordinates.every((pair) =>
                      pair is List &&
                      pair.length >= 2 &&
                      pair[0] is num &&
                      pair[1] is num);
            }).toList();
            if (localData['code'] != 'Ok' || usableLocalRoutes.isEmpty) {
              throw Exception(
                'Офлайн-маршрутизатор вернул некорректные данные маршрута.',
              );
            }
            localData['routes'] = usableLocalRoutes;
            routeData = localData;
          } catch (error) {
            routingNotice = AppLocale.pick(
              '${_valhallaErrorForUser(error)} Пробуем построить маршрут через интернет.',
              '${_valhallaErrorForUser(error)} Интернет арқылы маршрут құрып көреміз.',
              '${_valhallaErrorForUser(error)} Trying the online router.',
            );
            debugPrint('BAKE Valhalla route failed; falling back to OSRM: $error');
          }
        }
      }

      if (!_walkingMode && _routeStops.isEmpty && !isInsideShymkentGraph) {
        routingNotice = AppLocale.pick(
          'Точка вне зоны офлайн-графа Шымкента. Используем интернет-маршрут.',
          'Нүкте Шымкент офлайн графы аймағынан тыс. Интернет маршрутын қолданамыз.',
          'Destination is outside Shymkent offline coverage. Using online routing.',
        );
      }

      if (routeData == null) {
        final routeEndpoint = _walkingMode
            ? 'https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
            : 'https://router.project-osrm.org/route/v1/driving/';
        final uri = Uri.parse(
          '$routeEndpoint$coordinates'
          '?overview=full&geometries=geojson&steps=true&alternatives=${isIntercityDriving ? 3 : 'true'}',
        );
        // FOSSGIS provides a separate pedestrian profile. Car routes keep
        // their existing OSRM endpoint and behavior.
        final response = await http.get(
          uri,
          headers: const {'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)'},
        ).timeout(Duration(seconds: _walkingMode ? 12 : (isIntercityDriving ? 15 : 5)));
        if (response.statusCode != 200) throw Exception(AppLocale.pick('Сервис маршрутов временно недоступен.', 'Маршрут қызметі уақытша қолжетімсіз.', 'Route service is temporarily unavailable.'));
        routeData = jsonDecode(response.body) as Map<String, dynamic>;
      }

      final data = routeData!;
      final routes = (data['routes'] as List?) ?? const [];
      if (data['code'] != 'Ok' || routes.isEmpty) {
        throw Exception(AppLocale.pick('Маршрут не найден. Попробуйте изменить выбранные точки.', 'Маршрут табылмады. Таңдалған нүктелерді өзгертіп көріңіз.', 'Route not found. Try changing the selected points.'));
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
        throw Exception(AppLocale.pick('Сервис вернул слишком длинный маршрут. Проверьте выбранные точки.', 'Қызмет тым ұзын маршрут қайтарды. Таңдалған нүктелерді тексеріңіз.', 'The service returned a route that is too long. Check the selected points.'));
      }

      // Prefer the shortest distance by default. Keep the returned alternatives
      // available so the driver can still select the fastest option.
      validRoutes.sort((a, b) =>
          (a['distance'] as num).compareTo(b['distance'] as num));
      if (validRoutes.length > 3) {
        validRoutes.removeRange(3, validRoutes.length);
      }

      final first = validRoutes.first;
      final points = _routePointsFromDecodedRoute(first);
      final instructions = _readInstructions(first);
      final distance = (first['distance'] as num).toDouble();
      final duration = (first['duration'] as num).toDouble();

      if (!mounted || requestGeneration != _routeRequestGeneration) return;
      setState(() {
        _routeAlternatives = validRoutes;
        _selectedRouteIndex = 0;
        _routeProgressSegmentIndex = 0;
_navigationMatchedLocation = null;
        _routePoints = points;
        _routeReady = points.length >= 2;
        _routeActionDismissed = false;
        _instructions = instructions;
        _prepareNavigationProgress(points, instructions);
        _navigationActive = resumeNavigation;
        _instructionIndex = resumeNavigation && instructions.length > 1 ? 1 : 0;
        _offRouteSamples = 0;
        _routeDistanceMeters = distance;
        _routeDurationSeconds = duration;
        // Keep the map clear; route alternatives are presented in the route-search screen.
        _message = routingNotice ?? (automaticReroute
            ? AppLocale.pick('Маршрут перестроен. Продолжаем навигацию.', 'Маршрут қайта құрылды. Навигация жалғасуда.', 'Route recalculated. Continuing navigation.')
            : '');
      });
      if (points.isNotEmpty) {
        if (!automaticReroute || _mapFollowEnabled) _fitMapCamera(points);
        if (automaticReroute && resumeNavigation && _mapFollowEnabled && _currentLocation != null) {
          _moveMapCamera(_currentLocation!, 17);
          final heading = _gpsHeadingDegrees;
          if (heading != null && _currentSpeedKmh >= 5.4) {
            _rotateMapCamera(-heading);
            _lastCameraHeadingDegrees = heading;
          }
        }
      }
      if (automaticReroute && resumeNavigation) {
        if (_voiceMode >= 1) await _speakText(_localized('Вы отклонились от маршрута. Маршрут перестроен.', 'Бағыттан ауытқыдыңыз. Маршрут қайта құрылды.', 'You left the route. The route has been recalculated.'));
        await _speakCurrentInstruction();
      } else {
        final distanceKm = (distance / 1000).toStringAsFixed(1);
        final minutes = (duration / 60).round();
        if (_voiceMode >= 3) await _speakText(_localized('Маршрут построен. Расстояние $distanceKm километра. Примерное время в пути $minutes минут.', 'Маршрут құрылды. Қашықтық $distanceKm километр. Жол уақыты шамамен $minutes минут.', 'Route built. Distance $distanceKm kilometers. Estimated travel time $minutes minutes.'));
        // Keep the map's persistent «Поехали» control unchanged.
      }
      // Route alternatives remain visible on the map; select a line directly.
    } catch (error) {
      if (!mounted || requestGeneration != _routeRequestGeneration) return;
      final failure = error.toString().replaceFirst('Exception: ', '');
      setState(() => _message = routingNotice == null
          ? failure
          : AppLocale.pick(
              '$routingNotice Интернет-маршрут тоже не ответил. Проверьте подключение.',
              '$routingNotice Интернет маршруты да жауап бермеді. Байланысты тексеріңіз.',
              '$routingNotice The online router also did not respond. Check your connection.',
            ));
    } finally {
      if (mounted && requestGeneration == _routeRequestGeneration) {
        setState(() => _isBuildingRoute = false);
      }
    }
  }

  String _routeAlternativeLabel(int index) {
    if (_routeAlternatives.isEmpty || index < 0 ||
        index >= _routeAlternatives.length) {
      return AppLocale.pick('Вариант маршрута', 'Маршрут нұсқасы', 'Route option');
    }

    var shortestIndex = 0;
    var fastestIndex = 0;
    for (var i = 1; i < _routeAlternatives.length; i++) {
      final candidate = _routeAlternatives[i];
      final shortest = _routeAlternatives[shortestIndex];
      final fastest = _routeAlternatives[fastestIndex];
      if ((candidate['distance'] as num) < (shortest['distance'] as num)) {
        shortestIndex = i;
      }
      if ((candidate['duration'] as num) < (fastest['duration'] as num)) {
        fastestIndex = i;
      }
    }

    if (index == shortestIndex && index == fastestIndex) {
      return AppLocale.pick(
        'Самый короткий и быстрый',
        'Ең қысқа әрі жылдам',
        'Shortest and fastest',
      );
    }
    if (index == shortestIndex) {
      return AppLocale.pick('Самый короткий', 'Ең қысқа', 'Shortest');
    }
    if (index == fastestIndex) {
      return AppLocale.pick('Самый быстрый', 'Ең жылдам', 'Fastest');
    }
    return AppLocale.pick('Альтернативный', 'Балама маршрут', 'Alternative');
  }

  void _selectRouteAlternative(int index) {
    if (index < 0 || index >= _routeAlternatives.length) return;
    final route = _routeAlternatives[index];
    final points = _routePointsFromDecodedRoute(route);
    final instructions = _readInstructions(route);
    final wasNavigating = _navigationActive;
    var nearestInstructionIndex = 0;
    if (wasNavigating && _currentLocation != null && instructions.isNotEmpty) {
      var nearestDistance = double.infinity;
      for (var i = 0; i < instructions.length; i++) {
        final distance = Geolocator.distanceBetween(
          _currentLocation!.latitude,
          _currentLocation!.longitude,
          instructions[i].location.latitude,
          instructions[i].location.longitude,
        );
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestInstructionIndex = i;
        }
      }
    }
    setState(() {
      _selectedRouteIndex = index;
      _routeProgressSegmentIndex = 0;
_navigationMatchedLocation = null;
      _routePoints = points;
      _routeReady = points.length >= 2;
      _instructions = instructions;
      _prepareNavigationProgress(points, instructions);
      if (wasNavigating && _currentLocation != null && _routeCumulativeMeters.isNotEmpty) {
        _setNavigationProgressAnchor(
          _projectRouteProgress(points, _routeCumulativeMeters, _currentLocation!),
        );
        nearestInstructionIndex = _instructionProgressMeters.indexWhere(
          (progress) => progress >= _navigationProgressMeters - 8,
        );
        if (nearestInstructionIndex < 0) nearestInstructionIndex = instructions.length - 1;
      }
      _instructionIndex = nearestInstructionIndex;
      _routeDistanceMeters = (route['distance'] as num).toDouble();
      _routeDurationSeconds = (route['duration'] as num).toDouble();
      _message = _localized('Выбран вариант маршрута ${index + 1}.', '${index + 1}-маршрут нұсқасы таңдалды.', 'Route option ${index + 1} selected.');
    });
    if (points.isNotEmpty) {
      if (!wasNavigating) {
        _fitMapCamera(points);
      } else if (_currentLocation != null) {
        final heading = _gpsHeadingDegrees ?? _routeBearingAt(_currentLocation!);
        _updateNavigationCamera(_currentLocation!, 17, heading);
      }
    }
  }

  Future<void> _addRouteStop(LatLng point) async {
    if (_routeStops.length >= 5) {
      setState(() => _message = AppLocale.tr('Можно добавить не более пяти промежуточных остановок.'));
      return;
    }
    setState(() {
      _routeStops.add(point);
      _message = AppLocale.tr('Промежуточная остановка добавлена. Перестройте маршрут.');
    });
  }



  Future<void> _openSearchPanel() async {
    final prefs = await SharedPreferences.getInstance();
    final savedNominatimTestMode = prefs.getBool('nominatim_test_mode') ?? false;
    if (mounted && _nominatimTestMode != savedNominatimTestMode) {
      setState(() => _nominatimTestMode = savedNominatimTestMode);
    }
    List<Map<String, dynamic>> photonSuggestions = <Map<String, dynamic>>[];
    bool photonLoadingSuggestions = false;
    Timer? photonDebounce;
    var photonRequestVersion = 0;
    var photonRequestRunning = false;
    String? pendingPhotonQuery;
    var pendingPhotonVersion = 0;
    final history = prefs.getStringList('search_history') ?? <String>[];
    if (!mounted) return;
    const categories = <Map<String, Object>>[
      {'name': 'АЗС', 'query': 'АЗС', 'icon': Icons.local_gas_station},
      {'name': 'Рестораны', 'query': 'ресторан', 'icon': Icons.restaurant},
      {'name': 'Магазины', 'query': 'магазин', 'icon': Icons.store},
      {'name': 'Гостиницы', 'query': 'гостиница', 'icon': Icons.hotel},
      {'name': 'Аптеки', 'query': 'аптека', 'icon': Icons.local_pharmacy},
      {'name': 'Парковки', 'query': 'парковка', 'icon': Icons.local_parking},
      {'name': 'Больницы', 'query': 'больница', 'icon': Icons.local_hospital},
      {'name': 'Ещё', 'query': '', 'icon': Icons.apps},
    ];

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(            title: Text(AppLocale.tr('Поиск')),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                StatefulBuilder(
                  builder: (searchContext, refreshSearch) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment<bool>(
                              value: false,
                              icon: Icon(Icons.bolt_outlined),
                              label: Text('Photon'),
                            ),
                            ButtonSegment<bool>(
                              value: true,
                              icon: Icon(Icons.science_outlined),
                              label: Text('Тест Nominatim'),
                            ),
                          ],
                          selected: <bool>{_nominatimTestMode},
                          onSelectionChanged: (selection) async {
                            final enabled = selection.first;
                            photonDebounce?.cancel();
                            photonRequestVersion++;
                            pendingPhotonQuery = null;
                            await prefs.setBool('nominatim_test_mode', enabled);
                            if (!mounted || !searchContext.mounted) return;
                            setState(() => _nominatimTestMode = enabled);
                            refreshSearch(() {
                              photonSuggestions = <Map<String, dynamic>>[];
                              photonLoadingSuggestions = false;
                            });
                          },
                        ),
                        if (_nominatimTestMode)
                          const Padding(
                            padding: EdgeInsets.only(top: 6, bottom: 8),
                            child: Text(
                              'Изолированный тест: только Nominatim. Подсказки при вводе отключены; поиск выполняется после Enter или нажатия кнопки. Ограничение — не чаще 1 запроса в секунду.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF687786)),
                            ),
                          ),
                        VoiceTextField(
                          controller: _searchController,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) {
                            photonDebounce?.cancel();
                            if (_nominatimTestMode) {
                              photonRequestVersion++;
                              pendingPhotonQuery = null;
                              refreshSearch(() {
                                photonSuggestions = <Map<String, dynamic>>[];
                                photonLoadingSuggestions = false;
                              });
                              return;
                            }
                            final requestVersion = ++photonRequestVersion;
                            if (value.trim().length < 2) {
                              pendingPhotonQuery = null;
                              refreshSearch(() {
                                photonSuggestions = <Map<String, dynamic>>[];
                                photonLoadingSuggestions = false;
                              });
                              return;
                            }
                            refreshSearch(() {
                                photonLoadingSuggestions = true;
                              });
                            // Keep typing responsive: one Photon batch at a time.
                            // While it runs, retain only the newest text value.
                            Future<void> loadLatestPhotonSuggestions(
                              String query,
                              int version,
                            ) async {
                              if (photonRequestRunning) {
                                pendingPhotonQuery = query;
                                pendingPhotonVersion = version;
                                return;
                              }
                              photonRequestRunning = true;
                              var activeQuery = query;
                              var activeVersion = version;
                              try {
                                while (true) {
                                  pendingPhotonQuery = null;
                                  final found = await _fetchPhotonFeatures(
                                    activeQuery,
                                    includeCitySearch: true,
                                    includeNominatimCitySearch: false,
                                    includeNominatimAddressFallback: false,
                                    resultLimit: 12,
                                  ).timeout(const Duration(seconds: 4));
                                  if (searchContext.mounted &&
                                      activeVersion == photonRequestVersion) {
                                    if (_flutterMapExperimentEnabled && !_isOfflineMapActive) {
                                      _sortSearchFeatures(found, activeQuery);
                                    } else {
                                      found.sort((left, right) =>
                                          (_photonFeatureDistanceMeters(left) ?? double.infinity)
                                              .compareTo(_photonFeatureDistanceMeters(right) ?? double.infinity));
                                    }
                                    refreshSearch(() {
                                      photonSuggestions = found;
                                      photonLoadingSuggestions = false;
                                    });
                                  }
                                  final nextQuery = pendingPhotonQuery;
                                  if (nextQuery == null) break;
                                  activeQuery = nextQuery;
                                  activeVersion = pendingPhotonVersion;
                                }
                              } catch (error) {
                                debugPrint('BAKE Photon autocomplete failed: $error');
                                if (searchContext.mounted &&
                                    activeVersion == photonRequestVersion) {
                                  refreshSearch(() => photonLoadingSuggestions = false);
                                }
                              } finally {
                                photonRequestRunning = false;
                              }
                            }
                            photonDebounce = Timer(const Duration(milliseconds: 300), () {
                              unawaited(loadLatestPhotonSuggestions(value, requestVersion));
                            });
                          },
                          onSubmitted: (_) {
                            photonDebounce?.cancel();
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
                                      photonDebounce?.cancel();
                                      Navigator.pop(pageContext);
                                      _searchAddress();
                                    },
                              icon: const Icon(Icons.arrow_forward),
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                        if (photonLoadingSuggestions)
                          const Padding(
                            padding: EdgeInsets.all(10),
                            child: LinearProgressIndicator(minHeight: 2),
                          ),
                        if (photonSuggestions.isNotEmpty)
                          Container(
                            constraints: const BoxConstraints(maxHeight: 320),
                            margin: const EdgeInsets.only(top: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: const Color(0xFFE3E6EA)),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: ListView.separated(
                              shrinkWrap: true,
                              itemCount: photonSuggestions.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final feature = photonSuggestions[index];
                                final label = _photonFeatureAddress(feature);
                                final rawProperties = feature['properties'];
                                final properties = rawProperties is Map
                                    ? Map<String, dynamic>.from(rawProperties)
                                    : <String, dynamic>{};
                                final name = (properties['name'] ?? label).toString().trim();
                                final address = _photonFeatureStreetAddress(feature);
                                return ListTile(
                                  dense: true,
                                  leading: Icon(feature['_roadReport'] == true ? Icons.push_pin : Icons.location_on_outlined, size: 20, color: feature['_roadReport'] == true ? const Color(0xFF16834A) : null),
                                  title: Text(name.isEmpty ? 'Адрес' : name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  subtitle: (address.isNotEmpty || feature['_roadReport'] == true)
                                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                                          if (address.isNotEmpty) Text(address, maxLines: 1, overflow: TextOverflow.ellipsis),
                                          if (feature['_roadReport'] == true) const Text('✓ Проверено', style: TextStyle(color: Color(0xFF16834A), fontWeight: FontWeight.w700)),
                                        ])
                                      : null,
                                  trailing: Text(_formatSearchDistance(feature), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF303840))),
                                  onTap: () {
                                    photonDebounce?.cancel();
                                    final geometry = feature['geometry'];
                                    final coordinates = geometry is Map ? geometry['coordinates'] : null;
                                    if (coordinates is! List || coordinates.length < 2) return;
                                    final lon = double.tryParse(coordinates[0].toString());
                                    final lat = double.tryParse(coordinates[1].toString());
                                    if (lat == null || lon == null || lat < 40 || lat > 56 || lon < 46 || lon > 88) return;
                                    final point = LatLng(lat, lon);
                                    _searchController.text = label.isEmpty ? valueForPhotonFeature(feature) : label;
                                    Navigator.pop(pageContext);
                                    _selectDestination(point);
                                    _moveMapCamera(point, 16);
                                    setState(() => _message = label.isEmpty ? 'Адрес найден.' : label);
                                    unawaited(_buildRoute());
                                  },
                                );
                              },
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 22),
                Text(
                  AppLocale.tr('Недавние запросы'),
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
                    title: Text(query, maxLines: 3, softWrap: true, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.north_west, size: 18),
                    onTap: () {
                      Navigator.pop(pageContext);
                      _searchController.text = query;
                      _searchAddress();
                    },
                  )),
                const Divider(height: 24),
                Text(
                  AppLocale.tr('Категории'),
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
    photonDebounce?.cancel();
  }

  Future<void> _openMoreSearchCategories() async {
    const categories = <Map<String, Object>>[
      {'name': 'Кафе', 'query': 'кафе', 'icon': Icons.local_cafe},
      {'name': 'Банкоматы', 'query': 'банкомат', 'icon': Icons.atm},
      {'name': 'Автомойки', 'query': 'автомойка', 'icon': Icons.local_car_wash},
      {'name': 'Автосервисы', 'query': 'автосервис', 'icon': Icons.car_repair},
      {'name': 'Школы', 'query': 'школа', 'icon': Icons.school},
      {'name': 'Остановки', 'query': 'автобусная остановка', 'icon': Icons.directions_bus},
      {'name': 'Полиция', 'query': 'полиция', 'icon': Icons.local_police},
      {'name': 'Парки', 'query': 'парк', 'icon': Icons.park},
      {'name': 'Торговые центры', 'query': 'торговый центр', 'icon': Icons.shopping_bag},
      {'name': 'Пункты выдачи', 'query': 'пункт выдачи заказов', 'icon': Icons.inventory_2},
      {'name': 'Кинотеатры', 'query': 'кинотеатр', 'icon': Icons.movie},
      {'name': 'Почта', 'query': 'почтовое отделение', 'icon': Icons.local_post_office},
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
                      Text(AppLocale.tr(name), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
      await _showUnavailableFeature('Геопозиция', AppLocale.pick('Сначала дождитесь определения GPS.', 'Алдымен GPS анықталғанын күтіңіз.', 'Wait for GPS to determine your location first.'));
      return;
    }
    final value = 'Моя геопозиция BAKE: https://www.openstreetmap.org/?mlat=${point.latitude}&mlon=${point.longitude}#map=17/${point.latitude}/${point.longitude}';
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) setState(() => _message = AppLocale.pick('Ссылка на геопозицию скопирована.', 'Геолокация сілтемесі көшірілді.', 'Location link copied.'));
  }

  Future<void> _shareRoute() async {
    if (_destination == null || _routePoints.isEmpty) {
      await _showUnavailableFeature('Поделиться маршрутом', AppLocale.pick('Сначала постройте маршрут.', 'Алдымен маршрут құрыңыз.', 'Build a route first.'));
      return;
    }
    final origin = _routeOrigin ?? _currentLocation;
    final value = 'Маршрут BAKE Navigator\\n'
        'Откуда: ${origin == null ? 'текущее местоположение' : '${origin.latitude}, ${origin.longitude}'}\\n'
        'Куда: ${_destination!.latitude}, ${_destination!.longitude}\\n'
        '${_routeSummary()}\\n'
        'https://www.openstreetmap.org/directions?engine=fossgis_osrm_car&route=${origin?.latitude}%2C${origin?.longitude}%3B${_destination!.latitude}%2C${_destination!.longitude}';
    await Clipboard.setData(ClipboardData(text: value));
    if (mounted) setState(() => _message = AppLocale.pick('Описание маршрута скопировано для отправки.', 'Маршрут сипаттамасы жіберу үшін көшірілді.', 'Route description copied for sharing.'));
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
    if (mounted) setState(() => _message = AppLocale.pick(AppLocale.pick(AppLocale.pick('Отчёт скопирован. Отправка на сервер пока не подключена.', 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'), 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'), 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'));
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
    final trafficKeyController = TextEditingController(
      text: prefs.getString('tomtom_traffic_api_key') ?? '',
    );
    var roadEvents = prefs.getBool('layer_road_events') ?? true;
    var parking = prefs.getBool('layer_parking') ?? false;
    Future<void> saveLayer(String key, bool value) async {
      await prefs.setBool(key, value);
      if (!mounted) return;
      setState(() {
        if (key == 'layer_traffic') _trafficLayerEnabled = value;
        if (key == 'layer_road_events') _roadEventsLayerEnabled = value;
        _message = key == 'layer_traffic'
            ? AppLocale.pick(
                'Слой дорожных сообщений включён. Показываются подтверждённые отметки пользователей.',
                'Жол хабарламалары қабаты қосылды. Расталған пайдаланушы белгілері көрсетіледі.',
                'Road reports layer enabled. Confirmed user reports are shown.',
              )
            : AppLocale.pick(
                'Настройка сохранена. Для этого слоя источник данных ещё не подключён.',
                'Баптау сақталды. Бұл қабатқа дерек көзі әлі қосылмаған.',
                'Setting saved. This layer does not have a connected data source yet.',
              );
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
                Text(
                  AppLocale.tr('Слои карты'),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocale.pick(
                          'Реальные пробки и скорость движения TomTom. Введите API-ключ TomTom:',
                          'TomTom нақты кептелістер мен қозғалыс жылдамдығы. TomTom API кілтін енгізіңіз:',
                          'TomTom live traffic flow and incidents. Enter your TomTom API key:',
                        ),
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: trafficKeyController,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          hintText: 'TomTom API key',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: AppLocale.tr('Сохранить ключ'),
                            icon: const Icon(Icons.save_outlined),
                            onPressed: () async {
                              final key = trafficKeyController.text.trim();
                              await prefs.setString('tomtom_traffic_api_key', key);
                              if (!mounted) return;
                              setState(() {
                                _tomtomTrafficApiKey = key;
                                _message = key.isEmpty
                                    ? AppLocale.tr('Ключ TomTom удалён.')
                                    : AppLocale.tr('Ключ TomTom сохранён на телефоне.');
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
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

                const Divider(),
                const SizedBox(height: 10),
                Text(
                  AppLocale.tr('Офлайн-карты'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
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
                  !_isOfflineMapActive
                      ? AppLocale.pick('Офлайн-карта не подключена. Размер и покрытие файла проверяются после выбора; готовые пакеты для скачивания пока не предоставляются.', 'Офлайн карта қосылмаған. Файл таңдалғаннан кейін оның өлшемі мен қамту аумағы тексеріледі; дайын жүктеу пакеттері әзірге берілмейді.', 'No offline map is connected. File size and coverage are checked after selection; ready-made download packages are not provided yet.')
                      : AppLocale.pick('Офлайн-карта подключена. Для построения маршрута пока нужен интернет.', 'Офлайн карта қосылды. Маршрут құру үшін әзірге интернет қажет.', 'Offline map connected. Internet is still required to build routes.'),
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
    trafficKeyController.dispose();
  }

  Future<void> _openProfileMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.88),
          child: SingleChildScrollView(
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
              _menuTile(sheetContext, Icons.settings_outlined, AppLocale.tr('Настройки'), () { Navigator.pop(sheetContext); _openSettings(); }),
              _menuTile(sheetContext, Icons.download_for_offline_outlined, AppLocale.tr('Загрузка карт'), () { Navigator.pop(sheetContext); _openOfflineAndVehicleSettings(); }),
              _menuTile(sheetContext, Icons.support_agent_outlined, AppLocale.tr('Поддержка'), () { Navigator.pop(sheetContext); _openSupportPage(); }),
              _menuTile(sheetContext, Icons.map_outlined, AppLocale.tr('Изменить карту и слои'), () { Navigator.pop(sheetContext); _openMapLayers(); }),
              _menuTile(sheetContext, Icons.add_location_alt_outlined, AppLocale.tr('Разместить объект'), () { Navigator.pop(sheetContext); _openPlaceSubmissionPage(); }),
              _menuTile(sheetContext, Icons.share_location_outlined, AppLocale.tr('Поделиться геопозицией'), () { Navigator.pop(sheetContext); _shareCurrentLocation(); }),
              _menuTile(sheetContext, Icons.bookmark_border, AppLocale.tr('Закладки'), () { Navigator.pop(sheetContext); _openBookmarks(); }),
              _menuTile(sheetContext, Icons.place_outlined, AppLocale.tr('Мои места'), () { Navigator.pop(sheetContext); _openMyPlaces(); }),
              _menuTile(sheetContext, Icons.warning_amber_outlined, AppLocale.tr('События на дороге'), () { Navigator.pop(sheetContext); _openRoadEvents(); }),
              _menuTile(sheetContext, Icons.speed_outlined, AppLocale.tr('Камеры контроля скорости'), () { Navigator.pop(sheetContext); _openCameraAlertsPage(); }),
              _menuTile(sheetContext, Icons.location_city_outlined, AppLocale.tr('Камеры Шымкента'), () { Navigator.pop(sheetContext); _openShymkentCamerasPage(); }),
              _menuTile(sheetContext, Icons.local_gas_station_outlined, AppLocale.tr('Заправки'), () { Navigator.pop(sheetContext); _openStationNetworks(); }),
              _menuTile(sheetContext, Icons.local_parking_outlined, AppLocale.tr('Парковки'), () { Navigator.pop(sheetContext); _searchController.text = 'парковка'; _searchAddress(); }),
              _menuTile(sheetContext, Icons.history, AppLocale.tr('Бронирования и история заказов'), () { Navigator.pop(sheetContext); _openBookingsPage(); }),
              _menuTile(sheetContext, Icons.rate_review_outlined, AppLocale.tr('Лента отзывов и исправлений'), () { Navigator.pop(sheetContext); _openFeedbackPage(); }),
              _menuTile(sheetContext, Icons.workspace_premium_outlined, AppLocale.tr('BAKE Plus'), () { Navigator.pop(sheetContext); _openBakePlusPage(); }),
              _menuTile(sheetContext, Icons.music_note_outlined, AppLocale.tr('Музыка'), () { Navigator.pop(sheetContext); _openMusicPage(); }),
            ]),
          ),
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
            title: Text(AppLocale.tr(title), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                      Text(AppLocale.tr(title), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Text(AppLocale.tr(description), style: const TextStyle(fontSize: 16, height: 1.45)),
                      const SizedBox(height: 18),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F4F7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(AppLocale.tr(status), style: const TextStyle(fontSize: 14, color: Color(0xFF555B63))),
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
                    label: Text(AppLocale.tr(actionLabel)),
                  ),
                ],
              ],
            ),
          ),
        ),      ),
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

  void _captureMapLongPressPoint(LatLng point) {
    _pendingMapLongPressPoint = point;
    // Native FlutterMap long-press callbacks can arrive just after
    // the pointer-up event. Preserve a completed one-second hold in that case.
    if (_mapPointerDownAt == null &&
        !_mapPointerMoved &&
        _lastMapPointerHoldDuration >= const Duration(seconds: 1)) {
      _pendingMapLongPressPoint = null;
      unawaited(_handleMapTap(point));
    }
  }

  Future<void> _handleMapTap(LatLng point) async {
    // Address selection requires a deliberate one-second hold.
    if (_lastMapPointerHoldDuration < const Duration(seconds: 1)) return;
    await _selectMapDestination(point);
  }

  List<Map<String, dynamic>>? _alternativeHitTestCacheSource;
  int _alternativeHitTestCacheLength = -1;
  List<List<LatLng>> _alternativeHitTestCache = const [];

  List<List<LatLng>> _cachedAlternativeHitTestPoints() {
    if (!identical(_alternativeHitTestCacheSource, _routeAlternatives) ||
        _alternativeHitTestCacheLength != _routeAlternatives.length) {
      _alternativeHitTestCacheSource = _routeAlternatives;
      _alternativeHitTestCacheLength = _routeAlternatives.length;
      _alternativeHitTestCache = _routeAlternatives
          .map((route) => _simplifyRouteForDisplay(_routePointsFromDecodedRoute(route)))
          .toList(growable: false);
    }
    return _alternativeHitTestCache;
  }

  bool _alternativeTapInProgress = false;

  bool _trySelectAlternativeAt(LatLng point) {
    // MapOptions.onTap is a tap-recognizer callback; long presses are
    // handled separately by onLongPress. Do not gate this callback using
    // the Listener's last pointer-up duration, which can be stale.
    if (!_routeReady || _routeAlternatives.length < 2) return false;

    final hitTestRoutes = _cachedAlternativeHitTestPoints();

    // Use the same screen-space hit test in online and offline modes.
    // The map is rendered by FlutterMap in both cases, so this keeps the
    // touch target consistent regardless of the active tile provider.
    if (!_offlineMapReady) return false;
    final camera = _mapController.camera;
    final tapPosition = camera.latLngToScreenPoint(point);
    var bestIndex = -1;
    var bestDistance = double.infinity;
    var selectedDistance = double.infinity;

    for (var i = 0; i < hitTestRoutes.length; i++) {
      final distance = _distanceToPolylineScreenPixels(
        tapPosition,
        hitTestRoutes[i],
        camera,
      );
      if (i == _selectedRouteIndex) {
        selectedDistance = distance;
      } else if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    // A 40 logical-pixel touch radius works at every zoom level.
    // At route crossings, keep the current route when distances are close.
    if (bestIndex < 0 || bestDistance > 40 ||
        selectedDistance <= bestDistance + 3) {
      return false;
    }

    _applyAlternativeRouteTap(bestIndex);
    return true;
  }

  double _distanceToPolylineScreenPixels(
    math.Point<double> position,
    List<LatLng> points,
    MapCamera camera,
  ) {
    if (points.length < 2) return double.infinity;
    var best = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final a = camera.latLngToScreenPoint(points[i]);
      final b = camera.latLngToScreenPoint(points[i + 1]);
      final dx = b.x - a.x;
      final dy = b.y - a.y;
      final lengthSquared = dx * dx + dy * dy;
      final t = lengthSquared == 0
          ? 0.0
          : (((position.x - a.x) * dx + (position.y - a.y) * dy) /
                  lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
      final offsetX = position.x - a.x - t * dx;
      final offsetY = position.y - a.y - t * dy;
      best = math.min(best, math.sqrt(
        offsetX * offsetX + offsetY * offsetY,
      ));
    }
    return best;
  }

  // Route selection is based on the same screen projection as the map tap.
  // The invisible touch radius does not change the visible route width.
  void _applyAlternativeRouteTap(int index) {
    if (index == _selectedRouteIndex) return;
    _selectRouteAlternative(index);
    if (mounted) {
      setState(() => _message = AppLocale.tr(
        _navigationActive
            ? 'Выбран альтернативный маршрут. Продолжаем движение по нему.'
            : 'Выбран альтернативный маршрут.',
      ));
    }
    if (_navigationActive) unawaited(_speakCurrentInstruction());
  }

  double _distanceToPolylineMeters(LatLng position, List<LatLng> points) {
    if (points.length < 2) return double.infinity;
    const latScale = 110540.0;
    final lonScale = 111320.0 * math.cos(position.latitude * math.pi / 180);
    final px = position.longitude * lonScale;
    final py = position.latitude * latScale;
    var best = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i], b = points[i + 1];
      final ax = a.longitude * lonScale, ay = a.latitude * latScale;
      final dx = (b.longitude - a.longitude) * lonScale;
      final dy = (b.latitude - a.latitude) * latScale;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (((px - ax) * dx + (py - ay) * dy) / len2).clamp(0.0, 1.0).toDouble();
      final ex = px - ax - t * dx, ey = py - ay - t * dy;
      best = math.min(best, math.sqrt(ex * ex + ey * ey));
    }
    return best;
  }

  Future<void> _rememberMapAddress(String address, LatLng point) async {
    final value = address.trim();
    if (value.isEmpty || value == 'Адрес не найден.' || value == 'Адрес определяется…') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final records = prefs.getStringList('map_address_history_v1') ?? <String>[];
      records.removeWhere((raw) {
        try {
          final item = jsonDecode(raw);
          if (item is! Map) return false;
          final oldLat = double.tryParse(item['lat']?.toString() ?? '');
          final oldLon = double.tryParse(item['lon']?.toString() ?? '');
          return oldLat != null && oldLon != null &&
              (oldLat - point.latitude).abs() < 0.00002 &&
              (oldLon - point.longitude).abs() < 0.00002;
        } catch (_) {
          return false;
        }
      });
      records.insert(0, jsonEncode({
        'address': value,
        'lat': point.latitude.toStringAsFixed(6),
        'lon': point.longitude.toStringAsFixed(6),
      }));
      await prefs.setStringList('map_address_history_v1', records.take(100).toList());

      final history = prefs.getStringList('search_history') ?? <String>[];
      history.remove(value);
      history.insert(0, value);
      await prefs.setStringList('search_history', history.take(20).toList());
    } catch (error) {
      debugPrint('BAKE map address history save failed: $error');
    }
  }

  Future<void> _selectMapDestination(LatLng point) async {
    if (point.latitude < 40 || point.latitude > 56 ||
        point.longitude < 46 || point.longitude > 88) {
      if (mounted) {
        setState(() => _message = AppLocale.tr('Выберите точку на территории Казахстана.'));
      }
      return;
    }
    if (_navigationActive) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(AppLocale.tr('Изменить текущий заказ?')),
          content: Text(AppLocale.tr('Текущий маршрут останется активным, пока вы не подтвердите перестроение.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(AppLocale.tr('Продолжить текущий маршрут'))),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(AppLocale.tr('Построить новый маршрут'))),
          ],
        ),
      );
      if (accepted != true || !mounted) return;
    }
    _selectDestination(point);
    _moveMapCamera(point, 15);
    if (mounted) {
      setState(() {
        _selectedMapPointAddress = 'Адрес определяется…';
        _message = AppLocale.pick(
          'Определяем адрес и строим варианты маршрута…',
          'Мекенжай анықталып, маршрут нұсқалары құрылуда…',
          'Resolving address and building route options…',
        );
      });
    }
    try {
      final address = await _lookupPhotonReverseAddress(point);
      await _rememberMapAddress(address, point);
      if (mounted && _destination == point) {
        setState(() => _selectedMapPointAddress = address);
      }
    } catch (error) {
      debugPrint('BAKE selected point address lookup failed: $error');
      if (mounted && _destination == point) {
        setState(() => _selectedMapPointAddress = 'Адрес не найден.');
      }
    }
    if (!mounted || _destination != point) return;
    await _buildRoute();
  }

  Future<void> _openPointMenu(LatLng point) async {
    if (!mounted) return;
    await HapticFeedback.lightImpact();
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
              leading: const Icon(Icons.flag_outlined, color: Colors.red),
              title: Text(AppLocale.tr('Выбрать как пункт назначения')),
              onTap: () {
                Navigator.pop(sheetContext);
                unawaited(_selectMapDestination(point));
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

    Future<String> _lookupPhotonReverseAddress(LatLng point) async {
    // Photon is the primary geocoder. Its reverse endpoint can return an
    // empty feature list for mapped streets, so fall back to OSM Nominatim.
    try {
      final uri = Uri.https('photon.komoot.io', '/reverse', {
        'lon': point.longitude.toString(),
        'lat': point.latitude.toString(),
      });
      final response = await http.get(uri, headers: const {
        'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)',
        'Accept': 'application/geo+json, application/json',
      }).timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final rawFeatures = decoded is Map ? decoded['features'] : null;
        if (rawFeatures is List) {
          Map<String, dynamic>? bestFeature;
          var bestScore = -1;
          for (final item in rawFeatures) {
            if (item is! Map) continue;
            final feature = Map<String, dynamic>.from(item);
            final raw = feature['properties'];
            final p = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
            final hasName = (p['name']?.toString().trim().isNotEmpty ?? false);
            final hasStreet = (p['street']?.toString().trim().isNotEmpty ?? false);
            final hasHouse = (p['housenumber']?.toString().trim().isNotEmpty ?? false);
            final score = (hasStreet ? 4 : 0) + (hasHouse ? 2 : 0) + (hasName ? 2 : 0);
            if (score > bestScore) {
              bestScore = score;
              bestFeature = feature;
            }
          }
          if (bestFeature != null) {
            final address = _photonDestinationAddress(bestFeature);
            if (address.isNotEmpty) return address;
          }
        }
      } else {
        debugPrint('BAKE Photon reverse: HTTP ${response.statusCode}');
      }
    } catch (error) {
      debugPrint('BAKE Photon reverse failed: $error');
    }

    final fallback = await _lookupNominatimReverseAddress(point);
    return fallback.isEmpty ? 'Адрес не найден.' : fallback;
  }

  Future<String> _lookupNominatimReverseAddress(LatLng point) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'format': 'jsonv2',
        'addressdetails': '1',
        'zoom': '18',
        'namedetails': '1',
      });
      final response = await http.get(uri, headers: const {
        'User-Agent': 'BAKE-Navigator/1.0 (Android navigation app)',
        'Accept': 'application/json',
        'Accept-Language': 'ru,kk,en',
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        debugPrint('BAKE Nominatim reverse: HTTP ${response.statusCode}');
        return '';
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) return '';
      final rawAddress = decoded['address'];
      final address = rawAddress is Map
          ? Map<String, dynamic>.from(rawAddress)
          : <String, dynamic>{};
      String first(Iterable<String> keys) {
        for (final key in keys) {
          final value = address[key]?.toString().trim() ?? '';
          if (value.isNotEmpty) return value;
        }
        return '';
      }
      final street = first(const ['road', 'pedestrian', 'residential', 'footway', 'path']);
      final house = first(const ['house_number']);
      final city = first(const ['city', 'town', 'village', 'municipality']);
      final district = first(const ['suburb', 'city_district', 'district', 'neighbourhood']);
      final namedetails = decoded['namedetails'];
      final namedName = namedetails is Map
          ? namedetails['name']?.toString().trim() ?? ''
          : '';
      final rawName = decoded['name']?.toString().trim() ?? '';
      final name = rawName.isNotEmpty ? rawName : namedName;
      final parts = <String>[
        if (district.isNotEmpty && district != city) district,
        if (name.isNotEmpty && name != street && name != house) name,
        if (street.isNotEmpty) street,
        if (house.isNotEmpty && house != street) 'дом $house',
        if (city.isNotEmpty && city != district) city,
      ];
      final uniqueParts = <String>[];
      for (final part in parts) {
        if (part.isNotEmpty && !uniqueParts.any((item) => item.toLowerCase() == part.toLowerCase())) {
          uniqueParts.add(part);
        }
      }
      if (uniqueParts.isNotEmpty) return uniqueParts.join(', ');
      return decoded['display_name']?.toString().trim() ?? '';
    } catch (error) {
      debugPrint('BAKE Nominatim reverse failed: $error');
      return '';
    }
  }

  Future<void> _resolveSelectedMapPointAddress(LatLng point) async {
    try {
      final address = await _lookupPhotonReverseAddress(point);
      if (address == 'Адрес не найден.') return;
      await _rememberMapAddress(address, point);
      if (!mounted || _destination != point) return;
      setState(() => _message = 'Метка: $address');
    } catch (error) {
      debugPrint('BAKE Photon reverse lookup failed: $error');
    }
  }

  Future<void> _showPointDetails(LatLng point) async {
    try {
      final address = await _lookupPhotonReverseAddress(point);
      await _rememberMapAddress(address, point);
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
    if (mounted) setState(() => _message = AppLocale.pick('Ссылка на точку скопирована.', 'Нүкте сілтемесі көшірілді.', 'Point link copied.'));
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
                  items: eventTypes.map((type) => DropdownMenuItem(value: type, child: Text(AppLocale.tr(type)))).toList(),
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
    if (title == 'Дорожное событие') {      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('road_event_reports') ?? <String>[];
      saved.add(jsonEncode({'kind': selectedType, 'detail': detail, 'lat': point.latitude, 'lon': point.longitude, 'date': DateTime.now().toLocal().toString().substring(0, 16)}));
      await prefs.setStringList('road_event_reports', saved);
    }
    await Clipboard.setData(ClipboardData(text: report));
    controller.dispose();
    if (mounted) {
      setState(() => _message = title == 'Дорожное событие'
        ? AppLocale.pick('Событие сохранено на устройстве. Отправка другим водителям пока не подключена.', 'Оқиға құрылғыда сақталды. Басқа жүргізушілерге жіберу әлі қосылмаған.', 'Event saved on this device. Sharing with other drivers is not connected yet.')
        : AppLocale.pick(AppLocale.pick(AppLocale.pick('Отчёт скопирован. Отправка на сервер пока не подключена.', 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'), 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'), 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'));
    }
  }

  Future<void> _openMyPlaces() async {
    final prefs = await SharedPreferences.getInstance();
    var home = prefs.getString('my_place_home') ?? '';
    var work = prefs.getString('my_place_work') ?? '';
    var customPlaces = prefs.getStringList('my_custom_places') ?? <String>[];
    var customPlacePoints = prefs.getStringList('my_custom_place_points_v1') ?? <String>[];
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
            decoration: InputDecoration(
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
                  subtitle: Text(home.isEmpty ? AppLocale.tr('Добавьте домашний адрес') : home),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    await editAddress(
                      title: AppLocale.tr('Адрес дома'),
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
                  subtitle: Text(work.isEmpty ? AppLocale.tr('Добавьте адрес работы') : work),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    await editAddress(
                      title: AppLocale.tr('Адрес работы'),
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
                Text(
                  AppLocale.tr('Избранное'),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                if (customPlaces.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
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
                      onTap: address.isEmpty ? null : () {
                        final savedPoint = index < customPlacePoints.length ? customPlacePoints[index] : '';
                        final coords = savedPoint.split(',');
                        final lat = coords.length == 2 ? double.tryParse(coords[0]) : null;
                        final lon = coords.length == 2 ? double.tryParse(coords[1]) : null;
                        Navigator.pop(pageContext);
                        if (lat != null && lon != null) {
                          final point = LatLng(lat, lon); _selectDestination(point); _moveMapCamera(point, 16);
                          setState(() => _message = name); unawaited(_buildRoute());
                        } else { _searchController.text = address; _searchAddress(); }
                      },
                      trailing: IconButton(
                        tooltip: AppLocale.tr('Удалить место'),
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          customPlaces.removeAt(index);
                          if (index < customPlacePoints.length) customPlacePoints.removeAt(index);
                          await prefs.setStringList('my_custom_places', customPlaces);
                          await prefs.setStringList('my_custom_place_points_v1', customPlacePoints);
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
                    LatLng? selectedPlacePoint;
                    final accepted = await showDialog<bool>(
                      context: pageContext,
                      builder: (dialogContext) => StatefulBuilder(builder: (dialogContext, refreshDialog) => AlertDialog(
                        title: Text(AppLocale.tr('Добавить место')),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            VoiceTextField(
                              controller: nameController,
                              decoration: InputDecoration(
                                labelText: AppLocale.tr('Название'),
                                hintText: AppLocale.tr('Например, спортзал'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            VoiceTextField(
                              controller: addressController,
                              decoration: InputDecoration(
                                labelText: AppLocale.tr('Адрес'),
                                hintText: AppLocale.tr('Улица, дом или место'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(onPressed: () async {
                              final point = await MapPointPickerPage.pick(dialogContext,
                                initialPoint: selectedPlacePoint ?? const LatLng(42.3154, 69.5869));
                              if (point != null) refreshDialog(() => selectedPlacePoint = point);
                            }, icon: const Icon(Icons.my_location), label: Text(selectedPlacePoint == null ? 'Уточнить на карте' :
                              '${selectedPlacePoint!.latitude.toStringAsFixed(6)}, ${selectedPlacePoint!.longitude.toStringAsFixed(6)}')),
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
                      )),
                    );
                    final name = nameController.text.trim();
                    final address = addressController.text.trim();
                    nameController.dispose();
                    addressController.dispose();
                    if (accepted != true || name.isEmpty || address.isEmpty) return;
                    customPlaces = [...customPlaces, '$name|$address'];
                    customPlacePoints = [...customPlacePoints, selectedPlacePoint == null ? '' : '${selectedPlacePoint!.latitude},${selectedPlacePoint!.longitude}'];
                    await prefs.setStringList('my_custom_places', customPlaces);
                    await prefs.setStringList('my_custom_place_points_v1', customPlacePoints);
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

  Future<void> _openShymkentCamerasPage() async {
    if (!mounted) return;
    if (_bundledRoadAlerts.isEmpty) {
      await _loadBundledRoadAlerts();
    }
    if (!mounted) return;
    final cameras = _shymkentCameraAlerts();
    var addressRecords = <Map<String, String>>[];
    try {
      addressRecords = await _roadAlertService.loadShymkentCameraDirectory();
    } catch (error) {
      debugPrint('Не удалось открыть справочник камер Шымкента: $error');
    }
    if (!mounted) return;
    final addressOnlyRecords = addressRecords
        .where((record) => record['precision'] == 'address_only')
        .toList();

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, refresh) => Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              title: Text(AppLocale.tr('Камеры Шымкента')),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
            ),
            body: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.camera_alt_outlined),
                  title: Text(AppLocale.tr('Показывать камеры на карте')),
                  subtitle: Text(AppLocale.tr('В радиусе 25 км от центра Шымкента')),
                  value: _showShymkentCamerasOnMap,
                  onChanged: (value) {
                    setState(() => _showShymkentCamerasOnMap = value);
                    refresh(() {});
                  },
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      AppLocale.pick(
                        'Точек с координатами: ${cameras.length}. Приблизительные места отмечены отдельно.',
                        'Координаттары бар нүктелер: ${cameras.length}. Шамамен орындар бөлек белгіленген.',
                        'Camera points with coordinates: ${cameras.length}. Approximate locations are marked.',
                      ),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      if (cameras.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            AppLocale.tr('Координатные точки пока не загружены.'),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        ...cameras.map((camera) {
                          final coordinates =
                              '${camera.location.latitude.toStringAsFixed(5)}, ${camera.location.longitude.toStringAsFixed(5)}';
                          return ListTile(
                            leading: Icon(
                              camera.isApproximate
                                  ? Icons.location_searching
                                  : Icons.camera_alt,
                              color: camera.isApproximate
                                  ? Colors.orange.shade800
                                  : const Color(0xFF1C4E7D),
                            ),
                            title: Text(camera.name ?? AppLocale.tr('Камера')),
                            subtitle: Text(
                              camera.isApproximate
                                  ? '$coordinates · примерный ориентир, камера не подтверждена'
                                  : coordinates,
                            ),
                            onTap: () {
                              Navigator.pop(pageContext);
                              _moveMapCamera(camera.location, 16);
                            },
                          );
                        }),
                      if (addressOnlyRecords.isNotEmpty) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Text(
                            AppLocale.pick(
                              'Адреса из базы без точных GPS: ${addressOnlyRecords.length}',
                              'Нақты GPS жоқ мекенжайлар: ${addressOnlyRecords.length}',
                              'Address records without exact GPS: ${addressOnlyRecords.length}',
                            ),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        ...addressOnlyRecords.map((record) => ListTile(
                          leading: const Icon(Icons.location_on_outlined, color: Colors.orange),
                          title: Text(record['name']?.isNotEmpty == true
                              ? record['name']!
                              : AppLocale.tr('Камера')),
                          subtitle: Text(
                            record['notes']?.isNotEmpty == true
                                ? record['notes']!
                                : AppLocale.tr('Адрес известен, координаты камеры не подтверждены'),
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(
                    AppLocale.tr('На карту ставятся только записи с GPS-координатами. Адреса без точного GPS не превращаются в выдуманные точки.'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openCameraAlertsPage() async {
    if (!mounted) return;
    var alerts = <RoadAlert>[];
    var loading = true;
    String? error;
    late StateSetter pageRefresh;

    Future<void> loadAlerts() async {
      pageRefresh(() {
        loading = true;
        error = null;
      });
      try {
        final point = _currentLocation ?? _mapCameraCenter;
        final result = await _roadAlertService.fetchNearby(
          point,
          radiusMeters: 3000,
        );
        if (!mounted) return;
        pageRefresh(() {
          alerts = result;
          loading = false;
        });
      } catch (exception) {
        if (!mounted) return;
        pageRefresh(() {
          error = exception.toString().replaceFirst('Exception: ', '');
          loading = false;
        });
      }
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (pageContext, refresh) {
            pageRefresh = refresh;
            if (loading && alerts.isEmpty && error == null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (pageContext.mounted && loading) {
                  unawaited(loadAlerts());
                }
              });
            }

            return Scaffold(
              backgroundColor: Colors.white,
              appBar: AppBar(
                title: Text(AppLocale.tr('Камеры и дорожные события')),
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.white,
                actions: [
                  IconButton(
                    tooltip: AppLocale.tr('Обновить'),
                    onPressed: loading ? null : () => unawaited(loadAlerts()),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              body: loading
                  ? const Center(child: CircularProgressIndicator())
                  : error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.cloud_off_outlined, size: 42),
                                const SizedBox(height: 12),
                                Text(error!, textAlign: TextAlign.center),
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => unawaited(loadAlerts()),
                                  icon: const Icon(Icons.refresh),
                                  label: Text(AppLocale.tr('Повторить')),
                                ),
                              ],
                            ),
                          ),
                        )
                      : alerts.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  AppLocale.pick(
                                    'В радиусе 3 км не найдены камеры контроля скорости, отмеченные в OpenStreetMap.',
                                    '3 км радиуста OpenStreetMap картасында белгіленген жылдамдық камералары табылмады.',
                                    'No speed cameras mapped in OpenStreetMap were found within 3 km.',
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                              itemCount: alerts.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final alert = alerts[index];
                                final title = AppLocale.tr('Камера контроля скорости');
                                final distance = alert.distanceMeters >= 1000
                                    ? '${(alert.distanceMeters / 1000).toStringAsFixed(1)} км'
                                    : '${alert.distanceMeters.round()} м';
                                final details = <String>[
                                  distance,
                                  if (alert.maxSpeedKmh != null) '${alert.maxSpeedKmh} км/ч',
                                  if (alert.direction != null && alert.direction!.isNotEmpty) alert.direction!,
                                  if (alert.name != null && alert.name!.isNotEmpty) alert.name!,
                                ].join(' · ');
                                return ListTile(
                                  leading: Icon(
                                    Icons.speed,
                                    color: const Color(0xFF1976D2),
                                    size: 30,                                  ),
                                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(details),
                                );
                              },
                            ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  AppLocale.pick(
                    'Данные берутся из OpenStreetMap. Камеры, которые ещё не внесены участниками, могут отсутствовать на карте.',
                    'Деректер OpenStreetMap жүйесінен алынады. Қатысушылар әлі қоспаған камералар мен жол жұмыстары картада болмауы мүмкін.',
                    'Data comes from OpenStreetMap. Cameras not yet mapped by contributors may be missing.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            );
          },
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppLocale.tr('Пока нет сохранённых сообщений о дорожных событиях.'),
                      textAlign: TextAlign.center,
                    ),                  ),
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
                  title: Text(AppLocale.tr(item['label']?.toString() ?? 'Сохранённая точка')),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    final point = LatLng(lat, lon);
                    _selectDestination(point);
                    _moveMapCamera(point, 16);
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
    final originFocusNode = FocusNode();
    final destinationFocusNode = FocusNode();
    final routeSheetExpanded = ValueNotifier<bool>(false);
    originFocusNode.addListener(() {
      if (originFocusNode.hasFocus) routeSheetExpanded.value = true;
    });
    destinationFocusNode.addListener(() {
      if (destinationFocusNode.hasFocus) routeSheetExpanded.value = true;
    });
    var searchAfterClose = false;
    var searchOriginAfterClose = false;
    var buildRouteAfterClose = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (sheetContext) => ValueListenableBuilder<bool>(
        valueListenable: routeSheetExpanded,
        builder: (sheetContext, expanded, _) => AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: FractionallySizedBox(
            heightFactor: expanded ? 0.94 : 0.44,
            alignment: Alignment.bottomCenter,
            child: StatefulBuilder(
        builder: (sheetContext, refreshSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Container(width: 42, height: 5, decoration: BoxDecoration(color: const Color(0xFFD6D9DE), borderRadius: BorderRadius.circular(8)))),
                  const SizedBox(height: 14),
                  Text(AppLocale.tr('Планирование маршрута'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(AppLocale.tr('Тип маршрута'), style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 7),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.directions_car_outlined),
                        label: Text('Автомобиль'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.directions_walk),
                        label: Text('Пешком'),
                      ),
                    ],
                    selected: <bool>{_walkingMode},
                    onSelectionChanged: (selection) {
                      setState(() => _walkingMode = selection.first);
                      refreshSheet(() {});
                    },
                  ),
                  if (_walkingMode)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Пешеходный маршрут: тротуары и пешеходные дорожки. Для построения нужен интернет или доступный офлайн-граф.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF687786)),
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.my_location, color: Color(0xFF269B68), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: originController,
                          focusNode: originFocusNode,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) { searchOriginAfterClose = originController.text.trim().isNotEmpty; Navigator.pop(sheetContext); },
                          decoration: InputDecoration(
                            hintText: AppLocale.tr('Откуда'),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: AppLocale.tr('Моё местоположение'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () { Navigator.pop(sheetContext); unawaited(_locateMe()); },
                        icon: const Icon(Icons.gps_fixed, size: 20),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  Row(children: [
                    const Icon(Icons.location_on, color: Color(0xFFE45D52), size: 20),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(
                      controller: destinationController,
                      focusNode: destinationFocusNode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) { searchAfterClose = true; Navigator.pop(sheetContext); },
                      decoration: InputDecoration(
                        hintText: AppLocale.tr('Куда'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    )),
                    IconButton(
                      tooltip: AppLocale.tr('Найти место'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () { searchAfterClose = destinationController.text.trim().isNotEmpty; Navigator.pop(sheetContext); },
                      icon: const Icon(Icons.search, color: Color(0xFF343434), size: 21),
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
                        onPressed: () { setState(() { _routeStops.removeAt(entry.key); _routeProgressSegmentIndex = 0; _routePoints = []; _routeReady = false; _instructions = []; }); refreshSheet(() {}); },
                      ),
                    )),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _routeStops.length >= 5 ? null : () { Navigator.pop(sheetContext); setState(() => _message = AppLocale.tr('Удерживайте нужную точку карты и выберите «Добавить как промежуточную остановку».')); },
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: Text(AppLocale.tr('Добавить остановку на карте')),
                  ),
                  const Divider(height: 20),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.schedule, color: Color(0xFF343434)),
                    title: Text(AppLocale.tr('Время выезда'), style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_plannedDeparture == null ? AppLocale.tr('Сейчас') : _formatDeparture(_plannedDeparture!)),
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
      )))),
    );
    final destinationQuery = destinationController.text.trim();
    final originQuery = originController.text.trim();
    destinationController.dispose();
    originController.dispose();
    destinationFocusNode.dispose();
    originFocusNode.dispose();
    routeSheetExpanded.dispose();
    if (searchOriginAfterClose && originQuery.isNotEmpty && mounted) {
      _searchController.text = originQuery;
      await _searchAddress(selectAsOrigin: true);
    } else if (searchAfterClose && destinationQuery.isNotEmpty && mounted) {
      _searchController.text = destinationQuery;
      await _searchAddress();
    }
    if (buildRouteAfterClose && mounted) {
      if (destinationQuery.isNotEmpty) {
        // _searchAddress() builds the route after the destination is selected.
        // Do not call _buildRoute() again here: that caused a duplicate route
        // calculation and could reopen route-choice UI after the map was ready.
        _searchController.text = destinationQuery;
        await _searchAddress();
      } else if (_destination != null) {
        await _buildRoute();
      }
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
            _menuTile(sheetContext, Icons.edit_road_outlined, AppLocale.tr('Планирование маршрута'), () { Navigator.pop(sheetContext); _openRoutePlanner(); }),
            _menuTile(sheetContext, Icons.edit_location_alt_outlined, AppLocale.tr('Изменить маршрут'), () { Navigator.pop(sheetContext); _openRoutePlanner(); }),
            _menuTile(sheetContext, Icons.add_location_alt_outlined, AppLocale.tr('Добавить точку'), () { Navigator.pop(sheetContext); _openRoutePlanner(); }),
            _menuTile(sheetContext, Icons.alt_route, AppLocale.tr('Построить маршрут'), () { Navigator.pop(sheetContext); if (_destination == null) { _openRoutePlanner(); } else { unawaited(_buildRoute()); } }),
            _menuTile(sheetContext, Icons.tune, AppLocale.tr('Параметры маршрута'), () { Navigator.pop(sheetContext); _openRoutePreferences(); }),
            _menuTile(sheetContext, Icons.share_outlined, AppLocale.tr('Поделиться маршрутом'), () { Navigator.pop(sheetContext); _shareRoute(); }),
            _menuTile(sheetContext, Icons.flag_outlined, AppLocale.tr('Сообщить об ошибке'), () { Navigator.pop(sheetContext); _reportRouteIssue(); }),
            const Divider(height: 18),
            _menuTile(sheetContext, Icons.place_outlined, AppLocale.tr('Мои места'), () { Navigator.pop(sheetContext); _openMyPlaces(); }),
            _menuTile(sheetContext, Icons.layers_outlined, AppLocale.tr('Слои и офлайн-карты'), () { Navigator.pop(sheetContext); _openMapLayers(); }),
            _menuTile(sheetContext, Icons.warning_amber_outlined, AppLocale.tr('События на дороге'), () { Navigator.pop(sheetContext); _openRoadEvents(); }),
            _menuTile(sheetContext, Icons.settings_outlined, AppLocale.tr('Настройки'), () { Navigator.pop(sheetContext); _openSettings(); }),
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
      return AppLocale.tr('Маршрут ещё не построен');
    }
    final km = (_routeDistanceMeters! / 1000).toStringAsFixed(1);
    final minutes = (_routeDurationSeconds! / 60).round();
    return '${_walkingMode ? 'Пешком · ' : ''}$km км · около $minutes мин';
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
                    await prefs.setStringList('selected_station_networks', initial.toList());                    if (!pageContext.mounted) return;
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
                Text(
                  AppLocale.tr('Выбери сети, которые нужно учитывать при поиске заправок.'),
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
                  child: Text(AppLocale.tr(initial.length == networks.length ? 'Снять все отметки' : 'Выбрать все сети')),
                ),
                const SizedBox(height: 8),
                Text(
                  AppLocale.tr('Примечание: поиск использует названия сетей в OpenStreetMap. Если бренд не указан в данных карты, заправка может не попасть в отфильтрованный список.'),
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
                  style: TextStyle(fontSize: 9, fontWeight: selected ? FontWeight.w800 : FontWeight.w500, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleRoutePoints = _remainingRoutePoints();
    // Both renderers draw and hit-test the same cached simplified alternatives.
    final simplifiedAlternativeRoutePoints = _cachedAlternativeHitTestPoints();
    final visibleRoadAlerts = _roadAlertsVisibleOnMap();
    final markers = <Marker>[
      ..._buildOfflineRouteArrowMarkers(visibleRoutePoints),
      if (_navigationActive && _instructionIndex < _instructions.length)
        Marker(
          point: _instructions[_instructionIndex].location,
          width: 54,
          height: 54,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF169B55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2))],
            ),
            child: Icon(
              _maneuverIcon(_instructions[_instructionIndex]),
              color: Colors.white,
              size: 29,
            ),
          ),
        ),
      if (_currentLocation != null &&
          _navigationActive &&
          _routePoints.length > 1 &&
          _distanceToNextManeuverMeters != null &&
          _distanceToNextManeuverMeters! <= 150)
        Marker(
          point: _offsetAlongRoute(
            _currentLocation!, _routeBearingAt(_currentLocation!), 35,
          ),
          width: 96,
          height: 38,
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: const Offset(12, -26),
            child: _buildManeuverDistanceCue(),
          ),
        ),
      if (_vehicleDisplayLocation != null)
        Marker(
          point: _vehicleDisplayLocation!,
          width: 20,
          height: 20,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE53935),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
          ),
        ),
      ...visibleRoadAlerts.map((alert) => Marker(
        point: alert.location,
        width: 28,
        height: 30,
        child: _buildRoadAlertMapMarker(alert),
      )),
      if (_isOfflineMapActive || _roadEventsLayerEnabled)
        ..._confirmedRoadReports.where(_isRoadWarningReport).map((report) => Marker(
        point: LatLng((report['latitude'] as num).toDouble(), (report['longitude'] as num).toDouble()),
        width: 28,
        height: 28,
        child: _buildConfirmedRoadReportMarker(report),
      )),
      if (_mapCameraZoom >= 14)
        ..._confirmedRoadReports.where(_isStreetNameReport).map((report) => Marker(
          point: LatLng(
            (report['latitude'] as num).toDouble(),
            (report['longitude'] as num).toDouble(),
          ),
          width: 168,
          height: 30,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.94),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: const Color(0xFF777777), width: 0.7),
            ),
            alignment: Alignment.center,
            child: Text(
              _roadReportStreetLabel(report),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF111111),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        )),
      if (_trafficLayerEnabled)
        ..._trafficReports.map((report) => Marker(
          point: LatLng(
            (report['latitude'] as num).toDouble(),
            (report['longitude'] as num).toDouble(),
          ),
          width: 38,
          height: 38,
          child: Container(
            decoration: BoxDecoration(
              color: _trafficReportColor(report).withOpacity(0.28),
              shape: BoxShape.circle,
              border: Border.all(color: _trafficReportColor(report), width: 3),
            ),
          ),
        )),
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
          width: 54,
          height: 58,
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF263238), width: 2),
              boxShadow: const [
                BoxShadow(color: Color(0x44000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.flag, color: Color(0xFFE53935), size: 32),
          ),
        ),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF3F6FA),
      body: Stack(
        children: [
          Listener(
              onPointerDown: (event) {
                _mapPointerDownAt = DateTime.now();
                _mapPointerDownPosition = event.localPosition;
                _mapPointerMoved = false;
                _lastMapPointerHoldDuration = Duration.zero;
                _headingUpGestureActive = true;
                _headingUpResumeTimer?.cancel();
              },
              onPointerMove: (event) {
                final start = _mapPointerDownPosition;
                if (start != null && (event.localPosition - start).distance > 12) {
                  _mapPointerMoved = true;
                  _mapFollowEnabled = false;
                }
              },
              onPointerUp: (_) {
                final startedAt = _mapPointerDownAt;
                _lastMapPointerHoldDuration = startedAt == null
                    ? Duration.zero
                    : DateTime.now().difference(startedAt);
                _mapPointerDownAt = null;
                _mapPointerDownPosition = null;
                final heldPoint = _pendingMapLongPressPoint;
                _pendingMapLongPressPoint = null;
                if (heldPoint != null && !_mapPointerMoved &&
                    _lastMapPointerHoldDuration >= const Duration(seconds: 1)) {
                  unawaited(_handleMapTap(heldPoint));
                }
                _scheduleHeadingUpReturn();
              },
              onPointerCancel: (_) {
                _mapPointerDownAt = null;
                _lastMapPointerHoldDuration = Duration.zero;
                _pendingMapLongPressPoint = null;
                _scheduleHeadingUpReturn();
              },
              child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                onMapReady: _onOfflineMapReady,
                initialCenter: _shymkent,
                initialZoom: 13,
                onTap: (_, point) {
                  // A short tap may switch an alternative route, never set an address.
                  _trySelectAlternativeAt(point);
                },
                onLongPress: (_, point) => _captureMapLongPressPoint(point),
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture) {
                    _mapFollowEnabled = false;
                    _scheduleHeadingUpReturn();
                  }
                },
              ),
              children: [
                if (!_isOfflineMapActive && _flutterMapOnlineStyle != null)
                  VectorTileLayer(
                    theme: _flutterMapOnlineStyle!.theme,
                    sprites: _flutterMapOnlineStyle!.sprites,
                    tileProviders: _flutterMapOnlineStyle!.providers,
                    maximumZoom: 18,
                  )
                else if (_isOfflineMapActive && _offlineVectorTileProvider != null)
                  VectorTileLayer(
                    theme: _offlineVectorTheme,
                    tileProviders: TileProviders({
                      'openmaptiles': _offlineVectorTileProvider!,
                    }),
                    maximumZoom: 18,
                  )
                else if (_isOfflineMapActive)
                  TileLayer(tileProvider: _offlineTileProvider!)
                else
                  const SizedBox.expand(),
                if (!_isOfflineMapActive &&
                    _trafficLayerEnabled &&
                    _tomtomTrafficApiKey.isNotEmpty)
                  TileLayer(
                    urlTemplate: 'https://api.tomtom.com/traffic/map/4/tile/flow/relative0/{z}/{x}/{y}.png?key={key}',
                    additionalOptions: {'key': _tomtomTrafficApiKey},
                    userAgentPackageName: 'kz.bake.bake_navigator',
                    minZoom: 5,
                    maxZoom: 22,
                    maxNativeZoom: 22,
                    keepBuffer: 2,
                    panBuffer: 0,
                  ),
                if (_routeAlternatives.length > 1)
                  PolylineLayer(
                    polylines: [
                      for (var i = 0; i < _routeAlternatives.length; i++)
                        if (i != _selectedRouteIndex)
                          Polyline(
                            points: simplifiedAlternativeRoutePoints[i],
                            strokeWidth: 8,
                            color: const [Color(0xFFFF9800), Color(0xFF9C27B0), Color(0xFF00A6A6)][i % 3].withOpacity(0.9),
                          ),
                    ],
                  ),
                if (visibleRoutePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: visibleRoutePoints, strokeWidth: 10, color: const Color(0xFF0878F9)),
                    ],
                  ),
                MarkerLayer(markers: markers),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                    if (!_isOfflineMapActive &&
                        _trafficLayerEnabled &&
                        _tomtomTrafficApiKey.isNotEmpty)
                      TextSourceAttribution('Traffic data © TomTom'),
                  ],
                ),
              ],
            ),
            ),
          Positioned(
            // Place the route action beside, not underneath, the zoom/compass
            // column. Keep it aligned with that column as its bottom changes.
            // Keep the route control lifted beside the map controls so the
            // compact destination dashboard cannot cover its touch target.
            bottom: _navigationActive ? 190 : (_routeReady ? 250 : 144),
            right: 78,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: _isBuildingRoute ? const Color(0xFFFFF1C2) : Colors.white,
                elevation: 5,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Построить и показать маршруты',
                  onPressed: _isBuildingRoute
                      ? null
                      : () {
                          if (_destination == null) {
                            _openRoutePlanner();
                          } else {
                            unawaited(_buildRoute());
                          }
                        },
                  icon: Icon(
                    Icons.alt_route,
                    color: _isBuildingRoute
                        ? const Color(0xFFB88A00)
                        : const Color(0xFF1769AA),
                    size: 25,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 238,
            right: 14,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: _trafficLayerEnabled ? const Color(0xFFE8F5E9) : Colors.white,
                elevation: 5,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Пробки TomTom и дорожные события',
                  onPressed: () {
                    setState(() => _trafficLayerEnabled = !_trafficLayerEnabled);
                    unawaited(SharedPreferences.getInstance().then(
                      (prefs) => prefs.setBool('layer_traffic', _trafficLayerEnabled),
                    ));
                    if (_trafficLayerEnabled && _trafficReports.isEmpty) {
                      final hasTomTomKey = _tomtomTrafficApiKey.isNotEmpty;
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(hasTomTomKey
                            ? 'Поток TomTom включён. Подтверждённых отметок о дорожных событиях пока нет.'
                            : 'Для отображения реальных пробок добавьте ключ TomTom в настройках слоёв.'),
                        duration: const Duration(seconds: 3),
                        behavior: SnackBarBehavior.floating,
                      ));
                    }
                  },
                  icon: Icon(
                    Icons.traffic,
                    color: _trafficLayerEnabled
                        ? const Color(0xFF169B55)
                        : const Color(0xFF555B63),                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 142,
            right: 14,
            child: SafeArea(
              bottom: false,
              child: Material(
                color: Colors.white,
                elevation: 5,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: _isOfflineMapActive ? 'Офлайн-карта' : 'Онлайн-карта',
                  onPressed: _toggleOfflineMapFromMap,
                  icon: Icon(
                    _isOfflineMapActive ? Icons.cloud_off_outlined : Icons.cloud_done_outlined,
                    size: 21,
                    color: _isOfflineMapActive ? const Color(0xFF8A929B) : const Color(0xFF169B55),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 14,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Material(
                  color: Colors.white,
                  elevation: 5,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: _isSpeeding ? const Color(0xFFFFE2E2) : Colors.white,
                            border: Border.all(
                              color: _isSpeeding ? const Color(0xFFE53935) : const Color(0xFF202020),
                              width: 2.2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _currentSpeedKmh.round().toString(),
                            style: TextStyle(
                              fontSize: 25, height: 1, fontWeight: FontWeight.w900,
                              color: _isSpeeding ? const Color(0xFFE53935) : const Color(0xFF202020),
                            ),
                          ),
                        ),
                        Text('км/ч', style: TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700,
                          color: _isSpeeding ? const Color(0xFFE53935) : const Color(0xFF343434),
                        )),
                        const SizedBox(height: 4),
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _isSpeeding ? const Color(0xFFE53935) : const Color(0xFF202020),
                              width: 3,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            _effectiveSpeedLimitKmh.toString(),
                            style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w900,
                              color: _isSpeeding ? const Color(0xFFE53935) : const Color(0xFF202020),
                            ),
                          ),
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
              top: 0,
              left: 12,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    color: Colors.white,
                    elevation: 5,
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Дорожные отметки',
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RoadToolsMenu()),
                        );
                        await _loadConfirmedRoadReports();
                      },
                      icon: const Icon(Icons.menu, color: Color(0xFF343434)),
                    ),
                  ),
                ),
              ),
            ),
          if (!_navigationActive)
            Positioned(
              left: 12,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _roundMapButton(
                        icon: Icons.person_outline,
                        tooltip: AppLocale.tr('Профиль'),
                        onPressed: _openProfileMenu,
                      ),
                      const SizedBox(height: 8),
                      _roundMapButton(
                        icon: Icons.menu,
                        tooltip: 'Дорожные отметки',
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const RoadToolsMenu()),
                          );
                          await _loadConfirmedRoadReports();
                        },
                      ),
                      const SizedBox(height: 8),
                      _roundMapButton(
                        icon: Icons.my_location,
                        tooltip: AppLocale.tr('Моё местоположение'),
                        iconColor: const Color(0xFF343434),
                        onPressed: _isLocating ? null : () => unawaited(_locateMe()),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.white,
                        elevation: 5,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Парковки',
                          onPressed: () {
                            _searchController.text = 'парковка';
                            _searchAddress();
                          },
                          icon: const Text('P', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Color(0xFF1769AA))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (_navigationActive && _activeConfirmedCameraId != null)
            Positioned(
              top: 82,
              left: 68,
              right: 88,
              child: SafeArea(
                bottom: false,
                child: Material(
                  color: const Color(0xFFFFF4E5),
                  elevation: 5,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.camera_alt, color: Color(0xFFB42318), size: 22),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text('ВПЕРЕДИ КАМЕРА',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                        ),
                        Text(
                          '${(_activeConfirmedCameraDistance ?? 0).round()} м',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFFB42318)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_navigationActive)
            Positioned(
              top: 0,
              left: 68,
              right: 88,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Material(
                    color: const Color(0xF5FFFFFF),
                    elevation: 4,
                    borderRadius: BorderRadius.circular(13),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                      child: Row(
                        children: [
                          Icon(
                            _maneuverIcon(_instructionIndex < _instructions.length ? _instructions[_instructionIndex] : null),
                            size: 27,
                            color: const Color(0xFF169B55),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _instructionIndex < _instructions.length
                                      ? _instructions[_instructionIndex].text
                                      : _localized('Продолжайте по маршруту', 'Бағыт бойынша жүре беріңіз', 'Continue on the route'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12, height: 1.1, fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  _distanceToNextManeuverMeters == null ? '—' : (_distanceToNextManeuverMeters! >= 1000 ? '${(_distanceToNextManeuverMeters! / 1000).toStringAsFixed(1)} км' : '${_distanceToNextManeuverMeters!.round()} м'),
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF626A73)),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: List.generate(3, (index) {
                                    final lanes = _laneGuidanceForCurrentManeuver();
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 5),
                                      child: Icon(
                                        _maneuverIcon(_instructionIndex < _instructions.length
                                            ? _instructions[_instructionIndex]
                                            : null),
                                        size: 18,
                                        color: lanes[index]
                                            ? const Color(0xFF169B55)
                                            : const Color(0xFFB8BEC5),
                                      ),
                                    );
                                  }),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                            padding: EdgeInsets.zero,
                            tooltip: AppLocale.tr('Завершить навигацию'),
                            onPressed: _finishNavigation,
                            icon: const Icon(Icons.close, size: 18),
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
              left: 12,
              right: 12,
              bottom: 8,
              child: SafeArea(
                top: false,
                child: Material(
                  color: Colors.white,
                  elevation: 7,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_destination != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'B · ${_selectedMapPointAddress.trim().isNotEmpty ? _selectedMapPointAddress : (_searchController.text.trim().isNotEmpty ? _searchController.text.trim() : 'Адрес определяется…')}',
                                    maxLines: 3,
                                    softWrap: true,
                                    overflow: TextOverflow.fade,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF202020),
                                    ),
                                  ),
                                ),
                              Text(
                                _routeDistanceMeters == null ? '— км' : '${(_routeDistanceMeters! / 1000).toStringAsFixed(1)} км',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                              ),
                              Text(
                                _routeDurationSeconds == null ? 'Время прибытия —' : 'Прибытие · ${TimeOfDay.fromDateTime(DateTime.now().add(Duration(seconds: _routeDurationSeconds!.round()))).format(context)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF626A73)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 112,
                          height: 42,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFCC00),
                              foregroundColor: const Color(0xFF171717),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                            ),
                            onPressed: _finishNavigation,
                            child: Text(
                              AppLocale.tr('Завершить'),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.fade,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: _navigationActive ? 150 : (_routeReady ? 250 : 144),
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
                  icon: Icons.add,
                  tooltip: 'Приблизить карту',
                  onPressed: () => _zoomMapBy(1),
                ),
                const SizedBox(height: 8),
                _roundMapButton(
                  icon: Icons.remove,
                  tooltip: 'Отдалить карту',
                  onPressed: () => _zoomMapBy(-1),
                ),
                const SizedBox(height: 8),
                _roundMapButton(
                  icon: Icons.explore_outlined,
                  tooltip: AppLocale.tr('На север'),
                  onPressed: () {
                    setState(() => _northUpLocked = !_northUpLocked);
                    if (_northUpLocked) {
                      _lastCameraHeadingDegrees = 0;
                      _rotateMapCamera(0);
                    } else {
                      final heading = _gpsHeadingDegrees ?? 0.0;
                      _lastCameraHeadingDegrees = heading;
                      final point = _currentLocation;
                      if (point != null) {
                        _updateNavigationCamera(
                          point,
                          math.max(_mapCameraZoom, 17.0).toDouble(),
                          heading,
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),


          if (_navigationActive)
            Positioned(
              top: 0,
              left: 12,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Material(
                        color: Colors.white,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(13),
                          onTap: _isLocating ? null : () => unawaited(_locateMe()),
                          child: SizedBox(
                            width: 54,
                            height: 54,
                            child: Icon(
                              Icons.gps_fixed,
                              size: 27,
                              color: _gpsAvailable ? const Color(0xFF1976D2) : const Color(0xFF9AA0A6),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Material(
                        color: Colors.white,
                        elevation: 4,
                        borderRadius: BorderRadius.circular(13),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(13),
                          onTap: () async {
                            final enabled = _voiceMode == 0;
                            setState(() => _voiceMode = enabled ? 3 : 0);
                            final prefs = await SharedPreferences.getInstance();
                            await prefs.setInt('voice_mode', _voiceMode);
                            if (!enabled) {
                              await _tts.stop();
                              await _kazakhVoiceService.stopAndUnload();
                            } else if (_navigationActive) {
                              unawaited(_speakCurrentInstruction());
                            }
                          },
                          child: SizedBox(
                            width: 54,
                            height: 54,
                            child: Icon(
                              Icons.volume_up,
                              size: 27,
                              color: _voiceMode > 0 ? const Color(0xFF169B55) : const Color(0xFF9AA0A6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_routeReady && !_navigationActive && !_routeActionDismissed)
            Positioned(
              left: 12,              right: 12,
              bottom: 76,
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xEEFFFFFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _routeSummary(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF555B63)),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFFFCC00),
                              foregroundColor: const Color(0xFF171717),
                              elevation: 5,
                              padding: const EdgeInsets.symmetric(horizontal: 28),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            ),
                            onPressed: _startNavigation,
                            child: Text(
                              AppLocale.tr('Поехали'),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFB42318),
                              side: const BorderSide(color: Color(0xFFB42318)),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            ),
                            onPressed: _resetRoutePreview,
                            icon: const Icon(Icons.close, size: 16),
                            label: Text(
                              AppLocale.tr('Сбросить'),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (!_navigationActive)
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                top: false,
                child: Material(
                  color: Colors.white,
                  elevation: 7,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Row(
                      children: [
                        _mapBottomItem(Icons.search, AppLocale.tr('Поиск'), _openSearchPanel),
                        _mapBottomItem(Icons.alt_route, AppLocale.tr('Маршрут'), _openRouteMenu),
                        _mapBottomItem(Icons.local_gas_station_outlined, AppLocale.tr('АЗС'), _openStationNetworks),
                        _mapBottomItem(Icons.bookmark_border, AppLocale.tr('Избранное'), _openBookmarks),
                        _mapBottomItem(Icons.settings_outlined, AppLocale.tr('Настройки'), _openSettings),
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

class NavigatorPreferencesScreen extends StatefulWidget {
  const NavigatorPreferencesScreen({
    super.key,
    required this.onOpenSoundSettings,
    required this.onOpenRoutePreferences,
    required this.onOpenProfile,
    required this.onOpenGpsDiagnostics,
    required this.onVoiceChanged,
  });

  final Future<void> Function() onOpenSoundSettings;
  final Future<void> Function() onOpenRoutePreferences;
  final Future<void> Function() onOpenProfile;
  final Future<void> Function() onOpenGpsDiagnostics;
  final ValueChanged<bool> onVoiceChanged;

  @override
  State<NavigatorPreferencesScreen> createState() => _NavigatorPreferencesScreenState();
}

class _NavigatorPreferencesScreenState extends State<NavigatorPreferencesScreen> {
  bool _voiceEnabled = true;
  bool _avoidTolls = false;
  bool _loading = true;
  String _appLanguage = 'kk';

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
      _appLanguage = prefs.getString('app_language') ?? 'kk';
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
      applicationLegalese: AppLocale.tr('Навигационное приложение BAKE.'),
      children: [
        Text(AppLocale.tr('Часть функций зависит от подключённых источников картографических и дорожных данных.')),
        const Text('Данные камер: © OpenStreetMap contributors, ODbL 1.0. Набор SpeedCams.world, снимок от 21.09.2026. Сведения могут быть неполными или устаревшими.'),
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
                  leading: const Icon(Icons.record_voice_over_outlined),
                  title: Text(AppLocale.pick('Язык и голос озвучки', 'Дауыс тілі мен дауысы', 'Voice language and voice')),
                  subtitle: Text(AppLocale.pick('Казахский, русский или английский', 'Қазақша, орысша немесе ағылшынша', 'Kazakh, Russian or English')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenSoundSettings,
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
                  leading: const Icon(Icons.gps_fixed),
                  title: const Text('Диагностика GPS'),
                  subtitle: const Text('Запись интервалов, точности и скачков координат'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: widget.onOpenGpsDiagnostics,
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
  const NavigatorSettingsScreen({super.key, required this.onRetryValhalla});

  final Future<bool> Function() onRetryValhalla;

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
  String? _valhallaExtractPath;
  bool _importingValhallaExtract = false;
  String _valhallaStatus = 'Офлайн-граф ещё не подключён';
  static const MethodChannel _valhallaChannel =
      MethodChannel('bake.navigator/valhalla');
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
    _valhallaExtractPath = prefs.getString('valhalla_tile_extract_path');
    if (_valhallaExtractPath != null) {
      try {
        final savedArchive = File(_valhallaExtractPath!);
        final exists = await savedArchive.exists().timeout(
          const Duration(seconds: 2), onTimeout: () => false,
        );
        final size = exists
            ? await savedArchive.length().timeout(
                const Duration(seconds: 2), onTimeout: () => 0,
              )
            : 0;
        if (!exists || size < 100000) {
          _valhallaExtractPath = null;
          await prefs.remove('valhalla_tile_extract_path');
        }
      } catch (_) {
        _valhallaExtractPath = null;
        await prefs.remove('valhalla_tile_extract_path');
      }
    }
    _valhallaStatus = _valhallaExtractPath == null
        ? 'Офлайн-граф ещё не скачан. Интернет-маршрут доступен.'
        : 'Граф найден на телефоне; подключение проверяется автоматически.';
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
        type: FileType.any,
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      if (!result.files.single.name.toLowerCase().endsWith('.mbtiles')) {
        throw Exception('Выберите файл с расширением .mbtiles.');
      }
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
      final validationDatabase = MbTiles(mbtilesPath: destination.path);
      final validationFormat = validationDatabase.getMetadata().format?.toLowerCase();
      validationDatabase.dispose();
      if (validationFormat != 'pbf' && validationFormat != 'mvt') {
        final validationProvider = MbTilesTileProvider.fromPath(path: destination.path);
        validationProvider.dispose();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_map_path', destination.path);
      if (!mounted) return;
      setState(() => _offlineMapPath = destination.path);
      Navigator.of(context).pop(destination.path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_valhallaErrorForUser(error, duringImport: true))),
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

  Future<void> _importValhallaExtract() async {
    if (_importingValhallaExtract) return;
    setState(() => _importingValhallaExtract = true);
    try {
      final ready = await widget.onRetryValhalla().timeout(
        const Duration(seconds: 2),
        onTimeout: () => false,
      );
      final prefs = await SharedPreferences.getInstance();
      final savedPath = prefs.getString('valhalla_tile_extract_path');
      if (!mounted) return;
      setState(() {
        _valhallaExtractPath = savedPath;
        _valhallaStatus = ready
            ? 'Офлайн-маршрутизация Шымкента готова'
            : 'Загрузка или подключение продолжается в фоне; пока используется интернет-маршрут';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ready
              ? 'Офлайн-маршрутизатор Шымкента готов.'
              : 'Подключение графа продолжается в фоне. Интернет-маршрут остаётся доступен.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _importingValhallaExtract = false);
    }
  }

  Future<void> _removeValhallaExtract() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('valhalla_tile_extract_path');
    try {
      await _valhallaChannel.invokeMethod<void>('dispose');
    } catch (_) {
      // The app can continue using OSRM if the native engine is already closed.
    }
    if (mounted) setState(() => _valhallaExtractPath = null);
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
  Widget build(BuildContext context) {    return Scaffold(
      appBar: AppBar(title: Text(AppLocale.tr('Настройки BAKE Navigator'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              top: false,
              child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('Экспериментальная карта OpenFreeMap'),
                    subtitle: const Text('Отдельная карта Liberty на движке FlutterMap'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const OpenFreeMapExperimentScreen(),
                        ),
                      );
                    },
                  ),
                ),
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
                          setState(() => _voiceVolume = value);                          unawaited(_saveNavigationPreferences());
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
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
                          subtitle: Text(AppLocale.tr(_offlineMapPath == null
                              ? 'Готовый MBTiles-файл пока не подключён.'
                              : 'Офлайн-карта подключена на этом устройстве.')),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _importingOfflineMap ? null : _importOfflineMap,
                            icon: _importingOfflineMap
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.file_open_outlined),
                            label: Text(AppLocale.tr(_importingOfflineMap ? 'Импортируем…' : 'Импортировать MBTiles-карту')),
                          ),
                        ),
                        if (_offlineMapPath != null)
                          TextButton.icon(
                            onPressed: _removeOfflineMap,
                            icon: const Icon(Icons.cloud_outlined),
                            label: Text(AppLocale.tr('Отключить офлайн-карту')),
                          ),
                        Text(
                          AppLocale.tr('Исходный OSM PBF не является готовой MBTiles-картой. Для офлайн-режима нужны отдельно подготовленные тайлы.'),
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Офлайн-маршрутизация', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.alt_route),
                          title: const Text('Дорожный граф Valhalla'),
                          subtitle: Text(_valhallaStatus),
                        ),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _importingValhallaExtract ? null : _importValhallaExtract,
                            icon: _importingValhallaExtract
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.route_outlined),
                            label: Text(_importingValhallaExtract
                                ? 'Подключаем граф…'
                                : _valhallaExtractPath == null
                                    ? 'Скачать дорожный граф Шымкента'
                                    : 'Подключить офлайн-граф'),
                          ),
                        ),
                        if (_valhallaExtractPath != null)
                          TextButton.icon(
                            onPressed: _removeValhallaExtract,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Отключить офлайн-маршрутизатор'),
                          ),
                        const Text(
                          'Дорожный граф Шымкента загружается и подключается автоматически один раз, затем хранится на телефоне. Для других районов и при ошибке офлайн-графа используется интернет-маршрут, если сеть доступна.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
    );
  }

}

// CI validation trigger for automatic rerouting fix.,
