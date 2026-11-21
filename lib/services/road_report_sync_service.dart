import 'package:supabase_flutter/supabase_flutter.dart';

/// Optional cloud sync for community road reports.
/// Configure with --dart-define=SUPABASE_URL=... and SUPABASE_ANON_KEY=...
class RoadReportSyncService {
  RoadReportSyncService._();

  static const String _url = String.fromEnvironment('SUPABASE_URL');
  static const String _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool _initialized = false;
  static RealtimeChannel? _reportsChannel;

  static bool get isConfigured => _url.isNotEmpty && _anonKey.isNotEmpty;
  static bool get isInitialized => _initialized;

  static Future<void> initialize() async {
    if (!isConfigured || _initialized) return;
    await Supabase.initialize(url: _url, anonKey: _anonKey);
    _initialized = true;
    await ensureSession();
  }

  static SupabaseClient get _client {
    if (!_initialized) {
      throw StateError('Supabase is not configured for this build.');
    }
    return Supabase.instance.client;
  }

  static Future<void> ensureSession() async {
    if (!_initialized) return;
    if (_client.auth.currentSession == null) {
      await _client.auth.signInAnonymously();
    }
  }

  static Map<String, dynamic> _toDatabase(Map<String, dynamic> report) {
    final createdAt = DateTime.tryParse(report['createdAt']?.toString() ?? '');
    return <String, dynamic>{
      'id': report['id'].toString(),
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

  static Future<void> uploadReport(Map<String, dynamic> report) async {
    if (!_initialized) return;
    await ensureSession();
    await _client.from('road_reports').upsert(
      _toDatabase(report),
      onConflict: 'id',
      ignoreDuplicates: true,
    );
  }

  static Future<List<Map<String, dynamic>>> fetchConfirmedReports() async {
    if (!_initialized) return <Map<String, dynamic>>[];
    await ensureSession();
    final rows = await _client
        .from('road_reports')
        .select()
        .eq('status', 'Подтверждено')
        .order('created_at', ascending: false);
    return rows.map((row) => _fromDatabase(row)).toList();
  }

  static Future<List<Map<String, dynamic>>> fetchAllReportsForAdmin() async {
    if (!_initialized) throw StateError('Облачная синхронизация не настроена.');
    final rows = await _client
        .from('road_reports')
        .select()
        .order('created_at', ascending: false);
    return rows.map((row) => _fromDatabase(row)).toList();
  }

  static Future<bool> hasAdminAccess() async {
    if (!_initialized || _client.auth.currentUser == null) return false;
    final userId = _client.auth.currentUser!.id;
    final row = await _client
        .from('road_admins')
        .select('user_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row != null;
  }

  static Future<void> signInAdmin(String email, String password) async {
    if (!_initialized) throw StateError('Сервер не настроен в этой версии приложения.');
    await _client.auth.signInWithPassword(email: email.trim(), password: password);
    if (!await hasAdminAccess()) {
      await _client.auth.signOut();
      await ensureSession();
      throw StateError('У этой учётной записи нет прав администратора BAKE.');
    }
  }

  static Future<void> signOutAdmin() async {
    if (!_initialized) return;
    await _client.auth.signOut();
    await ensureSession();
  }

  static Future<void> setReportStatus(String id, String status) async {
    if (!_initialized) throw StateError('Сервер не настроен.');
    final userId = _client.auth.currentUser?.id;
    await _client.from('road_reports').update({
      'status': status,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
      'reviewed_by': userId,
    }).eq('id', id);
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
