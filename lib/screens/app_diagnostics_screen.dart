import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show FrameTiming, SchedulerBinding;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/road_report_sync_service.dart';

enum _CheckState { ok, warning, error, notChecked }

class _CheckResult {
  const _CheckResult(this.name, this.state, this.details, this.checkedAt);

  final String name;
  final _CheckState state;
  final String details;
  final DateTime checkedAt;

  Map<String, Object?> toJson() => {
    'name': name,
    'state': state.name,
    'details': details,
    'checkedAt': checkedAt.toIso8601String(),
  };

  factory _CheckResult.fromJson(Map<String, dynamic> json) => _CheckResult(
    json['name'] as String? ?? 'Проверка',
    _CheckState.values.firstWhere(
      (state) => state.name == json['state'],
      orElse: () => _CheckState.notChecked,
    ),
    json['details'] as String? ?? '',
    DateTime.tryParse(json['checkedAt'] as String? ?? '') ?? DateTime.now(),
  );
}

class AppDiagnosticsScreen extends StatefulWidget {
  const AppDiagnosticsScreen({super.key});

  static const _startupArmedKey = 'bake_app_diagnostics_startup_armed';
  static const _startupResultKey = 'bake_app_diagnostics_startup_result';

  static Future<void> armNextStartupCheck() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_startupArmedKey, true);
    await prefs.remove(_startupResultKey);
  }

  static Future<bool> isStartupCheckArmed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_startupArmedKey) ?? false;
  }

  static Future<void> recordStartupMapReady(int elapsedMs) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_startupArmedKey) ?? false)) return;
    await prefs.setString(_startupResultKey, 'MAP_READY:$elapsedMs');
    await prefs.setBool(_startupArmedKey, false);
  }

  static Future<void> recordStartupMapTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(_startupArmedKey) ?? false)) return;
    await prefs.setString(_startupResultKey, 'MAP_TIMEOUT: карта не отобразилась за 30 секунд');
    await prefs.setBool(_startupArmedKey, false);
  }

  static Future<void> recordStartupRuntimeError(String source, Object error) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool(_startupArmedKey) ?? false)) return;
      await prefs.setString(_startupResultKey, 'STARTUP_ERROR:$source: ${error.runtimeType}: $error');
      await prefs.setBool(_startupArmedKey, false);
      final history = prefs.getStringList('bake_app_diagnostics_history') ?? <String>[];
      history.add('${DateTime.now().toIso8601String()} | STARTUP_ERROR | $source | ${error.runtimeType}: $error');
      await prefs.setStringList('bake_app_diagnostics_history', history.length > 100 ? history.sublist(history.length - 100) : history);
    } catch (_) {}
  }

  // Navigation components call this hook; it writes nothing unless a trip session is active.
  static Future<void> recordTripEvent(String title, String details) async {
    await _TripDiagnosticsRecorder.instance.addEvent(title, details);
  }

  static bool get isTripDiagnosticsActive =>
      _TripDiagnosticsRecorder.instance.active;

  // Record unexpected runtime errors only while the user explicitly records a trip.
  static Future<void> recordTripRuntimeError(String source, Object error) async {
    try {
      await _TripDiagnosticsRecorder.instance.addEvent(
        'Ошибка приложения: $source',
        '${error.runtimeType}: $error',
      );
    } catch (_) {
      // Diagnostics must never interrupt normal error handling.
    }
  }

  // Runtime errors are retained on this device only. No network request is made.
  static Future<void> recordRuntimeError(String source, Object error) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList('bake_app_diagnostics_history') ?? [];
      history.add(
        '${DateTime.now().toIso8601String()} | ERROR | $source | ${error.runtimeType}: $error',
      );
      await prefs.setStringList(
        'bake_app_diagnostics_history',
        history.length > 100 ? history.sublist(history.length - 100) : history,
      );
      await _TripDiagnosticsRecorder.instance.addEvent('Ошибка приложения: $source', '${error.runtimeType}: $error');
    } catch (_) {
      // Diagnostics must never interrupt the app's normal error handling.
    }
  }

  @override
  State<AppDiagnosticsScreen> createState() => _AppDiagnosticsScreenState();
}

class _AppDiagnosticsScreenState extends State<AppDiagnosticsScreen> {
  static const _historyKey = 'bake_app_diagnostics_history';
  final List<_CheckResult> _results = [];
  List<String> _history = [];
  List<Map<String, dynamic>> _cloudErrors = [];
  bool _loadingCloudErrors = false;
  String? _cloudErrorMessage;
  String? _startupResult;
  bool _checking = false;
  DateTime? _lastRun;

  @override
  void initState() {
    super.initState();
    _loadSavedData(); // Loads history only; never runs checks on app/screen startup.
  }

