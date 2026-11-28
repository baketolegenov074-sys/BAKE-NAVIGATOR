import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local-only diagnostics for the Shymkent offline address search.
/// No network, Supabase, or user-enabled recording session is required.
class OfflineSearchDiagnostics {
  OfflineSearchDiagnostics._();

  static final OfflineSearchDiagnostics instance = OfflineSearchDiagnostics._();

  static const int _maxBytes = 2 * 1024 * 1024;
  static const String _fileName = 'offline_search.jsonl';

  final revision = ValueNotifier<int>(0);
  Future<void> _writeQueue = Future<void>.value();

  Future<Directory> _directory() async {
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/bake_offline_search_diagnostics');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<void> record(String event, {Map<String, Object?> details = const {}}) {
    final entry = <String, Object?>{
      'time': DateTime.now().toIso8601String(),
      'event': event,
      'details': details,
    };
    _writeQueue = _writeQueue.then((_) async {
      try {
        final directory = await _directory();
        final file = File('${directory.path}/$_fileName');
        if (await file.exists() && await file.length() >= _maxBytes) {
          final previous = File('${directory.path}/offline_search.previous.jsonl');
          if (await previous.exists()) await previous.delete();
          await file.rename(previous.path);
        }
        await file.writeAsString('${jsonEncode(entry)}\n', mode: FileMode.append, flush: true);
        revision.value++;
      } catch (_) {
        // Diagnostics must never interrupt address search or navigation.
      }
    });
    return _writeQueue;
  }

  Future<List<File>> listReports() async {
    try {
      final directory = await _directory();
      final files = <File>[
        File('${directory.path}/$_fileName'),
        File('${directory.path}/offline_search.previous.jsonl'),
      ].where((file) => file.existsSync()).toList();
      files.sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return <File>[];
    }
  }

  Future<String> readReport(File file) async {
    await _writeQueue;
    return file.readAsString();
  }

  Future<File?> exportReport() async {
    await _writeQueue;
    final files = await listReports();
    if (files.isEmpty) return null;
    final directory = await getTemporaryDirectory();
    final output = File('${directory.path}/bake_offline_search_diagnostics.txt');
    final buffer = StringBuffer('BAKE Navigator — локальная диагностика офлайн-поиска улиц\n');
    for (final file in files.reversed) {
      buffer.writeln('\n--- ${file.path.split(Platform.pathSeparator).last} ---');
      buffer.write(await file.readAsString());
    }
    await output.writeAsString(buffer.toString(), flush: true);
    return output;
  }

  Future<void> clear() async {
    await _writeQueue;
    final files = await listReports();
    for (final file in files) {
      try {
        await file.delete();
      } catch (_) {}
    }
    revision.value++;
  }
}
