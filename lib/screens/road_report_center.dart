import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/road_report_sync_service.dart';

/// Local-first road reports. Reports remain unverified until an administrator
/// reviews them. Supabase sync is enabled when build-time credentials are provided.
class RoadReportCenter extends StatelessWidget {
  const RoadReportCenter({super.key});

  static const _items = <_ReportType>[
    _ReportType('Камера скорости', Icons.camera_alt_outlined),
    _ReportType('Дорожный знак', Icons.signpost_outlined),
    _ReportType('Светофор', Icons.traffic_outlined),
    _ReportType('Пешеходный переход', Icons.directions_walk),
    _ReportType('Лежачий полицейский', Icons.speed),
    _ReportType('Опасный участок', Icons.warning_amber_rounded),
    _ReportType('Железнодорожный переезд', Icons.train_outlined),
    _ReportType('Запрещённый поворот', Icons.turn_left),
    _ReportType('Одностороннее движение', Icons.arrow_forward),
    _ReportType('Ремонт или перекрытие', Icons.construction),
    _ReportType('Школа или важное здание', Icons.school_outlined),
    _ReportType('Другой объект', Icons.add_location_alt_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(title: const Text('Дорожные отметки')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Что хотите отметить?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          const Text('Нажмите один раз на объект. BAKE запишет GPS-координаты, время, точность и направление.'),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3, crossAxisSpacing: 9, mainAxisSpacing: 9, childAspectRatio: 0.94,
            ),
            itemBuilder: (context, index) {
              final item = _items[index];
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _capture(context, item),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(item.icon, size: 30, color: const Color(0xFF303943)),
                        const SizedBox(height: 7),
                        Text(item.title, textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRoadMarksPage())),
            icon: const Icon(Icons.bookmarks_outlined),
            label: const Text('Мои дорожные отметки'),
          ),
        ],
      ),
    );
  }

  Future<void> _capture(BuildContext context, _ReportType type) async {
    final messenger = ScaffoldMessenger.of(context);
    void notify(SnackBar snackBar) {
      if (context.mounted) messenger.showSnackBar(snackBar);
    }
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        notify(const SnackBar(content: Text('Нет разрешения на GPS. Разрешите доступ к местоположению и повторите.')));
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        notify(const SnackBar(content: Text('GPS выключен. Включите геолокацию и повторите.')));
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (position.accuracy > 30) {
        notify(SnackBar(content: Text('GPS пока неточный: ±${position.accuracy.toStringAsFixed(0)} м. Подождите улучшения сигнала и повторите.')));
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList('bake_road_reports_v1') ?? <String>[];
      final now = DateTime.now();
      final duplicate = rows.any((raw) {
        try {
          final old = jsonDecode(raw) as Map<String, dynamic>;
          final sameType = old['type'] == type.title;
          final samePlace = ( (old['latitude'] as num? ?? 999).toDouble() - position.latitude).abs() < 0.00008 &&
              ( (old['longitude'] as num? ?? 999).toDouble() - position.longitude).abs() < 0.00008;
          final recent = now.difference(DateTime.tryParse(old['createdAt']?.toString() ?? '') ?? DateTime(2000)).inMinutes < 2;
          return sameType && samePlace && recent;
        } catch (_) { return false; }
      });
      if (duplicate) {
        notify(const SnackBar(content: Text('Такая отметка уже сохранена рядом.')));
        return;
      }
      final record = <String, dynamic>{
        'id': now.microsecondsSinceEpoch.toString(),
        'deviceId': await RoadReportSyncService.getDeviceId(),
        'type': type.title,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'headingDegrees': position.heading,
        'createdAt': now.toIso8601String(),
        'status': 'На проверке',
        if (type.title == 'Камера скорости') 'cameraOperationalStatus': 'Неизвестно',
        if (type.title == 'Ремонт или перекрытие') 'validUntil': null,
        'syncStatus': 'Ожидает подключения сервера',
      };
      rows.insert(0, jsonEncode(record));
      await prefs.setStringList('bake_road_reports_v1', rows);
      var uploaded = false;
      if (RoadReportSyncService.isInitialized) {
        try {
          await RoadReportSyncService.uploadReport(record);
          record['syncStatus'] = 'Синхронизировано';
          rows[0] = jsonEncode(record);
          await prefs.setStringList('bake_road_reports_v1', rows);
          uploaded = true;
        } catch (error) {
          // Keep the report locally. The navigator retries on resume and periodically.
          debugPrint('BAKE road report upload failed: ${error.runtimeType}');
        }
      }
      final configurationProblem = RoadReportSyncService.configurationProblem;
      notify(SnackBar(content: Text(uploaded
          ? 'Отметка «${type.title}» отправлена на общую проверку.'
          : configurationProblem != null
              ? 'Отметка сохранена на телефоне. Настройка сервера: $configurationProblem'
              : 'Отметка «${type.title}» сохранена на телефоне и ждёт связи с сервером.')));
    } catch (error) {
      notify(SnackBar(content: Text('Не удалось получить GPS или сохранить отметку: $error')));
    }
  }
}

class RoadToolsMenu extends StatelessWidget {
  const RoadToolsMenu({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Дорожные инструменты')),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      Card(child: ListTile(
        leading: const Icon(Icons.add_location_alt_outlined),
        title: const Text('Сообщить об объекте'),
        subtitle: const Text('Один тап — сохранить объект с GPS'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoadReportCenter())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.bookmarks_outlined),
        title: const Text('Мои дорожные отметки'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MyRoadMarksPage())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.edit_location_alt_outlined),
        title: const Text('Исправить адрес'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddressCorrectionPage())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.admin_panel_settings_outlined),
        title: const Text('Кабинет администратора'),
        subtitle: const Text('Локальный просмотр отметок на этом устройстве'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoadAdminPage())),
      )),
    ]),
  );
}

