import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'abi_generated.dart';
import 'bridge_lifecycle.dart';

typedef FrameClearColor = ({
  double red,
  double green,
  double blue,
  double alpha,
});

// ── Symbol data from placed symbols (text and/or icon) ──────────────
class LabelData {
  final int crossTileId; // stable MapLibre CrossTileSymbolIndex identity
  final double lat; // text anchor
  final double lon;
  final double iconLat; // icon anchor
  final double iconLon;
  final double fontSize;
  final double textR, textG, textB, textA;
  final double haloR, haloG, haloB, haloA;
  final double haloWidth;
  final double textW, textH; // text collision box size (logical px)
  final double iconW, iconH; // icon collision box size (logical px)
  final double iconScale; // evaluated icon-size
  final double iconOpacity;
  final double iconR, iconG, iconB, iconA; // icon-color (SDF icons)
  final double textOffsetX, textOffsetY; // screen-pixel offset from map anchor
  final double iconOffsetX, iconOffsetY;
  final bool textPlaced;
  final bool iconPlaced;
  final bool alongLine; // line placement (street names)
  final double angle; // label angle in radians (line placement only)
  final String text;
  final String layer;
  final String icon; // icon-image ID ('' when none)

  const LabelData({
    this.crossTileId = 0,
    required this.lat,
    required this.lon,
    this.iconLat = 0,
    this.iconLon = 0,
    required this.fontSize,
    required this.textR,
    required this.textG,
    required this.textB,
    required this.textA,
    required this.haloR,
    required this.haloG,
    required this.haloB,
    required this.haloA,
    required this.haloWidth,
    this.textW = 0,
    this.textH = 0,
    this.iconW = 0,
    this.iconH = 0,
    this.iconScale = 1,
    this.iconOpacity = 1,
    this.iconR = 0,
    this.iconG = 0,
    this.iconB = 0,
    this.iconA = 1,
    this.textOffsetX = 0,
    this.textOffsetY = 0,
    this.iconOffsetX = 0,
    this.iconOffsetY = 0,
    this.textPlaced = true,
    this.iconPlaced = false,
    this.alongLine = false,
    this.angle = 0,
    required this.text,
    required this.layer,
    this.icon = '',
  });

  /// Converts premultiplied color channels to a Flutter Color.
  static Color _pmColor(double r, double g, double b, double a) {
    final ai = (a * 255).round().clamp(0, 255);
    if (ai == 0) return const Color(0x00000000);
    // premultiplied → straight
    final ri = (r / a * 255).round().clamp(0, 255);
    final gi = (g / a * 255).round().clamp(0, 255);
    final bi = (b / a * 255).round().clamp(0, 255);
    return Color.fromARGB(ai, ri, gi, bi);
  }

  Color get textColor => _pmColor(textR, textG, textB, textA);
  Color get haloColor => _pmColor(haloR, haloG, haloB, haloA);
  Color get iconColor => _pmColor(iconR, iconG, iconB, iconA);
}

// ── Native type definitions ─────────────────────────────────────────
typedef _InitN =
    Int32 Function(Int32 w, Int32 h, Float pixelRatio, Pointer<Utf8> url);
typedef _InitD =
    int Function(int w, int h, double pixelRatio, Pointer<Utf8> url);

typedef _Int32VoidN = Int32 Function();
typedef _Int32VoidD = int Function();

typedef _VoidVoidN = Void Function();
typedef _VoidVoidD = void Function();

typedef _DoubleVoidN = Double Function();
typedef _DoubleVoidD = double Function();

typedef _SetCameraN = Void Function(Double lat, Double lon, Double zoom);
typedef _SetCameraD = void Function(double lat, double lon, double zoom);

typedef _SetCameraFullN =
    Void Function(
      Double lat,
      Double lon,
      Double zoom,
      Double bearing,
      Double pitch,
    );
typedef _SetCameraFullD =
    void Function(
      double lat,
      double lon,
      double zoom,
      double bearing,
      double pitch,
    );

typedef _SetBoundsN =
    Void Function(
      Int32 hasBounds,
      Double south,
      Double west,
      Double north,
      Double east,
      Int32 hasMinZoom,
      Double minZoom,
      Int32 hasMaxZoom,
      Double maxZoom,
    );
typedef _SetBoundsD =
    void Function(
      int hasBounds,
      double south,
      double west,
      double north,
      double east,
      int hasMinZoom,
      double minZoom,
      int hasMaxZoom,
      double maxZoom,
    );

typedef _SetSizeN = Void Function(Int32 w, Int32 h);
typedef _SetSizeD = void Function(int w, int h);

typedef _GetPixelsN = Pointer<Uint8> Function();
typedef _GetPixelsD = Pointer<Uint8> Function();

typedef _MoveByN = Void Function(Double dx, Double dy);
typedef _MoveByD = void Function(double dx, double dy);

typedef _AdjustByN = Void Function(Double degrees);
typedef _AdjustByD = void Function(double degrees);

typedef _ScaleByN = Void Function(Double scale, Double cx, Double cy);
typedef _ScaleByD = void Function(double scale, double cx, double cy);

typedef _CameraEaseN =
    Int32 Function(
      Double lat,
      Double lon,
      Double zoom,
      Double bearing,
      Double pitch,
      Int32 durationMs,
      Int32 easing,
    );
