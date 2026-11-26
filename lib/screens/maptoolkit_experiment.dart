import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';

/// Isolated Maptoolkit Street vector-map experiment.
/// It does not touch the main map, offline MBTiles, GPS or routing.
class MaptoolkitExperimentScreen extends StatefulWidget {
  const MaptoolkitExperimentScreen({super.key});

  @override
  State<MaptoolkitExperimentScreen> createState() =>
      _MaptoolkitExperimentScreenState();
}

class _MaptoolkitExperimentScreenState
    extends State<MaptoolkitExperimentScreen> {
  static const _styleUrl = 'https://styles.maptoolkit.org/street.json';
  static const _initialTarget = LatLng(42.3417, 69.5901);
  static const _logoUrl =
      'https://www.maptoolkit.org/assets/maptoolkit-attribution.png';

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
        _error = 'Не удалось загрузить Maptoolkit Street: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _style;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maptoolkit Street — тест'),
        actions: [
          IconButton(
            tooltip: 'Вернуться к Шымкенту',
            onPressed: () {
              setState(() => _error = null);
              if (_mapReady) _mapController.move(_initialTarget, 12);
            },
            icon: const Icon(Icons.my_location),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (style != null)
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _initialTarget,
                initialZoom: 12,
                minZoom: 2,
                maxZoom: 15,
                onMapReady: () => _mapReady = true,
              ),
              children: [
                VectorTileLayer(
                  theme: style.theme,
                  sprites: style.sprites,
                  tileProviders: style.providers,
                  maximumZoom: 15,
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
            left: 8,
            bottom: 8,
            child: Image.network(
              _logoUrl,
              height: 28,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Text(
                'Maptoolkit',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const Positioned(
            right: 6,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Color(0xCCFFFFFF)),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  '© Maptoolkit © OpenStreetMap',
                  style: TextStyle(fontSize: 10, color: Colors.black87),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
