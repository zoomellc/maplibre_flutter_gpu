import 'dart:async' show Timer, unawaited;
import 'dart:math' as math;
import 'dart:ui' as dart_ui show Image;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math.dart' as vector_math;

import 'camera.dart';
import 'gpu_renderer.dart';
import 'label_reconciler.dart';
import 'maplibre_gpu_render_context.dart';
import 'maplibre_map_controller.dart';
import 'maplibre_map_controls.dart';
import 'maplibre_map_options.dart';
import 'maplibre_styles.dart';
import 'map_style_resolver.dart';
import 'native/maplibre_ffi.dart';
import 'sprite_atlas.dart';
import 'symbol_overlay.dart';

/// Callback invoked when the map has been created and is ready to use.
typedef MapCreatedCallback = void Function(MapLibreMapController controller);

/// Callback invoked when the map style has finished loading.
typedef OnStyleLoadedCallback = void Function();

/// Callback invoked when the camera moves.
typedef OnCameraMoveCallback = void Function(CameraPosition cameraPosition);

/// Callback invoked when a camera movement ends.
typedef OnCameraIdleCallback = void Function();

/// Callback invoked when the map has no more pending work.
typedef OnMapIdleCallback = void Function();

/// Callback invoked for a map tap or long press.
typedef OnMapClickCallback =
    void Function(math.Point<double> point, LatLng coordinates);

@visibleForTesting
vector_math.Vector4 maplibreClearValue(FrameClearColor? color) =>
    vector_math.Vector4(
      color?.red ?? 0.0,
      color?.green ?? 0.0,
      color?.blue ?? 0.0,
      color?.alpha ?? 0.0,
    );

@visibleForTesting
bool maplibreLabelSnapshotChanged(int previous, int next) => previous != next;

@visibleForTesting
bool maplibreDoubleClickZoomIsEnabled(
  bool? doubleClickZoomEnabled,
  bool zoomGesturesEnabled,
) => doubleClickZoomEnabled ?? zoomGesturesEnabled;

@visibleForTesting
double maplibreBearingGestureDelta(double rotationDelta) =>
    -rotationDelta * 180 / math.pi;

@visibleForTesting
double maplibreTrackpadScaleDelta(double currentScale, double previousScale) {
  if (!currentScale.isFinite ||
      !previousScale.isFinite ||
      currentScale <= 0 ||
      previousScale <= 0) {
    return 1;
  }
  return currentScale / previousScale;
}

@visibleForTesting
({double accumulatedRotation, bool active, double rotationDelta})
maplibreRotationGestureUpdate({
  required double frameRotationDelta,
  required double accumulatedRotation,
  required bool active,
}) {
  if (active) {
    return (
      accumulatedRotation: accumulatedRotation,
      active: true,
      rotationDelta: frameRotationDelta,
    );
  }
  final nextAccumulated = accumulatedRotation + frameRotationDelta;
  return (
    accumulatedRotation: nextAccumulated,
    active: nextAccumulated.abs() >= math.pi / 60,
    rotationDelta: 0,
  );
}

@visibleForTesting
double? maplibreTiltGestureDelta({
  required Offset focalPointDelta,
  required double scaleDelta,
  required double rotationDelta,
  required bool fingersApproximatelyHorizontal,
  double minimumVerticalDelta = 1,
}) {
  if (!fingersApproximatelyHorizontal) return null;
  if ((scaleDelta - 1).abs() >= 0.015 || rotationDelta.abs() >= 0.015) {
    return null;
  }
  if (focalPointDelta.dy.abs() <= focalPointDelta.dx.abs() * math.sqrt(3) ||
      focalPointDelta.dy.abs() < minimumVerticalDelta) {
    return null;
  }
  return -focalPointDelta.dy * 0.5;
}

@visibleForTesting
bool maplibreTiltFingersApproximatelyHorizontal(Iterable<Offset> points) {
  if (points.length != 2) return false;
  final positions = points.toList(growable: false);
  final delta = positions[1] - positions[0];
  return delta.dx.abs() >= delta.dy.abs();
}

@visibleForTesting
Offset maplibreSymbolScreenPosition(
  Offset geographicAnchor,
  double offsetX,
  double offsetY,
) => geographicAnchor + Offset(offsetX, offsetY);

@visibleForTesting
Size? maplibreLayoutSize(BoxConstraints constraints) {
  if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
    return null;
  }
  final size = constraints.biggest;
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    return null;
  }
  return size;
}

@visibleForTesting
({int logicalWidth, int logicalHeight, int physicalWidth, int physicalHeight})
maplibreViewportDimensions(Size logicalSize, double devicePixelRatio) {
  final dpr = devicePixelRatio.isFinite && devicePixelRatio > 0
      ? devicePixelRatio
      : 1.0;
  final logicalWidth = logicalSize.width.floor();
  final logicalHeight = logicalSize.height.floor();
  final safeLogicalWidth = logicalWidth > 0 ? logicalWidth : 1;
  final safeLogicalHeight = logicalHeight > 0 ? logicalHeight : 1;
  final physicalWidth = (safeLogicalWidth * dpr).floor();
  final physicalHeight = (safeLogicalHeight * dpr).floor();
  return (
    logicalWidth: safeLogicalWidth,
    logicalHeight: safeLogicalHeight,
    physicalWidth: physicalWidth > 0 ? physicalWidth : 1,
    physicalHeight: physicalHeight > 0 ? physicalHeight : 1,
  );
}

