import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const String _kazakhModelName = 'vits-piper-kk_KZ-issai-high';
const String _kazakhModelUrl =
    'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/vits-piper-kk_KZ-issai-high.tar.bz2';

/// Offline Kazakh ISSAI voice pack. The 6-speaker model is downloaded once,
/// stored in app-private storage, and then works without an internet connection.
class KazakhVoiceOption {
  const KazakhVoiceOption({
    required this.id,
    required this.label,
    required this.gender,
  });

  final int id;
  final String label;
  final String gender;
}


// Synchronous worker-isolate implementation. Keeping the compressed and
// decompressed buffers off the UI isolate prevents the settings sheet from
// freezing while the 123 MB ISSAI archive is expanded.
String _extractArchiveInBackground({
  required String archivePath,
  required String stagingPath,
  required String modelPath,
}) {
  final staging = Directory(stagingPath);
  final modelDir = Directory(modelPath);
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);

  try {
    final compressed = File(archivePath).readAsBytesSync();
    final tarBytes = BZip2Decoder().decodeBytes(compressed);
    final tarArchive = TarDecoder().decodeBytes(tarBytes);

    for (final entry in tarArchive.files) {
      final relative = entry.name.replaceAll(String.fromCharCode(92), '/');
      if (relative.isEmpty || relative.startsWith('/') ||
          relative.split('/').contains('..')) {
        throw Exception('Архив ішінде жарамсыз файл жолы бар.');
      }
      final output = File('${staging.path}/$relative');
      if (entry.isFile) {
        output.parent.createSync(recursive: true);
        output.writeAsBytesSync(entry.content as List<int>, flush: false);
      } else {
        Directory(output.path).createSync(recursive: true);
      }
    }

    Directory? modelRoot;
    for (final entity in staging.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('/kk_KZ-issai-high.onnx')) continue;
      final candidate = entity.parent;
      if (File('${candidate.path}/tokens.txt').existsSync() &&
          Directory('${candidate.path}/espeak-ng-data').existsSync()) {
        modelRoot = candidate;
        break;
      }
    }
    if (modelRoot == null) {
      throw Exception('Архив ашылды, бірақ kk_KZ-issai-high.onnx, tokens.txt немесе espeak-ng-data табылмады. Толық ISSAI .tar.bz2 архивін таңдаңыз.');
    }

    if (modelDir.existsSync()) modelDir.deleteSync(recursive: true);
    modelDir.createSync(recursive: true);
    for (final entity in modelRoot.listSync(recursive: false, followLinks: false)) {
      final name = entity.uri.pathSegments.where((part) => part.isNotEmpty).last;
      final target = '${modelDir.path}/$name';
      if (entity is Directory) {
        entity.renameSync(target);
      } else if (entity is File) {
        entity.renameSync(target);
      }
    }

    if (!File('${modelDir.path}/kk_KZ-issai-high.onnx').existsSync() ||
        !File('${modelDir.path}/tokens.txt').existsSync() ||
        !Directory('${modelDir.path}/espeak-ng-data').existsSync()) {
      throw Exception('ISSAI моделі толық орнатылмады: негізгі файлдар табылған жоқ.');
    }
    return modelDir.path;
  } catch (_) {
    if (modelDir.existsSync() &&
        (!File('${modelDir.path}/kk_KZ-issai-high.onnx').existsSync() ||
         !File('${modelDir.path}/tokens.txt').existsSync() ||
         !Directory('${modelDir.path}/espeak-ng-data').existsSync())) {
      modelDir.deleteSync(recursive: true);
    }
    rethrow;
  } finally {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
  }
}

class KazakhVoiceService {
  static const List<KazakhVoiceOption> voices = [
    KazakhVoiceOption(id: 0, label: 'Мужской · ISSAI M2', gender: 'Мужской'),
    KazakhVoiceOption(id: 1, label: 'Мужской · Iseke', gender: 'Мужской'),
    KazakhVoiceOption(id: 2, label: 'Женский · ISSAI F3', gender: 'Женский'),
    KazakhVoiceOption(id: 3, label: 'Женский · Raya', gender: 'Женский'),
    KazakhVoiceOption(id: 4, label: 'Женский · ISSAI F1', gender: 'Женский'),
    KazakhVoiceOption(id: 5, label: 'Женский · ISSAI F2', gender: 'Женский'),
  ];