  Future<void> _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = prefs.getString('bake_app_diagnostics_last_results');
    if (saved != null) {
      try {
        final decoded = (jsonDecode(saved) as List)
            .whereType<Map>()
            .map((item) => _CheckResult.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _results
          ..clear()
          ..addAll(decoded);
        if (decoded.isNotEmpty) _lastRun = decoded.first.checkedAt;
      } catch (_) {
        // Ignore an incomplete previous report.
      }
    }
    setState(() {
      _history = prefs.getStringList(_historyKey) ?? [];
      _startupResult = prefs.getString('bake_app_diagnostics_startup_result');
    });
  }

  Future<void> _armStartupCheck() async {
    await AppDiagnosticsScreen.armNextStartupCheck();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Запись включена только на следующий запуск. Перезапустите приложение; карта и ошибки будут измерены один раз.')),
    );
  }

  Future<void> _loadCloudErrors() async {
    if (_loadingCloudErrors) return;
    setState(() {
      _loadingCloudErrors = true;
      _cloudErrorMessage = null;
    });
    try {
      final rows = await RoadReportSyncService.fetchDiagnosticReports();
      if (!mounted) return;
      setState(() => _cloudErrors = rows);
    } catch (error) {
      if (mounted) {
        setState(() => _cloudErrorMessage = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Облачный журнал недоступен: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingCloudErrors = false);
    }
  }

  void _clearCloudErrorPanels() {
    setState(() => _cloudErrors.clear());
  }

  Future<void> _runChecks() async {
    if (_checking) return;
    setState(() => _checking = true);
    final now = DateTime.now();
    final results = <_CheckResult>[];

    Future<void> check(String name, Future<({ _CheckState state, String details })> Function() action) async {
      try {
        final value = await action();
        results.add(_CheckResult(name, value.state, value.details, now));
      } catch (error) {
        results.add(_CheckResult(name, _CheckState.error, error.toString(), now));
        await AppDiagnosticsScreen.recordRuntimeError('Проверка: $name', error);
      }
    }

    await check('Запуск приложения и открытие карты', () async {
      final prefs = await SharedPreferences.getInstance();
      final result = prefs.getString('bake_app_diagnostics_startup_result');
      if (result == null) {
        return (state: _CheckState.warning, details: 'Нет замера. Нажмите «Записать следующий запуск» и перезапустите приложение.');
      }
      if (result.startsWith('MAP_READY:')) {
        final ms = int.tryParse(result.substring('MAP_READY:'.length)) ?? 0;
        return ms > 10000
            ? (state: _CheckState.warning, details: 'Карта открылась за ${(ms / 1000).toStringAsFixed(1)} с — медленно.')
            : (state: _CheckState.ok, details: 'Первый кадр карты готов за ${(ms / 1000).toStringAsFixed(1)} с.');
      }
      return (state: _CheckState.error, details: result.replaceFirst('STARTUP_ERROR:', '').replaceFirst('MAP_TIMEOUT:', ''));
    });

    await check('GPS и разрешение геолокации', () async {
      final enabled = await Geolocator.isLocationServiceEnabled();
      final permission = await Geolocator.checkPermission();
      if (!enabled) return (state: _CheckState.error, details: 'Служба геолокации Android выключена.');
      if (permission == LocationPermission.deniedForever) {
        return (state: _CheckState.error, details: 'Доступ к геолокации запрещён навсегда.');
      }
      if (permission == LocationPermission.denied) {
        return (state: _CheckState.warning, details: 'Разрешение геолокации не выдано.');
      }
      return (state: _CheckState.ok, details: 'Геолокация включена; разрешение: $permission. Поток GPS не запускался.');
    });

    await check('Поиск адресов и офлайн-индекс', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final hasIndex = manifest.listAssets().contains('assets/data/shymkent_search.json.gz');
      return hasIndex
          ? (state: _CheckState.ok, details: 'Файл офлайн-индекса найден в ресурсах приложения. Запросы поиска не выполнялись.')
          : (state: _CheckState.error, details: 'Офлайн-индекс адресов отсутствует в ресурсах сборки.');
    });

    await check('Маршрутизация Valhalla', () async {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('valhalla_tile_extract_path');
      if (path == null || path.isEmpty) {
        return (state: _CheckState.warning, details: 'Офлайн-граф не подключён; интернет-маршрут не запускался.');
      }
      final file = File(path);
      if (!await file.exists()) {
        return (state: _CheckState.error, details: 'Путь к офлайн-графу сохранён, но файл отсутствует: $path');
      }
      final size = await file.length();
      return size >= 100000
          ? (state: _CheckState.ok, details: 'Файл дорожного графа найден ($size байт). Построение маршрута не запускалось.')
          : (state: _CheckState.error, details: 'Файл дорожного графа слишком мал: $size байт.');
    });

    await check('Карта и офлайн MBTiles', () async {
      final prefs = await SharedPreferences.getInstance();
      final path = prefs.getString('offline_map_path');
      if (path == null || path.isEmpty) {
        return (state: _CheckState.warning, details: 'Офлайн-карта не подключена. Онлайн-карта не загружалась в рамках проверки.');
      }
      final file = File(path);
      if (!await file.exists()) {
        return (state: _CheckState.error, details: 'Сохранённый файл MBTiles не найден: $path');
      }
      final size = await file.length();
      return size > 100000
          ? (state: _CheckState.ok, details: 'Файл MBTiles найден ($size байт). Рендер карты не перезапускался.')
          : (state: _CheckState.error, details: 'Файл MBTiles подозрительно мал: $size байт.');
    });

    await check('Системный голос TTS', () async {
      final tts = FlutterTts();
      final languages = await tts.getLanguages;
      final values = languages is List ? languages.map((value) => value.toString()).toList() : <String>[];
      if (values.isEmpty) {
        return (state: _CheckState.warning, details: 'Системный движок не вернул список языков.');
      }
      final supported = ['ru-RU', 'kk-KZ', 'en-US'].where(
        (language) => values.any((value) => value.toLowerCase().replaceAll('_', '-').startsWith(language.substring(0, 2).toLowerCase())),
      ).toList();
      return supported.isEmpty
          ? (state: _CheckState.warning, details: 'Движок найден, но ru/kk/en не обнаружены. Доступно: ${values.take(8).join(', ')}')
          : (state: _CheckState.ok, details: 'Движок отвечает. Языки: ${supported.join(', ')}. Озвучивание не запускалось.');
    });

    await check('Камеры и дорожные данные', () async {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final bundledAssets = manifest.listAssets();
      const assets = [
        'assets/data/kazakhstan_speed_cameras.csv',
        'assets/data/shymkent_camera_candidates.csv',
        'assets/data/shymkent_cameras.json',
      ];
      final missing = assets.where((asset) => !bundledAssets.contains(asset)).toList();
      return missing.isEmpty
          ? (state: _CheckState.ok, details: 'Файлы данных камер присутствуют в сборке. Камера устройства и актуальность внешних данных не проверялись.')
          : (state: _CheckState.error, details: 'Не найдены ресурсы: ${missing.join(', ')}');
    });

    await check('Хранилище приложения', () async {
      final directory = await getApplicationSupportDirectory();
      final probe = File('${directory.path}/.bake_diagnostics_probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return (state: _CheckState.ok, details: 'Внутренняя папка приложения доступна для чтения и записи.');
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'bake_app_diagnostics_last_results',
      jsonEncode(results.map((result) => result.toJson()).toList()),
    );
    final history = prefs.getStringList(_historyKey) ?? [];
    final errors = results.where((result) => result.state == _CheckState.error).toList();
    final warnings = results.where((result) => result.state == _CheckState.warning).toList();
    if (errors.isNotEmpty || warnings.isNotEmpty) {
      history.add('${now.toIso8601String()} | Ошибок: ${errors.length}, предупреждений: ${warnings.length}');
      await prefs.setStringList(_historyKey, history.length > 100 ? history.sublist(history.length - 100) : history);
    }
    if (!mounted) return;
    setState(() {
      _results
        ..clear()
        ..addAll(results);
      _history = prefs.getStringList(_historyKey) ?? [];
      _lastRun = now;
      _checking = false;
    });
  }

  Future<void> _deleteHistoryEntry(int displayIndex) async {
    final originalIndex = _history.length - 1 - displayIndex;
    if (originalIndex < 0 || originalIndex >= _history.length) return;
    final updated = List<String>.from(_history)..removeAt(originalIndex);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, updated);
    if (!mounted) return;
    setState(() => _history = updated);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Очистить журнал ошибок?'),
        content: const Text('Будут удалены локальная история ошибок, результаты последней проверки и очередь старых диагностических событий на телефоне. Записи в облачной базе не удаляются.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Очистить')),
        ],
      ),
    );
    if (confirmed != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyKey);
    await prefs.remove('bake_app_diagnostics_last_results');
    await RoadReportSyncService.clearPendingDiagnosticEvents();
    if (!mounted) return;
    setState(() {
      _history = [];
      _results.clear();
      _lastRun = null;
    });
  }

  Future<void> _exportReport() async {
    final report = StringBuffer('BAKE Navigator — диагностика приложения\n');
    report.writeln('Дата: ${_lastRun?.toIso8601String() ?? '—'}');
    for (final result in _results) {
      report.writeln('\n${result.name}: ${_stateLabel(result.state)}');
      report.writeln(result.details);
    }
    report.writeln('\nИстория ошибок (локальный журнал):');
    for (final item in _history) {
      report.writeln(item);
    }
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/bake_app_diagnostics.txt');
    await file.writeAsString(report.toString(), flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Отчёт диагностики BAKE Navigator');
  }

  String _stateLabel(_CheckState state) => switch (state) {
    _CheckState.ok => 'Работает',
    _CheckState.warning => 'Предупреждение',
    _CheckState.error => 'Ошибка',
    _CheckState.notChecked => 'Не проверялось',
  };

  Color _stateColor(_CheckState state) => switch (state) {
    _CheckState.ok => Colors.green.shade700,
    _CheckState.warning => Colors.orange.shade800,
    _CheckState.error => Colors.red.shade700,
    _CheckState.notChecked => Colors.blueGrey,
  };

  IconData _stateIcon(_CheckState state) => switch (state) {
    _CheckState.ok => Icons.check_circle_outline,
    _CheckState.warning => Icons.warning_amber_rounded,
    _CheckState.error => Icons.error_outline,
    _CheckState.notChecked => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Кабинет диагностики'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.health_and_safety_outlined), text: 'Проверка'),
              Tab(icon: Icon(Icons.route_outlined), text: 'Поездка'),
              Tab(icon: Icon(Icons.error_outline), text: 'Ошибки'),
              Tab(icon: Icon(Icons.cloud_outlined), text: 'Облако'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildChecksTab(),
            _buildGpsTab(),
            _buildErrorsTab(),
            _buildCloudTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildChecksTab() {
    final errors = _results.where((result) => result.state == _CheckState.error).length;
    final warnings = _results.where((result) => result.state == _CheckState.warning).length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Проверки запускаются только вручную. При открытии кабинета проверки и сетевые запросы не выполняются.'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Запуск и белый экран', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text('Одноразовый замер следующего запуска: время до появления карты и ошибка отображения.'),
                if (_startupResult != null) ...[
                  const SizedBox(height: 8),
                  SelectableText('Последний результат: $_startupResult'),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _armStartupCheck,
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('Записать следующий запуск'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _checking ? null : _runChecks,
            icon: _checking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(_checking ? 'Проверяем…' : 'Проверить всё'),
          ),
        ),
        if (_lastRun != null) ...[
          const SizedBox(height: 8),
          Text('Последняя проверка: ${_lastRun!.toLocal()}'),
          Text('Ошибок: $errors · Предупреждений: $warnings'),
        ],
        const SizedBox(height: 12),
        if (_results.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Проверка ещё не запускалась.'),
            ),
          )
        else
          ..._results.map((result) => Card(
            child: ListTile(
              leading: Icon(_stateIcon(result.state), color: _stateColor(result.state)),
              title: Text(result.name),
              subtitle: Text('${_stateLabel(result.state)} · ${result.details}'),
              isThreeLine: true,
            ),
          )),
      ],
    );
  }

  Widget _buildGpsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        Text('Запись GPS начинается только после нажатия кнопки. Кабинет не запускает GPS-поток при открытии.'),
        SizedBox(height: 12),
        TripDiagnosticsPanel(),
      ],
    );
  }

  Widget _buildErrorsTab() {
    final visibleHistory = _history.reversed.take(100).toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Локальные записи ошибок', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              tooltip: 'Очистить всю историю',
              onPressed: _history.isEmpty && _results.isEmpty ? null : _clearHistory,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
            IconButton(
              tooltip: 'Экспорт отчёта',
              onPressed: _results.isEmpty && _history.isEmpty ? null : _exportReport,
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ),
        const Text('Записи хранятся только на этом телефоне. Удаление не затрагивает облачные данные и дорожные отметки.'),
        const SizedBox(height: 8),
        if (visibleHistory.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Локальных записей пока нет.'),
            ),
          )
        else
          ...visibleHistory.asMap().entries.map((entry) => Card(
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 20),
              title: SelectableText(entry.value, style: const TextStyle(fontSize: 12)),
              trailing: IconButton(
                tooltip: 'Удалить эту запись',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteHistoryEntry(entry.key),
              ),
            ),
          )),
      ],
    );
  }

  Widget _buildCloudTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Облачный журнал не подключается при запуске приложения и не проверяется кнопкой «Проверить всё». Подключение и загрузка — только вручную.'),
        const SizedBox(height: 8),
        const Text('Публичный ключ приложения не должен получать административное чтение. Если доступ закрыт политиками базы, экран покажет отказ; публичные права базы не расширяются.'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: Text('Загружено записей: ${_cloudErrors.length}')),
            TextButton.icon(
              onPressed: _cloudErrors.isEmpty ? null : _clearCloudErrorPanels,
              icon: const Icon(Icons.clear_all),
              label: const Text('Очистить экран'),
            ),
          ],
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _loadingCloudErrors ? null : _loadCloudErrors,
            icon: _loadingCloudErrors
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            label: Text(_loadingCloudErrors ? 'Подключаем…' : 'Подключить и загрузить ошибки'),
          ),
        ),
        if (_cloudErrorMessage != null) ...[
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SelectableText('Ошибка доступа к облачному журналу:\n$_cloudErrorMessage'),
            ),
          ),
        ],
        if (_cloudErrors.isEmpty && _cloudErrorMessage == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Облачные записи ещё не загружались.'),
          ),
        ..._cloudErrors.map((item) => Card(
          child: ListTile(
            title: Text('${item['category'] ?? 'Ошибка'} · ${item['platform'] ?? ''}'),
            subtitle: SelectableText('${item['message'] ?? ''}'),
            trailing: IconButton(
              tooltip: 'Скрыть на этом экране',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _cloudErrors.remove(item)),
            ),
          ),
        )),
        if (_cloudErrors.isNotEmpty)
          const Text('Очистка скрывает записи только на этом экране. Строки в облачной базе не удаляются.'),
      ],
    );
  }
}




