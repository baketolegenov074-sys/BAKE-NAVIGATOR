import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter/scheduler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Local-only diagnostics for map cold-start and app-resume latency.
/// This recorder never requests permissions and never performs network calls.
class MapStartupDiagnostics {
  MapStartupDiagnostics._();

  static final MapStartupDiagnostics instance = MapStartupDiagnostics._();

  final List<Map<String, Object?>> _events = <Map<String, Object?>>[];
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  DateTime? _startedAt;
  Stopwatch? _stopwatch;
  Timer? _finishTimer;
  bool _active = false;
  int _slowFrames = 0;
  int _maxFrameMs = 0;
  DateTime? _lastSlowFrameEventAt;
  String? _reportBaseName;
  Future<void> _writeQueue = Future<void>.value();

  bool get active => _active;

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/bake_map_startup_diagnostics');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> beginSession(
    String trigger, {
    bool mapAlreadyMounted = false,
  }) async {
    if (_active) await finish();
    _finishTimer?.cancel();
    _events.clear();
    _startedAt = DateTime.now();
    _stopwatch = Stopwatch()..start();
    _slowFrames = 0;
    _maxFrameMs = 0;
    _lastSlowFrameEventAt = null;
    _reportBaseName = 'map_startup_${_startedAt!.microsecondsSinceEpoch}';
    _active = true;
    _add('НАЧАЛО СЕССИИ', trigger);
    if (mapAlreadyMounted) {
      _add('КАРТА УЖЕ БЫЛА ОТКРЫТА', 'После возврата приложение использует ранее созданный виджет карты; измеряется первый кадр после возврата.');
    }
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
    _finishTimer = Timer(const Duration(seconds: 45), () {
      unawaited(finish());
    });
    await _persistJson();
  }

  void markFirstFrame() {
    if (!_active) return;
    _add('ПЕРВЫЙ КАДР ПОСЛЕ ВХОДА', 'Время от начала сессии: ${_elapsedMs} мс.');
  }

  void markMapReady(int elapsedMs) {
    if (!_active) return;
    _add('КАРТА СООБЩИЛА О ГОТОВНОСТИ', 'Время от начала холодного запуска: $elapsedMs мс. Это сигнал готовности виджета карты, не гарантия полной загрузки всех подписей и тайлов.');
  }

  void recordStage(String name, String details) {
    if (!_active) return;
    _add(name, details);
  }

  void recordError(String source, Object error, [StackTrace? stack]) {
    if (!_active) return;
    _add('ОШИБКА: $source', '${error.runtimeType}: $error${stack == null ? '' : '\n$stack'}');
  }

  void markBackground(String state) {
    if (!_active) return;
    _add('ПРИЛОЖЕНИЕ УШЛО В ФОН', 'Состояние Android/Flutter: $state.');
    unawaited(finish());
  }

  int get _elapsedMs => _stopwatch?.elapsedMilliseconds ?? 0;

  void _add(String title, String details) {
    if (!_active) return;
    _events.add(<String, Object?>{
      'time': DateTime.now().toIso8601String(),
      'elapsed_ms': _elapsedMs,
      'title': title,
      'details': details,
    });
    revision.value++;
    unawaited(_persistJson());
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_active) return;
    for (final timing in timings) {
      final total = (timing.buildDuration + timing.rasterDuration).inMilliseconds;
      if (total > _maxFrameMs) _maxFrameMs = total;
      if (total >= 100) {
        _slowFrames++;
        final now = DateTime.now();
        if (_lastSlowFrameEventAt == null ||
            now.difference(_lastSlowFrameEventAt!) >= const Duration(seconds: 3)) {
          _lastSlowFrameEventAt = now;
          _add(
            'ЗАМЕДЛЕННЫЙ КАДР',
            'Построение: ${timing.buildDuration.inMilliseconds} мс; отрисовка: ${timing.rasterDuration.inMilliseconds} мс; суммарно: $total мс.',
          );
        }
      }
    }
  }

  Map<String, Object?> _archive({required bool finished}) => <String, Object?>{
    'type': 'map_startup_diagnostics',
    'started_at': _startedAt?.toIso8601String(),
    'finished_at': finished ? DateTime.now().toIso8601String() : null,
    'duration_ms': _elapsedMs,
    'finished': finished,
    'slow_frame_count': _slowFrames,
    'max_frame_ms': _maxFrameMs,
    'events': List<Map<String, Object?>>.from(_events),
  };

  Future<void> _persistJson() async {
    final base = _reportBaseName;
    if (base == null || _startedAt == null) return;
    final snapshot = jsonEncode(_archive(finished: false));
    _writeQueue = _writeQueue.then((_) async {
      final directory = await _directory();
      await File('${directory.path}/$base.json').writeAsString(snapshot, flush: true);
    }).catchError((Object error) {
      // Diagnostic storage must never interrupt map rendering.
    });
    await _writeQueue;
  }

  Future<void> finish() async {
    if (!_active) return;
    _active = false;
    _finishTimer?.cancel();
    _finishTimer = null;
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _stopwatch?.stop();
    final base = _reportBaseName;
    if (base == null) return;
    final archive = _archive(finished: true);
    final jsonText = jsonEncode(archive);
    final text = _formatReport(archive);
    _writeQueue = _writeQueue.then((_) async {
      final directory = await _directory();
      await File('${directory.path}/$base.json').writeAsString(jsonText, flush: true);
      await File('${directory.path}/$base.txt').writeAsString(text, flush: true);
    }).catchError((Object error) {});
    await _writeQueue;
    revision.value++;
  }

  String _formatReport(Map<String, Object?> archive) {
    final out = StringBuffer('BAKE Navigator — диагностика запуска карты\n');
    out.writeln('Начало: ${archive['started_at']}');
    out.writeln('Окончание: ${archive['finished_at'] ?? 'запись прервана'}');
    out.writeln('Длительность наблюдения: ${archive['duration_ms']} мс');
    out.writeln('Медленных кадров (от 100 мс): ${archive['slow_frame_count']}');
    out.writeln('Максимальный кадр: ${archive['max_frame_ms']} мс');
    out.writeln('\nСОБЫТИЯ:');
    for (final item in (_events)) {
      out.writeln('\n+${item['elapsed_ms']} мс | ${item['title']}');
      out.writeln(item['details']);
    }
    out.writeln('\nПримечание: готовность виджета карты не означает, что все тайлы и подписи уже загружены.');
    return out.toString();
  }

  Future<List<File>> listReports() async {
    final directory = await _directory();
    if (!await directory.exists()) return <File>[];
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.txt'))
        .toList()
      ..sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  Future<void> deleteAllReports() async {
    final directory = await _directory();
    if (await directory.exists()) {
      await for (final entity in directory.list()) {
        if (entity is File) await entity.delete();
      }
    }
    revision.value++;
  }

  Future<void> exportReport(File file) async {
    if (!await file.exists()) return;
    // Share Plus handles the native Android share sheet.
    await Share.shareXFiles([XFile(file.path)], text: 'Диагностика запуска карты BAKE Navigator');
  }
}

