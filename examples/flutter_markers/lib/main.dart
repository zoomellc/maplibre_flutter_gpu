import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

void main() {
  runApp(const MaterialApp(home: MapExamplePage()));
}

/// Demo markers shown on top of [MapLibreMap].
class MapMarker {
  final double lat;
  final double lon;
  final String label;
  final IconData icon;
  final Color color;

  const MapMarker({
    required this.lat,
    required this.lon,
    required this.label,
    this.icon = Icons.location_on,
    this.color = Colors.red,
  });
}

const _markers = [
  MapMarker(
    lat: 35.65865762901756,
    lon: 139.74543151900602,
    label: 'Tokyo Tower',
    color: Colors.red,
  ),
  MapMarker(
    lat: 35.71009596771566,
    lon: 139.81071973182776,
    label: 'Skytree',
    color: Colors.blue,
  ),
];

/// Example app page that embeds [MapLibreMap] and draws Flutter markers.
class MapExamplePage extends StatefulWidget {
  const MapExamplePage({super.key});

  @override
  State<MapExamplePage> createState() => _MapExamplePageState();
}

class _MapExamplePageState extends State<MapExamplePage> {
  MapLibreMapController? _controller;
  final List<_MarkerPosition> _markerPositions = [];

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    controller.addListener(_updateMarkers);
    _updateMarkers();
  }

  void _updateMarkers() {
    final c = _controller;
    if (c == null || !mounted) return;
    final positions = <_MarkerPosition>[];
    for (final m in _markers) {
      final pos = c.toScreenOffset(LatLng(m.lat, m.lon));
      positions.add(_MarkerPosition(marker: m, screenPos: pos));
    }
    setState(() {
      _markerPositions
        ..clear()
        ..addAll(positions);
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_updateMarkers);
    super.dispose();
  }

  List<Widget> _buildMarkers(Size screenSize, double zoom) {
    if (_markerPositions.isEmpty) return const [];
    final scale = zoom >= 13
        ? 1.0
        : (0.1 + 0.9 * ((zoom - 8) / 5).clamp(0.0, 1.0));
    final iconSize = 32.0 * scale;
    final fontSize = 11.0 * scale;
    final widgets = <Widget>[];
    for (final mp in _markerPositions) {
      final pos = mp.screenPos;
      if (pos.dx < -30 ||
          pos.dx > screenSize.width + 30 ||
          pos.dy < -50 ||
          pos.dy > screenSize.height + 30) {
        continue;
      }
      final m = mp.marker;
      widgets.add(
        Positioned(
          left: pos.dx - iconSize / 2,
          top: pos.dy - iconSize * 1.25,
          child: IgnorePointer(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(m.icon, color: m.color, size: iconSize),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 6 * scale,
                    vertical: 2 * scale,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4 * scale),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 2,
                      ),
                    ],
                  ),
                  child: Text(
                    m.label,
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: m.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final zoom = _controller?.cameraPosition?.zoom ?? 13.0;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              styleString: MapLibreStyles.openFreeMapLiberty,
              initialCameraPosition: const CameraPosition(
                target: LatLng(35.6812, 139.7671),
                zoom: 13.0,
              ),
              trackCameraPosition: true,
              onMapCreated: _onMapCreated,
            ),
          ),
          ..._buildMarkers(screenSize, zoom),
        ],
      ),
    );
  }
}

class _MarkerPosition {
  final MapMarker marker;
  final Offset screenPos;

  const _MarkerPosition({required this.marker, required this.screenPos});
}