class _ReportType {
  final String title;
  final IconData icon;
  const _ReportType(this.title, this.icon);
}

class MyRoadMarksPage extends StatefulWidget {
  const MyRoadMarksPage({super.key});
  @override
  State<MyRoadMarksPage> createState() => _MyRoadMarksPageState();
}

class _MyRoadMarksPageState extends State<MyRoadMarksPage> {
  List<Map<String, dynamic>> _records = [];
  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList('bake_road_reports_v1') ?? [];
    if (!mounted) return;
    setState(() {
      _records = rows.map((raw) {
        try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); }
        catch (_) { return <String, dynamic>{}; }
      }).where((e) => e.isNotEmpty).toList();
    });
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить отметку?'),
        content: const Text('Эта отметка будет удалена только с этого телефона.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    _records.removeWhere((e) => e['id'] == id);
    await prefs.setStringList('bake_road_reports_v1', _records.map(jsonEncode).toList());
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мои дорожные отметки')),
    body: _records.isEmpty
      ? const Center(child: Text('Пока нет сохранённых отметок.'))
      : ListView.builder(
          padding: const EdgeInsets.all(12), itemCount: _records.length,
          itemBuilder: (context, index) {
            final r = _records[index];
            final date = DateTime.tryParse(r['createdAt']?.toString() ?? '')?.toLocal();
            return Card(child: ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(r['type']?.toString() ?? 'Объект'),
              subtitle: Text('${(r['latitude'] as num?)?.toStringAsFixed(6) ?? '—'}, ${(r['longitude'] as num?)?.toStringAsFixed(6) ?? '—'}\nGPS ±${(r['accuracyMeters'] as num?)?.toStringAsFixed(0) ?? '—'} м · ${date ?? 'время неизвестно'}\nСтатус: ${r['status'] ?? 'На проверке'}'),
              isThreeLine: true,
              trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(r['id']?.toString() ?? '')),
            ));
          },
        ),
  );
}

class AddressCorrectionPage extends StatefulWidget {
  const AddressCorrectionPage({super.key});
  @override
  State<AddressCorrectionPage> createState() => _AddressCorrectionPageState();
}

class _AddressCorrectionPageState extends State<AddressCorrectionPage> {
  final _addressController = TextEditingController();
  final _detailsController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _addressController.dispose();
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _saveCorrection() async {
    if (_addressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Укажите адрес или опишите, что нужно исправить.')));
      return;
    }
    setState(() => _saving = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever || !await Geolocator.isLocationServiceEnabled()) {
        throw Exception('Для привязки исправления включите GPS и разрешите доступ к местоположению.');
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (position.accuracy > 30) throw Exception('GPS пока неточный (±${position.accuracy.toStringAsFixed(0)} м). Повторите позже.');
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList('bake_address_corrections_v1') ?? <String>[];
      rows.insert(0, jsonEncode({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'address': _addressController.text.trim(),
        'details': _detailsController.text.trim(),
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'На проверке',
        'syncStatus': 'Ожидает подключения сервера',
      }));
      await prefs.setStringList('bake_address_corrections_v1', rows);
      if (!mounted) return;
      _addressController.clear();
      _detailsController.clear();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Исправление сохранено на телефоне. Отправка на сервер пока не подключена.')));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Исправить адрес')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Опишите ошибку адреса', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      TextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Адрес или название места', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      TextField(controller: _detailsController, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Что нужно исправить (необязательно)', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _saving ? null : _saveCorrection,
        icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
        label: Text(_saving ? 'Сохраняем…' : 'Сохранить с GPS'),
      ),
      const SizedBox(height: 8),
      const Text('Исправление сохранится локально с координатами и точностью GPS. Для отправки и общей модерации нужен сервер BAKE.', style: TextStyle(color: Colors.black54)),
    ]),
  );
}

class RoadAdminPage extends StatefulWidget {
  const RoadAdminPage({super.key});
  @override
  State<RoadAdminPage> createState() => _RoadAdminPageState();
}

class _RoadAdminPageState extends State<RoadAdminPage> {
  List<Map<String, dynamic>> _records = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    try {
      final rows = await RoadReportSyncService.fetchAllReportsForAdmin();
      if (!mounted) return;
      setState(() {
        _records = rows;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось загрузить отметки: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Дорожные отметки'),
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _loading ? null : _loadReports,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(_error!, textAlign: TextAlign.center),
                ))
              : _records.isEmpty
                  ? const Center(child: Text('Общих отметок пока нет.'))
                  : ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        Text('Всего отметок: ${_records.length}'),
                        const SizedBox(height: 8),
                        ..._records.map((record) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.location_on_outlined),
                                title: Text(record['type']?.toString() ?? 'Объект'),
                                subtitle: Text(
                                  '${record['latitude']}, ${record['longitude']}'
                                  ' · ±${record['accuracyMeters']} м'
                                  '\nСтатус: ${record['status']}'
                                  '\nУстройство: ${record['deviceId'] ?? '—'}',
                                ),
                                isThreeLine: true,
                              ),
                            )),
                      ],
                    ),
    );
  }
}