class _TripDiagnosticsRecorder {
  _TripDiagnosticsRecorder._();
  static final instance = _TripDiagnosticsRecorder._();
  final revision = ValueNotifier<int>(0);
  StreamSubscription<Position>? _subscription;
  bool active = false;
  bool _loaded = false;
  DateTime? startedAt;
  Position? _previous;
  DateTime? _previousTime;
  final List<Map<String, Object?>> events = [];
  final List<Map<String, Object?>> points = [];
  final List<File> reportFiles = <File>[];
  String? lastReport;
  int _saveCounter = 0;
  DateTime? _lastSlowFrameEventAt;
  FlutterExceptionHandler? _previousFlutterErrorHandler;
  bool Function(Object, StackTrace)? _previousPlatformErrorHandler;
  FlutterExceptionHandler? _activeFlutterErrorHandler;
  bool Function(Object, StackTrace)? _activePlatformErrorHandler;

  void _installRuntimeErrorHooks() {
    _previousFlutterErrorHandler = FlutterError.onError;
    _activeFlutterErrorHandler = (details) {
      if (active) {
        unawaited(addEvent(
          'Ошибка Flutter',
          '${details.exception.runtimeType}: ${details.exception}',
        ));
      }
      final previous = _previousFlutterErrorHandler;
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
    };
    FlutterError.onError = _activeFlutterErrorHandler;

    _previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
    _activePlatformErrorHandler = (error, stack) {
      if (active) {
        unawaited(addEvent('Необработанная ошибка приложения',
            '${error.runtimeType}: $error'));
      }
      return _previousPlatformErrorHandler?.call(error, stack) ?? false;
    };
    PlatformDispatcher.instance.onError = _activePlatformErrorHandler;
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!active) return;
    for (final timing in timings) {
      final totalMs = (timing.buildDuration + timing.rasterDuration).inMilliseconds;
      final now = DateTime.now();
      if (totalMs >= 250 &&
          (_lastSlowFrameEventAt == null ||
              now.difference(_lastSlowFrameEventAt!) >= const Duration(seconds: 5))) {
        _lastSlowFrameEventAt = now;
        unawaited(addEvent(
          'Медленный кадр интерфейса',
          'Построение: ${timing.buildDuration.inMilliseconds} мс; отрисовка: ${timing.rasterDuration.inMilliseconds} мс; всего: $totalMs мс.',
        ));
      }
    }
  }

  void _removeRuntimeErrorHooks() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    if (identical(FlutterError.onError, _activeFlutterErrorHandler)) {
      FlutterError.onError = _previousFlutterErrorHandler;
    }
    if (identical(PlatformDispatcher.instance.onError, _activePlatformErrorHandler)) {
      PlatformDispatcher.instance.onError = _previousPlatformErrorHandler;
    }
    _previousFlutterErrorHandler = null;
    _previousPlatformErrorHandler = null;
    _activeFlutterErrorHandler = null;
    _activePlatformErrorHandler = null;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    lastReport = prefs.getString('bake_trip_diagnostics_last_report');
    final unfinishedSession = prefs.getString('bake_trip_diagnostics_session');
    if (unfinishedSession != null) {
      try {
        final decoded = jsonDecode(unfinishedSession);
        if (decoded is Map<String, dynamic>) {
          final started = DateTime.tryParse(decoded['startedAt']?.toString() ?? '') ?? DateTime.now();
          final ended = DateTime.now();
          final wasFinished = decoded['finished'] == true;
          final recoveredPoints = (decoded['points'] as List?) ?? const [];
          final recoveredEvents = (decoded['events'] as List?) ?? const [];
          final recoveredReport = StringBuffer('BAKE Navigator — ${wasFinished ? 'восстановленный отчёт поездки' : 'прерванная диагностика поездки'}\n');
          recoveredReport.writeln('Начало: ${started.toLocal()}');
          recoveredReport.writeln('Последняя запись: ${ended.toLocal()}');
          recoveredReport.writeln('GPS-точек: ${recoveredPoints.length}');
          recoveredReport.writeln('Событий: ${recoveredEvents.length}');
          if (!wasFinished) recoveredReport.writeln('Причина завершения: приложение было закрыто до нажатия кнопки остановки.');
          for (final item in recoveredEvents.whereType<Map>()) {
            recoveredReport.writeln('\n${item['time']} | ${item['title']}');
            recoveredReport.writeln(item['details']);
          }
          final archive = <String, Object?>{
            'startedAt': started.toIso8601String(),
            'endedAt': ended.toIso8601String(),
            'interrupted': !wasFinished,
            'pointCount': recoveredPoints.length,
            'eventCount': recoveredEvents.length,
            'report': recoveredReport.toString(),
            'points': recoveredPoints,
            'events': recoveredEvents,
          };
          final recoveryDirectory = await _reportsDirectory();
          final recoveredFile = File('${recoveryDirectory.path}/trip_${started.microsecondsSinceEpoch}.json');
          await recoveredFile.writeAsString(jsonEncode(archive), flush: true);
          lastReport = recoveredReport.toString();
          await prefs.setString('bake_trip_diagnostics_last_report', lastReport!);
          await prefs.remove('bake_trip_diagnostics_session');
        }
      } catch (_) {
        // Keep a damaged session for manual inspection rather than deleting it.
      }
    }
    final directory = await _reportsDirectory();
    if (await directory.exists()) {
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.split(Platform.pathSeparator).last.startsWith('trip_') &&
              file.path.endsWith('.json'))
          .toList();
      files.sort((left, right) => right.path.compareTo(left.path));
      reportFiles
        ..clear()
        ..addAll(files);
      if (reportFiles.isNotEmpty) {
        try {
          final decoded = jsonDecode(await reportFiles.first.readAsString());
          if (decoded is Map<String, dynamic> && decoded['report'] is String) {
            lastReport = decoded['report'] as String;
          }
        } catch (_) {
          // Keep the previous plain-text report if the newest archive is damaged.
        }
      }
    }
    revision.value++;
  }

  Future<Directory> _reportsDirectory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/bake_trip_diagnostics');
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  String reportTitle(File file) {
    final name = file.path.split(Platform.pathSeparator).last;
    final micros = int.tryParse(name.replaceFirst('trip_', '').replaceFirst('.json', ''));
    if (micros == null) return name;
    final date = DateTime.fromMicrosecondsSinceEpoch(micros).toLocal();
    return 'Поездка · ${date.toString().split('.').first}';
  }

  Future<int> get storageBytes async {
    var total = 0;
    for (final file in reportFiles) {
      try {
        total += await file.length();
      } catch (_) {}
    }
    return total;
  }

  Future<void> openReport(BuildContext context, File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      final report = decoded is Map<String, dynamic>
          ? (decoded['report']?.toString() ?? file.readAsStringSync())
          : file.readAsStringSync();
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Отчёт поездки'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(child: SelectableText(report)),
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(exportReport(file));
              },
              icon: const Icon(Icons.ios_share),
              label: const Text('Экспорт'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть отчёт: $error')),
      );
    }
  }

  Future<void> exportReport(File file) async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      final report = decoded is Map<String, dynamic>
          ? (decoded['report']?.toString() ?? file.readAsStringSync())
          : file.readAsStringSync();
      final directory = await getTemporaryDirectory();
      final name = file.path.split(Platform.pathSeparator).last.replaceAll('.json', '.txt');
      final exportFile = File('${directory.path}/$name');
      await exportFile.writeAsString(report, flush: true);
      await Share.shareXFiles([XFile(exportFile.path)], text: 'Отчёт диагностики поездки BAKE Navigator');
    } catch (_) {
      // Export errors must not affect the stored report.
    }
  }

  Future<void> deleteReport(BuildContext context, File file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить отчёт поездки?'),
        content: const Text('Будет удалён только выбранный локальный отчёт.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true) return;
    final wasLatest = reportFiles.isNotEmpty && reportFiles.first.path == file.path;
    await file.delete();
    reportFiles.remove(file);
    if (reportFiles.isEmpty) {
      lastReport = null;
    } else if (wasLatest) {
      try {
        final decoded = jsonDecode(await reportFiles.first.readAsString());
        lastReport = decoded is Map<String, dynamic> ? decoded['report']?.toString() : null;
      } catch (_) {
        lastReport = null;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    if (lastReport == null) {
      await prefs.remove('bake_trip_diagnostics_last_report');
    } else {
      await prefs.setString('bake_trip_diagnostics_last_report', lastReport!);
    }
    revision.value++;
  }

  Future<void> clearReports(BuildContext context) async {
    if (reportFiles.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить все отчёты поездок?'),
        content: const Text('Будут удалены все сохранённые локальные отчёты поездок.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить все')),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final file in List<File>.from(reportFiles)) {
      if (await file.exists()) await file.delete();
    }
    reportFiles.clear();
    lastReport = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bake_trip_diagnostics_last_report');
    revision.value++;
  }

  Future<void> start(BuildContext context) async {
    if (active) return;
    final enabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();
    if (!enabled) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Включите геолокацию Android, затем повторите запуск диагностики.')),
      );
      return;
    }
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(permission == LocationPermission.deniedForever
            ? 'Доступ к геолокации запрещён. Разрешите его в настройках Android.'
            : 'Разрешение на геолокацию не выдано.'),
      ));
      return;
    }
    startedAt = DateTime.now();
    _previous = null; _previousTime = null; events.clear(); points.clear(); _saveCounter = 0;
    active = true;
    _installRuntimeErrorHooks();
    revision.value++;
    try {
      _subscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 1),
      ).listen(_onPosition, onError: (Object error) => addEvent('Ошибка GPS-потока', error.toString()));
      await _saveSession();
    } catch (error) {
      await addEvent('Не удалось запустить запись', error.toString());
      await stop();
    }
  }

  Future<void> _onPosition(Position position) async {
    if (!active) return;
    final time = position.timestamp;
    final gap = _previousTime == null ? null : time.difference(_previousTime!).inMilliseconds / 1000.0;
    double? jump; double? calculatedSpeed;
    if (_previous != null && gap != null) {
      jump = Geolocator.distanceBetween(_previous!.latitude, _previous!.longitude, position.latitude, position.longitude);
      if (gap > 0) calculatedSpeed = jump / gap;
      if (gap > 10) await addEvent('Длинный перерыв GPS', 'Между фиксациями ${gap.toStringAsFixed(1)} с.');
      if (gap > 0 && gap <= 5 && jump > 100 && (calculatedSpeed ?? 0) > 45) {
        await addEvent('Возможный скачок GPS', 'Смещение ${jump.toStringAsFixed(1)} м за ${gap.toStringAsFixed(1)} с; расчётная скорость ${(calculatedSpeed! * 3.6).toStringAsFixed(0)} км/ч; точность ±${position.accuracy.toStringAsFixed(1)} м.');
      }
    }
    if (position.accuracy > 50) await addEvent('Низкая точность GPS', 'Точность ±${position.accuracy.toStringAsFixed(1)} м.');
    _previous = position; _previousTime = time;
    points.add({
      'time': time.toIso8601String(), 'lat': position.latitude, 'lon': position.longitude,
      'accuracy_m': position.accuracy, 'speed_mps': position.speed, 'heading': position.heading,
      'gap_s': gap, 'jump_m': jump, 'calculated_speed_mps': calculatedSpeed, 'mocked': position.isMocked,
    });
    if (points.length > 5000) points.removeAt(0);
    if (++_saveCounter >= 10) { _saveCounter = 0; await _saveSession(); }
    revision.value++;
  }

  Future<void> addEvent(String title, String details) async {
    if (!active) return;
    events.add({
      'time': DateTime.now().toIso8601String(), 'title': title, 'details': details,
      if (_previous != null) 'lat': _previous!.latitude,
      if (_previous != null) 'lon': _previous!.longitude,
    });
    await _saveSession();
    revision.value++;
  }

  Future<void> _saveSession({bool finished = false}) async {
    if (startedAt == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bake_trip_diagnostics_session', jsonEncode({
      'startedAt': startedAt!.toIso8601String(), 'updatedAt': DateTime.now().toIso8601String(),
      'finished': finished, 'points': points, 'events': events,
    }));
  }

  Future<void> stop() async {
    if (!active) return;
    active = false;
    _removeRuntimeErrorHooks();
    revision.value++;
    await _subscription?.cancel(); _subscription = null;
    final ended = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final errors = (prefs.getStringList('bake_app_diagnostics_history') ?? []).where((line) {
      final date = DateTime.tryParse(line.split(' | ').first);
      return date != null && startedAt != null && !date.isBefore(startedAt!);
    }).toList();
    final report = StringBuffer('BAKE Navigator — диагностика поездки\n');
    report.writeln('Начало: ${startedAt?.toLocal()}');
    report.writeln('Окончание: ${ended.toLocal()}');
    report.writeln('GPS-точек: ${points.length}');
    report.writeln('GPS-событий: ${events.length}');
    report.writeln('Ошибок приложения за поездку: ${errors.length}');
    for (final event in events) {
      report.writeln('\n${event['time']} | ${event['title']}');
      report.writeln(event['details']);
      if (event['lat'] != null) report.writeln('Координаты: ${event['lat']}, ${event['lon']}');
    }
    if (errors.isNotEmpty) {
      report.writeln('\nОшибки приложения:');
      for (final error in errors) { report.writeln(error); }
    }
    await _saveSession(finished: true);
    lastReport = report.toString();
    final archive = <String, Object?>{
      'startedAt': startedAt?.toIso8601String(),
      'endedAt': ended.toIso8601String(),
      'durationSeconds': startedAt == null ? 0 : ended.difference(startedAt!).inSeconds,
      'pointCount': points.length,
      'eventCount': events.length,
      'report': lastReport,
      'points': points,
      'events': events,
    };
    final directory = await _reportsDirectory();
    final file = File('${directory.path}/trip_${startedAt?.microsecondsSinceEpoch ?? ended.microsecondsSinceEpoch}.json');
    await file.writeAsString(jsonEncode(archive), flush: true);
    reportFiles.removeWhere((existing) => existing.path == file.path);
    reportFiles.insert(0, file);
    await prefs.remove('bake_trip_diagnostics_session');
    await prefs.setString('bake_trip_diagnostics_last_report', lastReport!);
    revision.value++;
  }

  Future<void> export() async {
    if (lastReport == null || lastReport!.isEmpty) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/bake_trip_diagnostics.txt');
    await file.writeAsString(lastReport!, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: 'Диагностика поездки BAKE Navigator');
  }
}