typedef _CameraEaseD =
    int Function(
      double lat,
      double lon,
      double zoom,
      double bearing,
      double pitch,
      int durationMs,
      int easing,
    );

typedef _CameraFlyN = _CameraEaseN;
typedef _CameraFlyD = _CameraEaseD;

typedef _CameraMoveAnimatedN =
    Int32 Function(Double dx, Double dy, Int32 durationMs, Int32 easing);
typedef _CameraMoveAnimatedD =
    int Function(double dx, double dy, int durationMs, int easing);

typedef _CameraScaleAnimatedN =
    Int32 Function(
      Double scale,
      Int32 hasAnchor,
      Double x,
      Double y,
      Int32 durationMs,
      Int32 easing,
    );
typedef _CameraScaleAnimatedD =
    int Function(
      double scale,
      int hasAnchor,
      double x,
      double y,
      int durationMs,
      int easing,
    );

typedef _CameraFitBoundsN =
    Int32 Function(
      Double south,
      Double west,
      Double north,
      Double east,
      Double left,
      Double top,
      Double right,
      Double bottom,
      Int32 durationMs,
      Int32 easing,
      Int32 flyTo,
    );
typedef _CameraFitBoundsD =
    int Function(
      double south,
      double west,
      double north,
      double east,
      double left,
      double top,
      double right,
      double bottom,
      int durationMs,
      int easing,
      int flyTo,
    );

typedef _SetContentInsetsN =
    Int32 Function(
      Double top,
      Double left,
      Double bottom,
      Double right,
      Int32 animated,
    );
typedef _SetContentInsetsD =
    int Function(
      double top,
      double left,
      double bottom,
      double right,
      int animated,
    );

typedef _GetVisibleRegionN =
    Int32 Function(
      Pointer<Double> south,
      Pointer<Double> west,
      Pointer<Double> north,
      Pointer<Double> east,
    );
typedef _GetVisibleRegionD =
    int Function(
      Pointer<Double> south,
      Pointer<Double> west,
      Pointer<Double> north,
      Pointer<Double> east,
    );

typedef _DoubleArgN = Double Function(Double value);
typedef _DoubleArgD = double Function(double value);

typedef _StyleStringVoidN = Pointer<Utf8> Function();
typedef _StyleStringVoidD = Pointer<Utf8> Function();
typedef _StyleSetN = Int32 Function(Pointer<Utf8> value);
typedef _StyleSetD = int Function(Pointer<Utf8> value);
typedef _StyleSetVisibilityN =
    Int32 Function(Pointer<Utf8> layerId, Int32 visible);
typedef _StyleSetVisibilityD = int Function(Pointer<Utf8> layerId, int visible);
typedef _StyleGetVisibilityN =
    Int32 Function(Pointer<Utf8> layerId, Pointer<Int32> visible);
typedef _StyleGetVisibilityD =
    int Function(Pointer<Utf8> layerId, Pointer<Int32> visible);
typedef _StyleSetFilterN =
    Int32 Function(Pointer<Utf8> layerId, Pointer<Utf8> filterJson);
typedef _StyleSetFilterD =
    int Function(Pointer<Utf8> layerId, Pointer<Utf8> filterJson);
typedef _StyleGetFilterN = Pointer<Utf8> Function(Pointer<Utf8> layerId);
typedef _StyleGetFilterD = Pointer<Utf8> Function(Pointer<Utf8> layerId);

typedef _LatLonToScreenN =
    Void Function(
      Double lat,
      Double lon,
      Pointer<Double> outX,
      Pointer<Double> outY,
    );
typedef _LatLonToScreenD =
    void Function(
      double lat,
      double lon,
      Pointer<Double> outX,
      Pointer<Double> outY,
    );

class MaplibreBridge {
  static const int initSuccess = maplibreInitSuccess;
  static const int initFailure = maplibreInitFailure;
  static const int initBusy = maplibreInitBusy;

  late final DynamicLibrary _lib;
  final BridgeSessionLifecycle _lifecycle = BridgeSessionLifecycle();

  late final _InitD _init;
  late final _SetCameraD _setCamera;
  _SetCameraFullD? _setCameraFull;
  _SetBoundsD? _setBounds;
  late final _DoubleVoidD _getCameraLat;
  late final _DoubleVoidD _getCameraLon;
  late final _DoubleVoidD _getCameraZoom;
  _DoubleVoidD? _getCameraBearing;
  _DoubleVoidD? _getCameraPitch;
  _AdjustByD? _rotateBy;
  _AdjustByD? _pitchBy;
  _CameraEaseD? _cameraEase;
  _CameraFlyD? _cameraFly;
  _CameraMoveAnimatedD? _cameraMoveAnimated;
  _CameraScaleAnimatedD? _cameraScaleAnimated;
  _CameraFitBoundsD? _cameraFitBounds;
  _Int32VoidD? _isCameraMoving;
  _Int32VoidD? _cancelCameraTransitions;
  _SetContentInsetsD? _setContentInsets;
  _GetVisibleRegionD? _getVisibleRegion;
  _DoubleArgD? _getMetersPerPixelAtLatitude;
  _StyleStringVoidD? _styleLastError;
  _StyleSetD? _styleSet;
  _StyleStringVoidD? _styleGetJson;
  _StyleStringVoidD? _styleGetLayerIds;
  _StyleStringVoidD? _styleGetSourceIds;
  _StyleSetVisibilityD? _styleSetLayerVisibility;
  _StyleGetVisibilityD? _styleGetLayerVisibility;
  _StyleSetFilterD? _styleSetFilter;
  _StyleGetFilterD? _styleGetFilter;
  late final _MoveByD _moveBy;
  late final _ScaleByD _scaleBy;
  late final _LatLonToScreenD _latLonToScreen;
  _LatLonToScreenD? _screenToLatLon;
  _Int32VoidD? _isStyleLoaded;
  late final _SetSizeD _setSize;
  late final _VoidVoidD _destroy;

