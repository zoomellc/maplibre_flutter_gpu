import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;

import 'camera.dart';
import 'map_style_resolver.dart';
import 'native/maplibre_ffi.dart';

/// Controller for a single [MapLibreMap] instance.
///
/// Obtained via [MapLibreMap.onMapCreated]. Only the subset backed by the
/// Flutter GPU bridge is implemented today.
class MapLibreMapController extends ChangeNotifier {
  MapLibreMapController._(
    this._bridge, {
    VoidCallback? onCameraChangeRequested,
    Future<void> Function(String styleString, String resolvedStyle)?
    onStyleChangeRequested,
    VoidCallback? onStyleMutationRequested,
  }) : _onCameraChangeRequested = onCameraChangeRequested,
       _onStyleChangeRequested = onStyleChangeRequested,
       _onStyleMutationRequested = onStyleMutationRequested;

  MaplibreBridge? _bridge;
  VoidCallback? _onCameraChangeRequested;
  Future<void> Function(String styleString, String resolvedStyle)?
  _onStyleChangeRequested;
  VoidCallback? _onStyleMutationRequested;
  CameraPosition? _cameraPosition;
  bool _disposed = false;
  int _cameraTransitionGeneration = 0;
  int _styleChangeGeneration = 0;

  /// Creates a controller bound to an already-initialized bridge.
  ///
  /// Package-internal; app code should use [MapLibreMap.onMapCreated].
  factory MapLibreMapController.bind(
    MaplibreBridge bridge, {
    VoidCallback? onCameraChangeRequested,
    Future<void> Function(String styleString, String resolvedStyle)?
    onStyleChangeRequested,
    VoidCallback? onStyleMutationRequested,
  }) {
    final c = MapLibreMapController._(
      bridge,
      onCameraChangeRequested: onCameraChangeRequested,
      onStyleChangeRequested: onStyleChangeRequested,
      onStyleMutationRequested: onStyleMutationRequested,
    );
    c._syncCameraFromBridge();
    return c;
  }

  /// The current camera position, or `null` before the first frame.
  CameraPosition? get cameraPosition {
    _ensureNotDisposed();
    return _cameraPosition;
  }

  /// True while a programmatic native camera transition is active.
  bool get isCameraMoving {
    _ensureNotDisposed();
    return _bridge!.isCameraMoving();
  }

  /// Replaces the current style from raw JSON, URL, file, or Flutter asset.
  Future<void> setStyle(String styleString) async {
    _ensureNotDisposed();
    final generation = ++_styleChangeGeneration;
    final resolvedStyle = await resolveMapStyleString(styleString);
    _ensureNotDisposed();
    if (generation != _styleChangeGeneration) return;
    final callback = _onStyleChangeRequested;
    if (callback != null) {
      await callback(styleString, resolvedStyle);
    } else {
      _bridge!.setStyle(resolvedStyle);
    }
  }

  /// Returns the current style JSON, or `null` when unavailable.
  Future<String?> getStyle() async {
    _ensureNotDisposed();
    return _bridge!.getStyle();
  }

  Future<List> getLayerIds() async {
    _ensureNotDisposed();
    return _bridge!.getLayerIds();
  }

  Future<List<String>> getSourceIds() async {
    _ensureNotDisposed();
    return _bridge!.getSourceIds();
  }

  Future<void> setLayerVisibility(String layerId, bool visible) async {
    _ensureNotDisposed();
    _bridge!.setLayerVisibility(layerId, visible);
    _onStyleMutationRequested?.call();
  }

  Future<bool?> getLayerVisibility(String layerId) async {
    _ensureNotDisposed();
    return _bridge!.getLayerVisibility(layerId);
  }

  Future<void> setFilter(String layerId, dynamic filter) async {
    _ensureNotDisposed();
    final filterJson = jsonEncode(filter);
    _bridge!.setFilterJson(layerId, filterJson);
    _onStyleMutationRequested?.call();
  }

  Future<bool> setLayerFilter(String layerId, String filter) async {
    _ensureNotDisposed();
    final changed = _bridge!.setLayerFilterJson(layerId, filter);
    if (changed) _onStyleMutationRequested?.call();
    return changed;
  }

  Future<dynamic> getFilter(String layerId) async {
    _ensureNotDisposed();
    final filter = _bridge!.getLayerFilterJson(layerId);
    return filter == null ? null : jsonDecode(filter);
  }

  /// Moves the map camera immediately (no animation).
  Future<bool?> moveCamera(CameraUpdate update) async {
    _ensureNotDisposed();
    _cameraTransitionGeneration++;
    final applied = _applyCameraUpdate(
      update,
      duration: Duration.zero,
      interpolation: null,
      flyTo: false,
    );
    if (!applied) return false;
    _cameraChanged();
    return true;
  }

