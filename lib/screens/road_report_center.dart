import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/road_report_sync_service.dart';

/// Road reports are stored locally first and synchronized with the shared Supabase table.
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
      body: SafeArea(
        top: false,
        child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                        Text(item.title, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, height: 1.1, fontWeight: FontWeight.w700)),
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
        subtitle: const Text('Просмотр отметок из общей базы Supabase'),
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
    body: SafeArea(
      top: false,
      child: _records.isEmpty
        ? const Center(child: Text('Пока нет сохранённых отметок.'))
        : ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24), itemCount: _records.length,
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
    ),
  );
}


class MapPointPickerPage extends StatefulWidget {
  const MapPointPickerPage({super.key, required this.initialPoint});
  final LatLng initialPoint;
  static Future<LatLng?> pick(BuildContext context, {required LatLng initialPoint}) =>
      Navigator.of(context).push<LatLng>(MaterialPageRoute(builder: (_) => MapPointPickerPage(initialPoint: initialPoint)));
  @override State<MapPointPickerPage> createState() => _MapPointPickerPageState();
}
class _MapPointPickerPageState extends State<MapPointPickerPage> {
  late LatLng _center = widget.initialPoint;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Уточнить точку на карте')),
    body: Stack(children: [
      FlutterMap(options: MapOptions(initialCenter: widget.initialPoint, initialZoom: 17,
        onPositionChanged: (camera, hasGesture) { if (hasGesture && mounted) setState(() => _center = camera.center); }),
        children: [
          TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.bake.navigator'),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
        ]),
      const IgnorePointer(child: Center(child: Icon(Icons.location_pin, size: 48, color: Colors.red))),
      Positioned(left: 16, right: 16, bottom: 18, child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Card(child: Padding(padding: const EdgeInsets.all(10), child: Text(
          '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}', textAlign: TextAlign.center))),
        SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: () => Navigator.pop(context, _center),
          icon: const Icon(Icons.check), label: const Text('Готово'))),
      ]))),
    ]),
  );
}