  // Reusable native pointers for latLonToScreen
  final Pointer<Double> _outX = calloc<Double>();
  final Pointer<Double> _outY = calloc<Double>();
  final Pointer<Double> _cameraOutput = calloc<Double>(4);
  final Pointer<Int32> _styleBoolOutput = calloc<Int32>();

  // Preallocated buffers for batch label reprojection (grow as needed)
  Pointer<Float> _labelXsBuf = calloc<Float>(64);
  Pointer<Float> _labelYsBuf = calloc<Float>(64);
  int _labelBufCap = 64;

  MaplibreBridge() {
    if (Platform.isIOS || Platform.isMacOS) {
      debugPrint(
        'Loading MapLibre bridge from process (${Platform.operatingSystem})',
      );
      _lib = DynamicLibrary.process();
    } else if (Platform.isAndroid) {
      const libraryName = 'libmaplibre_bridge.so';
      debugPrint('Loading MapLibre bridge from: $libraryName');
      _lib = DynamicLibrary.open(libraryName);
    } else if (Platform.isLinux) {
      final libPath = _resolveBridgeLibraryPath();
      debugPrint('Loading MapLibre bridge from: $libPath');
      _lib = DynamicLibrary.open(libPath);
    } else {
      throw UnsupportedError(
        'MapLibre bridge is not available on ${Platform.operatingSystem}',
      );
    }

    _init = _lib.lookupFunction<_InitN, _InitD>('maplibre_init');
    _renderFrame = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
      'maplibre_render_frame',
    );
    _isIdle = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>('maplibre_is_idle');
    _setCamera = _lib.lookupFunction<_SetCameraN, _SetCameraD>(
      'maplibre_set_camera',
    );
    try {
      _setCameraFull = _lib.lookupFunction<_SetCameraFullN, _SetCameraFullD>(
        'maplibre_set_camera_full',
      );
      _setBounds = _lib.lookupFunction<_SetBoundsN, _SetBoundsD>(
        'maplibre_set_bounds',
      );
      _getCameraBearing = _lib.lookupFunction<_DoubleVoidN, _DoubleVoidD>(
        'maplibre_get_camera_bearing',
      );
      _getCameraPitch = _lib.lookupFunction<_DoubleVoidN, _DoubleVoidD>(
        'maplibre_get_camera_pitch',
      );
      _rotateBy = _lib.lookupFunction<_AdjustByN, _AdjustByD>(
        'maplibre_rotate_by',
      );
      _pitchBy = _lib.lookupFunction<_AdjustByN, _AdjustByD>(
        'maplibre_pitch_by',
      );
      _screenToLatLon = _lib.lookupFunction<_LatLonToScreenN, _LatLonToScreenD>(
        'maplibre_screen_to_lat_lon',
      );
      _isStyleLoaded = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
        'maplibre_is_style_loaded',
      );
    } catch (_) {
      // Older bundled libraries remain usable until they are rebuilt. New
      // camera/style features gracefully fall back where possible.
    }
    try {
      _cameraEase = _lib.lookupFunction<_CameraEaseN, _CameraEaseD>(
        'maplibre_camera_ease_to',
      );
      _cameraFly = _lib.lookupFunction<_CameraFlyN, _CameraFlyD>(
        'maplibre_camera_fly_to',
      );
      _cameraMoveAnimated = _lib
          .lookupFunction<_CameraMoveAnimatedN, _CameraMoveAnimatedD>(
            'maplibre_camera_move_by_animated',
          );
      _cameraScaleAnimated = _lib
          .lookupFunction<_CameraScaleAnimatedN, _CameraScaleAnimatedD>(
            'maplibre_camera_scale_by_animated',
          );
      _cameraFitBounds = _lib
          .lookupFunction<_CameraFitBoundsN, _CameraFitBoundsD>(
            'maplibre_camera_fit_bounds',
          );
      _isCameraMoving = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
        'maplibre_is_camera_moving',
      );
      _cancelCameraTransitions = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
        'maplibre_cancel_camera_transitions',
      );
      _setContentInsets = _lib
          .lookupFunction<_SetContentInsetsN, _SetContentInsetsD>(
            'maplibre_set_content_insets',
          );
      _getVisibleRegion = _lib
          .lookupFunction<_GetVisibleRegionN, _GetVisibleRegionD>(
            'maplibre_get_visible_region',
          );
      _getMetersPerPixelAtLatitude = _lib
          .lookupFunction<_DoubleArgN, _DoubleArgD>(
            'maplibre_get_meters_per_pixel_at_latitude',
          );
    } catch (_) {
      // Camera compatibility calls require rebuilt native libraries. Each
      // public method below either has a correct fallback or reports this.
    }
    try {
      _styleLastError = _lib
          .lookupFunction<_StyleStringVoidN, _StyleStringVoidD>(
            'maplibre_style_last_error',
          );
      _styleSet = _lib.lookupFunction<_StyleSetN, _StyleSetD>(
        'maplibre_style_set',
      );
      _styleGetJson = _lib.lookupFunction<_StyleStringVoidN, _StyleStringVoidD>(
        'maplibre_style_get_json',
      );
      _styleGetLayerIds = _lib
          .lookupFunction<_StyleStringVoidN, _StyleStringVoidD>(
            'maplibre_style_get_layer_ids',
          );
      _styleGetSourceIds = _lib
          .lookupFunction<_StyleStringVoidN, _StyleStringVoidD>(
            'maplibre_style_get_source_ids',
          );
      _styleSetLayerVisibility = _lib
          .lookupFunction<_StyleSetVisibilityN, _StyleSetVisibilityD>(
            'maplibre_style_set_layer_visibility',
          );
      _styleGetLayerVisibility = _lib
          .lookupFunction<_StyleGetVisibilityN, _StyleGetVisibilityD>(
            'maplibre_style_get_layer_visibility',
          );
      _styleSetFilter = _lib.lookupFunction<_StyleSetFilterN, _StyleSetFilterD>(
        'maplibre_style_set_filter',
      );
      _styleGetFilter = _lib.lookupFunction<_StyleGetFilterN, _StyleGetFilterD>(
        'maplibre_style_get_filter',
      );
    } catch (_) {
      // Runtime style APIs require rebuilt native libraries.
    }
    _getCameraLat = _lib.lookupFunction<_DoubleVoidN, _DoubleVoidD>(
      'maplibre_get_camera_lat',
    );
    _getCameraLon = _lib.lookupFunction<_DoubleVoidN, _DoubleVoidD>(
      'maplibre_get_camera_lon',
    );
    _getCameraZoom = _lib.lookupFunction<_DoubleVoidN, _DoubleVoidD>(
      'maplibre_get_camera_zoom',
    );
    _moveBy = _lib.lookupFunction<_MoveByN, _MoveByD>('maplibre_move_by');
    _scaleBy = _lib.lookupFunction<_ScaleByN, _ScaleByD>('maplibre_scale_by');
    _latLonToScreen = _lib.lookupFunction<_LatLonToScreenN, _LatLonToScreenD>(
      'maplibre_lat_lon_to_screen',
    );
    _setSize = _lib.lookupFunction<_SetSizeN, _SetSizeD>('maplibre_set_size');
    _destroy = _lib.lookupFunction<_VoidVoidN, _VoidVoidD>('maplibre_destroy');
    _getDrawableCount = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
      'maplibre_get_drawable_count',
    );
    _getDrawableSummary = _lib.lookupFunction<_GetPixelsN, _GetPixelsD>(
      'maplibre_get_drawable_summary',
    );

    _initDrawCommandFFI();
  }

  int init(int width, int height, double pixelRatio, String styleUrl) {
    return _lifecycle.initialize(() {
      final urlPtr = styleUrl.toNativeUtf8();
      try {
        return _init(width, height, pixelRatio, urlPtr.cast());
      } finally {
        calloc.free(urlPtr);
      }
    });
  }

  int renderFrame() {
    _lifecycle.ensureActive();
    return _renderFrame();
  }

  /// True when the map is fully rendered and settled (no pending tiles or
  /// transitions after the last rendered frame).
  bool isMapIdle() {
    _lifecycle.ensureActive();
    return _isIdle() != 0;
  }

  /// True after MapLibre has parsed and loaded the current style document.
  bool isStyleLoaded() {
    _lifecycle.ensureActive();
    final callback = _isStyleLoaded;
    return callback == null || callback() != 0;
  }

  void setStyle(String styleValue) {
    _lifecycle.ensureActive();
    final callback = _styleSet;
    if (callback == null) {
      throw UnsupportedError('setStyle requires rebuilt native libraries');
    }
    final value = styleValue.toNativeUtf8();
    try {
      if (callback(value) == 0) _throwStyleError('setStyle failed');
    } finally {
      calloc.free(value);
    }
  }

  String? getStyle() {
    _lifecycle.ensureActive();
    final callback = _styleGetJson;
    if (callback == null) {
      throw UnsupportedError('getStyle requires rebuilt native libraries');
    }
    final value = callback();
    return value.address == 0 ? null : value.toDartString();
  }

  List<String> getLayerIds() => _readStyleStringList(
    _styleGetLayerIds,
    'getLayerIds requires rebuilt native libraries',
  );

  List<String> getSourceIds() => _readStyleStringList(
    _styleGetSourceIds,
    'getSourceIds requires rebuilt native libraries',
  );

  void setLayerVisibility(String layerId, bool visible) {
    _lifecycle.ensureActive();
    final callback = _styleSetLayerVisibility;
    if (callback == null) {
      throw UnsupportedError(
        'setLayerVisibility requires rebuilt native libraries',
      );
    }
    final id = layerId.toNativeUtf8();
    try {
      if (callback(id, visible ? 1 : 0) == 0) {
        _throwStyleError('setLayerVisibility failed');
      }
    } finally {
      calloc.free(id);
    }
  }

  bool? getLayerVisibility(String layerId) {
    _lifecycle.ensureActive();
    final callback = _styleGetLayerVisibility;
    if (callback == null) {
      throw UnsupportedError(
        'getLayerVisibility requires rebuilt native libraries',
      );
    }
    final id = layerId.toNativeUtf8();
    try {
      final status = callback(id, _styleBoolOutput);
      if (status < 0) _throwStyleError('getLayerVisibility failed');
      if (status == 0) return null;
      return _styleBoolOutput.value != 0;
    } finally {
      calloc.free(id);
    }
  }

  bool setLayerFilterJson(String layerId, String filterJson) {
    _lifecycle.ensureActive();
    final callback = _styleSetFilter;
    if (callback == null) {
      throw UnsupportedError('setFilter requires rebuilt native libraries');
    }
    final id = layerId.toNativeUtf8();
    final filter = filterJson.toNativeUtf8();
    try {
      return callback(id, filter) != 0;
    } finally {
      calloc.free(filter);
      calloc.free(id);
    }
  }

  void setFilterJson(String layerId, String filterJson) {
    if (!setLayerFilterJson(layerId, filterJson)) {
      _throwStyleError('setFilter failed');
    }
  }

  String? getLayerFilterJson(String layerId) {
    _lifecycle.ensureActive();
    final callback = _styleGetFilter;
    if (callback == null) {
      throw UnsupportedError('getFilter requires rebuilt native libraries');
    }
    final id = layerId.toNativeUtf8();
    try {
      final value = callback(id);
      if (value.address == 0) _throwStyleError('getFilter failed');
      return value.toDartString();
    } finally {
      calloc.free(id);
    }
  }

  List<String> _readStyleStringList(
    _StyleStringVoidD? callback,
    String unsupportedMessage,
  ) {
    _lifecycle.ensureActive();
    if (callback == null) throw UnsupportedError(unsupportedMessage);
    final value = callback();
    if (value.address == 0) _throwStyleError(unsupportedMessage);
    final decoded = jsonDecode(value.toDartString());
    if (decoded is! List) {
      throw StateError('MapLibre returned an invalid style ID list');
    }
    return decoded.whereType<String>().toList(growable: false);
  }

  Never _throwStyleError(String fallback) {
    final value = _styleLastError?.call();
    final message = value == null || value.address == 0
        ? fallback
        : value.toDartString();
    throw StateError(message.isEmpty ? fallback : message);
  }

  late final _Int32VoidD _renderFrame;
  late final _Int32VoidD _isIdle;

  void setCamera(double lat, double lon, double zoom) {
    _lifecycle.ensureActive();
    _setCamera(lat, lon, zoom);
  }

  void setCameraFull(
    double lat,
    double lon,
    double zoom,
    double bearing,
    double pitch,
  ) {
    _lifecycle.ensureActive();
    final callback = _setCameraFull;
    if (callback != null) {
      callback(lat, lon, zoom, bearing, pitch);
    } else {
      _setCamera(lat, lon, zoom);
    }
  }

  bool easeCameraFull({
    required double latitude,
    required double longitude,
    required double zoom,
    required double bearing,
    required double pitch,
    required Duration duration,
    required int easing,
  }) {
    _lifecycle.ensureActive();
    final callback = _cameraEase;
    if (callback == null) {
      setCameraFull(latitude, longitude, zoom, bearing, pitch);
      return true;
    }
    return callback(
          latitude,
          longitude,
          zoom,
          bearing,
          pitch,
          duration.inMilliseconds,
          easing,
        ) !=
        0;
  }

  bool animateCameraFull({
    required double latitude,
    required double longitude,
    required double zoom,
    required double bearing,
    required double pitch,
    required Duration duration,
  }) {
    _lifecycle.ensureActive();
    final callback = _cameraFly;
    if (callback == null) {
      return easeCameraFull(
        latitude: latitude,
        longitude: longitude,
        zoom: zoom,
        bearing: bearing,
        pitch: pitch,
        duration: duration,
        easing: -1,
      );
    }
    return callback(
          latitude,
          longitude,
          zoom,
          bearing,
          pitch,
          duration.inMilliseconds,
          -1,
        ) !=
        0;
  }

  bool moveByAnimated({
    required double dx,
    required double dy,
    required Duration duration,
    required int easing,
  }) {
    _lifecycle.ensureActive();
    final callback = _cameraMoveAnimated;
    if (callback == null) {
      moveBy(dx, dy);
      return true;
    }
    return callback(dx, dy, duration.inMilliseconds, easing) != 0;
  }

  bool scaleByAnimated({
    required double amount,
    Offset? focus,
    required Duration duration,
    required int easing,
  }) {
    _lifecycle.ensureActive();
    final scale = math.pow(2.0, amount).toDouble();
    final callback = _cameraScaleAnimated;
    if (callback == null) {
      if (focus != null) {
        scaleBy(scale, focus.dx, focus.dy);
      } else {
        setCameraFull(
          getCameraLat(),
          getCameraLon(),
          getCameraZoom() + amount,
          getCameraBearing(),
          getCameraPitch(),
        );
      }
      return true;
    }
    return callback(
          scale,
          focus == null ? 0 : 1,
          focus?.dx ?? 0,
          focus?.dy ?? 0,
          duration.inMilliseconds,
          easing,
        ) !=
        0;
  }

  bool fitCameraBounds({
    required double south,
    required double west,
    required double north,
    required double east,
    required double left,
    required double top,
    required double right,
    required double bottom,
    required Duration duration,
    required int easing,
    required bool flyTo,
  }) {
    _lifecycle.ensureActive();
    final callback = _cameraFitBounds;
    if (callback == null) {
      throw UnsupportedError(
        'CameraUpdate.newLatLngBounds requires rebuilt native libraries',
      );
    }
    return callback(
          south,
          west,
          north,
          east,
          left,
          top,
          right,
          bottom,
          duration.inMilliseconds,
          easing,
          flyTo ? 1 : 0,
        ) !=
        0;
  }

  bool isCameraMoving() {
    _lifecycle.ensureActive();
    return (_isCameraMoving?.call() ?? 0) != 0;
  }

  void cancelCameraTransitions() {
    _lifecycle.ensureActive();
    _cancelCameraTransitions?.call();
  }

  void setContentInsets({
    required double top,
    required double left,
    required double bottom,
    required double right,
    required bool animated,
  }) {
    _lifecycle.ensureActive();
    final callback = _setContentInsets;
    if (callback == null) {
      throw UnsupportedError(
        'updateContentInsets requires rebuilt native libraries',
      );
    }
    if (callback(top, left, bottom, right, animated ? 1 : 0) == 0) {
      throw StateError('MapLibre rejected the content insets');
    }
  }

  ({double south, double west, double north, double east}) getVisibleRegion() {
    _lifecycle.ensureActive();
    final callback = _getVisibleRegion;
    if (callback == null) {
      throw UnsupportedError(
        'getVisibleRegion requires rebuilt native libraries',
      );
    }
    final result = callback(
      _cameraOutput,
      _cameraOutput + 1,
      _cameraOutput + 2,
      _cameraOutput + 3,
    );
    if (result == 0) {
      throw StateError('MapLibre could not determine the visible region');
    }
    return (
      south: _cameraOutput[0],
      west: _cameraOutput[1],
      north: _cameraOutput[2],
      east: _cameraOutput[3],
    );
  }

  double getMetersPerPixelAtLatitude(double latitude) {
    _lifecycle.ensureActive();
    final callback = _getMetersPerPixelAtLatitude;
    if (callback != null) return callback(latitude);
    final clampedLatitude = latitude.clamp(-85.0511287798066, 85.0511287798066);
    return math.cos(clampedLatitude * math.pi / 180) *
        2 *
        math.pi *
        6378137.0 /
        (512 * math.pow(2, getCameraZoom()));
  }

  void setBounds({
    double? south,
    double? west,
    double? north,
    double? east,
    double? minZoom,
    double? maxZoom,
  }) {
    _lifecycle.ensureActive();
    final hasBounds =
        south != null && west != null && north != null && east != null;
    _setBounds?.call(
      hasBounds ? 1 : 0,
      south ?? 0,
      west ?? 0,
      north ?? 0,
      east ?? 0,
      minZoom == null ? 0 : 1,
      minZoom ?? 0,
      maxZoom == null ? 0 : 1,
      maxZoom ?? 0,
    );
  }

  double getCameraLat() {
    _lifecycle.ensureActive();
    return _getCameraLat();
  }

  double getCameraLon() {
    _lifecycle.ensureActive();
    return _getCameraLon();
  }

  double getCameraZoom() {
    _lifecycle.ensureActive();
    return _getCameraZoom();
  }

  double getCameraBearing() {
    _lifecycle.ensureActive();
    return _getCameraBearing?.call() ?? 0;
  }

  double getCameraPitch() {
    _lifecycle.ensureActive();
    return _getCameraPitch?.call() ?? 0;
  }

  void moveBy(double dx, double dy) {
    _lifecycle.ensureActive();
    _moveBy(dx, dy);
  }

  void scaleBy(double scale, double cx, double cy) {
    _lifecycle.ensureActive();
    _scaleBy(scale, cx, cy);
  }

  void rotateBy(double degrees) {
    _lifecycle.ensureActive();
    _rotateBy?.call(degrees);
  }

  void pitchBy(double degrees) {
    _lifecycle.ensureActive();
    _pitchBy?.call(degrees);
  }

  Offset latLonToScreen(double lat, double lon) {
    _lifecycle.ensureActive();
    _latLonToScreen(lat, lon, _outX, _outY);
    return Offset(_outX.value, _outY.value);
  }

  ({double latitude, double longitude}) screenToLatLon(double x, double y) {
    _lifecycle.ensureActive();
    final callback = _screenToLatLon;
    if (callback == null) {
      throw UnsupportedError(
        'screenToLatLon requires rebuilt MapLibre native libraries',
      );
    }
    callback(x, y, _outX, _outY);
    return (latitude: _outX.value, longitude: _outY.value);
  }

  void setSize(int width, int height) {
    _lifecycle.ensureActive();
    _setSize(width, height);
  }

  int getDrawableCount() {
    _lifecycle.ensureActive();
    return _getDrawableCount();
  }

  String getDrawableSummary() {
    _lifecycle.ensureActive();
    final ptr = _getDrawableSummary();
    if (ptr == nullptr) return '';
    return ptr.cast<Utf8>().toDartString();
  }

  late final _Int32VoidD _getDrawableCount;
  late final _GetPixelsD _getDrawableSummary;

  // ── Label data FFI ─────────────────────────────────────────────────
  _Int32VoidD? _getLabelCount;
  Pointer<Void> Function()? _getLabels;
  _Int32VoidD? _getLabelStride;
  void Function(Pointer<Float>, Pointer<Float>)? _reprojectLabels;
  int Function()? _getLabelsVersion;
  void Function()? _requestLabelExtraction;

  // ── DrawCommand-based FFI (FlutterGPU backend) ──────────────────────
  _VoidVoidD? _frameBegin;
  _VoidVoidD? _frameEnd;
  _Int32VoidD? _frameGetCommandCount;
  Pointer<Void> Function()? _frameGetCommands;
  _Int32VoidD? _frameGetCommandStride;
  Pointer<Float> Function()? _frameGetClearColor;

  void _initDrawCommandFFI() {
    try {
      _getLabelCount = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
        'maplibre_get_label_count',
      );
      _getLabels = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_get_labels',
          );
      _getLabelStride = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
        'maplibre_get_label_stride',
      );
      _reprojectLabels = _lib
          .lookupFunction<
            Void Function(Pointer<Float>, Pointer<Float>),
            void Function(Pointer<Float>, Pointer<Float>)
          >('maplibre_reproject_labels');
      _getLabelsVersion = _lib
          .lookupFunction<Uint32 Function(), int Function()>(
            'maplibre_get_labels_version',
          );
      _requestLabelExtraction = _lib.lookupFunction<_VoidVoidN, _VoidVoidD>(
        'maplibre_request_label_extraction',
      );
    } catch (_) {}
    try {
      _frameBegin = _lib.lookupFunction<_VoidVoidN, _VoidVoidD>(
        'maplibre_frame_begin',
      );
      _frameEnd = _lib.lookupFunction<_VoidVoidN, _VoidVoidD>(
        'maplibre_frame_end',
      );
      _frameGetCommandCount = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
        'maplibre_frame_get_command_count',
      );
      _frameGetCommands = _lib
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'maplibre_frame_get_commands',
          );
      _frameGetCommandStride = _lib.lookupFunction<_Int32VoidN, _Int32VoidD>(
        'maplibre_frame_get_command_stride',
      );
      _frameGetClearColor = _lib
          .lookupFunction<Pointer<Float> Function(), Pointer<Float> Function()>(
            'maplibre_frame_get_clear_color',
          );
    } catch (_) {
      // DrawCommand FFI not available (Metal backend build)
    }
  }

  void frameBegin() {
    _lifecycle.ensureActive();
    _frameBegin?.call();
  }

  void frameEnd() {
    _lifecycle.ensureActive();
    _frameEnd?.call();
  }

  int frameGetCommandCount() {
    _lifecycle.ensureActive();
    return _frameGetCommandCount?.call() ?? 0;
  }

  Pointer<Void> frameGetCommands() {
    _lifecycle.ensureActive();
    return _frameGetCommands?.call() ?? nullptr;
  }

  int frameGetCommandStride() {
    _lifecycle.ensureActive();
    return _frameGetCommandStride?.call() ?? 0;
  }

  FrameClearColor? frameGetClearColor() {
    _lifecycle.ensureActive();
    final ptr = _frameGetClearColor?.call() ?? nullptr;
    if (ptr == nullptr) return null;
    final rgba = ptr.asTypedList(4);
    return (
      red: rgba[0].toDouble(),
      green: rgba[1].toDouble(),
      blue: rgba[2].toDouble(),
      alpha: rgba[3].toDouble(),
    );
  }

  int getLabelCount() {
    _lifecycle.ensureActive();
    return _getLabelCount?.call() ?? 0;
  }

  Pointer<Void> getLabels() {
    _lifecycle.ensureActive();
    return _getLabels?.call() ?? nullptr;
  }

  int getLabelStride() {
    _lifecycle.ensureActive();
    return _getLabelStride?.call() ?? 0;
  }

  int getLabelsVersion() {
    _lifecycle.ensureActive();
    return _getLabelsVersion?.call() ?? 0;
  }

  void requestLabelExtraction() {
    _lifecycle.ensureActive();
    _requestLabelExtraction?.call();
  }

  /// Reproject all cached labels to screen coords in one FFI call.
  /// Returns a list of Offsets matching [count] labels.
  List<Offset> reprojectLabels(int count) {
    _lifecycle.ensureActive();
    if (count <= 0 || _reprojectLabels == null) return const [];
    // Grow buffers if needed
    if (count > _labelBufCap) {
      calloc.free(_labelXsBuf);
      calloc.free(_labelYsBuf);
      _labelBufCap = count + 32;
      _labelXsBuf = calloc<Float>(_labelBufCap);
      _labelYsBuf = calloc<Float>(_labelBufCap);
    }
    _reprojectLabels!(_labelXsBuf, _labelYsBuf);
    final xs = _labelXsBuf.asTypedList(count);
    final ys = _labelYsBuf.asTypedList(count);
    return List.generate(
      count,
      (i) => Offset(xs[i].toDouble(), ys[i].toDouble()),
    );
  }

  static String _cstr(Uint8List bytes, int start, int max) {
    var end = start;
    while (end < start + max && bytes[end] != 0) {
      end++;
    }
    return utf8.decode(bytes.sublist(start, end), allowMalformed: true);
  }

  /// Get placed symbols (text and/or icon) as a list of LabelData objects.
  List<LabelData> getPlacedLabels() {
    final count = getLabelCount();
    if (count <= 0) return const [];
    final ptr = getLabels();
    if (ptr == nullptr) return const [];
    final stride = getLabelStride();
    if (stride != LabelExportAbi.size) {
      debugPrint(
        '[MaplibreBridge] LabelExport stride mismatch: '
        '$stride != ${LabelExportAbi.size}',
      );
      return const [];
    }
    // Field offsets come from LabelExportAbi (generated from the C++ ABI
    // locks in native/bridge_labels.cpp — see tool/gen_abi.dart). The
    // text/layer/icon char buffers are 128/64/64 bytes wide.
    final bytes = ptr.cast<Uint8>().asTypedList(count * stride);
    final bd = ByteData.sublistView(bytes);
    final labels = <LabelData>[];
    for (var i = 0; i < count; i++) {
      final o = i * stride;
      final flags = bd.getUint32(o + LabelExportAbi.flags, Endian.little);
      labels.add(
        LabelData(
          lat: bd.getFloat64(o + LabelExportAbi.lat, Endian.little),
          lon: bd.getFloat64(o + LabelExportAbi.lon, Endian.little),
          iconLat: bd.getFloat64(o + LabelExportAbi.iconLat, Endian.little),
          iconLon: bd.getFloat64(o + LabelExportAbi.iconLon, Endian.little),
          fontSize: bd.getFloat32(o + LabelExportAbi.fontSize, Endian.little),
          textR: bd.getFloat32(o + LabelExportAbi.textR, Endian.little),
          textG: bd.getFloat32(o + LabelExportAbi.textG, Endian.little),
          textB: bd.getFloat32(o + LabelExportAbi.textB, Endian.little),
          textA: bd.getFloat32(o + LabelExportAbi.textA, Endian.little),
          haloR: bd.getFloat32(o + LabelExportAbi.haloR, Endian.little),
          haloG: bd.getFloat32(o + LabelExportAbi.haloG, Endian.little),
          haloB: bd.getFloat32(o + LabelExportAbi.haloB, Endian.little),
          haloA: bd.getFloat32(o + LabelExportAbi.haloA, Endian.little),
          haloWidth: bd.getFloat32(o + LabelExportAbi.haloWidth, Endian.little),
          textW: bd.getFloat32(o + LabelExportAbi.textW, Endian.little),
          textH: bd.getFloat32(o + LabelExportAbi.textH, Endian.little),
          iconW: bd.getFloat32(o + LabelExportAbi.iconW, Endian.little),
          iconH: bd.getFloat32(o + LabelExportAbi.iconH, Endian.little),
          iconScale: bd.getFloat32(o + LabelExportAbi.iconSize, Endian.little),
          iconOpacity: bd.getFloat32(
            o + LabelExportAbi.iconOpacity,
            Endian.little,
          ),
          iconR: bd.getFloat32(o + LabelExportAbi.iconR, Endian.little),
          iconG: bd.getFloat32(o + LabelExportAbi.iconG, Endian.little),
          iconB: bd.getFloat32(o + LabelExportAbi.iconB, Endian.little),
          iconA: bd.getFloat32(o + LabelExportAbi.iconA, Endian.little),
          textOffsetX: bd.getFloat32(
            o + LabelExportAbi.textOffsetX,
            Endian.little,
          ),
          textOffsetY: bd.getFloat32(
            o + LabelExportAbi.textOffsetY,
            Endian.little,
          ),
          iconOffsetX: bd.getFloat32(
            o + LabelExportAbi.iconOffsetX,
            Endian.little,
          ),
          iconOffsetY: bd.getFloat32(
            o + LabelExportAbi.iconOffsetY,
            Endian.little,
          ),
          textPlaced: (flags & 1) != 0,
          iconPlaced: (flags & 2) != 0,
          alongLine: (flags & 4) != 0,
          angle: bd.getFloat32(o + LabelExportAbi.textAngle, Endian.little),
          crossTileId: bd.getUint32(
            o + LabelExportAbi.crossTileID,
            Endian.little,
          ),
          text: _cstr(bytes, o + LabelExportAbi.text, 128),
          layer: _cstr(bytes, o + LabelExportAbi.layer, 64),
          icon: _cstr(bytes, o + LabelExportAbi.icon, 64),
        ),
      );
    }
    return labels;
  }

  double _devicePixelRatio = 1.0;

  double get devicePixelRatio {
    _lifecycle.ensureActive();
    return _devicePixelRatio;
  }

  set devicePixelRatio(double value) {
    _lifecycle.ensureActive();
    _devicePixelRatio = value;
  }

  void destroy() {
    _lifecycle.dispose(
      destroyNativeSession: _destroy,
      releaseLocalResources: () {
        calloc.free(_outX);
        calloc.free(_outY);
        calloc.free(_cameraOutput);
        calloc.free(_styleBoolOutput);
        calloc.free(_labelXsBuf);
        calloc.free(_labelYsBuf);
      },
    );
  }
}

/// Resolves `libmaplibre_bridge.so` from the package root or a standalone app
/// nested one level below `examples/`.
String _resolveBridgeLibraryPath() {
  final candidates = <String>[
    '${Directory.current.path}/native/libmaplibre_bridge.so',
    '${Directory.current.path}/../native/libmaplibre_bridge.so',
    '${Directory.current.path}/../../native/libmaplibre_bridge.so',
  ];
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return candidates.first;
}