  /// Animates the map camera. The result is false when MapLibre rejects the
  /// update or the controller is disposed before completion.
  Future<bool?> animateCamera(CameraUpdate update, {Duration? duration}) async {
    _ensureNotDisposed();
    final transitionDuration = duration ?? const Duration(milliseconds: 300);
    final generation = ++_cameraTransitionGeneration;
    final applied = _applyCameraUpdate(
      update,
      duration: transitionDuration,
      interpolation: null,
      flyTo: true,
    );
    if (!applied) return false;
    _cameraChanged();
    return _waitForCameraTransition(transitionDuration, generation);
  }

  /// Eases the camera using the selected interpolation curve.
  Future<bool> easeCamera(
    CameraUpdate update, {
    Duration? duration,
    CameraAnimationInterpolation? interpolation,
  }) async {
    _ensureNotDisposed();
    final transitionDuration = duration ?? const Duration(milliseconds: 300);
    final generation = ++_cameraTransitionGeneration;
    final applied = _applyCameraUpdate(
      update,
      duration: transitionDuration,
      interpolation: interpolation,
      flyTo: false,
    );
    if (!applied) return false;
    _cameraChanged();
    return _waitForCameraTransition(transitionDuration, generation);
  }

  /// Queries MapLibre instead of relying on the last reported widget frame.
  Future<CameraPosition?> queryCameraPosition() async {
    _ensureNotDisposed();
    _syncCameraFromBridge();
    return _cameraPosition;
  }

  /// Projects a geographic coordinate to logical screen pixels.
  Future<math.Point<num>> toScreenLocation(LatLng latLng) async {
    final value = toScreenOffset(latLng);
    return math.Point<double>(value.dx, value.dy);
  }

  /// Projects many coordinates in input order.
  Future<List<math.Point<num>>> toScreenLocationBatch(
    Iterable<LatLng> latLngs,
  ) async {
    _ensureNotDisposed();
    final result = <math.Point<num>>[];
    for (final latLng in latLngs) {
      final value = _bridge!.latLonToScreen(latLng.latitude, latLng.longitude);
      result.add(math.Point<double>(value.dx, value.dy));
    }
    return result;
  }

  /// Synchronous Flutter-Offset projection used by Flutter overlays.
  Offset toScreenOffset(LatLng latLng) {
    _ensureNotDisposed();
    return _bridge!.latLonToScreen(latLng.latitude, latLng.longitude);
  }

  /// Converts logical screen pixels into a geographic coordinate.
  Future<LatLng> toLatLng(math.Point<num> screenLocation) async {
    return toLatLngOffset(
      Offset(screenLocation.x.toDouble(), screenLocation.y.toDouble()),
    );
  }

  /// Synchronous Offset variant used by Flutter overlays and controls.
  LatLng toLatLngOffset(Offset screenLocation) {
    _ensureNotDisposed();
    final result = _bridge!.screenToLatLon(
      screenLocation.dx,
      screenLocation.dy,
    );
    return LatLng(result.latitude, result.longitude);
  }

  /// Returns current visible geographic bounds.
  Future<LatLngBounds> getVisibleRegion() async {
    _ensureNotDisposed();
    final region = _bridge!.getVisibleRegion();
    return LatLngBounds(
      southwest: LatLng(region.south, region.west),
      northeast: LatLng(region.north, region.east),
    );
  }

  /// Returns ground meters represented by one logical pixel at [latitude].
  Future<double> getMetersPerPixelAtLatitude(double latitude) async {
    _ensureNotDisposed();
    return _bridge!.getMetersPerPixelAtLatitude(latitude);
  }