class VoiceTextField extends StatefulWidget {
  const VoiceTextField({super.key, required this.controller, required this.decoration,
    this.autofocus = false, this.focusNode, this.textInputAction, this.onChanged, this.onSubmitted, this.minLines = 1, this.maxLines = 1});
  final TextEditingController controller; final InputDecoration decoration; final bool autofocus;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction; final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted; final int minLines; final int? maxLines;
  @override State<VoiceTextField> createState() => _VoiceTextFieldState();
}
class _VoiceTextFieldState extends State<VoiceTextField> {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _available = false, _listening = false, _initializing = false;
  Future<void> _toggleVoice() async {
    if (_listening) { await _speech.stop(); if (mounted) setState(() => _listening = false); return; }
    if (!_available && !_initializing) {
      _initializing = true;
      _available = await _speech.initialize(
        onStatus: (status) { if (mounted) setState(() => _listening = status == 'listening'); },
        onError: (error) { if (mounted) { setState(() => _listening = false);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Голосовой ввод: ${error.errorMsg}'))); } },
      );
      _initializing = false;
    }
    if (!_available) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Распознавание речи недоступно. Проверьте микрофон и русский языковой пакет.')));
      return;
    }
    await _speech.listen(localeId: 'ru_RU', onResult: (result) {
      final text = result.recognizedWords;
      widget.controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
      widget.onChanged?.call(text);
    });
    if (mounted) setState(() => _listening = true);
  }
  @override void dispose() { _speech.cancel(); super.dispose(); }
  @override Widget build(BuildContext context) => Row(children: [
    Expanded(child: TextField(controller: widget.controller, focusNode: widget.focusNode, autofocus: widget.autofocus,
      textInputAction: widget.textInputAction, onChanged: widget.onChanged, onSubmitted: widget.onSubmitted,
      minLines: widget.minLines, maxLines: widget.maxLines, decoration: widget.decoration)),
    IconButton(tooltip: _listening ? 'Остановить диктовку' : 'Надиктовать по-русски',
      onPressed: _toggleVoice, icon: Icon(_listening ? Icons.mic : Icons.mic_none, color: _listening ? Colors.red : null)),
  ]);
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
  LatLng? _selectedPoint;

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
      double latitude;
      double longitude;
      double accuracy;
      if (_selectedPoint != null) {
        latitude = _selectedPoint!.latitude; longitude = _selectedPoint!.longitude; accuracy = 0;
      } else {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever || !await Geolocator.isLocationServiceEnabled()) {
          throw Exception('Уточните точку на карте или разрешите GPS.');
        }
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
        );
        if (position.accuracy > 30) throw Exception('GPS пока неточный (±${position.accuracy.toStringAsFixed(0)} м). Повторите позже.');
        latitude = position.latitude; longitude = position.longitude; accuracy = position.accuracy;
      }
      final prefs = await SharedPreferences.getInstance();
      final rows = prefs.getStringList('bake_address_corrections_v1') ?? <String>[];
      rows.insert(0, jsonEncode({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'address': _addressController.text.trim(),
        'details': _detailsController.text.trim(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracyMeters': accuracy,
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
      VoiceTextField(controller: _addressController, decoration: const InputDecoration(labelText: 'Адрес или название места', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      VoiceTextField(controller: _detailsController, minLines: 3, maxLines: 5, decoration: const InputDecoration(labelText: 'Что нужно исправить (необязательно)', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: _saving ? null : () async {
        final point = await MapPointPickerPage.pick(context, initialPoint: _selectedPoint ?? const LatLng(42.3154, 69.5869));
        if (point != null && mounted) setState(() => _selectedPoint = point);
      }, icon: const Icon(Icons.my_location), label: Text(_selectedPoint == null ? 'Уточнить на карте' :
        'Точка: ${_selectedPoint!.latitude.toStringAsFixed(6)}, ${_selectedPoint!.longitude.toStringAsFixed(6)}')),
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
  int _localPendingCount = 0;
  final Set<String> _busyRecordIds = <String>{};

  @override
  void initState() {
    super.initState();
    RoadReportSyncService.adminModeActive = true;
    _loadReports();
    _loadLocalPendingCount();
  }

  @override
  void dispose() {
    RoadReportSyncService.adminModeActive = false;
    super.dispose();
  }

  Future<void> _loadLocalPendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final rows = prefs.getStringList('bake_road_reports_v1') ?? <String>[];
    final pending = rows.where((raw) {
      try {
        final row = jsonDecode(raw) as Map<String, dynamic>;
        return row['syncStatus'] != 'Синхронизировано';
      } catch (_) {
        return false;
      }
    }).length;
    if (mounted) setState(() => _localPendingCount = pending);
  }

  @override

  Future<void> _loadReports() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    await _loadLocalPendingCount();
    try {
      final rows = await RoadReportSyncService.fetchAllReportsForAdmin();
      if (!mounted) return;
      setState(() { _records = rows; _loading = false; });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Не удалось загрузить отметки: ' + error.toString(); });
    }
  }

  Future<void> _moderateReport(Map<String, dynamic> record, String status) async {
    final id = record['id']?.toString();
    if (id == null || id.isEmpty || _busyRecordIds.contains(id)) return;
    setState(() => _busyRecordIds.add(id));
    try {
      await RoadReportSyncService.updateReportStatus(id, status);
      await _loadReports();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'Подтверждено' ? 'Объект подтверждён.' : 'Объект отклонён.'),
        ));
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка модерации: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyRecordIds.remove(id));
    }
  }


  Future<void> _editReport(Map<String, dynamic> record) async {
    final id = record['id']?.toString();
    final lat = (record['latitude'] as num?)?.toDouble();
    final lon = (record['longitude'] as num?)?.toDouble();
    if (id == null || lat == null || lon == null) return;
    final title = TextEditingController(text: (record['title'] ?? record['type'] ?? '').toString());
    final address = TextEditingController(text: (record['address'] ?? '').toString());
    final comment = TextEditingController(text: (record['comment'] ?? '').toString());
    var point = LatLng(lat, lon);
    final save = await showDialog<bool>(context: context, builder: (dialogContext) =>
      StatefulBuilder(builder: (context, refresh) => AlertDialog(
        title: const Text('Редактировать точку'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          VoiceTextField(controller: title, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 8),
          VoiceTextField(controller: address, decoration: const InputDecoration(labelText: 'Адрес')),
          const SizedBox(height: 8),
          VoiceTextField(controller: comment, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: 'Комментарий')),
          OutlinedButton.icon(onPressed: () async {
            final p = await MapPointPickerPage.pick(context, initialPoint: point);
            if (p != null) refresh(() => point = p);
          }, icon: const Icon(Icons.my_location), label: const Text('Уточнить на карте')),
          Text('${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}'),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Сохранить')),
        ],
      )));
    if (save == true && mounted) {
      try {
        await RoadReportSyncService.updateReportDetails(id: id, title: title.text.trim(),
          address: address.text.trim(), comment: comment.text.trim(), latitude: point.latitude, longitude: point.longitude);
        await _loadReports();
      } catch (error) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Не удалось сохранить изменения: $error')));
      }
    }
    title.dispose(); address.dispose(); comment.dispose();
  }

  Future<void> _deleteReport(Map<String, dynamic> record) async {
    final id = record['id']?.toString();
    if (id == null || id.isEmpty || _busyRecordIds.contains(id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить объект из базы?'),
        content: const Text('Запись будет удалена из Supabase без возможности восстановления.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busyRecordIds.add(id));
    try {
      await RoadReportSyncService.deleteReport(id);
      await _loadReports();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Объект удалён из Supabase.')),
      );
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка удаления: $error')),
      );
    } finally {
      if (mounted) setState(() => _busyRecordIds.remove(id));
    }
  }

  Widget _buildReportList(String? status) {
    final rows = status == null ? _records
        : _records.where((row) => row['status']?.toString() == status).toList();
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _loadReports, icon: const Icon(Icons.refresh), label: const Text('Повторить')),
        ]),
      ));
    }
    if (rows.isEmpty) return Center(child: Text(status == null ? 'Общих отметок пока нет.' : 'В этой вкладке отметок нет.'));
    return RefreshIndicator(
      onRefresh: _loadReports,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: rows.length,
        itemBuilder: (context, index) {
          final record = rows[index];
          final latitude = (record['latitude'] as num?)?.toDouble();
          final longitude = (record['longitude'] as num?)?.toDouble();
          final accuracy = (record['accuracyMeters'] as num?)?.toDouble();
          final date = DateTime.tryParse(record['createdAt']?.toString() ?? '')?.toLocal();
          final currentStatus = record['status']?.toString() ?? '—';
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text(record['type']?.toString() ?? 'Объект',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                  _statusChip(currentStatus),
                ]),
                const SizedBox(height: 8),
                Text('GPS: ' + (latitude?.toStringAsFixed(6) ?? '—') + ', ' + (longitude?.toStringAsFixed(6) ?? '—')),
                Text('Точность: ' + (accuracy == null ? '—' : '±' + accuracy.toStringAsFixed(1) + ' м')),
                Text('Устройство: ' + (record['deviceId']?.toString() ?? '—')),
                if (date != null) Text('Добавлено: ' + date.toString()),
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                    onPressed: _busyRecordIds.contains(record['id']?.toString()) ? null : () => _editReport(record),
                    icon: const Icon(Icons.edit_outlined), label: const Text('Редактировать'),
                  ),
                  OutlinedButton.icon(
                    onPressed: latitude == null || longitude == null ? null : () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => RoadReportMapPage(
                        latitude: latitude, longitude: longitude,
                        title: record['type']?.toString() ?? 'Отметка',
                      )),
                    ),
                    icon: const Icon(Icons.map_outlined), label: const Text('На карте'),
                  ),
                  if (record['status']?.toString() != 'Подтверждено')
                    FilledButton.icon(
                      onPressed: _busyRecordIds.contains(record['id']?.toString()) ? null : () => _moderateReport(record, 'Подтверждено'),
                      icon: const Icon(Icons.check_circle_outline), label: const Text('Подтвердить'),
                    ),
                  if (record['status']?.toString() != 'Отклонено')
                    OutlinedButton.icon(
                      onPressed: _busyRecordIds.contains(record['id']?.toString()) ? null : () => _moderateReport(record, 'Отклонено'),
                      icon: const Icon(Icons.cancel_outlined), label: const Text('Отклонить'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _busyRecordIds.contains(record['id']?.toString()) ? null : () => _deleteReport(record),
                    icon: const Icon(Icons.delete_outline), label: const Text('Удалить'),
                  ),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _statusChip(String status) {
    final color = status == 'Подтверждено' ? Colors.green
        : status == 'Отклонено' ? Colors.red : Colors.orange;
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(status, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.12),
      side: BorderSide(color: color.withValues(alpha: 0.35)),
      padding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Админ-кабинет', maxLines: 1, overflow: TextOverflow.visible),
        actions: [IconButton(
          tooltip: 'Обновить', onPressed: _loading ? null : _loadReports,
          icon: const Icon(Icons.refresh),
        )],
        bottom: const TabBar(
          labelPadding: EdgeInsets.symmetric(horizontal: 12),
          tabs: [
            Tab(text: 'Новые'),
            Tab(text: 'Одобрено'),
            Tab(text: 'Все'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(
                    _loading ? Icons.sync : _error == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
                    color: _loading ? Colors.blueGrey : _error == null ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    _loading ? 'Проверяем связь с Supabase…' : _error == null ? 'Supabase подключён' : 'Нет связи с Supabase',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  )),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _loadReports,
                    icon: const Icon(Icons.wifi_tethering, size: 18),
                    label: const Text('Проверить'),
                  ),
                ]),
                const SizedBox(height: 5),
                Text(
                  RoadReportSyncService.configurationSummary,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 5),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 4),
                Text('Всего в общей базе: ${_records.length}'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                      'На этом телефоне не отправлено: $_localPendingCount',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const MyRoadMarksPage()),
                      );
                      _loadLocalPendingCount();
                    },
                    icon: const Icon(Icons.phone_android, size: 18),
                    label: const Text('Локальные'),
                  ),
                ]),
              ]),
            ),
          ),
        ),
        Expanded(child: TabBarView(children: [
          _buildReportList('На проверке'),
          _buildReportList('Подтверждено'),
          _buildReportList(null),
        ])),
      ]),
      ),
    ),
  );
}

class RoadReportMapPage extends StatelessWidget {
  const RoadReportMapPage({super.key, required this.latitude, required this.longitude, required this.title});
  final double latitude;
  final double longitude;
  final String title;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FlutterMap(
        options: MapOptions(initialCenter: point, initialZoom: 17),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.bake.navigator',
          ),
          MarkerLayer(markers: [Marker(
            point: point, width: 54, height: 54,
            child: const Icon(Icons.location_pin, size: 48, color: Colors.red),
          )]),
          const RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(12),
        child: SelectableText(
          latitude.toStringAsFixed(6) + ', ' + longitude.toStringAsFixed(6),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
