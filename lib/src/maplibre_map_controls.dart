import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'camera.dart';
import 'maplibre_map_controller.dart';

/// Compass view position, matching `maplibre_gl`.
enum CompassViewPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Attribution button position, matching `maplibre_gl`.
enum AttributionButtonPosition { topLeft, topRight, bottomLeft, bottomRight }

/// MapLibre logo position, matching `maplibre_gl`.
enum LogoViewPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Scale control position, matching `maplibre_gl`.
enum ScaleControlPosition { topLeft, topRight, bottomLeft, bottomRight }

/// Scale control unit, matching `maplibre_gl`.
enum ScaleControlUnit { metric, imperial, nautical }

@immutable
class MapLibreScaleBarValue {
  const MapLibreScaleBarValue({required this.label, required this.width});

  final String label;
  final double width;

  @override
  bool operator ==(Object other) =>
      other is MapLibreScaleBarValue &&
      other.label == label &&
      other.width == width;

  @override
  int get hashCode => Object.hash(label, width);
}

@visibleForTesting
double maplibreDistanceMeters(LatLng a, LatLng b) {
  const earthRadiusMeters = 6371008.8;
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final deltaLat = lat2 - lat1;
  var deltaLon = (b.longitude - a.longitude) * math.pi / 180;
  if (deltaLon > math.pi) deltaLon -= math.pi * 2;
  if (deltaLon < -math.pi) deltaLon += math.pi * 2;
  final sinLat = math.sin(deltaLat / 2);
  final sinLon = math.sin(deltaLon / 2);
  final haversine =
      sinLat * sinLat + math.cos(lat1) * math.cos(lat2) * sinLon * sinLon;
  return earthRadiusMeters * 2 * math.asin(math.sqrt(haversine.clamp(0, 1)));
}

@visibleForTesting
MapLibreScaleBarValue maplibreScaleBarValue(
  double metersAcrossMaxWidth,
  ScaleControlUnit unit, {
  double maxWidth = 80,
}) {
  if (!metersAcrossMaxWidth.isFinite || metersAcrossMaxWidth <= 0) {
    return const MapLibreScaleBarValue(label: '', width: 0);
  }

  late final double unitsAcrossMaxWidth;
  late final String suffix;
  switch (unit) {
    case ScaleControlUnit.metric:
      if (metersAcrossMaxWidth >= 1000) {
        unitsAcrossMaxWidth = metersAcrossMaxWidth / 1000;
        suffix = 'km';
      } else {
        unitsAcrossMaxWidth = metersAcrossMaxWidth;
        suffix = 'm';
      }
    case ScaleControlUnit.imperial:
      if (metersAcrossMaxWidth >= 1609.344) {
        unitsAcrossMaxWidth = metersAcrossMaxWidth / 1609.344;
        suffix = 'mi';
      } else {
        unitsAcrossMaxWidth = metersAcrossMaxWidth * 3.280839895;
        suffix = 'ft';
      }
    case ScaleControlUnit.nautical:
      unitsAcrossMaxWidth = metersAcrossMaxWidth / 1852;
      suffix = 'nm';
  }

  final niceUnits = _niceScaleFloor(unitsAcrossMaxWidth);
  final width = (niceUnits / unitsAcrossMaxWidth * maxWidth)
      .clamp(0, maxWidth)
      .toDouble();
  return MapLibreScaleBarValue(
    label: '${_formatScaleNumber(niceUnits)} $suffix',
    width: width,
  );
}

double _niceScaleFloor(double value) {
  final exponent = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final fraction = value / exponent;
  final niceFraction = fraction >= 5
      ? 5.0
      : fraction >= 2
      ? 2.0
      : 1.0;
  return niceFraction * exponent;
}

