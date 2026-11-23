import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
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
  Style? _style;
  bool _styleLoading = true;
  bool _mapReady = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  @override
  void dispose() {
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
              setState(() => _error = null);
              if (_mapReady) _mapController.move(_initialTarget, 4);
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
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
                if (_error != null)
                  Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      margin: const EdgeInsets.all(10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_error!),
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
