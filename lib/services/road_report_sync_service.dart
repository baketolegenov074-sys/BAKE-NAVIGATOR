import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Local-first road reports with public Supabase REST access.
/// SUPABASE_ANON_KEY may contain the project's Supabase Publishable key.
class RoadReportSyncService {
  RoadReportSyncService._();

  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _publishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool _initialized = false;
  static bool _diagnosticFlushInProgress = false;
  static bool adminModeActive = false;
  static const String _diagnosticQueueKey = 'bake_app_error_queue_v1';
  static RealtimeChannel? _reportsChannel;

  static const String _expectedProjectRef = 'cnyshqvdonqhkkcqgucf';

  static String? get configurationProblem {
    if (_url.trim().isEmpty) return 'SUPABASE_URL is missing from this APK.';
    if (_publishableKey.trim().isEmpty) {
      return 'SUPABASE_ANON_KEY is missing from this APK.';
    }
    final uri = Uri.tryParse(_url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'SUPABASE_URL must be a valid HTTPS project URL.';
    }
    final expectedHost = '$_expectedProjectRef.supabase.co';
    if (uri.host.toLowerCase() != expectedHost) {
      return 'SUPABASE_URL points to ${uri.host}; expected $expectedHost.';
    }
    return null;
  }

  static String get configurationSummary {
    final uri = Uri.tryParse(_url.trim());
    final host = uri?.host.isNotEmpty == true ? uri!.host : 'missing-or-invalid';
    return 'host=$host, publishable_key_present=${_publishableKey.trim().isNotEmpty}';
  }

