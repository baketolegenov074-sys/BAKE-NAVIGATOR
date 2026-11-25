import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    setState(() => _history = prefs.getStringList(_historyKey) ?? []);
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
      final manifest = await rootBundle.loadString('AssetManifest.json');
      final hasIndex = manifest.contains('assets/data/shymkent_search.json.gz');
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
      final manifest = await rootBundle.loadString('AssetManifest.json');
      const assets = [
        'assets/data/kazakhstan_speed_cameras.csv',
        'assets/data/shymkent_camera_candidates.csv',
        'assets/data/shymkent_cameras.json',
      ];
      final missing = assets.where((asset) => !manifest.contains(asset)).toList();
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

    // Network/Supabase and live route/search calls are intentionally not run
    // as part of this safe batch: they need explicit active tests.
    results.add(_CheckResult(
      'Supabase и интернет-сервисы',
      _CheckState.notChecked,
      'Не проверялись: сетевые запросы и отправка данных не выполнялись.',
      now,
    ));

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
    final errors = _results.where((result) => result.state == _CheckState.error).length;
    final warnings = _results.where((result) => result.state == _CheckState.warning).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Диагностика приложения')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Проверка запускается только вручную. Автоматических проверок при открытии приложения нет.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _checking ? null : _runChecks,
            icon: _checking
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(_checking ? 'Проверяем…' : 'Проверить всё'),
          ),
          if (_lastRun != null) ...[
            const SizedBox(height: 8),
            Text('Последняя проверка: ${_lastRun!.toLocal()}'),
            Text('Ошибок: $errors · Предупреждений: $warnings'),
          ],
          const SizedBox(height: 12),
          if (_results.isEmpty)
            const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Проверка ещё не запускалась.')))
          else
            ..._results.map((result) => Card(
              child: ListTile(
                leading: Icon(_stateIcon(result.state), color: _stateColor(result.state)),
                title: Text(result.name),
                subtitle: Text('${_stateLabel(result.state)} · ${result.details}'),
                isThreeLine: true,
              ),
            )),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('История ошибок', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: _results.isEmpty && _history.isEmpty ? null : _exportReport,
                icon: const Icon(Icons.ios_share),
                label: const Text('Экспорт'),
              ),
            ],
          ),
          if (_history.isEmpty)
            const Text('Записей пока нет.')
          else
            ..._history.reversed.take(30).map((item) => ListTile(
              dense: true,
              leading: const Icon(Icons.history, size: 18),
              title: Text(item, style: const TextStyle(fontSize: 12)),
            )),
        ],
      ),
    );
  }
}
