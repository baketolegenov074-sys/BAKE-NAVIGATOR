import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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

  Future<String> _downloadAndExtractModel() async {
    final modelDir = await _modelDirectory();
    if (await isInstalled) return modelDir;

    final support = await getApplicationSupportDirectory();
    final archiveFile = File('${support.path}/$_kazakhModelName.tar.bz2');
    final client = http.Client();
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(_kazakhModelUrl)))
          .timeout(const Duration(minutes: 5));
      if (response.statusCode != 200) {
        throw Exception('Не удалось загрузить казахский голос (HTTP ${response.statusCode}).');
      }

      final sink = archiveFile.openWrite();
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      final compressed = await archiveFile.readAsBytes();
      final tarBytes = BZip2Decoder().decodeBytes(compressed);
      final tarArchive = TarDecoder().decodeBytes(tarBytes);
      for (final entry in tarArchive.files) {
        if (!entry.isFile) continue;
        final relative = entry.name.replaceAll('\\\\', '/');
        if (relative.startsWith('/') || relative.split('/').contains('..')) {
          continue;
        }
        final output = File('${support.path}/$relative');
        await output.parent.create(recursive: true);
        await output.writeAsBytes(entry.content as List<int>, flush: false);
      }

      if (!await isInstalled) {
        throw Exception('Архив загрузился, но файлы казахского голоса неполные.');
      }
      return modelDir;
    } finally {
      client.close();
      if (await archiveFile.exists()) await archiveFile.delete();
    }
  }

  Future<void> ensureReady() async {
    if (_starting != null) return _starting!;
    _starting = _start();
    try {
      await _starting;
    } catch (_) {
      _starting = null;
      rethrow;
    }
  }

  Future<void> _start() async {
    final modelDir = await _downloadAndExtractModel();
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
              completer.completeError(Exception('Не удалось создать аудио казахского голоса.'));
            }
          }
        }
      }
    });

    _isolate = await Isolate.spawn(_kazakhTtsWorker, receivePort.sendPort);
    await _ready!.future.timeout(const Duration(minutes: 3));
  }

  Future<void> speak({
    required String text,
    required int speakerId,
    double speed = 1.0,
  }) async {
    await ensureReady();
    final id = _requestId++;
    final temp = await getTemporaryDirectory();
    final wavPath = '${temp.path}/bake_kazakh_voice_$id.wav';
    final completer = Completer<void>();
    _pending[id] = completer;
    _workerPort!.send({
      'command': 'speak',
      'id': id,
      'text': text,
      'speakerId': speakerId.clamp(0, 5),
      'speed': speed,
      'wavPath': wavPath,
    });
    await completer.future.timeout(const Duration(seconds: 45));
    await _player.stop();
    final completed = _player.onPlayerComplete.first;
    await _player.play(DeviceFileSource(wavPath));
    try {
      await completed.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Do not block the next navigation event if Android delays completion.
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

  receivePort.listen((message) {
    if (message is! Map) return;
    final command = message['command'];
    if (command == 'init') {
      try {
        sherpa.initBindings();
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
          maxNumSentences: 1,
        );
        engine = sherpa.OfflineTts(config);
        mainPort.send({'type': 'ready', 'speakers': engine!.numSpeakers});
      } catch (error) {
        mainPort.send({'type': 'error', 'message': error.toString()});
      }
    } else if (command == 'speak' && engine != null) {
      final id = message['id'] as int;
      try {
        final audio = engine!.generateWithConfig(
          text: message['text'] as String,
          config: sherpa.OfflineTtsGenerationConfig(
            sid: message['speakerId'] as int,
            speed: (message['speed'] as num).toDouble(),
            silenceScale: 0.2,
          ),
        );
        final ok = sherpa.writeWave(
          filename: message['wavPath'] as String,
          samples: audio.samples,
          sampleRate: audio.sampleRate,
        );
        mainPort.send({'type': 'done', 'id': id, 'ok': ok});
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