  final AudioPlayer _player = AudioPlayer();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 15),
    sendTimeout: const Duration(minutes: 2),
    followRedirects: true,
    maxRedirects: 8,
  ));
  final Map<int, Completer<void>> _pending = {};
  ReceivePort? _receivePort;
  Isolate? _isolate;
  SendPort? _workerPort;
  Completer<void>? _ready;
  Future<void>? _starting;
  int _requestId = 0;

  Future<String> _modelDirectory() async {
    final support = await getApplicationSupportDirectory();
    return '${support.path}/$_kazakhModelName';
  }

  Future<bool> get isInstalled async {
    final dir = await _modelDirectory();
    return await File('$dir/kk_KZ-issai-high.onnx').exists() &&
        await File('$dir/tokens.txt').exists() &&
        await Directory('$dir/espeak-ng-data').exists();
  }

  Future<String> _extractArchive(File archiveFile) async {
    final support = await getApplicationSupportDirectory();
    final modelPath = await _modelDirectory();
    final stagingPath = '${support.path}/${_kazakhModelName}_extracting';

    // BZip2/TAR decoding is CPU- and memory-intensive. Run it in a worker
    // isolate so the Android UI thread remains responsive during extraction.
    return Isolate.run(() => _extractArchiveInBackground(
      archivePath: archiveFile.path,
      stagingPath: stagingPath,
      modelPath: modelPath,
    ));
  }

  Future<String?> importModelArchive() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['bz2'],
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final picked = result.files.single;
    final path = picked.path;
    if (path == null) {
      throw Exception('Файлға қол жеткізу мүмкін болмады. Оны телефонның Download бумасынан таңдаңыз.');
    }
    final archiveFile = File(path);
    if (!await archiveFile.exists()) {
      throw Exception('Таңдалған архив табылмады. Файлды қайта таңдаңыз.');
    }
    if (!picked.name.toLowerCase().endsWith('.tar.bz2')) {
      throw Exception('Тек толық .tar.bz2 архивін таңдаңыз.');
    }
    if (await archiveFile.length() < 1024) {
      throw Exception('Архив бос немесе толық жүктелмеген.');
    }
    return _extractArchive(archiveFile);
  }

  Future<String> _downloadAndExtractModel({
    void Function(int received, int total)? onProgress,
    void Function(String stage)? onStage,
  }) async {
    final modelDir = await _modelDirectory();
    if (await isInstalled) return modelDir;

    final support = await getApplicationSupportDirectory();
    final partial = File('${support.path}/$_kazakhModelName.tar.bz2.part');
    final archiveFile = File('${support.path}/$_kazakhModelName.tar.bz2');

    // Reuse a previously completed archive. A failed TTS initialization must
    // never force the user to download the 129 MB package again.
    if (await archiveFile.exists() && await archiveFile.length() > 1024) {
      onStage?.call('extracting');
      return _extractArchive(archiveFile);
    }

    for (var attempt = 0; attempt < 5; attempt++) {
      var offset = await partial.exists() ? await partial.length() : 0;
      try {
        final response = await _dio.download(
          _kazakhModelUrl,
          partial.path,
          options: Options(
            headers: offset > 0 ? {'Range': 'bytes=$offset-'} : <String, dynamic>{},
            validateStatus: (status) => status == 200 || status == 206,
          ),
          fileAccessMode: offset > 0 ? FileAccessMode.append : FileAccessMode.write,
          deleteOnError: false,
          onReceiveProgress: (received, total) {
            final fullTotal = total > 0 ? total + offset : -1;
            onProgress?.call(offset + received, fullTotal);
          },
        );

        if (offset > 0 && response.statusCode == 200) {
          // The server ignored Range; the response was appended, so restart cleanly.
          await partial.delete();
          if (attempt == 4) {
            throw Exception('Сервер не қолдайды жалғастырып жүктеуді.');
          }
          continue;
        }
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw Exception('Жүктеу серверінен қате жауап алынды.');
        }

        if (await archiveFile.exists()) await archiveFile.delete();
        await partial.rename(archiveFile.path);
        // Keep the completed archive if extraction or model validation fails.
        // The next retry can inspect/re-extract it without another network download.
        onStage?.call('extracting');
        return await _extractArchive(archiveFile);
      } catch (error) {
        if (attempt == 4) {
          if (error is DioException) {
            throw Exception('Жүктеу үзілді, интернетті тексеріңіз.');
          }
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 2 << attempt));
      }
    }
    throw Exception('Жүктеу үзілді, интернетті тексеріңіз.');
  }

  Future<void> ensureReady({
    void Function(int received, int total)? onProgress,
    void Function(String stage)? onStage,
  }) async {
    if (_starting != null) return _starting!;
    _starting = _start(onProgress: onProgress, onStage: onStage);
    try {
      await _starting;
    } catch (_) {
      _starting = null;
      rethrow;
    }
  }

  Future<void> _start({
    void Function(int received, int total)? onProgress,
    void Function(String stage)? onStage,
  }) async {
    final modelDir = await _downloadAndExtractModel(onProgress: onProgress, onStage: onStage);
    onStage?.call('initializing');
    final receivePort = ReceivePort();
    _receivePort = receivePort;
    _ready = Completer<void>();

    receivePort.listen((message) {
      if (message is SendPort) {
        _workerPort = message;
        message.send({'command': 'init', 'modelDir': modelDir});
        return;
      }
      if (message is! Map) return;
      final type = message['type'];
      if (type == 'ready') {
        if (!(_ready?.isCompleted ?? true)) _ready!.complete();
      } else if (type == 'error') {
        final error = Exception(message['message']?.toString() ?? 'Ошибка голосового движка.');
        if (!(_ready?.isCompleted ?? true)) _ready!.completeError(error);
        final id = message['id'];
        if (id is int) {
          final completer = _pending.remove(id);
          if (completer != null && !completer.isCompleted) completer.completeError(error);
        }
      } else if (type == 'done') {
        final id = message['id'];
        if (id is int) {
          final completer = _pending.remove(id);
          if (completer != null && !completer.isCompleted) {
            if (message['ok'] == true) {
              completer.complete();
            } else {
              final details = message['message']?.toString();
              completer.completeError(
                Exception(details?.isNotEmpty == true
                    ? details
                    : 'Не удалось создать аудио казахского голоса.'),
              );
            }
          }
        }
      }
    });

    try {
      _isolate = await Isolate.spawn(_kazakhTtsWorker, receivePort.sendPort);
      await _ready!.future.timeout(const Duration(minutes: 3));
    } catch (error) {
      // A failed native model initialization must not leave a dead worker
      // and ReceivePort behind. Otherwise the next test can appear to do nothing.
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _workerPort = null;
      _receivePort?.close();
      _receivePort = null;
      _ready = null;
      rethrow;
    }
  }

  Future<void> speak({
    required String text,
    required int speakerId,
    double speed = 1.0,
    void Function(int received, int total)? onDownloadProgress,
    void Function(String stage)? onStage,
  }) async {
    await ensureReady(onProgress: onDownloadProgress, onStage: onStage);
    final worker = _workerPort;
    if (worker == null) {
      throw Exception('Казахский голосовой движок не запустился: нет связи с аудиомодулем.');
    }

    final id = _requestId++;
    final temp = await getTemporaryDirectory();
    final wavPath = '${temp.path}/bake_kazakh_voice_$id.wav';
    final wavFile = File(wavPath);
    final completer = Completer<void>();
    _pending[id] = completer;
    try {
      worker.send({
        'command': 'speak',
        'id': id,
        'text': text,
        'speakerId': speakerId.clamp(0, 5).toInt(),
        'speed': speed,
        'wavPath': wavPath,
      });

      await completer.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('Казахский голос не успел создать аудио за 45 секунд.'),
      );

      if (!await wavFile.exists()) {
        throw Exception('Голосовой движок сообщил об успехе, но аудиофайл не создан.');
      }
      final audioBytes = await wavFile.length();
      if (audioBytes <= 44) {
        throw Exception('Создан пустой или повреждённый аудиофайл ($audioBytes байт).');
      }

      await _player.stop();
      final completed = _player.onPlayerComplete.first;
      try {
        await _player.play(DeviceFileSource(wavPath));
      } catch (error) {
        throw Exception('Аудио создано ($audioBytes байт), но Android не смог его воспроизвести: $error');
      }
      try {
        await completed.timeout(const Duration(seconds: 30));
      } on TimeoutException {
        // Android may not report completion reliably; stop playback before cleanup.
        await _player.stop();
        throw TimeoutException('Аудиофайл создан, но воспроизведение не подтвердилось за 30 секунд.');
      }
    } finally {
      _pending.remove(id);
      if (await wavFile.exists()) {
        await wavFile.delete();
      }
    }
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    _workerPort?.send({'command': 'dispose'});
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(StateError('Voice service disposed'));
    }
    _pending.clear();
    await _player.dispose();
  }
}

