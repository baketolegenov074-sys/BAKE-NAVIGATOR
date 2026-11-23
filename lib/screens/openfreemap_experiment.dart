import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Isolated OpenFreeMap Liberty experiment rendered with FlutterMap.
/// It does not touch the main map, offline MBTiles, GPS or routing.
class OpenFreeMapExperimentScreen extends StatefulWidget {
  const OpenFreeMapExperimentScreen({super.key});

  @override
  State<OpenFreeMapExperimentScreen> createState() =>
      _OpenFreeMapExperimentScreenState();
}

class _OpenFreeMapExperimentScreenState
    extends State<OpenFreeMapExperimentScreen> {
  static const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';
  static const _initialTarget = LatLng(48, 67);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  Style? _style;
  List<Map<String, dynamic>> _results = [];
  LatLng? _selectedPoint;
  bool _styleLoading = true;
  bool _mapReady = false;
  bool _searchLoading = false;
  String? _error;
  DateTime? _lastSearchAt;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadStyle() async {
    try {
      final style = await StyleReader(uri: _styleUrl).read();
      if (!mounted) return;
      setState(() {
        _style = style;
        _styleLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _styleLoading = false;
        _error = 'Не удалось загрузить Liberty: $error';
      });
    }
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 2 || _searchLoading) return;

    setState(() {
      _searchLoading = true;
      _error = null;
      _results = [];
    });

    try {
      // Nominatim public service: keep at least one second between requests.
      final previous = _lastSearchAt;
      if (previous != null) {
        final elapsed = DateTime.now().difference(previous);
        if (elapsed < const Duration(seconds: 1)) {
          await Future.delayed(const Duration(seconds: 1) - elapsed);
        }
      }
      if (!mounted) return;
      _lastSearchAt = DateTime.now();

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '10',
        'addressdetails': '1',
        'accept-language': 'ru,kk,en',
      });
      final response = await http.get(uri, headers: const {
        'User-Agent': 'BAKE-Navigator-OpenFreeMap-Experiment/2.0',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception('Поиск временно недоступен (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) throw Exception('Некорректный ответ поиска.');

      final found = decoded
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) =>
              double.tryParse(item['lat']?.toString() ?? '') != null &&
              double.tryParse(item['lon']?.toString() ?? '') != null)
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _results = found;
        if (found.isEmpty) _error = 'Ничего не найдено.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _showResult(Map<String, dynamic> item) {
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return;

    final point = LatLng(lat, lon);
    setState(() {
      _selectedPoint = point;
      _results = [];
    });
    if (_mapReady) _mapController.move(point, 14);
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Экспериментальная карта'),
        actions: [
          IconButton(
            tooltip: 'Сбросить поиск',
            onPressed: () {
              _searchController.clear();
              setState(() {
                _results = [];
                _selectedPoint = null;
                _error = null;
              });
              if (_mapReady) _mapController.move(_initialTarget, 4);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      hintText: 'Город или место в любой стране',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Искать',
                  onPressed: _searchLoading ? null : _search,
                  icon: _searchLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                if (style != null)
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _initialTarget,
                      initialZoom: 4,
                      minZoom: 2,
                      maxZoom: 18,
                      onMapReady: () => _mapReady = true,
                    ),
                    children: [
                      VectorTileLayer(
                        theme: style.theme,
                        sprites: style.sprites,
                        tileProviders: style.providers,
                        maximumZoom: 18,
                      ),
                      if (_selectedPoint != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _selectedPoint!,
                              width: 44,
                              height: 44,
                              child: const Icon(
                                Icons.location_pin,
                                size: 42,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                    ],
                  )
                else
                  const ColoredBox(
                    color: Color(0xFFE8EDF2),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                if (_styleLoading)
                  const Align(
                    alignment: Alignment.topCenter,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_results.isNotEmpty || _error != null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 260),
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(blurRadius: 10, color: Colors.black26),
                        ],
                      ),
                      child: _results.isNotEmpty
                          ? ListView.separated(
                              shrinkWrap: true,
                              itemCount: _results.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _results[index];
                                return ListTile(
                                  dense: true,
                                  title: Text(
                                    item['name']?.toString() ??
                                        item['display_name']?.toString() ??
                                        'Место',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    item['display_name']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _showResult(item),
                                );
                              },
                            )
                          : Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(_error ?? ''),
                            ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Chip(
                    avatar: Icon(
                      style == null ? Icons.sync : Icons.check_circle,
                      size: 17,
                    ),
                    label: Text(
                      style == null
                          ? 'Загрузка OpenFreeMap Liberty…'
                          : 'OpenFreeMap Liberty · FlutterMap',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
