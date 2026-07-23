import 'package:flutter/foundation.dart';

import 'camera.dart';

/// Bounds for the map camera target.
@immutable
class CameraTargetBounds {
  const CameraTargetBounds(this.bounds);

  /// The geographical bounding box, or `null` for an unbounded target.
  final LatLngBounds? bounds;

  static const CameraTargetBounds unbounded = CameraTargetBounds(null);

  dynamic toJson() => <dynamic>[bounds?.toList()];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraTargetBounds && other.bounds == bounds;

  @override
  int get hashCode => bounds.hashCode;

  @override
  String toString() => 'CameraTargetBounds(bounds: $bounds)';
}

/// Preferred minimum and maximum map zoom levels.
@immutable
class MinMaxZoomPreference {
  const MinMaxZoomPreference(this.minZoom, this.maxZoom)
    : assert(minZoom == null || maxZoom == null || minZoom <= maxZoom);

  final double? minZoom;
  final double? maxZoom;

  static const MinMaxZoomPreference unbounded = MinMaxZoomPreference(
    null,
    null,
  );

  dynamic toJson() => <dynamic>[minZoom, maxZoom];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MinMaxZoomPreference &&
          other.minZoom == minZoom &&
          other.maxZoom == maxZoom;

  @override
  int get hashCode => Object.hash(minZoom, maxZoom);

  @override
  String toString() =>
      'MinMaxZoomPreference(minZoom: $minZoom, maxZoom: $maxZoom)';
}