/// Shows a MapLibre map rendered with Flutter GPU.
///
/// The native bridge currently supports one active [MapLibreMap] per process.
/// A second map reports an initialization error and must be remounted after the
/// active map is removed.
class MapLibreMap extends StatefulWidget {
  const MapLibreMap({
    super.key,
    this.initialCameraPosition,
    this.styleString = MapLibreStyles.demo,
    this.onMapCreated,
    this.onStyleLoadedCallback,
    this.onCameraMove,
    this.onCameraIdle,
    this.onMapIdle,
    this.onMapClick,
    this.onMapLongClick,
    this.cameraTargetBounds = CameraTargetBounds.unbounded,
    this.minMaxZoomPreference = MinMaxZoomPreference.unbounded,
    this.rotateGesturesEnabled = true,
    this.scrollGesturesEnabled = true,
    this.zoomGesturesEnabled = true,
    this.tiltGesturesEnabled = true,
    this.doubleClickZoomEnabled,
    this.trackCameraPosition = false,
    this.compassEnabled = true,
    this.logoEnabled = false,
    this.logoViewPosition,
    this.logoViewMargins,
    this.compassViewPosition,
    this.compassViewMargins,
    this.attributionButtonEnabled = true,
    this.attributionButtonPosition = AttributionButtonPosition.bottomRight,
    this.attributionButtonMargins,
    this.scaleControlEnabled = false,
    this.scaleControlPosition = ScaleControlPosition.bottomLeft,
    this.scaleControlUnit = ScaleControlUnit.metric,
    this.foregroundLoadColor = Colors.transparent,
    this.symbolIconBuilder,
    this.symbolTextBuilder,
    this.gpuRenderCallback,
    this.gpuRepaint,
  });

  /// The initial position of the map's camera.
  ///
  /// If `null`, the camera declared by the style is used.
  final CameraPosition? initialCameraPosition;

  /// A MapLibre style URL, raw JSON document, file path, or Flutter asset.
  ///
  /// See the [MapLibre style spec](https://maplibre.org/maplibre-style-spec/).
  final String styleString;

  /// Called once when the map controller is ready.
  final MapCreatedCallback? onMapCreated;

  /// Called after the style has been set and the first tiles begin loading.
  final OnStyleLoadedCallback? onStyleLoadedCallback;

  /// Called on each camera change when [trackCameraPosition] is true, and
  /// always when [onCameraMove] is non-null.
  final OnCameraMoveCallback? onCameraMove;

  /// Called when a gesture-driven camera movement ends.
  final OnCameraIdleCallback? onCameraIdle;

  /// Called when the map reports idle (no pending tiles/network).
  final OnMapIdleCallback? onMapIdle;

  /// Called after a tap with logical map pixels and geographic coordinates.
  final OnMapClickCallback? onMapClick;

  /// Called after a long press with logical map pixels and coordinates.
  final OnMapClickCallback? onMapLongClick;

  /// Bounds that constrain the map camera target.
  final CameraTargetBounds cameraTargetBounds;

  /// Preferred minimum and maximum zoom levels.
  final MinMaxZoomPreference minMaxZoomPreference;

  /// Whether two-finger rotate gestures are enabled.
  final bool rotateGesturesEnabled;

  /// Whether one-finger pan gestures move the map.
  final bool scrollGesturesEnabled;

  /// Whether pinch / scroll-wheel zoom is enabled.
  final bool zoomGesturesEnabled;

  /// Whether three-finger vertical tilt gestures are enabled.
  final bool tiltGesturesEnabled;

  /// Whether double-tap zoom is enabled.
  ///
  /// When `null`, follows [zoomGesturesEnabled], matching `maplibre_gl`.
  final bool? doubleClickZoomEnabled;

  /// When true, [MapLibreMapController] notifies listeners on camera moves.
  final bool trackCameraPosition;

  /// Whether a compass is shown while the map is rotated.
  final bool compassEnabled;

  /// Whether the MapLibre logo is shown.
  final bool logoEnabled;

  /// Position of the MapLibre logo.
  final LogoViewPosition? logoViewPosition;

  /// Horizontal and vertical logo margins in logical pixels.
  final math.Point<num>? logoViewMargins;

  /// Position of the compass.
  final CompassViewPosition? compassViewPosition;

  /// Horizontal and vertical compass margins in logical pixels.
  final math.Point<num>? compassViewMargins;

  /// Whether the attribution button is shown.
  ///
  /// This is a GPU-package extension. `maplibre_gl` exposes attribution
  /// position and margins but not the native visibility switch.
  final bool attributionButtonEnabled;

  /// Position of the attribution button.
  final AttributionButtonPosition? attributionButtonPosition;

  /// Horizontal and vertical attribution margins in logical pixels.
  final math.Point<num>? attributionButtonMargins;

  /// Whether a scale control is shown.
  final bool scaleControlEnabled;

  /// Position of the scale control.
  final ScaleControlPosition scaleControlPosition;

  /// Unit used by the scale control.
  final ScaleControlUnit scaleControlUnit;

  /// Color shown above the map until the style has loaded.
  final Color? foregroundLoadColor;

  /// Replaces the icon part of a placed symbol.
  ///
  /// Returning `null` uses the style sprite. Use `SizedBox.shrink()` to hide
  /// the icon without falling back.
  final SymbolWidgetBuilder? symbolIconBuilder;

  /// Replaces the text-label part of a placed symbol.
  ///
  /// Returning `null` uses the default style-derived text widget. Use
  /// `SizedBox.shrink()` to hide the label without falling back.
  final SymbolWidgetBuilder? symbolTextBuilder;

  /// Records additional Flutter GPU commands above the rendered map.
  ///
  /// The callback receives a render pass using the map's GPU context and color
  /// target. It runs synchronously during paint; it must not submit or retain
  /// the pass. See [MapLibreGpuRenderContext].
  final MapLibreGpuRenderCallback? gpuRenderCallback;

  /// Optional repaint signal for animated [gpuRenderCallback] content.
  ///
  /// Each notification replays the current map frame into a fresh target and
  /// invokes [gpuRenderCallback], without requiring a widget rebuild.
  final Listenable? gpuRepaint;

  @override
  State<MapLibreMap> createState() => _MapLibreMapState();
}

