import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Local-first road reports. Reports remain unverified until an administrator
/// reviews them. No server endpoint is configured in this app yet.
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
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        messenger.showSnackBar(const SnackBar(content: Text('Нет разрешения на GPS. Разрешите доступ к местоположению и повторите.')));
        return;
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        messenger.showSnackBar(const SnackBar(content: Text('GPS выключен. Включите геолокацию и повторите.')));
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      if (position.accuracy > 30) {
        messenger.showSnackBar(SnackBar(content: Text('GPS пока неточный: ±${position.accuracy.toStringAsFixed(0)} м. Подождите улучшения сигнала и повторите.')));
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
        messenger.showSnackBar(const SnackBar(content: Text('Такая отметка уже сохранена рядом.')));
        return;
      }
      final record = <String, dynamic>{
        'id': now.microsecondsSinceEpoch.toString(),
        'type': type.title,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracyMeters': position.accuracy,
        'headingDegrees': position.heading,
        'createdAt': now.toIso8601String(),
        'status': 'На проверке',
        'syncStatus': 'Ожидает подключения сервера',
      };
      rows.insert(0, jsonEncode(record));
      await prefs.setStringList('bake_road_reports_v1', rows);
      messenger.showSnackBar(SnackBar(content: Text('Отметка «${type.title}» сохранена на телефоне.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Не удалось получить GPS или сохранить отметку: $error')));
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

class AddressCorrectionPage extends StatelessWidget {
  const AddressCorrectionPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Исправить адрес')),
    body: const Padding(
      padding: EdgeInsets.all(20),
      child: Text('Выберите точку на карте и подготовьте сообщение об ошибке адреса. Отправка и проверка адресов появятся после подключения серверной службы.'),
    ),
  );
}

class RoadAdminPage extends StatefulWidget {
  const RoadAdminPage({super.key});
  @override
  State<RoadAdminPage> createState() => _RoadAdminPageState();
}

class _RoadAdminPageState extends State<RoadAdminPage> {
  List<Map<String, dynamic>> _records = [];
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList('bake_road_reports_v1') ?? [];
    if (!mounted) return;
    setState(() => _records = rows.map((e) {
      try { return Map<String, dynamic>.from(jsonDecode(e) as Map); } catch (_) { return <String, dynamic>{}; }
    }).where((e) => e.isNotEmpty).toList());
  }
  Future<void> _setStatus(Map<String, dynamic> record, String status) async {
    final prefs = await SharedPreferences.getInstance();
    record['status'] = status;
    await prefs.setStringList('bake_road_reports_v1', _records.map(jsonEncode).toList());
    if (mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Кабинет администратора')),
    body: ListView(padding: const EdgeInsets.all(12), children: [
      const Card(child: Padding(padding: EdgeInsets.all(12), child: Text('Локальный просмотр на этом телефоне. Защищённый вход и общий сервер модерации ещё не подключены. Не используйте этот экран как удалённую админ-панель.'))),
      if (_records.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('Новых отметок нет.')),
      ..._records.map((r) => Card(child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(r['type']?.toString() ?? 'Объект', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text('${r['latitude']}, ${r['longitude']} · ±${r['accuracyMeters']} м'),
          Text('Текущий статус: ${r['status']}'),
          Wrap(spacing: 8, children: [
            TextButton(onPressed: () => _setStatus(r, 'Подтверждено'), child: const Text('Подтвердить')),
            TextButton(onPressed: () => _setStatus(r, 'Отклонено'), child: const Text('Отклонить')),
            TextButton(onPressed: () => _setStatus(r, 'На проверке'), child: const Text('На проверке')),
          ]),
        ]),
      ))),
    ]),
  );
}
