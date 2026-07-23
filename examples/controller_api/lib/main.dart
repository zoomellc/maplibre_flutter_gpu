import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'style_layer_selection.dart';

void main() {
  runApp(const ControllerExampleApp());
}

class ControllerExampleApp extends StatelessWidget {
  const ControllerExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapLibre Controller API',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff14747c)),
        useMaterial3: true,
      ),
      home: const ControllerApiPage(),
    );
  }
}

class ControllerApiPage extends StatefulWidget {
  const ControllerApiPage({super.key});

  @override
  State<ControllerApiPage> createState() => _ControllerApiPageState();
}

class _ControllerApiPageState extends State<ControllerApiPage> {
  static const _demoBounds = LatLngBounds(
    southwest: LatLng(35.651, 139.738),
    northeast: LatLng(35.708, 139.793),
  );

  MapLibreMapController? _controller;
  bool _styleDidLoad = false;
  bool _inspecting = false;
  bool _styleReady = false;
  bool _selectedLayerVisible = true;
  String? _selectedLayerId;
  String _status = 'Loading map style…';

  void _onMapCreated(MapLibreMapController controller) {
    _controller = controller;
    if (_styleDidLoad) unawaited(_inspectStyle());
  }

  void _onStyleLoaded() {
    _styleDidLoad = true;
    unawaited(_inspectStyle());
  }

  Future<void> _inspectStyle() async {
    final controller = _controller;
    if (controller == null || _inspecting) return;

    _inspecting = true;
    try {
      final rawLayerIds = await controller.getLayerIds();
      final layerIds = rawLayerIds.whereType<String>().toList(growable: false);
      final sourceIds = await controller.getSourceIds();
      final selectedLayerId = chooseToggleLayer(layerIds);
      final selectedLayerVisible = selectedLayerId == null
          ? true
          : await controller.getLayerVisibility(selectedLayerId) ?? true;
      if (!mounted) return;
      setState(() {
        _selectedLayerId = selectedLayerId;
        _selectedLayerVisible = selectedLayerVisible;
        _styleReady = true;
        _status =
            'Ready: ${layerIds.length} layers, '
            '${sourceIds.length} sources. Tap the map for coordinates.';
      });
    } catch (error) {
      _showError('Style inspection failed: $error');
    } finally {
      _inspecting = false;
    }
  }

  Future<String> _toggleSelectedLayer(MapLibreMapController controller) async {
    final layerId = _selectedLayerId;
    if (layerId == null) return 'The style has no layers to toggle.';
    final next = !_selectedLayerVisible;
    await controller.setLayerVisibility(layerId, next);
    _selectedLayerVisible = next;
    return 'Layer "$layerId": ${next ? 'visible' : 'hidden'}';
  }

  Future<String> _styleSummary(MapLibreMapController controller) async {
    final style = await controller.getStyle();
    if (style == null) return 'Style JSON is unavailable.';
    final layerIds = await controller.getLayerIds();
    final sourceIds = await controller.getSourceIds();
    return 'Style: ${style.length} chars, '
        '${layerIds.length} layers, ${sourceIds.length} sources';
  }

  void _showCoordinates(LatLng coordinates) {
    if (!_styleReady) return;
    setState(
      () => _status =
          'Tap: ${coordinates.latitude.toStringAsFixed(5)}, '
          '${coordinates.longitude.toStringAsFixed(5)}',
    );
  }

  Future<void> _run(
    Future<String> Function(MapLibreMapController controller) action,
  ) async {
    final controller = _controller;
    if (controller == null || !_styleReady) return;
    try {
      final status = await action(controller);
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      _showError(error.toString());
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _status = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _styleReady;

    return Scaffold(
      appBar: AppBar(title: const Text('Controller API')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              styleString: MapLibreStyles.openFreeMapLiberty,
              initialCameraPosition: const CameraPosition(
                target: LatLng(35.6812, 139.765),
                zoom: 12.5,
              ),
              trackCameraPosition: true,
              scaleControlEnabled: true,
              onMapCreated: _onMapCreated,
              onStyleLoadedCallback: _onStyleLoaded,
              onMapClick: (_, coordinates) => _showCoordinates(coordinates),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: Card(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.94),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_status, key: const Key('controller-status')),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: enabled
                                ? () => unawaited(
                                    _run((controller) async {
                                      await controller.animateCamera(
                                        CameraUpdate.newLatLngBounds(
                                          _demoBounds,
                                          left: 36,
                                          top: 36,
                                          right: 36,
                                          bottom: 190,
                                        ),
                                      );
                                      return 'Camera: fitted demo bounds';
                                    }),
                                  )
                                : null,
                            icon: const Icon(Icons.fit_screen),
                            label: const Text('Fit'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: enabled
                                ? () => unawaited(
                                    _run((controller) async {
                                      await controller.animateCamera(
                                        CameraUpdate.newLatLngZoom(
                                          const LatLng(35.6587, 139.7454),
                                          14,
                                        ),
                                      );
                                      return 'Camera: Tokyo Tower';
                                    }),
                                  )
                                : null,
                            icon: const Icon(Icons.location_searching),
                            label: const Text('Tower'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: enabled && _selectedLayerId != null
                                ? () => unawaited(_run(_toggleSelectedLayer))
                                : null,
                            icon: Icon(
                              _selectedLayerVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                            label: const Text('Layer'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: enabled
                                ? () => unawaited(_run(_styleSummary))
                                : null,
                            icon: const Icon(Icons.info_outline),
                            label: const Text('Style'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: enabled
                                ? () => unawaited(
                                    _run((controller) async {
                                      final bounds = await controller
                                          .getVisibleRegion();
                                      return 'Bounds SW '
                                          '${bounds.southwest.latitude.toStringAsFixed(3)}, '
                                          '${bounds.southwest.longitude.toStringAsFixed(3)}';
                                    }),
                                  )
                                : null,
                            icon: const Icon(Icons.crop_free),
                            label: const Text('Bounds'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: enabled
                                ? () => unawaited(
                                    _run((controller) async {
                                      await controller.resetNorth();
                                      return 'Camera: bearing reset to north';
                                    }),
                                  )
                                : null,
                            icon: const Icon(Icons.explore_outlined),
                            label: const Text('North'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