class _MapLibreMapState extends State<MapLibreMap>
    with SingleTickerProviderStateMixin {
  MaplibreBridge? _bridge;
  GpuFrameRenderer? _gpuRenderer;
  MapLibreMapController? _controller;
  final _gpuResources = _MapGpuResources();
  bool _initializing = false;
  bool _initialized = false;
  bool _rendered = false;
  bool _styleLoaded = false;
  String? _initializationError;

  final Map<String, LabelReconcileEntry> _labelEntries = {};
  int _labelFallbackGeneration = 0;
  int _labelsVersion = -1;
  List<MapSymbol> _cachedSymbols = [];
  SpriteAtlas? _spriteAtlas;
  int _styleGeneration = 0;

  int _mapWidth = 800;
  int _mapHeight = 600;
  int _logicalMapWidth = 0;
  int _logicalMapHeight = 0;
  double _dpr = 1.0;
  Size? _logicalMapSize;
  double? _observedDpr;
  ({Size logicalSize, double dpr})? _pendingViewport;
  bool _viewportUpdateScheduled = false;
  bool _reportedDprChange = false;

  late final AnimationController _flingController;
  Offset _flingVelocity = Offset.zero;
  double _previousFlingProgress = 0.0;
  final _panSamples = <_PanSample>[];
  static const _maxPanSamples = 5;
  static const _flingThreshold = 100.0;
  static const _flingDuration = Duration(milliseconds: 998);
  _TwoFingerGestureMode _twoFingerGestureMode = _TwoFingerGestureMode.undecided;
  final Map<int, Offset> _pointerPositions = <int, Offset>{};
  final Map<int, Offset> _twoFingerStartPositions = <int, Offset>{};
  Offset? _previousTwoFingerCenter;
  double? _previousTwoFingerDistance;
  double? _previousTwoFingerAngle;
  bool _twoFingerUpdateScheduled = false;
  bool _trackpadGestureActive = false;
  double _previousTrackpadScale = 1;
  double _previousTrackpadRotation = 0;
  Offset? _doubleTapPosition;

  @override
  void initState() {
    super.initState();
    _flingController =
        AnimationController(vsync: this, duration: _flingDuration)
          ..addListener(_onFlingTick)
          ..addStatusListener(_onFlingStatus);
    _bridge = MaplibreBridge();
  }

  Future<void> _initMap() async {
    if (_initializing || _initialized || _initializationError != null) return;
    _initializing = true;
    try {
      // Brief delay so MediaQuery / GPU context are ready.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      final logicalSize = _logicalMapSize;
      final observedDpr = _observedDpr;
      if (logicalSize == null || observedDpr == null) return;
      _dpr = observedDpr.isFinite && observedDpr > 0 ? observedDpr : 1.0;
      final dimensions = maplibreViewportDimensions(logicalSize, _dpr);
      _logicalMapWidth = dimensions.logicalWidth;
      _logicalMapHeight = dimensions.logicalHeight;
      _mapWidth = dimensions.physicalWidth;
      _mapHeight = dimensions.physicalHeight;

      late String requestedStyle;
      late String resolvedStyle;
      while (true) {
        requestedStyle = widget.styleString;
        try {
          resolvedStyle = await resolveMapStyleString(requestedStyle);
        } catch (_) {
          if (mounted && requestedStyle != widget.styleString) continue;
          rethrow;
        }
        if (!mounted) return;
        if (requestedStyle == widget.styleString) break;
      }

      final result = _bridge!.init(
        _logicalMapWidth,
        _logicalMapHeight,
        _dpr,
        resolvedStyle,
      );

      if (result != MaplibreBridge.initSuccess) {
        final message = result == MaplibreBridge.initBusy
            ? 'Only one MapLibreMap can be active per process. Remove the '
                  'existing map, then remount this widget.'
            : 'MapLibre native initialization failed (error $result).';
        debugPrint('[MapLibreMap] $message');
        if (mounted) {
          setState(() => _initializationError = message);
        }
        return;
      }

      _initialized = true;
      _bridge!.devicePixelRatio = _dpr;

      _loadSpriteAtlas(resolvedStyle, baseStyleUrl: requestedStyle);

      final initial = widget.initialCameraPosition;
      if (initial != null) {
        _bridge!.setCameraFull(
          initial.target.latitude,
          initial.target.longitude,
          initial.zoom,
          initial.bearing,
          initial.tilt,
        );
      }

      _gpuRenderer = GpuFrameRenderer(bridge: _bridge!);
      _controller = MapLibreMapController.bind(
        _bridge!,
        onCameraChangeRequested: _onProgrammaticCameraChange,
        onStyleChangeRequested: _onProgrammaticStyleChange,
        onStyleMutationRequested: _onProgrammaticStyleMutation,
      );
      widget.onMapCreated?.call(_controller!);

      for (var attempt = 0; attempt < 100; attempt++) {
        _bridge!.frameBegin();
        _bridge!.renderFrame();
        _bridge!.frameEnd();
        final wasStyleLoaded = _styleLoaded;
        _updateStyleLoadedState();
        if (_styleLoaded && wasStyleLoaded) break;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!mounted) return;
      }
      _rendered = true;
      _syncLabelsFromCpp();
      _cacheSymbolPositions();
      setState(() {});
      _ensureRepaintLoop();
    } catch (error, stackTrace) {
      debugPrint('[MapLibreMap] initialization failed: $error\n$stackTrace');
      if (mounted) {
        setState(() => _initializationError = error.toString());
      }
    } finally {
      _initializing = false;
    }
  }

  void _applyCameraConstraints() {
    final bounds = widget.cameraTargetBounds.bounds;
    final zoom = widget.minMaxZoomPreference;
    _bridge!.setBounds(
      south: bounds?.southwest.latitude,
      west: bounds?.southwest.longitude,
      north: bounds?.northeast.latitude,
      east: bounds?.northeast.longitude,
      minZoom: zoom.minZoom,
      maxZoom: zoom.maxZoom,
    );
  }

  void _updateStyleLoadedState() {
    if (_styleLoaded || !_bridge!.isStyleLoaded()) return;
    _styleLoaded = true;
    _applyCameraConstraints();
    widget.onStyleLoadedCallback?.call();
  }

  void _loadSpriteAtlas(String styleSource, {String? baseStyleUrl}) {
    final generation = ++_styleGeneration;
    SpriteAtlas.load(styleSource, baseStyleUrl: baseStyleUrl).then((atlas) {
      if (!mounted || !_initialized || generation != _styleGeneration) {
        atlas?.dispose();
        return;
      }
      if (atlas == null) return;
      setState(() {
        _spriteAtlas?.dispose();
        _spriteAtlas = atlas;
        _cacheSymbolPositions();
      });
    });
  }

  Future<void> _onProgrammaticStyleChange(
    String styleString,
    String resolvedStyle,
  ) async {
    if (!mounted || !_initialized) {
      throw StateError('MapLibreMap is not available for a style change');
    }
    _styleGeneration++;
    setState(() {
      _styleLoaded = false;
      _labelsVersion = -1;
      _labelFallbackGeneration = 0;
      _labelEntries.clear();
      _cachedSymbols = const [];
      _spriteAtlas?.dispose();
      _spriteAtlas = null;
    });
    _programmaticCameraIdlePending = false;
    _bridge!.setStyle(resolvedStyle);
    _loadSpriteAtlas(resolvedStyle, baseStyleUrl: styleString);
    _renderGesture();
    _ensureRepaintLoop();
  }

  void _onProgrammaticStyleMutation() {
    if (!mounted || !_initialized) return;
    _renderGesture();
    _ensureRepaintLoop();
  }

  void _scheduleViewportUpdate(Size logicalSize, double dpr) {
    final pending = _pendingViewport;
    if (pending != null &&
        pending.logicalSize == logicalSize &&
        pending.dpr == dpr) {
      return;
    }
    if (pending == null &&
        _logicalMapSize == logicalSize &&
        _observedDpr == dpr) {
      return;
    }

    _pendingViewport = (logicalSize: logicalSize, dpr: dpr);
    if (_viewportUpdateScheduled) return;
    _viewportUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportUpdateScheduled = false;
      if (!mounted) return;
      final viewport = _pendingViewport;
      _pendingViewport = null;
      if (viewport == null) return;
      _applyViewport(viewport.logicalSize, viewport.dpr);
    });
  }

  void _applyViewport(Size logicalSize, double observedDpr) {
    final sizeChanged = _logicalMapSize != logicalSize;
    final dprChanged = _observedDpr != observedDpr;
    _logicalMapSize = logicalSize;
    _observedDpr = observedDpr;

    if (!_initialized) {
      if (!_initializing) _initMap();
      return;
    }

    if (dprChanged && (observedDpr - _dpr).abs() > 0.000001) {
      if (!_reportedDprChange) {
        _reportedDprChange = true;
        debugPrint(
          '[MapLibreMap] devicePixelRatio changed after initialization; '
          'keeping native DPR $_dpr until the map is remounted',
        );
      }
    }
    if (!sizeChanged) return;

    // HeadlessFrontend retains the pixel ratio supplied at construction.
    // Keep Dart's render target on that same ratio after logical resizes.
    final dimensions = maplibreViewportDimensions(logicalSize, _dpr);
    if (dimensions.logicalWidth == _logicalMapWidth &&
        dimensions.logicalHeight == _logicalMapHeight) {
      return;
    }

    _logicalMapWidth = dimensions.logicalWidth;
    _logicalMapHeight = dimensions.logicalHeight;
    _mapWidth = dimensions.physicalWidth;
    _mapHeight = dimensions.physicalHeight;
    _bridge!.setSize(_logicalMapWidth, _logicalMapHeight);
    _renderGesture();
    _ensureRepaintLoop();
  }

  bool _syncLabelsFromCpp() {
    final version = _bridge!.getLabelsVersion();
    if (!maplibreLabelSnapshotChanged(_labelsVersion, version)) return false;
    final labels = _bridge!.getPlacedLabels();
    reconcileLabelEntries(
      _labelEntries,
      labels,
      fallbackGeneration: _labelFallbackGeneration++,
    );
    _labelsVersion = version;
    return true;
  }

  void _onLabelFadedOut(String key) {
    final entry = _labelEntries[key];
    if (entry != null && !entry.visible) _labelEntries.remove(key);
  }

  Timer? _repaintTimer;
  bool _programmaticCameraIdlePending = false;

  void _ensureRepaintLoop() {
    if (_repaintTimer != null || !_initialized) return;
    final interval = _bridge!.isCameraMoving()
        ? const Duration(milliseconds: 16)
        : const Duration(milliseconds: 150);
    _repaintTimer = Timer(interval, () {
      _repaintTimer = null;
      if (!mounted || !_initialized) {
        return;
      }
      // Render first, then inspect the status of that frame. Label snapshots
      // are published only when MapLibre performed placement in the same frame,
      // so consuming them remains safe while a fling is active.
      _renderGesture();
      _emitProgrammaticCameraIdleIfSettled();
      if (_styleLoaded &&
          _bridge!.isMapIdle() &&
          !_flingController.isAnimating) {
        widget.onMapIdle?.call();
      } else {
        _ensureRepaintLoop();
      }
    });
  }

  void _onProgrammaticCameraChange() {
    if (!mounted || !_initialized) return;
    _flingController.stop();
    _panSamples.clear();
    _programmaticCameraIdlePending = true;
    _renderGesture();
    _emitProgrammaticCameraIdleIfSettled();
    _ensureRepaintLoop();
  }

  void _emitProgrammaticCameraIdleIfSettled() {
    if (!_programmaticCameraIdlePending || _bridge!.isCameraMoving()) return;
    _programmaticCameraIdlePending = false;
    widget.onCameraIdle?.call();
  }

  void _renderGesture() {
    if (!_initialized) return;
    final sw = Stopwatch()..start();
    _bridge!.frameBegin();
    _bridge!.renderFrame();
    final t1 = sw.elapsedMicroseconds;
    _bridge!.frameEnd();
    _updateStyleLoadedState();
    final t2 = sw.elapsedMicroseconds;
    final nextZoom = _bridge!.getCameraZoom();
    _gpuRenderer?.cppRenderUs = t1;
    _gpuRenderer?.cppMergeUs = t2 - t1;
    _gpuRenderer?.zoom = nextZoom;
    _gpuRenderer?.frameSeq++;
    _rendered = true;
    _syncLabelsFromCpp();
    _cacheSymbolPositions();
    final cameraChanged =
        _controller?.notifyCameraChanged(
          notifyListeners: widget.trackCameraPosition,
        ) ??
        false;
    if (cameraChanged && widget.onCameraMove != null) {
      final pos = _controller?.cameraPosition;
      if (pos != null) widget.onCameraMove?.call(pos);
    }
    setState(() {});
  }

  void _cacheSymbolPositions() {
    final symbols = <MapSymbol>[];
    for (final entry in _labelEntries.entries) {
      final e = entry.value;
      final d = e.data;
      symbols.add(
        MapSymbol(
          key: entry.key,
          data: d,
          textPos: d.textPlaced
              ? maplibreSymbolScreenPosition(
                  _bridge!.latLonToScreen(d.lat, d.lon),
                  d.textOffsetX,
                  d.textOffsetY,
                )
              : null,
          iconPos: d.iconPlaced
              ? maplibreSymbolScreenPosition(
                  _bridge!.latLonToScreen(d.iconLat, d.iconLon),
                  d.iconOffsetX,
                  d.iconOffsetY,
                )
              : null,
          icon: d.icon.isEmpty ? null : _spriteAtlas?[d.icon],
          visible: e.visible,
          fadeIn: !e.appeared,
        ),
      );
      if (e.visible) e.appeared = true;
    }
    _cachedSymbols = symbols;
  }

  @override
  void didUpdateWidget(covariant MapLibreMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_initialized && oldWidget.styleString != widget.styleString) {
      final controller = _controller;
      if (controller != null) {
        unawaited(
          controller.setStyle(widget.styleString).catchError((
            Object error,
            StackTrace stackTrace,
          ) {
            debugPrint(
              '[MapLibreMap] style update failed: $error\n$stackTrace',
            );
          }),
        );
      }
      return;
    }
    if (!_initialized || !_styleLoaded) return;
    if (oldWidget.cameraTargetBounds == widget.cameraTargetBounds &&
        oldWidget.minMaxZoomPreference == widget.minMaxZoomPreference) {
      return;
    }
    _applyCameraConstraints();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_initialized) return;
      _renderGesture();
      _ensureRepaintLoop();
    });
  }

  @override
  void dispose() {
    _initialized = false;
    _styleGeneration++;
    _repaintTimer?.cancel();
    _repaintTimer = null;
    _flingController.dispose();
    _controller?.dispose();
    _controller = null;
    final bridge = _bridge;
    _bridge = null;
    bridge?.destroy();
    _gpuRenderer?.dispose();
    _gpuRenderer = null;
    _gpuResources.dispose();
    _labelEntries.clear();
    _cachedSymbols = const [];
    _spriteAtlas?.dispose();
    _spriteAtlas = null;
    _pendingViewport = null;
    super.dispose();
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!_initialized || !widget.zoomGesturesEnabled) return;
    if (event is PointerScrollEvent) {
      _programmaticCameraIdlePending = false;
      _controller?.notifyCameraGestureStarted();
      _flingController.stop();
      final factor = event.scrollDelta.dy < 0 ? 1.03 : 0.97;
      final local = event.localPosition;
      _bridge!.scaleBy(factor, local.dx, local.dy);
      _renderGesture();
      _ensureRepaintLoop();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointerPositions[event.pointer] = event.localPosition;
    if (_pointerPositions.length == 2 || _pointerPositions.length == 3) {
      _twoFingerStartPositions
        ..clear()
        ..addAll(_pointerPositions);
      final points = _pointerPositions.values.toList(growable: false);
      _previousTwoFingerCenter =
          points.fold(Offset.zero, (a, b) => a + b) / points.length.toDouble();
      if (points.length == 2) {
        final difference = points[1] - points[0];
        _previousTwoFingerDistance = difference.distance;
        _previousTwoFingerAngle = difference.direction;
        _twoFingerGestureMode = _TwoFingerGestureMode.undecided;
      } else {
        _previousTwoFingerDistance = null;
        _previousTwoFingerAngle = null;
        _twoFingerGestureMode = _TwoFingerGestureMode.tilt;
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    _pointerPositions[event.pointer] = event.localPosition;
    if ((_pointerPositions.length == 2 || _pointerPositions.length == 3) &&
        !_twoFingerUpdateScheduled) {
      _twoFingerUpdateScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _twoFingerUpdateScheduled = false;
        _processMultiPointerGesture();
      });
      WidgetsBinding.instance.scheduleFrame();
    }
  }

  void _onPointerEnd(PointerEvent event) {
    _pointerPositions.remove(event.pointer);
    if (_pointerPositions.length == 2) {
      final points = _pointerPositions.values.toList(growable: false);
      _twoFingerStartPositions
        ..clear()
        ..addAll(_pointerPositions);
      _previousTwoFingerCenter = (points[0] + points[1]) / 2;
      final difference = points[1] - points[0];
      _previousTwoFingerDistance = difference.distance;
      _previousTwoFingerAngle = difference.direction;
      _twoFingerGestureMode = _TwoFingerGestureMode.undecided;
    } else {
      _twoFingerStartPositions.clear();
      _previousTwoFingerCenter = null;
      _previousTwoFingerDistance = null;
      _previousTwoFingerAngle = null;
      _twoFingerGestureMode = _TwoFingerGestureMode.undecided;
    }
  }

  double _normalizedAngleDelta(double current, double previous) =>
      (current - previous + math.pi) % (2 * math.pi) - math.pi;

  void _processMultiPointerGesture() {
    if (!mounted || !_initialized) return;
    final pointerCount = _pointerPositions.length;
    if (pointerCount != 2 && pointerCount != 3) return;
    final ids = _twoFingerStartPositions.keys.toList(growable: false);
    if (ids.length != pointerCount ||
        ids.any((id) => !_pointerPositions.containsKey(id))) {
      return;
    }

    if (pointerCount == 3) {
      final points = ids
          .map((id) => _pointerPositions[id]!)
          .toList(growable: false);
      final currentCenter = points.fold(Offset.zero, (a, b) => a + b) / 3.0;
      final tiltDelta = widget.tiltGesturesEnabled
          ? maplibreTiltGestureDelta(
              focalPointDelta: currentCenter - _previousTwoFingerCenter!,
              scaleDelta: 1,
              rotationDelta: 0,
              fingersApproximatelyHorizontal: true,
              minimumVerticalDelta: 0,
            )
          : null;
      _previousTwoFingerCenter = currentCenter;
      if (tiltDelta != null) {
        _bridge!.pitchBy(tiltDelta);
        _renderGesture();
      }
      return;
    }

    final startA = _twoFingerStartPositions[ids[0]]!;
    final startB = _twoFingerStartPositions[ids[1]]!;
    final currentA = _pointerPositions[ids[0]]!;
    final currentB = _pointerPositions[ids[1]]!;
    final startCenter = (startA + startB) / 2;
    final currentCenter = (currentA + currentB) / 2;
    final translation = currentCenter - startCenter;
    final currentDifference = currentB - currentA;
    final currentDistance = currentDifference.distance;
    final currentAngle = currentDifference.direction;
    final startDifference = startB - startA;
    final startDistance = startDifference.distance;
    final startAngle = startDifference.direction;
    final rotationFromStart = _normalizedAngleDelta(currentAngle, startAngle);

    if (_twoFingerGestureMode == _TwoFingerGestureMode.undecided) {
      final pinchRecognized =
          widget.zoomGesturesEnabled &&
          (currentDistance - startDistance).abs() >= 4;
      final rotationRecognized =
          widget.rotateGesturesEnabled &&
          rotationFromStart.abs() >= math.pi / 60;
      if (pinchRecognized || rotationRecognized || translation.distance >= 4) {
        _twoFingerGestureMode = _TwoFingerGestureMode.transform;
      }
    }

    var cameraChanged = false;
    if (_twoFingerGestureMode == _TwoFingerGestureMode.transform) {
      final previousDistance = _previousTwoFingerDistance!;
      if (widget.zoomGesturesEnabled && previousDistance > 0) {
        final scale = currentDistance / previousDistance;
        if ((scale - 1).abs() > 0.001) {
          _bridge!.scaleBy(scale, currentCenter.dx, currentCenter.dy);
          cameraChanged = true;
        }
      }
      if (widget.rotateGesturesEnabled) {
        final rotation = _normalizedAngleDelta(
          currentAngle,
          _previousTwoFingerAngle!,
        );
        if (rotation.abs() > 0.001) {
          _bridge!.rotateBy(maplibreBearingGestureDelta(rotation));
          cameraChanged = true;
        }
      }
    }

    _previousTwoFingerCenter = currentCenter;
    _previousTwoFingerDistance = currentDistance;
    _previousTwoFingerAngle = currentAngle;
    if (cameraChanged) _renderGesture();
  }

  Widget _buildSymbolOverlay(Size screenSize) {
    return MapSymbolOverlay(
      symbols: _cachedSymbols,
      screenSize: screenSize,
      iconBuilder: widget.symbolIconBuilder,
      textBuilder: widget.symbolTextBuilder,
      onFadedOut: _onLabelFadedOut,
    );
  }

  Offset _estimateVelocity() {
    if (_panSamples.length < 2) return Offset.zero;
    final first = _panSamples.first;
    final last = _panSamples.last;
    final dt = last.time.difference(first.time).inMicroseconds / 1e6;
    if (dt < 0.005) return Offset.zero;
    var totalDx = 0.0, totalDy = 0.0;
    for (final s in _panSamples) {
      totalDx += s.delta.dx;
      totalDy += s.delta.dy;
    }
    return Offset(totalDx / dt, totalDy / dt);
  }

  void _onScaleStart(ScaleStartDetails details) {
    _programmaticCameraIdlePending = false;
    _controller?.notifyCameraGestureStarted();
    _flingController.stop();
    _panSamples.clear();
    _trackpadGestureActive = details.kind == PointerDeviceKind.trackpad;
    _previousTrackpadScale = 1;
    _previousTrackpadRotation = 0;
  }

  void _emitMapClick(Offset localPosition, OnMapClickCallback? callback) {
    if (!_initialized || callback == null) return;
    try {
      final coordinate = _bridge!.screenToLatLon(
        localPosition.dx,
        localPosition.dy,
      );
      callback(
        math.Point<double>(localPosition.dx, localPosition.dy),
        LatLng(coordinate.latitude, coordinate.longitude),
      );
    } on UnsupportedError catch (error) {
      debugPrint('[MapLibreMap] map click unavailable: $error');
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.localPosition;
  }

  void _onDoubleTap() {
    if (!_initialized ||
        !maplibreDoubleClickZoomIsEnabled(
          widget.doubleClickZoomEnabled,
          widget.zoomGesturesEnabled,
        )) {
      return;
    }
    _programmaticCameraIdlePending = false;
    _controller?.notifyCameraGestureStarted();
    final position =
        _doubleTapPosition ??
        Offset(_logicalMapWidth / 2, _logicalMapHeight / 2);
    _bridge!.scaleBy(2, position.dx, position.dy);
    _renderGesture();
    widget.onCameraIdle?.call();
    _ensureRepaintLoop();
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (!_initialized) {
      _panSamples.clear();
      _trackpadGestureActive = false;
      return;
    }
    // Reproject only. Extracting here re-reads placement boxes that may still
    // be in an older camera's screen space (placement is rate-limited ~300ms),
    // which freezes labels at a wrong offset until the next good extract.
    // New labels are picked up when the camera settles (idle repaint loop).
    _renderGesture();

    var startedFling = false;
    if (details.pointerCount <= 1 && widget.scrollGesturesEnabled) {
      final velocity = _estimateVelocity();
      if (velocity.distance > _flingThreshold) {
        _startFling(velocity);
        startedFling = true;
      }
    }
    _panSamples.clear();
    _trackpadGestureActive = false;
    _previousTrackpadScale = 1;
    _previousTrackpadRotation = 0;
    if (!startedFling) {
      widget.onCameraIdle?.call();
      _ensureRepaintLoop();
    }
  }

  void _startFling(Offset velocity) {
    if (!_initialized) return;
    _flingVelocity = velocity;
    _previousFlingProgress = 0.0;
    _flingController.forward(from: 0.0);
  }

  void _onFlingTick() {
    if (!mounted || !_initialized || _bridge == null) return;
    final t = _flingController.value;
    final eased = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t);
    final previous = _previousFlingProgress;
    _previousFlingProgress = eased;
    final delta = eased - previous;
    final dx = _flingVelocity.dx * 0.998 / 4.0 * delta;
    final dy = _flingVelocity.dy * 0.998 / 4.0 * delta;
    if (dx.abs() > 0.01 || dy.abs() > 0.01) {
      _bridge!.moveBy(dx, dy);
      // Reproject only — same rule as pan: keep anchors geographic until settle.
      _renderGesture();
    }
  }

  void _onFlingStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed ||
        !mounted ||
        !_initialized ||
        _bridge == null) {
      return;
    }
    // Still reproject only. Label re-extraction waits for map idle so placement
    // can catch up to the stopped camera (see _ensureRepaintLoop).
    _renderGesture();
    widget.onCameraIdle?.call();
    _ensureRepaintLoop();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (!_initialized) return;
    if (_trackpadGestureActive) {
      var cameraChanged = false;
      if (widget.scrollGesturesEnabled &&
          details.focalPointDelta != Offset.zero) {
        _bridge!.moveBy(details.focalPointDelta.dx, details.focalPointDelta.dy);
        cameraChanged = true;
      }
      if (widget.zoomGesturesEnabled) {
        final scale = maplibreTrackpadScaleDelta(
          details.scale,
          _previousTrackpadScale,
        );
        if ((scale - 1).abs() > 0.0001) {
          _bridge!.scaleBy(
            scale,
            details.localFocalPoint.dx,
            details.localFocalPoint.dy,
          );
          cameraChanged = true;
        }
      }
      if (widget.rotateGesturesEnabled) {
        final rotation = _normalizedAngleDelta(
          details.rotation,
          _previousTrackpadRotation,
        );
        if (rotation.abs() > 0.0001) {
          _bridge!.rotateBy(maplibreBearingGestureDelta(rotation));
          cameraChanged = true;
        }
      }
      _previousTrackpadScale = details.scale;
      _previousTrackpadRotation = details.rotation;
      if (cameraChanged) _renderGesture();
      return;
    }
    if (details.pointerCount >= 2) {
      return;
    } else {
      if (!widget.scrollGesturesEnabled) return;
      final delta = details.focalPointDelta;
      _panSamples.add(_PanSample(delta: delta, time: DateTime.now()));
      if (_panSamples.length > _maxPanSamples) {
        _panSamples.removeAt(0);
      }
      _bridge!.moveBy(delta.dx, delta.dy);
      _renderGesture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalSize = maplibreLayoutSize(constraints);
        if (logicalSize == null) return const SizedBox.shrink();

        final initializationError = _initializationError;
        if (initializationError != null) {
          return ErrorWidget(initializationError);
        }

        final dpr = MediaQuery.devicePixelRatioOf(context);
        _scheduleViewportUpdate(logicalSize, dpr);

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.hardEdge,
            children: [
              const SizedBox.expand(),
              Listener(
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerEnd,
                onPointerCancel: _onPointerEnd,
                onPointerSignal: _onPointerSignal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: _onScaleStart,
                  onScaleUpdate: _onScaleUpdate,
                  onScaleEnd: _onScaleEnd,
                  onTapUp: widget.onMapClick == null
                      ? null
                      : (details) => _emitMapClick(
                          details.localPosition,
                          widget.onMapClick,
                        ),
                  onLongPressStart: widget.onMapLongClick == null
                      ? null
                      : (details) => _emitMapClick(
                          details.localPosition,
                          widget.onMapLongClick,
                        ),
                  onDoubleTapDown:
                      maplibreDoubleClickZoomIsEnabled(
                        widget.doubleClickZoomEnabled,
                        widget.zoomGesturesEnabled,
                      )
                      ? _onDoubleTapDown
                      : null,
                  onDoubleTap:
                      maplibreDoubleClickZoomIsEnabled(
                        widget.doubleClickZoomEnabled,
                        widget.zoomGesturesEnabled,
                      )
                      ? _onDoubleTap
                      : null,
                  child: _rendered
                      ? CustomPaint(
                          painter: _MapGpuPainter(
                            bridge: _bridge!,
                            gpuRenderer: _gpuRenderer!,
                            resources: _gpuResources,
                            width: _mapWidth,
                            height: _mapHeight,
                            logicalWidth: _logicalMapWidth,
                            logicalHeight: _logicalMapHeight,
                            devicePixelRatio: _dpr,
                            frameSeq: _gpuRenderer!.frameSeq,
                            gpuRenderCallback: widget.gpuRenderCallback,
                            repaint: widget.gpuRepaint,
                          ),
                          size: Size.infinite,
                        )
                      : const SizedBox.expand(),
                ),
              ),
              _buildSymbolOverlay(logicalSize),
              if (!_styleLoaded && widget.foregroundLoadColor != null)
                IgnorePointer(
                  child: ColoredBox(color: widget.foregroundLoadColor!),
                ),
              MapLibreMapControls(
                mapSize: logicalSize,
                controller: _controller,
                compassEnabled: widget.compassEnabled,
                logoEnabled: widget.logoEnabled,
                logoViewPosition: widget.logoViewPosition,
                logoViewMargins: widget.logoViewMargins,
                compassViewPosition: widget.compassViewPosition,
                compassViewMargins: widget.compassViewMargins,
                attributionButtonEnabled: widget.attributionButtonEnabled,
                attributionButtonPosition: widget.attributionButtonPosition,
                attributionButtonMargins: widget.attributionButtonMargins,
                scaleControlEnabled: widget.scaleControlEnabled,
                scaleControlPosition: widget.scaleControlPosition,
                scaleControlUnit: widget.scaleControlUnit,
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _TwoFingerGestureMode { undecided, transform, tilt }

class _PanSample {
  final Offset delta;
  final DateTime time;
  const _PanSample({required this.delta, required this.time});
}

class _MapGpuPainter extends CustomPainter {
  final MaplibreBridge bridge;
  final GpuFrameRenderer gpuRenderer;
  final _MapGpuResources resources;
  final int width;
  final int height;
  final int logicalWidth;
  final int logicalHeight;
  final double devicePixelRatio;
  final int frameSeq;
  final MapLibreGpuRenderCallback? gpuRenderCallback;

  _MapGpuPainter({
    required this.bridge,
    required this.gpuRenderer,
    required this.resources,
    required this.width,
    required this.height,
    required this.logicalWidth,
    required this.logicalHeight,
    required this.devicePixelRatio,
    required this.frameSeq,
    required this.gpuRenderCallback,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final dstRect = Rect.fromLTWH(0, 0, size.width, size.height);

    if (frameSeq != resources.lastPaintedSeq ||
        gpuRenderCallback != null ||
        resources.hadGpuRenderCallback) {
      try {
        resources.resize(width, height);
        var idx = -1;
        for (var i = 0; i < resources.textures.length; i++) {
          if (i != resources.displayIndex) {
            idx = i;
            break;
          }
        }
        if (idx < 0) {
          final t = gpu.gpuContext.createTexture(
            gpu.StorageMode.devicePrivate,
            width,
            height,
            enableRenderTargetUsage: true,
            enableShaderReadUsage: true,
          );
          resources.textures.add(t);
          resources.images.add(t.asImage());
          idx = resources.textures.length - 1;
        }
        final texture = resources.textures[idx];
        final clearColor = bridge.frameGetClearColor();
        var depthStencilTexture = gpuRenderer.prepareDepthStencilTexture(
          texture,
        );
        gpu.RenderTarget initialRenderTarget() => gpu.RenderTarget.singleColor(
          gpu.ColorAttachment(
            texture: texture,
            clearValue: maplibreClearValue(clearColor),
          ),
          depthStencilAttachment: depthStencilTexture == null
              ? null
              : gpu.DepthStencilAttachment(
                  texture: depthStencilTexture,
                  depthLoadAction: gpu.LoadAction.clear,
                  depthStoreAction: gpu.StoreAction.store,
                  depthClearValue: 1.0,
                  stencilLoadAction: gpu.LoadAction.clear,
                  stencilStoreAction: gpu.StoreAction.store,
                  stencilClearValue: 0,
                ),
        );

        late gpu.CommandBuffer commandBuffer;
        late gpu.RenderPass renderPass;
        try {
          commandBuffer = gpu.gpuContext.createCommandBuffer();
          renderPass = commandBuffer.createRenderPass(initialRenderTarget());
        } catch (e) {
          if (depthStencilTexture == null) rethrow;
          gpuRenderer.disableDepthStencil(e);
          depthStencilTexture = null;
          commandBuffer = gpu.gpuContext.createCommandBuffer();
          renderPass = commandBuffer.createRenderPass(initialRenderTarget());
        }
        gpuRenderer.cmdBuf = commandBuffer;
        gpuRenderer.renderFrame(
          renderPass,
          texture: texture,
          initialDepthStencilTexture: depthStencilTexture,
          logicalWidth: logicalWidth.toDouble(),
          logicalHeight: logicalHeight.toDouble(),
        );
        _renderGpuOverlay(texture);

        resources.lastImage = resources.images[idx];
        resources.displayIndex = idx;
        resources.lastPaintedSeq = frameSeq;
        resources.hadGpuRenderCallback = gpuRenderCallback != null;
      } catch (e) {
        debugPrint('[MapLibreMap] paint error: $e');
      }
    }

    final image = resources.lastImage;
    if (image != null) {
      final srcRect = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      canvas.drawImageRect(image, srcRect, dstRect, Paint());
    }
  }

  @override
  bool shouldRepaint(covariant _MapGpuPainter oldDelegate) => true;

  void _renderGpuOverlay(gpu.Texture texture) {
    final callback = gpuRenderCallback;
    if (callback == null) return;

    final commandBuffer = gpu.gpuContext.createCommandBuffer();
    final renderPass = commandBuffer.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(texture: texture, loadAction: gpu.LoadAction.load),
      ),
    );
    try {
      callback(
        MapLibreGpuRenderContext(
          gpuContext: gpu.gpuContext,
          renderPass: renderPass,
          logicalSize: Size(logicalWidth.toDouble(), logicalHeight.toDouble()),
          physicalSize: Size(width.toDouble(), height.toDouble()),
          devicePixelRatio: devicePixelRatio,
          frameSequence: frameSeq,
        ),
      );
    } catch (e, st) {
      debugPrint('[MapLibreMap] gpuRenderCallback error: $e\n$st');
    } finally {
      commandBuffer.submit();
    }
  }
}

class _MapGpuResources {
  dart_ui.Image? lastImage;
  int lastPaintedSeq = -1;
  final List<gpu.Texture> textures = [];
  final List<dart_ui.Image> images = [];
  int width = 0;
  int height = 0;
  int displayIndex = -1;
  bool hadGpuRenderCallback = false;

  void resize(int nextWidth, int nextHeight) {
    if (width == nextWidth && height == nextHeight) return;
    dispose();
    width = nextWidth;
    height = nextHeight;
  }

  void dispose() {
    for (final image in images) {
      image.dispose();
    }
    textures.clear();
    images.clear();
    lastImage = null;
    lastPaintedSeq = -1;
    displayIndex = -1;
    hadGpuRenderCallback = false;
    width = 0;
    height = 0;
  }
}
