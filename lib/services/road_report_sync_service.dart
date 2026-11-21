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

  static Map<String, dynamic> _toDatabase(Map<String, dynamic> report) {
    final createdAt = DateTime.tryParse(report['createdAt']?.toString() ?? '');
    return <String, dynamic>{
      'id': report['id'].toString(),
      'device_id': report['deviceId'].toString(),
      'type': report['type'].toString(),
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
        'latitude': row['latitude'],
        'longitude': row['longitude'],
        'accuracyMeters': row['accuracy_meters'],
        'headingDegrees': row['heading_degrees'],
        'createdAt': row['created_at'],
        'status': row['status'],
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
      if (error.code == '23505') return;
      rethrow;
    }
  }

  static Future<List<Map<String, dynamic>>> fetchConfirmedReports() async {
    if (!_initialized) return <Map<String, dynamic>>[];
    final rows = await _client
        .from('road_reports')
        .select()
        .eq('status', 'approved')
        .order('created_at', ascending: false);
    return rows.map((row) => _fromDatabase(row)).toList();
  }

  static void _requireAdmin() {
    final user = _client.auth.currentUser;
    if (user == null || user.appMetadata['role'] != 'admin') {
      throw StateError('Вход администратора не выполнен. Нужна учётная запись Supabase Auth с app_metadata.role = admin.');
    }
  }

  static Future<void> updateReportStatus(String id, String status) async {
    if (status != 'approved' && status != 'rejected') {
      throw ArgumentError.value(status, 'status', 'Недопустимый статус');
    }
    _requireAdmin();
    await _client.from('road_reports').update({'status': status}).eq('id', id);
  }

  static Future<void> deleteReport(String id) async {
    _requireAdmin();
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