  static bool get isConfigured => configurationProblem == null;
  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (_initialized) return;
    final problem = configurationProblem;
    if (problem != null) throw StateError(problem);
    debugPrint('BAKE Supabase configuration: $configurationSummary');
    await Supabase.initialize(url: _url.trim(), anonKey: _publishableKey.trim());
    _initialized = true;
  }

  /// Performs a read-only connectivity check against the same table used by the admin cabinet.
  static Future<String> checkConnection() async {
    final problem = configurationProblem;
    if (problem != null) throw StateError(problem);
    if (!_initialized) await initialize();
    await _client.from('road_reports').select('id').limit(1);
    return 'Подключение подтверждено: чтение таблицы road_reports успешно.';
  }

  /// Fetches cloud error reports only after an explicit user action.
  static Future<List<Map<String, dynamic>>> fetchDiagnosticReports() async {
    if (!_initialized) await initialize();
    final rows = await _client.from('app_error_reports').select()
        .order('created_at', ascending: false).limit(100);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  /// Clears only the pending local diagnostic upload queue. Cloud rows are untouched.
  static Future<void> clearPendingDiagnosticEvents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_diagnosticQueueKey);
  }

  static SupabaseClient get _client {
    if (!_initialized) {
      throw StateError('Supabase is not configured for this build.');
    }
    return Supabase.instance.client;
  }

  /// Stable random identifier stored only on this device.
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('bake_road_device_id_v1');
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    final id = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
    await prefs.setString('bake_road_device_id_v1', id);
    return id;
  }

  static String _truncateDiagnosticText(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);

  static String _sanitizeDiagnosticText(String value) {
    return value
        .replaceAll(RegExp(r'https?://[^\s]+'), '[url]')
        .replaceAll(
          RegExp(r'-?\d{1,2}\.\d{4,}\s*[,;]\s*-?\d{1,3}\.\d{4,}'),
          '[coordinates]',
        )
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  /// Stores app diagnostics locally first, then uploads when Supabase is online.
  /// Raw GPS coordinates, addresses, routes and search queries are never sent.
  static Future<void> recordDiagnosticEvent({
    required String category,
    required String message,
    String? stackTrace,
    Map<String, dynamic>? details,
  }) async {
    try {
      final safeDetails = <String, dynamic>{};
      for (final entry in (details ?? const <String, dynamic>{}).entries) {
        if (RegExp(r'(lat|lon|coord|address|route|query|destination)', caseSensitive: false)
            .hasMatch(entry.key)) {
          continue;
        }
        final value = entry.value;
        if (value == null || value is num || value is bool) {
          safeDetails[entry.key] = value;
        } else if (value is String) {
          safeDetails[entry.key] = _truncateDiagnosticText(_sanitizeDiagnosticText(value), 300);
        }
      }

      final now = DateTime.now().toUtc();
      final id = '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
      final record = <String, dynamic>{
        'id': id,
        'app_version': '1.0.0+1',
        'platform': Platform.operatingSystem,
        'category': category,
        'message': _truncateDiagnosticText(_sanitizeDiagnosticText(message), 4000),
        if (stackTrace != null && stackTrace.isNotEmpty)
          'stack_trace': _truncateDiagnosticText(_sanitizeDiagnosticText(stackTrace), 10000),
        'details': safeDetails,
      };

      final prefs = await SharedPreferences.getInstance();
      final queue = prefs.getStringList(_diagnosticQueueKey) ?? <String>[];
      queue.add(jsonEncode(record));
      if (queue.length > 100) {
        queue.removeRange(0, queue.length - 100);
      }
      await prefs.setStringList(_diagnosticQueueKey, queue);

      // Diagnostic events are never uploaded automatically. Any future upload must be explicit.
    } catch (error) {
      debugPrint('BAKE diagnostic event could not be queued: ${error.runtimeType}');
    }
  }

  /// Uploads queued diagnostics in the background. Failed records stay on-device.
  static Future<void> flushPendingDiagnosticEvents() async {
    if (!_initialized || _diagnosticFlushInProgress) return;
    _diagnosticFlushInProgress = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final queued = prefs.getStringList(_diagnosticQueueKey) ?? <String>[];
      if (queued.isEmpty) return;

      final sentIds = <String>{};
      for (final raw in queued.take(20)) {
        try {
          final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          await _client.from('app_error_reports').insert(record);
          sentIds.add(record['id'].toString());
        } on PostgrestException catch (error) {
          if (error.code == '23505') {
            // The report already exists in Supabase; remove the local duplicate.
            try {
              final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
              sentIds.add(record['id'].toString());
            } catch (_) {}
            continue;
          }
          break;
        } catch (_) {
          break;
        }
      }

      if (sentIds.isNotEmpty) {
        // Re-read to avoid overwriting events queued while this upload was running.
        final latest = prefs.getStringList(_diagnosticQueueKey) ?? <String>[];
        final remaining = <String>[];
        for (final raw in latest) {
          try {
            final record = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            if (!sentIds.contains(record['id']?.toString())) remaining.add(raw);
          } catch (_) {
            // Drop only malformed local queue entries.
          }
        }
        await prefs.setStringList(_diagnosticQueueKey, remaining);
      }
    } catch (error) {
      debugPrint('BAKE diagnostic upload deferred: ${error.runtimeType}');
    } finally {
      _diagnosticFlushInProgress = false;
    }
  }

  static Map<String, dynamic> _toDatabase(Map<String, dynamic> report) {
    final createdAt = DateTime.tryParse(report['createdAt']?.toString() ?? '');
    return <String, dynamic>{
      'id': report['id'].toString(),
      'device_id': report['deviceId'].toString(),
      'type': report['type'].toString(),
      if (report['title'] != null) 'title': report['title'],
      if (report['address'] != null) 'address': report['address'],
      if (report['comment'] != null) 'comment': report['comment'],
      'latitude': (report['latitude'] as num).toDouble(),
      'longitude': (report['longitude'] as num).toDouble(),
      'accuracy_meters': (report['accuracyMeters'] as num?)?.toDouble(),
      'heading_degrees': (report['headingDegrees'] as num?)?.toDouble(),
      'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      if (report['cameraOperationalStatus'] != null)
        'camera_operational_status': report['cameraOperationalStatus'],
      if (report['validUntil'] != null) 'valid_until': report['validUntil'],
      'status': 'На проверке',
    };
  }

  static Map<String, dynamic> _fromDatabase(Map<String, dynamic> row) =>
      <String, dynamic>{
        'id': row['id'],
        'deviceId': row['device_id'],
        'type': row['type'],
        'title': row['title'],
        'address': row['address'],
        'comment': row['comment'],
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'accuracyMeters': row['accuracy_meters'],
        'headingDegrees': row['heading_degrees'],
        'createdAt': row['created_at'],
        'status': row['status'] == 'approved' ? 'Подтверждено' : row['status'] == 'rejected' ? 'Отклонено' : row['status'],
        if (row['camera_operational_status'] != null)
          'cameraOperationalStatus': row['camera_operational_status'],
        if (row['valid_until'] != null) 'validUntil': row['valid_until'],
        'syncStatus': 'Синхронизировано',
      };

  /// Submit a new report to the shared Supabase table.
  static Future<void> uploadReport(Map<String, dynamic> report) async {
    if (!_initialized) {
      throw StateError(configurationProblem ?? 'Supabase has not initialized.');
    }
    final payload = Map<String, dynamic>.from(report);
    payload['deviceId'] ??= await getDeviceId();
    try {
      await _client.from('road_reports').insert(_toDatabase(payload));
    } on PostgrestException catch (error) {
      // A retry of an already uploaded local report is considered successful.
      if (error.code != '23505') rethrow;
    }
    if (adminModeActive) {
      await _client.from('road_reports').update({
        'status': 'approved',
        'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', payload['id'].toString());
    }
  }

  static Future<List<Map<String, dynamic>>> fetchConfirmedReports() async {
    if (!_initialized) return <Map<String, dynamic>>[];
    final rows = await _client.from('road_reports').select()
        .inFilter('status', ['approved', 'Подтверждено'])
        .order('created_at', ascending: false);
    return rows.map((row) => _fromDatabase(row)).toList();
  }

  static Future<List<Map<String, dynamic>>> searchConfirmedReports(String query) async {
    if (!_initialized || query.trim().isEmpty) return <Map<String, dynamic>>[];
    final rows = await _client.from('road_reports').select()
        .inFilter('status', ['approved', 'Подтверждено'])
        .order('created_at', ascending: false).limit(500);
    final needle = query.trim().toLowerCase();
    return rows.where((row) => [row['title'], row['address'], row['comment'], row['type']]
        .whereType<Object>().any((value) => value.toString().toLowerCase().contains(needle)))
        .map((row) => _fromDatabase(row)).toList();
  }

  static Future<void> updateReportDetails({
    required String id, required String title, required String address,
    required String comment, required double latitude, required double longitude,
  }) async {
    await _client.from('road_reports').update({
      'title': title, 'address': address, 'comment': comment,
      'latitude': latitude, 'longitude': longitude,
    }).eq('id', id);
  }

  /// Public moderation requests use the project's publishable/anon key.
  /// No Supabase Auth session or administrator account is used by this app.
  static Future<void> updateReportStatus(String id, String status) async {
    if (status != 'Подтверждено' && status != 'Отклонено') {
      throw ArgumentError.value(status, 'status', 'Недопустимый статус');
    }
    await _client.from('road_reports').update({
      'status': status,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  static Future<void> deleteReport(String id) async {
    await _client.from('road_reports').delete().eq('id', id);
  }

  /// List road reports for the admin screen.
  static Future<List<Map<String, dynamic>>> fetchAllReportsForAdmin() async {
    if (!_initialized) throw StateError('Облачная синхронизация не настроена.');
    final rows = await _client
        .from('road_reports')
        .select()
        .order('created_at', ascending: false);
    return rows.map((row) => _fromDatabase(row)).toList();
  }

  static void subscribeToChanges(void Function() onChanged) {
    if (!_initialized) return;
    _reportsChannel ??= _client
        .channel('bake-road-reports-live')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'road_reports',
          callback: (_) => onChanged(),
        )
      ..subscribe();
  }
}