void _kazakhTtsWorker(SendPort mainPort) {
  final receivePort = ReceivePort();
  mainPort.send(receivePort.sendPort);
  sherpa.OfflineTts? engine;

  receivePort.listen((message) async {
    if (message is! Map) return;
    final command = message['command'];
    if (command == 'init') {
      try {
        // Initialize FFI asynchronously inside the worker isolate before creating native objects.
        await sherpa.initBindingsAsync();
        final dir = message['modelDir'] as String;
        final config = sherpa.OfflineTtsConfig(
          model: sherpa.OfflineTtsModelConfig(
            vits: sherpa.OfflineTtsVitsModelConfig(
              model: '$dir/kk_KZ-issai-high.onnx',
              tokens: '$dir/tokens.txt',
              dataDir: '$dir/espeak-ng-data',
            ),
            numThreads: 2,
            debug: false,
          ),
          maxNumSentences: 2,
        );
        engine = sherpa.OfflineTts(config);
        mainPort.send({'type': 'ready', 'speakers': engine!.numSpeakers});
      } catch (error) {
        mainPort.send({'type': 'error', 'message': error.toString()});
      }
    } else if (command == 'speak' && engine != null) {
      final id = message['id'] as int;
      try {
        // Use the simple, documented VITS generation API. It passes speaker ID
        // and speed directly and avoids the advanced config FFI path.
        final audio = engine!.generate(
          text: message['text'] as String,
          sid: message['speakerId'] as int,
          speed: (message['speed'] as num).toDouble(),
        );
        final samples = audio.samples;
        final sampleRate = audio.sampleRate;
        final speakerCount = engine!.numSpeakers;
        var peakAmplitude = 0.0;
        for (final sample in samples) {
          final amplitude = sample.abs();
          if (amplitude > peakAmplitude) peakAmplitude = amplitude;
        }

        // Check generated samples, not only whether a WAV header was written.
        if (samples.isEmpty || sampleRate <= 0 || peakAmplitude == 0.0) {
          mainPort.send({
            'type': 'done',
            'id': id,
            'ok': false,
            'message':
                'Диагностика TTS: пустой или нулевой звук. '
                'Отсчётов: ${samples.length}; частота: $sampleRate Гц; '
                'пиковый уровень: $peakAmplitude; голосов модели: $speakerCount.',
          });
          return;
        }

        final ok = sherpa.writeWave(
          filename: message['wavPath'] as String,
          samples: samples,
          sampleRate: sampleRate,
        );
        mainPort.send({
          'type': 'done',
          'id': id,
          'ok': ok,
          'message': ok
              ? 'Создано отсчётов: ${samples.length}; частота: $sampleRate Гц; '
                  'пиковый уровень: $peakAmplitude; голосов модели: $speakerCount.'
              : 'Sherpa-ONNX не смог записать WAV. Отсчётов: ${samples.length}; '
                  'частота: $sampleRate Гц; пиковый уровень: $peakAmplitude; '
                  'голосов модели: $speakerCount.',
        });
      } catch (error) {
        mainPort.send({'type': 'error', 'id': id, 'message': error.toString()});
      }
    } else if (command == 'dispose') {
      engine?.free();
      engine = null;
      receivePort.close();
    }
  });
}