class TripDiagnosticsPanel extends StatelessWidget {
  const TripDiagnosticsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final recorder = _TripDiagnosticsRecorder.instance;
    recorder.load();
    return ValueListenableBuilder<int>(
      valueListenable: recorder.revision,
      builder: (context, revision, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(recorder.active ? Icons.fiber_manual_record : Icons.route_outlined,
                color: recorder.active ? Colors.red : Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text('Диагностика поездки', style: Theme.of(context).textTheme.titleMedium)),
              if (recorder.active) const Chip(label: Text('Запись')),
            ]),
            const SizedBox(height: 6),
            const Text('Запускается только вручную из кабинета. После выхода продолжает запись GPS и необработанных ошибок приложения; при остановке перехват ошибок и GPS-поток отключаются. Данные остаются на телефоне.'),
            if (recorder.active) Text('GPS-точек: ${recorder.points.length} · событий: ${recorder.events.length}'),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, child: FilledButton.icon(
              onPressed: recorder.active ? recorder.stop : () => recorder.start(context),
              icon: Icon(recorder.active ? Icons.stop : Icons.play_arrow),
              label: Text(recorder.active ? 'Завершить диагностику поездки' : 'Начать диагностику поездки'),
              style: recorder.active ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700) : null,
            )),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: FutureBuilder<int>(
                    future: recorder.storageBytes,
                    builder: (context, snapshot) => Text(
                      'Отчётов: ${recorder.reportFiles.length} · Занято: ${snapshot.hasData ? (snapshot.data! / 1024).toStringAsFixed(1) : '…'} КБ',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: recorder.reportFiles.isEmpty ? null : () => recorder.clearReports(context),
                  child: const Text('Удалить все'),
                ),
              ],
            ),
            if (recorder.reportFiles.isEmpty)
              const Text('Сохранённых поездок пока нет.')
            else
              ...recorder.reportFiles.map((file) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.description_outlined),
                title: Text(recorder.reportTitle(file)),
                subtitle: const Text('Локальный отчёт поездки'),
                onTap: () => recorder.openReport(context, file),
                trailing: IconButton(
                  tooltip: 'Удалить отчёт',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => recorder.deleteReport(context, file),
                ),
              )),
            if (recorder.lastReport != null) ...[
              const Divider(),
              Text(recorder.lastReport!, maxLines: 7, overflow: TextOverflow.ellipsis),
              Align(alignment: Alignment.centerRight, child: TextButton.icon(
                onPressed: recorder.export, icon: const Icon(Icons.ios_share), label: const Text('Экспорт последнего отчёта'),
              )),
            ],
          ]),
        ),
      ),
    );
  }
}