  /// Fits the given bounds with equal logical-pixel padding.
  Future<void> setCameraBounds({
    required double west,
    required double north,
    required double south,
    required double east,
    required int padding,
  }) async {
    await animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(south, west),
          northeast: LatLng(north, east),
        ),
        left: padding.toDouble(),
        top: padding.toDouble(),
        right: padding.toDouble(),
        bottom: padding.toDouble(),
      ),
      duration: const Duration(milliseconds: 200),
    );
  }

  /// Changes the logical viewport insets.
  Future<void> updateContentInsets(
    EdgeInsets insets, [
    bool animated = false,
  ]) async {
    _ensureNotDisposed();
    final generation = ++_cameraTransitionGeneration;
    _bridge!.setContentInsets(
      top: insets.top,
      left: insets.left,
      bottom: insets.bottom,
      right: insets.right,
      animated: animated,
    );
    _cameraChanged();
    if (animated) {
      await _waitForCameraTransition(
        const Duration(milliseconds: 300),
        generation,
      );
    }
  }

  /// Resets the camera bearing to north without changing its target or zoom.
  Future<void> resetNorth() async {
    _ensureNotDisposed();
    final current = _cameraPosition;
    if (current == null) return;
    await moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: current.target,
          zoom: current.zoom,
          tilt: current.tilt,
        ),
      ),
    );
  }

  bool _applyCameraUpdate(
    CameraUpdate update, {
    required Duration duration,
    required CameraAnimationInterpolation? interpolation,
    required bool flyTo,
  }) {
    final current = _cameraPosition;
    if (current == null) return false;
    final easing = interpolation?.index ?? -1;
    switch (update.kind) {
      case CameraUpdateKind.bounds:
        final bounds = update.bounds!;
        return _bridge!.fitCameraBounds(
          south: bounds.southwest.latitude,
          west: bounds.southwest.longitude,
          north: bounds.northeast.latitude,
          east: bounds.northeast.longitude,
          left: update.left,
          top: update.top,
          right: update.right,
          bottom: update.bottom,
          duration: duration,
          easing: easing,
          flyTo: flyTo,
        );
      case CameraUpdateKind.scroll:
        if (duration == Duration.zero) {
          _bridge!.moveBy(update.dx, update.dy);
          return true;
        }
        return _bridge!.moveByAnimated(
          dx: update.dx,
          dy: update.dy,
          duration: duration,
          easing: easing,
        );
      case CameraUpdateKind.zoomBy:
        return _bridge!.scaleByAnimated(
          amount: update.amount,
          focus: update.focus,
          duration: duration,
          easing: easing,
        );
      default:
        final next = update.resolveAgainst(current);
        if (duration == Duration.zero) {
          _bridge!.setCameraFull(
            next.target.latitude,
            next.target.longitude,
            next.zoom,
            next.bearing,
            next.tilt,
          );
          return true;
        }
        if (flyTo) {
          return _bridge!.animateCameraFull(
            latitude: next.target.latitude,
            longitude: next.target.longitude,
            zoom: next.zoom,
            bearing: next.bearing,
            pitch: next.tilt,
            duration: duration,
          );
        }
        return _bridge!.easeCameraFull(
          latitude: next.target.latitude,
          longitude: next.target.longitude,
          zoom: next.zoom,
          bearing: next.bearing,
          pitch: next.tilt,
          duration: duration,
          easing: easing,
        );
    }
  }

  void _cameraChanged() {
    final callback = _onCameraChangeRequested;
    if (callback != null) {
      callback();
    } else if (_syncCameraFromBridge()) {
      notifyListeners();
    }
  }

  Future<bool> _waitForCameraTransition(
    Duration duration,
    int generation,
  ) async {
    if (duration == Duration.zero) return true;
    final timeout = duration + const Duration(seconds: 2);
    final stopwatch = Stopwatch()..start();
    var observedMoving = false;
    while (!_disposed && stopwatch.elapsed < timeout) {
      if (generation != _cameraTransitionGeneration) return false;
      final moving = _bridge!.isCameraMoving();
      observedMoving = observedMoving || moving;
      if (observedMoving && !moving) {
        _syncCameraFromBridge();
        return true;
      }
      if (!observedMoving && stopwatch.elapsed >= duration) {
        _syncCameraFromBridge();
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    return !_disposed &&
        generation == _cameraTransitionGeneration &&
        !_bridge!.isCameraMoving();
  }

  /// Cancels completion of an active programmatic camera Future when a
  /// gesture takes ownership of the camera.
  @internal
  void notifyCameraGestureStarted() {
    if (_disposed) return;
    _bridge!.cancelCameraTransitions();
    _cameraTransitionGeneration++;
  }

  /// Latest placed symbol labels (text/icons) from the native placement pass.
  List<LabelData> getPlacedLabels() {
    _ensureNotDisposed();
    return _bridge!.getPlacedLabels();
  }

  /// True when the map has no pending tile/network work after the last frame.
  bool get isMapIdle {
    _ensureNotDisposed();
    return _bridge!.isMapIdle();
  }

  /// Package-internal access to the FFI bridge.
  @visibleForTesting
  MaplibreBridge get bridge {
    _ensureNotDisposed();
    return _bridge!;
  }

  bool _syncCameraFromBridge() {
    final next = CameraPosition(
      bearing: _bridge!.getCameraBearing(),
      target: LatLng(_bridge!.getCameraLat(), _bridge!.getCameraLon()),
      tilt: _bridge!.getCameraPitch(),
      zoom: _bridge!.getCameraZoom(),
    );
    if (next == _cameraPosition) return false;
    _cameraPosition = next;
    return true;
  }

  /// Called by [MapLibreMap] after gesture-driven camera changes.
  ///
  /// Returns whether the native camera differs from the cached position.
  bool notifyCameraChanged({bool notifyListeners = true}) {
    _ensureNotDisposed();
    final changed = _syncCameraFromBridge();
    if (changed && notifyListeners) super.notifyListeners();
    return changed;
  }

  void _ensureNotDisposed() {
    if (_disposed) {
      throw StateError('MapLibreMapController used after dispose');
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cameraTransitionGeneration++;
    _styleChangeGeneration++;
    _onCameraChangeRequested = null;
    _onStyleChangeRequested = null;
    _onStyleMutationRequested = null;
    _bridge = null;
    _cameraPosition = null;
    super.dispose();
  }
}
