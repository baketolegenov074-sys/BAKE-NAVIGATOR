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
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:shared_preferences/shared_preferences.dart';
import 'kazakh_voice_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
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
      'Навигация завершена.': 'Навигация аяқталды.',
      'Расстояние неизвестно': 'Қашықтық белгісіз',
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
  });
  final LatLng location;
  final String text;
  final double distanceMeters;
  final String maneuverType;
  final String maneuverModifier;
}

class NavigatorScreen extends StatefulWidget {
  const NavigatorScreen({super.key});

  @override
  State<NavigatorScreen> createState() => _NavigatorScreenState();
}

class _NavigatorScreenState extends State<NavigatorScreen> {
  static const LatLng _shymkent = LatLng(42.3154, 69.5869);

  final MapController _mapController = MapController();
  ml.MapLibreMapController? _mapLibreController;
  bool _mapLibreStyleReady = false;
  bool _mapLibreAnnotationSyncInProgress = false;
  bool _mapLibreAnnotationSyncPending = false;
  bool _mapLibreRouteSyncPending = false;
  final FlutterTts _tts = FlutterTts();
  final KazakhVoiceService _kazakhVoiceService = KazakhVoiceService();
  int _kazakhVoiceId = 0;
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
  bool _routeReady = false;
  bool _routeActionDismissed = false;
  double _currentSpeedKmh = 0;
  double? _routeDistanceMeters;
  double? _routeDurationSeconds;
  StreamSubscription<Position>? _positionSubscription;
  bool _isLocating = false;
  bool _isSearching = false;
  bool _isBuildingRoute = false;
  int _voiceMode = 3;
  double? _gpsHeadingDegrees;
  double? _lastCameraHeadingDegrees;
  int _announcedManeuverStage = 0;
  int _offRouteSamples = 0;
  DateTime? _lastAutomaticReroute;
  DateTime? _plannedDeparture;
  String _message = AppLocale.pick('Нажмите «Моё местоположение» или удерживайте точку на карте', '«Менің орналасқан жерім» түймесін басыңыз немесе картадағы нүктені басып тұрыңыз', 'Tap “My location” or long-press a point on the map');

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
      _navigationLanguage = prefs.getString('navigation_language') ?? 'kk-KZ';
      _selectedVoiceName = prefs.getString('voice_name');
      _selectedVoiceLocale = prefs.getString('voice_locale');
      _kazakhVoiceId = (prefs.getInt('kazakh_voice_sid') ?? 0).clamp(0, 5).toInt();
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
    try {
      // Kazakh navigation speech is provided by BAKE's bundled ISSAI engine.
      // It must never depend on a Kazakh voice installed in Android.
      if (_navigationLanguage == 'kk-KZ') {
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
                'Could not start the selected navigation voice.',
              ));
      }
    }
  }

  String _localized(String ru, String kk, String en) {
    if (_navigationLanguage == 'kk-KZ') return kk;
    if (_navigationLanguage == 'en-US') return en;
    return ru;
  }

  ml.LatLng _toMapLibrePoint(LatLng point) => ml.LatLng(point.latitude, point.longitude);

  LatLng get _mapCameraCenter {
    if (_offlineTileProvider != null) return _mapController.camera.center;
    final target = _mapLibreController?.cameraPosition?.target;
    return target == null ? (_currentLocation ?? _shymkent) : LatLng(target.latitude, target.longitude);
  }

  double get _mapCameraZoom => _offlineTileProvider != null
      ? _mapController.camera.zoom
      : (_mapLibreController?.cameraPosition?.zoom ?? 13);

  void _moveMapCamera(LatLng point, double zoom) {
    if (_offlineTileProvider != null) {
      _mapController.move(point, zoom);
      return;
    }
    final controller = _mapLibreController;
    if (controller == null) return;
    unawaited(controller.animateCamera(ml.CameraUpdate.newLatLngZoom(
      _toMapLibrePoint(point), zoom,
    ), duration: const Duration(milliseconds: 350)));
  }

  void _rotateMapCamera(double rotation) {
    if (_offlineTileProvider != null) {
      _mapController.rotate(rotation);
      return;
    }
    final controller = _mapLibreController;
    if (controller == null) return;
    final current = controller.cameraPosition;
    unawaited(controller.animateCamera(ml.CameraUpdate.newCameraPosition(
      ml.CameraPosition(
        target: current?.target ?? _toMapLibrePoint(_currentLocation ?? _shymkent),
        zoom: current?.zoom ?? 17,
        bearing: -rotation,
        tilt: _navigationActive ? 48 : 0,
      ),
    ), duration: const Duration(milliseconds: 350)));
  }

  void _fitMapCamera(List<LatLng> points) {
    if (points.isEmpty) return;
    if (_offlineTileProvider != null) {
      _mapController.fitCamera(CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(36, 100, 36, 250),
      ));
      return;
    }
    final controller = _mapLibreController;
    if (controller == null) return;
    final lats = points.map((p) => p.latitude);
    final lons = points.map((p) => p.longitude);
    final bounds = ml.LatLngBounds(
      southwest: ml.LatLng(
        lats.reduce((a, b) => math.min(a, b).toDouble()),
        lons.reduce((a, b) => math.min(a, b).toDouble()),
      ),
      northeast: ml.LatLng(
        lats.reduce((a, b) => math.max(a, b).toDouble()),
        lons.reduce((a, b) => math.max(a, b).toDouble()),
      ),
    );
    unawaited(controller.animateCamera(ml.CameraUpdate.newLatLngBounds(
      bounds, left: 36, top: 100, right: 36, bottom: 250,
    ), duration: const Duration(milliseconds: 500)));
  }

  void _zoomMapBy(double delta) {
    _moveMapCamera(_mapCameraCenter, (_mapCameraZoom + delta).clamp(3.0, 20.0).toDouble());
  }

  void _onMapLibreCreated(ml.MapLibreMapController controller) {
    _mapLibreStyleReady = false;
    _mapLibreController = controller;
  }

  void _onMapLibreStyleLoaded() {
    _mapLibreStyleReady = true;
    unawaited(_syncMapLibreAnnotations(updateRoute: true));
    // GPS may finish before MapLibre has created its controller. In that case
    // the first camera move is ignored, so center the map again when the style
    // becomes ready to make the live-position arrow visible immediately.
    final currentLocation = _currentLocation;
    if (currentLocation != null) {
      _moveMapCamera(currentLocation, 16);
    }
    if (_routePoints.length > 1) _fitMapCamera(_routePoints);
  }

  Future<void> _syncMapLibreAnnotations({bool updateRoute = false}) async {
    // GPS updates can arrive while the previous annotation update is still
    // clearing and recreating symbols. Serialize those updates and run once
    // more with the newest position instead of allowing overlapping clears.
    if (_mapLibreAnnotationSyncInProgress) {
      _mapLibreAnnotationSyncPending = true;
      if (updateRoute) _mapLibreRouteSyncPending = true;
      return;
    }
    _mapLibreAnnotationSyncInProgress = true;
    try {
      do {
        _mapLibreAnnotationSyncPending = false;
        final syncRoute = updateRoute || _mapLibreRouteSyncPending;
        _mapLibreRouteSyncPending = false;
        final controller = _mapLibreController;
        if (controller == null || !_mapLibreStyleReady || _offlineTileProvider != null) return;
        // GPS refreshes must never remove the already-rendered route line.
        // Only route/style changes are allowed to replace route geometry.
        if (syncRoute) {
          await controller.clearLines();
          if (_routePoints.length > 1) {
            await controller.addLine(ml.LineOptions(
              geometry: _routePoints.map(_toMapLibrePoint).toList(),
              lineColor: '#2378C8',
              lineWidth: 6,
              lineOpacity: 0.96,
            ));
          }
        }
        await controller.clearSymbols();
        await controller.clearCircles();

        // Place direction arrows at regular intervals along the route geometry.
        // These are separate from the GPS heading marker and follow the route itself.
        if (_routePoints.length > 1) {
          const arrowSpacingMeters = 700.0;
          var distanceUntilNextArrow = arrowSpacingMeters;
          for (var i = 0; i < _routePoints.length - 1; i++) {
            final a = _routePoints[i];
            final b = _routePoints[i + 1];
            final segmentMeters = Geolocator.distanceBetween(
              a.latitude, a.longitude, b.latitude, b.longitude,
            );
            if (segmentMeters <= 0) continue;
            var travelledOnSegment = 0.0;
            while (travelledOnSegment + distanceUntilNextArrow <= segmentMeters) {
              travelledOnSegment += distanceUntilNextArrow;
              final fraction = travelledOnSegment / segmentMeters;
              final arrowPoint = LatLng(
                a.latitude + (b.latitude - a.latitude) * fraction,
                a.longitude + (b.longitude - a.longitude) * fraction,
              );
              final bearing = Geolocator.bearingBetween(
                a.latitude, a.longitude, b.latitude, b.longitude,
              );
              await controller.addSymbol(ml.SymbolOptions(
                geometry: _toMapLibrePoint(arrowPoint),
                textField: '➤',
                textSize: 22,
                textColor: '#2378C8',
                textHaloColor: '#FFFFFF',
                textHaloWidth: 3,
                textRotate: bearing,
              ));
              distanceUntilNextArrow = arrowSpacingMeters;
            }
            distanceUntilNextArrow -= segmentMeters - travelledOnSegment;
          }
        }

        // Show the route start even when it was taken automatically from GPS.
        final routeStart = _routeOrigin ??
            (_routePoints.length > 1 ? _routePoints.first : null);
        if (routeStart != null && _routePoints.length > 1) {
          await controller.addCircle(ml.CircleOptions(
            geometry: _toMapLibrePoint(routeStart),
            circleRadius: 10,
            circleColor: '#269B68',
            circleOpacity: 1,
            circleStrokeColor: '#FFFFFF',
            circleStrokeWidth: 3,
            circleStrokeOpacity: 1,
          ));
        }
      if (_currentLocation != null) {
        // Draw GPS position as a native MapLibre circle, not a text glyph.
        // Text symbols depend on font glyph availability in the active map style.
        await controller.addCircle(ml.CircleOptions(
          geometry: _toMapLibrePoint(_currentLocation!),
          circleRadius: 9,
          circleColor: '#1769AA',
          circleOpacity: 1,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
          circleStrokeOpacity: 1,
        ));
        // Direction arrow above the GPS dot on the online MapLibre map.
        await controller.addSymbol(ml.SymbolOptions(
          geometry: _toMapLibrePoint(_currentLocation!),
          textField: '▲',
          textSize: 27,
          textColor: '#1769AA',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 3,
          textRotate: _gpsHeadingDegrees ?? 0,
        ));
      }
      for (var i = 0; i < _routeStops.length; i++) {
        await controller.addSymbol(ml.SymbolOptions(
          geometry: _toMapLibrePoint(_routeStops[i]), textField: '${i + 1}',
          textSize: 16, textColor: '#FFFFFF',
          textHaloColor: '#343434', textHaloWidth: 5,
        ));
      }
      if (_destination != null) {
        await controller.addCircle(ml.CircleOptions(
          geometry: _toMapLibrePoint(_destination!),
          circleRadius: 12,
          circleColor: '#E53935',
          circleOpacity: 1,
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 3,
          circleStrokeOpacity: 1,
        ));
      }
      } while (_mapLibreAnnotationSyncPending);
    } catch (error, stackTrace) {
      // Do not silently lose the user's GPS marker when MapLibre rejects an
      // annotation update. Keep a visible symbol fallback at the latest fix.
      debugPrint('BAKE Navigator: GPS/map annotation update failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      final controller = _mapLibreController;
      final point = _currentLocation;
      if (controller != null && _mapLibreStyleReady &&
          _offlineTileProvider == null && point != null) {
        try {
          await controller.addSymbol(ml.SymbolOptions(
            geometry: _toMapLibrePoint(point),
            textField: '●',
            textSize: 28,
            textColor: '#1769AA',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 3,
          ));
        } catch (fallbackError, fallbackStackTrace) {
          debugPrint('BAKE Navigator: GPS marker fallback failed: $fallbackError');
          debugPrintStack(stackTrace: fallbackStackTrace);
        }
      }
    } finally {
      _mapLibreAnnotationSyncInProgress = false;
      if (_mapLibreAnnotationSyncPending) {
        final syncRoute = _mapLibreRouteSyncPending;
        _mapLibreRouteSyncPending = false;
        unawaited(_syncMapLibreAnnotations(updateRoute: syncRoute));
      }
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _offlineTileProvider?.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tts.stop();
    unawaited(_kazakhVoiceService.dispose());
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
            if (!enabled) {
              unawaited(_tts.stop());
              unawaited(_kazakhVoiceService.stop());
            }
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
      setState(() { _offlineTileProvider = null; _message = AppLocale.pick('Включена онлайн-карта.', 'Онлайн карта қосылды.', 'Online map enabled.'); });
      return;
    }
    try {
      final provider = MbTilesTileProvider.fromPath(path: selectedPath);
      _offlineTileProvider?.dispose();
      setState(() { _offlineTileProvider = provider; _message = AppLocale.pick('Офлайн-карта подключена. Для построения маршрута пока нужен интернет.', 'Офлайн карта қосылды. Маршрут құру үшін әзірге интернет қажет.', 'Offline map connected. Internet is still required to build routes.'); });
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = AppLocale.pick('Не удалось открыть офлайн-карту: $error', 'Офлайн картаны ашу мүмкін болмады: $error', 'Could not open offline map: $error'));
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
    var offlineVoiceBusy = false;
    var offlineVoiceReady = await _kazakhVoiceService.isInstalled;
    var offlineVoiceStatus = '';
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
        await _kazakhVoiceService.speak(
          text: 'Дауысты тексеру. Бағыт бойынша жүре беріңіз.',
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
            text: 'Дауысты тексеру. Бағыт бойынша жүре беріңіз.',
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
                      await _refreshAvailableVoices();
                      await _prepareSpeechVoice();
                      refresh(() {});
                    },
                  ),
                  if (language == 'kk-KZ') ...[
                    const SizedBox(height: 14),
                    Text('Қазақша офлайн дауысы · ISSAI', style: const TextStyle(fontWeight: FontWeight.w700)),
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
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: offlineVoiceBusy ? null : loadAndPreviewVoice,
                      icon: offlineVoiceBusy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_for_offline_outlined),
                      label: Text(offlineVoiceBusy
                          ? AppLocale.pick('Подождите…', 'Күте тұрыңыз…', 'Please wait…')
                          : offlineVoiceReady
                              ? AppLocale.pick('Прослушать выбранный голос', 'Таңдалған дауысты тыңдау', 'Preview selected voice')
                              : AppLocale.pick('Загрузить и прослушать голос', 'Жүктеу және дауысты тыңдау', 'Download and preview voice')),
                    ),
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
                          await _kazakhVoiceService.stop();
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
      if (!mounted) return;
      setState(() {
        _currentLocation = point;
        _currentSpeedKmh = math.max(0, position.speed * 3.6).toDouble();
        if (position.speed >= 0.8 && position.heading.isFinite) {
          _gpsHeadingDegrees = position.heading;
        }
        _message = AppLocale.pick('GPS определён. Положение будет обновляться в реальном времени.', 'GPS анықталды. Орналасқан жер нақты уақытта жаңартылып отырады.', 'GPS located. Your position will update in real time.');
      });
      // Render the first GPS fix immediately, without waiting for the next stream event.
      unawaited(_syncMapLibreAnnotations());
      _moveMapCamera(point, 15);
      await _startLiveLocationUpdates();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }


  Future<void> _startLiveLocationUpdates({
    bool backgroundNavigation = false,
    bool waitForFirstFix = false,
  }) async {
    await _positionSubscription?.cancel();
    if (!mounted) return;

    final firstFix = Completer<void>();
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
        final point = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentLocation = point;
          _currentSpeedKmh = math.max(0, position.speed * 3.6).toDouble();
          // Ignore unstable compass headings while stopped or moving very slowly.
          if (position.speed >= 0.8 && position.heading.isFinite) {
            _gpsHeadingDegrees = position.heading;
          }
        });
        unawaited(_syncMapLibreAnnotations());

        // Follow the live GPS position and rotate/pitch the MapLibre camera in navigation mode.
        if (_navigationActive) {
          final cameraCenter = _mapCameraCenter;
          if (Geolocator.distanceBetween(
                cameraCenter.latitude, cameraCenter.longitude,
                point.latitude, point.longitude,
              ) > 3) {
            _moveMapCamera(point, math.max(_mapCameraZoom, 17.0).toDouble());
          }
          final heading = _gpsHeadingDegrees;
          if (heading != null && position.speed >= 1.5) {
            final normalizedHeading = (heading % 360 + 360) % 360;
            final previousHeading = _lastCameraHeadingDegrees;
            final difference = previousHeading == null
                ? 360.0
                : ((normalizedHeading - previousHeading + 540) % 360) - 180;
            if (difference.abs() >= 4) {
              _rotateMapCamera(-normalizedHeading);
              _lastCameraHeadingDegrees = normalizedHeading;
            }
          }
        }

        if (!firstFix.isCompleted) firstFix.complete();
        _updateNavigationProgress(point);
        _checkForOffRoute(position);
      },
      onError: (Object error) {
        if (waitForFirstFix && !firstFix.isCompleted) {
          firstFix.completeError(error, StackTrace.current);
        }
        if (!mounted) return;
        setState(() {
          _message = AppLocale.pick('Потеряна связь с GPS. Проверьте геолокацию телефона.', 'GPS байланысы жоғалды. Телефон геолокациясын тексеріңіз.', 'GPS signal lost. Check your phone location settings.');
        });
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
      _message = selectAsOrigin ? AppLocale.pick('Ищем начальную точку…', 'Бастапқы нүкте ізделуде…', 'Searching for starting point…') : AppLocale.pick('Ищем пункт назначения…', 'Межелі орын ізделуде…', 'Searching for destination…');
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
          throw Exception(AppLocale.pick('Сервис поиска просит подождать. Повторите через минуту.', 'Іздеу қызметі күте тұруды сұрайды. Бір минуттан кейін қайталаңыз.', 'Search service asks you to wait. Try again in a minute.'));
        }
        if (response.statusCode != 200) {
          throw Exception(AppLocale.pick('Поиск адресов временно недоступен.', 'Мекенжай іздеу уақытша қолжетімсіз.', 'Address search is temporarily unavailable.'));
        }
        return jsonDecode(response.body) as List<dynamic>;
      }

      // Search Kazakhstan without a hard 50 km cutoff. Keep the local area
      // as the ranking anchor so nearby streets appear before distant matches.
      final results = await requestSearch(bounded: false, limit: '40');
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() => _message = AppLocale.pick('Такой объект не найден в Казахстане. Проверьте название.', 'Қазақстаннан мұндай нысан табылмады. Атауын тексеріңіз.', 'This place was not found in Kazakhstan. Check the name.'));
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
        setState(() => _message = AppLocale.pick('Поиск вернул некорректные координаты. Попробуйте другое название.', 'Іздеу қате координаттарды қайтарды. Басқа атауды қолданып көріңіз.', 'Search returned invalid coordinates. Try another name.'));
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
                Center(
                  child: Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6D9DE),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  selectAsOrigin
                      ? AppLocale.tr('Выберите начальную точку')
                      : AppLocale.tr('Выберите пункт назначения'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
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
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: Color(0xFF343434),
                        ),
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
                        onTap: () => Navigator.of(sheetContext).pop(item),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(AppLocale.tr('Отмена')),
                ),
              ],
            ),
          ),
        ),
      );
      if (selected == null || !mounted) return;
      final lat = double.tryParse(selected['lat']?.toString() ?? '');
      final lon = double.tryParse(selected['lon']?.toString() ?? '');
      if (lat == null || lon == null || lat < 40 || lat > 56 || lon < 46 || lon > 88) {
        setState(() => _message = AppLocale.pick('Координаты результата не относятся к Казахстану.', 'Нәтиже координаттары Қазақстан аумағына жатпайды.', 'The result coordinates are outside Kazakhstan.'));
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
      setState(() => _message = selectAsOrigin
          ? AppLocale.pick('Начальная точка выбрана. Теперь введите пункт назначения.', 'Бастапқы нүкте таңдалды. Енді межелі орынды енгізіңіз.', 'Starting point selected. Now enter your destination.')
          : AppLocale.pick('Адрес найден. Автоматически строим маршрут от вашего GPS-положения…', 'Мекенжай табылды. GPS орналасқан жеріңізден маршрут автоматты түрде құрылады…', 'Address found. Building a route from your GPS location…'));
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
      _routeReady = false;
      _instructions = [];
      _navigationActive = false;
      _instructionIndex = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = '';
    });
    unawaited(_syncMapLibreAnnotations(updateRoute: true));
    unawaited(_saveRoutePoint(_savedRouteOriginKey, point));
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
  }

  void _resetRouteOrigin() {
    setState(() {
      _routeOrigin = null;
      _routePoints = [];
      _routeReady = false;
      _instructions = [];
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = AppLocale.pick('Начальная точка снова определяется по GPS.', 'Бастапқы нүкте қайтадан GPS арқылы анықталады.', 'Starting point will be detected by GPS again.');
    });
    unawaited(_syncMapLibreAnnotations(updateRoute: true));
    unawaited(_removeSavedRoutePoint(_savedRouteOriginKey));
  }

  void _selectDestination(LatLng point) {
    final wasNavigating = _navigationActive;
    setState(() {
      _destination = point;
      _routePoints = [];
      _routeReady = false;
      _instructions = [];
      _navigationActive = false;
      _instructionIndex = 0;
      _routeDistanceMeters = null;
      _routeDurationSeconds = null;
      _message = '';
    });
    unawaited(_syncMapLibreAnnotations(updateRoute: true));
    unawaited(_saveRoutePoint(_savedRouteDestinationKey, point));
    if (wasNavigating) unawaited(_startLiveLocationUpdates());
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
          maneuverType: maneuver['type']?.toString() ?? '',
          maneuverModifier: maneuver['modifier']?.toString() ?? '',
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
          'Allow background GPS',
        )),
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

    setState(() {
      _navigationActive = true;
      _announcedManeuverStage = 0;
      _instructionIndex = _instructions.isNotEmpty && _instructions.length > 1 ? 1 : 0;
      _message = _currentLocation == null
          ? AppLocale.pick('Маршрут запущен. Ожидаем сигнал GPS — движение и подсказки начнутся после получения координат.', 'Маршрут басталды. GPS сигналы күтілуде — координат алынған соң қозғалыс пен нұсқаулар басталады.', 'Route started. Waiting for GPS; tracking and guidance will begin when a location fix arrives.')
          : AppLocale.pick('Включаем фоновый GPS и голосовые подсказки…', 'Фондық GPS пен дауыстық нұсқаулар қосылуда…', 'Enabling background GPS and voice guidance…');
    });
    try {
      // Keep the location stream active without blocking route start on first fix.
      await _startLiveLocationUpdates(
        backgroundNavigation: true,
        waitForFirstFix: false,
      );
    } catch (error) {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
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
      _moveMapCamera(livePoint, 17);
      final initialHeading = _gpsHeadingDegrees;
      if (initialHeading != null && _currentSpeedKmh >= 5.4) {
        _rotateMapCamera(-initialHeading);
        _lastCameraHeadingDegrees = initialHeading;
      } else {
        _rotateMapCamera(0);
      }
      await _speakCurrentInstruction();
    }
  }

  Future<void> _finishNavigation() async {
    if (!mounted) return;
    setState(() {
      _navigationActive = false;
      _routeActionDismissed = true;
      _routeReady = false;
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
    });
    await _tts.stop();
    await _removeSavedRoutePoint(_savedRouteDestinationKey);
    _lastCameraHeadingDegrees = null;
    _rotateMapCamera(0);
    // Force MapLibre to remove the old blue line and route markers.
    await _syncMapLibreAnnotations(updateRoute: true);
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
    final meters = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      instruction.location.latitude,
      instruction.location.longitude,
    );
    final distanceText = meters >= 1000
        ? _localized('${(meters / 1000).toStringAsFixed(1)} километра', '${(meters / 1000).toStringAsFixed(1)} километр', '${(meters / 1000).toStringAsFixed(1)} kilometers')
        : _localized('${meters.round()} метров', '${meters.round()} метр', '${meters.round()} meters');
    if (_voiceMode >= 2) {
      await _speakText(_localized('${instruction.text} через $distanceText.', '${instruction.text} $distanceText кейін.', '${instruction.text} in $distanceText.'));
    }
  }

  double? get _distanceToNextManeuverMeters {
    if (_currentLocation == null || _instructionIndex >= _instructions.length) return null;
    final target = _instructions[_instructionIndex].location;
    return Geolocator.distanceBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      target.latitude,
      target.longitude,
    );
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

    // Announce the upcoming maneuver in stages instead of speaking only once.
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
                : target.text;
        unawaited(_speakText(announcement));
      }
    }

    if (meters <= 35) {
      if (_instructionIndex + 1 >= _instructions.length) {
        setState(() {
          _navigationActive = false;
          _routeActionDismissed = true;
          _message = AppLocale.pick('Вы прибыли в пункт назначения.', 'Межелі жерге жеттіңіз.', 'You have arrived at your destination.');
        });
        if (_voiceMode >= 1) _speakText(AppLocale.pick('Вы прибыли в пункт назначения.', 'Межелі жерге жеттіңіз.', 'You have arrived at your destination.'));
        unawaited(_startLiveLocationUpdates());
        return;
      }
      setState(() {
        _instructionIndex++;
        _announcedManeuverStage = 0;
      });
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
      if (response.statusCode != 200) throw Exception(AppLocale.pick('Сервис маршрутов временно недоступен.', 'Маршрут қызметі уақытша қолжетімсіз.', 'Route service is temporarily unavailable.'));

      final data = jsonDecode(response.body) as Map<String, dynamic>;
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
        _routeReady = points.length >= 2;
        _routeActionDismissed = false;
        _instructions = instructions;
        _navigationActive = resumeNavigation;
        _instructionIndex = resumeNavigation && instructions.length > 1 ? 1 : 0;
        _offRouteSamples = 0;
        _routeDistanceMeters = distance;
        _routeDurationSeconds = duration;
        // Keep the map clear; route alternatives are presented in the route-search screen.
        _message = automaticReroute
            ? AppLocale.pick('Маршрут перестроен. Продолжаем навигацию.', 'Маршрут қайта құрылды. Навигация жалғасуда.', 'Route recalculated. Continuing navigation.')
            : '';
      });
      if (points.isNotEmpty) {
        unawaited(_syncMapLibreAnnotations(updateRoute: true));
        _fitMapCamera(points);
        if (automaticReroute && resumeNavigation && _currentLocation != null) {
          _moveMapCamera(_currentLocation!, 17);
          final heading = _gpsHeadingDegrees;
          if (heading != null && _currentSpeedKmh >= 5.4) {
            _rotateMapCamera(-heading);
            _lastCameraHeadingDegrees = heading;
          }
        }
      }
      if (automaticReroute && resumeNavigation) {
        if (_voiceMode >= 1) await _speakText(AppLocale.pick('Вы отклонились от маршрута. Маршрут перестроен.', 'Бағыттан ауытқыдыңыз. Маршрут қайта құрылды.', 'You left the route. The route has been recalculated.'));
        await _speakCurrentInstruction();
      } else {
        final distanceKm = (distance / 1000).toStringAsFixed(1);
        final minutes = (duration / 60).round();
        if (_voiceMode >= 3) await _speakText(AppLocale.pick('Маршрут построен. Расстояние $distanceKm километра. Примерное время в пути $minutes минут.', 'Маршрут құрылды. Қашықтық $distanceKm километр. Жол уақыты шамамен $minutes минут.', 'Route built. Distance $distanceKm kilometers. Estimated travel time $minutes minutes.'));
        // Stay on the map: its persistent «Поехали» button starts navigation.
        // Route alternatives remain available from the Route menu.
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
      _routeReady = points.length >= 2;
      _instructions = instructions;
      _instructionIndex = 0;
      _routeDistanceMeters = (route['distance'] as num).toDouble();
      _routeDurationSeconds = (route['duration'] as num).toDouble();
      _message = _localized('Выбран вариант маршрута ${index + 1}.', '${index + 1}-маршрут нұсқасы таңдалды.', 'Route option ${index + 1} selected.');
    });
    if (points.isNotEmpty) {
      unawaited(_syncMapLibreAnnotations(updateRoute: true));
      _fitMapCamera(points);
    }
  }

  Future<void> _openRouteAlternatives() async {
    if (_routeAlternatives.isEmpty) {
      await _openRoutePlanner();
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD5D9DE),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                AppLocale.tr('Варианты маршрута'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ...List.generate(_routeAlternatives.length, (index) {
                final route = _routeAlternatives[index];
                final km = ((route['distance'] as num).toDouble() / 1000).toStringAsFixed(1);
                final minutes = (((route['duration'] as num).toDouble()) / 60).round();
                final selected = index == _selectedRouteIndex;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    selected ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: selected ? const Color(0xFFB88A00) : const Color(0xFF69737D),
                  ),
                  title: Text('$minutes мин · $km км', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${AppLocale.tr('Вариант ')}${index + 1}'),
                  onTap: () {
                    _selectRouteAlternative(index);
                    Navigator.pop(sheetContext);
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
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
                    title: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    var roadEvents = prefs.getBool('layer_road_events') ?? true;
    var parking = prefs.getBool('layer_parking') ?? false;
    var satellite = prefs.getBool('layer_satellite') ?? false;

    Future<void> saveLayer(String key, bool value) async {
      await prefs.setBool(key, value);
      if (!mounted) return;
      setState(() {
        _message = AppLocale.pick('Настройка сохранена. Для отображения этого слоя нужен подключённый источник данных.', 'Баптау сақталды. Бұл қабатты көрсету үшін деректер көзі қосылуы керек.', 'Setting saved. A connected data source is required to display this layer.');
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Text(
                    AppLocale.pick('Переключатели пока сохраняют выбор. Пробки, парковки, спутниковые снимки и общий слой дорожных событий ещё не подключены к источникам данных и не отображаются на карте.', 'Ауыстырғыштар әзірге таңдауды ғана сақтайды. Кептелістер, тұрақтар, спутниктік суреттер және жол оқиғалары қабаты деректер көздеріне қосылмаған, сондықтан картада көрсетілмейді.', 'These switches currently only save your selection. Traffic, parking, satellite imagery, and the road events layer are not connected to data sources and are not displayed on the map.'),
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
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
                  _offlineTileProvider == null
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

  Future<void> _selectMapDestination(LatLng point) async {
    if (point.latitude < 40 || point.latitude > 56 ||
        point.longitude < 46 || point.longitude > 88) {
      if (mounted) {
        setState(() => _message = AppLocale.tr('Выберите точку на территории Казахстана.'));
      }
      return;
    }
    _selectDestination(point);
    _moveMapCamera(point, 15);
    if (mounted) {
      setState(() => _message = AppLocale.pick(
        'Пункт назначения выбран на карте. Строим маршрут…',
        'Межелі орын картадан таңдалды. Маршрут құрылуда…',
        'Destination selected on map. Building route…',
      ));
    }
    await _buildRoute();
  }

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
        ? AppLocale.pick('Событие сохранено на устройстве. Отправка другим водителям пока не подключена.', 'Оқиға құрылғыда сақталды. Басқа жүргізушілерге жіберу әлі қосылмаған.', 'Event saved on this device. Sharing with other drivers is not connected yet.')
        : AppLocale.pick(AppLocale.pick(AppLocale.pick('Отчёт скопирован. Отправка на сервер пока не подключена.', 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'), 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'), 'Есеп көшірілді. Серверге жіберу әлі қосылмаған.', 'Report copied. Server submission is not connected yet.'));
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
                              decoration: InputDecoration(
                                labelText: AppLocale.tr('Название'),
                                hintText: AppLocale.tr('Например, спортзал'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: addressController,
                              decoration: InputDecoration(
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
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      AppLocale.tr('Пока нет сохранённых сообщений о дорожных событиях.'),
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
                  const SizedBox(height: 16),
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
                        onPressed: () { setState(() { _routeStops.removeAt(entry.key); _routePoints = []; _routeReady = false; _instructions = []; }); refreshSheet(() {}); },
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
            _menuTile(sheetContext, Icons.alt_route, AppLocale.tr('Варианты маршрута'), () { Navigator.pop(sheetContext); _openRouteAlternatives(); }),
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
            angle: _navigationActive ? 0 : (_gpsHeadingDegrees ?? 0) * math.pi / 180,
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
          if (_offlineTileProvider == null)
            ml.MapLibreMap(
              initialCameraPosition: ml.CameraPosition(
                target: ml.LatLng(_shymkent.latitude, _shymkent.longitude),
                zoom: 13,
              ),
              styleString: 'https://tiles.openfreemap.org/styles/liberty',
              onMapCreated: _onMapLibreCreated,
              onStyleLoadedCallback: _onMapLibreStyleLoaded,
              onMapClick: (_, point) => _selectMapDestination(LatLng(point.latitude, point.longitude)),
              onMapLongClick: (_, point) => _openPointMenu(LatLng(point.latitude, point.longitude)),
              compassEnabled: false,
              trackCameraPosition: true,
              rotateGesturesEnabled: true,
              tiltGesturesEnabled: true,
              zoomGesturesEnabled: true,
              scrollGesturesEnabled: true,
              minMaxZoomPreference: const ml.MinMaxZoomPreference(3, 20),
            )
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _shymkent,
                initialZoom: 13,
                onTap: (_, point) => _selectMapDestination(point),
                onLongPress: (_, point) => _openPointMenu(point),
              ),
              children: [
                TileLayer(tileProvider: _offlineTileProvider!),
                if (_routePoints.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(points: _routePoints, strokeWidth: 7, color: const Color(0xFF2378C8)),
                    ],
                  ),
                MarkerLayer(markers: markers),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
                ),
              ],
            ),
          if (!_navigationActive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Material(
                        color: Colors.white,
                        elevation: 5,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: AppLocale.tr('Профиль'),
                          onPressed: _openProfileMenu,
                          icon: const Icon(Icons.person_outline, color: Color(0xFF343434)),
                        ),
                      ),
                      const Spacer(),
                      Material(
                        color: Colors.white,
                        elevation: 5,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: AppLocale.tr('Меню маршрута'),
                          onPressed: _openRouteMenu,
                          icon: const Icon(Icons.alt_route, color: Color(0xFF343434)),
                        ),
                      ),
                    ],
                  ),
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
                          Icon(
                            _maneuverIcon(
                              _instructionIndex < _instructions.length
                                  ? _instructions[_instructionIndex]
                                  : null,
                            ),
                            size: 34,
                            color: const Color(0xFF343434),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _instructionIndex < _instructions.length
                                      ? _instructions[_instructionIndex].text
                                      : _localized('Продолжайте по маршруту', 'Бағыт бойынша жүре беріңіз', 'Continue on the route'),
                                  softWrap: true,
                                  style: const TextStyle(fontSize: 15, height: 1.15, fontWeight: FontWeight.w800),
                                ),
                                if (_instructionIndex < _instructions.length)
                                  Text(
                                    '${_localized('Следующий манёвр', 'Келесі маневр', 'Next maneuver')} · ${_distanceToNextManeuverMeters == null ? '—' : (_distanceToNextManeuverMeters! >= 1000 ? '${(_distanceToNextManeuverMeters! / 1000).toStringAsFixed(1)} км' : '${_distanceToNextManeuverMeters!.round()} м')}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF626A73)),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: AppLocale.tr('Завершить навигацию'),
                            onPressed: _finishNavigation,
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
              bottom: 225,
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
                  onPressed: () => _rotateMapCamera(0),
                ),
              ],
            ),
          ),
          if (!_navigationActive && !_routeReady)
            Positioned(
              left: 14,
              top: 124,
              child: Material(
                color: Colors.white,
                elevation: 4,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'Парковки',
                  onPressed: () {
                    _searchController.text = 'парковка';
                    _searchAddress();
                  },
                  icon: const Text('P', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, color: Color(0xFF1769AA))),
                ),
              ),
            ),
          Positioned(
            left: 14,
            top: _navigationActive ? null : 68,
            bottom: _navigationActive ? 380 : null,
            child: _roundMapButton(
              icon: Icons.my_location,
              tooltip: AppLocale.tr('Моё местоположение'),
              iconColor: const Color(0xFF343434),
              onPressed: _isLocating ? null : () => unawaited(_locateMe()),
            ),
          ),
          if (_navigationActive && _message.isNotEmpty)
            Positioned(
              top: 0,
              left: 14,
              right: 14,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: IgnorePointer(
                    child: Material(
                      color: const Color(0xF2FFFFFF),
                      elevation: 3,
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        child: Text(
                          _message,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (!_navigationActive && _message.isNotEmpty)
            Positioned(
              top: 84,
              left: 14,
              right: 14,
              child: IgnorePointer(
                child: Material(
                  color: const Color(0xF2FFFFFF),
                  elevation: 3,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      _message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, height: 1.15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ),
          if (_routeReady && !_navigationActive && !_routeActionDismissed)
            Positioned(
              left: 12,
              right: 12,
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
                      child: Text(
                        _routeSummary(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF555B63)),
                      ),
                    ),
                    SizedBox(
                      height: 38,
                      child: FilledButton(
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
                    ),
                  ],
                ),
              ),
            ),
          if (!_navigationActive)
            Positioned(
              left: 12,
              right: 12,
              bottom: -10,
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
              ],
            ),
    );
  }

}

