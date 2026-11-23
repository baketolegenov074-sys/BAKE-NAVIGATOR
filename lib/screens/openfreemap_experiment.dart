import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;

/// Isolated OpenFreeMap + Nominatim experiment.
/// Does not use BAKE's Photon, local address index, offline tiles or routers.
class OpenFreeMapExperimentScreen extends StatefulWidget {
  const OpenFreeMapExperimentScreen({super.key});

  @override
  State<OpenFreeMapExperimentScreen> createState() =>
      _OpenFreeMapExperimentScreenState();
}

class _OpenFreeMapExperimentScreenState
    extends State<OpenFreeMapExperimentScreen> {
  static const _styleUrl = 'https://tiles.openfreemap.org/styles/liberty';
  static const _initialTarget = ml.LatLng(48.0, 67.0);

  final _searchController = TextEditingController();
  ml.MapLibreMapController? _mapController;
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;
  String _mapStatus = 'Подключение OpenFreeMap…';
  DateTime? _lastSearchAt;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _searchController.text.trim();
    if (query.length < 2 || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      // Respect the public Nominatim limit: no more than one request per second.
      final previousSearch = _lastSearchAt;
      if (previousSearch != null) {
        final elapsed = DateTime.now().difference(previousSearch);
        if (elapsed < const Duration(seconds: 1)) {
          await Future.delayed(const Duration(seconds: 1) - elapsed);
        }
      }
      if (!mounted) return;
      _lastSearchAt = DateTime.now();
      // Nominatim is queried only after explicit submission, not on each key.
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': query,
        'format': 'jsonv2',
        'limit': '10',
        'addressdetails': '1',
        'accept-language': 'ru,kk,en',
      });
      final response = await http.get(uri, headers: const {
        'User-Agent': 'BAKE-Navigator-OpenFreeMap-Experiment/1.0',
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showResult(Map<String, dynamic> item) async {
    final lat = double.tryParse(item['lat']?.toString() ?? '');
    final lon = double.tryParse(item['lon']?.toString() ?? '');
    if (lat == null || lon == null) return;

    final point = ml.LatLng(lat, lon);
    await _mapController?.animateCamera(
      ml.CameraUpdate.newCameraPosition(
        ml.CameraPosition(target: point, zoom: 14),
      ),
    );
    final controller = _mapController;
    if (controller != null) {
      try {
        await controller.clearSymbols();
        await controller.addSymbol(ml.SymbolOptions(
          geometry: point,
          iconImage: 'marker-15',
          iconSize: 1.6,
        ));
      } catch (error) {
        debugPrint('OpenFreeMap experiment marker: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                _error = null;
              });
              _mapController?.animateCamera(
                ml.CameraUpdate.newCameraPosition(
                  const ml.CameraPosition(target: _initialTarget, zoom: 4),
                ),
              );
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
                  onPressed: _loading ? null : _search,
                  icon: _loading
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
                ml.MapLibreMap(
                  styleString: _styleUrl,
                  initialCameraPosition: const ml.CameraPosition(
                    target: _initialTarget,
                    zoom: 4,
                  ),
                  compassEnabled: true,
                  myLocationEnabled: false,
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  onStyleLoadedCallback: () {
                    if (mounted) setState(() => _mapStatus = 'OpenFreeMap подключена');
                  },
                ),
                if (_results.isNotEmpty || _error != null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 250),
                      margin: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 8),
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
                                  leading: const Icon(Icons.place_outlined),
                                  title: Text(
                                    (item['name'] ?? item['display_name'] ?? 'Место')
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(
                                    (item['display_name'] ?? '').toString(),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  onTap: () => _showResult(item),
                                );
                              },
                            )
                          : Padding(
                              padding: const EdgeInsets.all(14),
                              child: Text(_error!),
                            ),
                    ),
                  ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      child: Text(
                        _mapStatus,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 5, 10, 8),
            child: Text(
              'Тестовый режим: карта OpenFreeMap, поиск Nominatim. '
              'Без Photon, Valhalla и офлайн-базы BAKE.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