String _formatScaleNumber(double value) {
  if (value >= 10 || value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  if (value >= 1) return value.toStringAsFixed(1);
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

class MapLibreMapControls extends StatelessWidget {
  const MapLibreMapControls({
    super.key,
    required this.mapSize,
    required this.controller,
    required this.compassEnabled,
    required this.logoEnabled,
    required this.logoViewPosition,
    required this.logoViewMargins,
    required this.compassViewPosition,
    required this.compassViewMargins,
    required this.attributionButtonEnabled,
    required this.attributionButtonPosition,
    required this.attributionButtonMargins,
    required this.scaleControlEnabled,
    required this.scaleControlPosition,
    required this.scaleControlUnit,
  });

  final Size mapSize;
  final MapLibreMapController? controller;
  final bool compassEnabled;
  final bool logoEnabled;
  final LogoViewPosition? logoViewPosition;
  final math.Point<num>? logoViewMargins;
  final CompassViewPosition? compassViewPosition;
  final math.Point<num>? compassViewMargins;
  final bool attributionButtonEnabled;
  final AttributionButtonPosition? attributionButtonPosition;
  final math.Point<num>? attributionButtonMargins;
  final bool scaleControlEnabled;
  final ScaleControlPosition scaleControlPosition;
  final ScaleControlUnit scaleControlUnit;

  static const _defaultMargin = math.Point<num>(8, 8);

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[];
    final bearing = controller?.cameraPosition?.bearing ?? 0;

    if (compassEnabled) {
      controls.add(
        _positionedControl(
          positionIndex:
              (compassViewPosition ?? CompassViewPosition.topRight).index,
          margins: compassViewMargins,
          child: _CompassButton(
            bearing: bearing,
            onPressed: controller?.resetNorth,
          ),
        ),
      );
    }
    if (logoEnabled) {
      controls.add(
        _positionedControl(
          positionIndex:
              (logoViewPosition ?? LogoViewPosition.bottomLeft).index,
          margins: logoViewMargins,
          child: const IgnorePointer(child: _MapLibreLogo()),
        ),
      );
    }

    if (attributionButtonEnabled) {
      controls.add(
        _positionedControl(
          positionIndex:
              (attributionButtonPosition ??
                      AttributionButtonPosition.bottomRight)
                  .index,
          margins: attributionButtonMargins,
          child: _AttributionButton(onPressed: () => _showAttribution(context)),
        ),
      );
    }

    if (scaleControlEnabled && controller != null) {
      final scale = _scaleBar(controller!);
      if (scale.width > 0) {
        final scalePosition = scaleControlPosition.index;
        final logoPosition =
            (logoViewPosition ?? LogoViewPosition.bottomLeft).index;
        final sharesBottomCorner =
            logoEnabled && scalePosition == logoPosition && scalePosition >= 2;
        controls.add(
          _positionedControl(
            positionIndex: scalePosition,
            margins: _defaultMargin,
            extraBottom: sharesBottomCorner ? 27 : 0,
            child: IgnorePointer(child: _ScaleBar(value: scale)),
          ),
        );
      }
    }

    return Stack(children: controls);
  }

  MapLibreScaleBarValue _scaleBar(MapLibreMapController mapController) {
    const maxWidth = 80.0;
    if (mapSize.width <= 0 || mapSize.height <= 0) {
      return const MapLibreScaleBarValue(label: '', width: 0);
    }
    final sampleWidth = math.min(maxWidth, mapSize.width).toDouble();
    final centerX = mapSize.width / 2;
    final centerY = mapSize.height / 2;
    try {
      final left = mapController.toLatLngOffset(
        Offset(centerX - sampleWidth / 2, centerY),
      );
      final right = mapController.toLatLngOffset(
        Offset(centerX + sampleWidth / 2, centerY),
      );
      return maplibreScaleBarValue(
        maplibreDistanceMeters(left, right),
        scaleControlUnit,
        maxWidth: sampleWidth,
      );
    } on UnsupportedError {
      return const MapLibreScaleBarValue(label: '', width: 0);
    }
  }

  Widget _positionedControl({
    required int positionIndex,
    required Widget child,
    math.Point<num>? margins,
    double extraBottom = 0,
  }) {
    final margin = margins ?? _defaultMargin;
    final horizontal = margin.x.toDouble();
    final vertical = margin.y.toDouble();
    return Positioned(
      left: positionIndex == 0 || positionIndex == 2 ? horizontal : null,
      right: positionIndex == 1 || positionIndex == 3 ? horizontal : null,
      top: positionIndex == 0 || positionIndex == 1 ? vertical : null,
      bottom: positionIndex == 2 || positionIndex == 3
          ? vertical + extraBottom
          : null,
      child: child,
    );
  }

  Future<void> _showAttribution(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map attribution'),
        content: const Text(
          'MapLibre renders the active style. Data attribution is defined by '
          'that style and its sources.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _CompassButton extends StatelessWidget {
  const _CompassButton({required this.bearing, required this.onPressed});

  final double bearing;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final facingNorth = bearing.abs() < 0.01;
    return IgnorePointer(
      ignoring: facingNorth,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: facingNorth ? 0 : 1,
        child: Material(
          color: Colors.white.withValues(alpha: 0.9),
          elevation: 2,
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: 'Reset bearing to north',
            onPressed: onPressed,
            icon: Transform.rotate(
              angle: -bearing * math.pi / 180,
              child: const Icon(Icons.navigation, color: Color(0xFFE53935)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapLibreLogo extends StatelessWidget {
  const _MapLibreLogo();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.88),
      borderRadius: BorderRadius.circular(4),
    ),
    child: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      child: Text(
        'MapLibre',
        style: TextStyle(
          color: Color(0xFF263238),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _AttributionButton extends StatelessWidget {
  const _AttributionButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white.withValues(alpha: 0.88),
    shape: const CircleBorder(),
    child: IconButton(
      style: IconButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      constraints: const BoxConstraints.tightFor(width: 24, height: 24),
      padding: EdgeInsets.zero,
      iconSize: 15,
      tooltip: 'Map attribution',
      onPressed: onPressed,
      icon: const Icon(Icons.info_outline),
    ),
  );
}

class _ScaleBar extends StatelessWidget {
  const _ScaleBar({required this.value});

  final MapLibreScaleBarValue value;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Map scale ${value.label}',
    child: SizedBox(
      width: value.width,
      height: 25,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.label,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.white, blurRadius: 2)],
            ),
          ),
          Container(
            height: 6,
            decoration: const BoxDecoration(
              border: Border(
                left: BorderSide(color: Colors.black, width: 2),
                right: BorderSide(color: Colors.black, width: 2),
                bottom: BorderSide(color: Colors.black, width: 2),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
