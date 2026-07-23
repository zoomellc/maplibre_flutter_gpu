import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

void main() {
  test('LatLng normalizes longitude like maplibre_gl', () {
    expect(const LatLng(100, 540), const LatLng(90, -180));
    expect(const LatLng(-100, -540), const LatLng(-90, -180));
    expect(const LatLng(35, 139).toGeoJsonCoordinates(), <double>[139, 35]);
  });

  test('LatLngBounds supports antimeridian-crossing bounds', () {
    const bounds = LatLngBounds(
      southwest: LatLng(-10, 170),
      northeast: LatLng(10, -170),
    );

    expect(bounds.contains(const LatLng(0, 175)), isTrue);
    expect(bounds.contains(const LatLng(0, -175)), isTrue);
    expect(bounds.contains(const LatLng(0, 0)), isFalse);
    expect(bounds.contains(const LatLng(20, 175)), isFalse);
  });

  test('camera bounds and zoom preferences are value objects', () {
    const bounds = LatLngBounds(
      southwest: LatLng(30, 130),
      northeast: LatLng(40, 145),
    );

    expect(const CameraTargetBounds(bounds), const CameraTargetBounds(bounds));
    expect(const CameraTargetBounds(bounds).toJson(), [
      [
        [30.0, 130.0],
        [40.0, 145.0],
      ],
    ]);
    expect(
      const MinMaxZoomPreference(3, 18),
      const MinMaxZoomPreference(3, 18),
    );
    expect(MinMaxZoomPreference.unbounded.toJson(), [null, null]);
  });

  test('gesture compatibility helpers resolve defaults and tilt intent', () {
    expect(maplibreDoubleClickZoomIsEnabled(null, true), isTrue);
    expect(maplibreDoubleClickZoomIsEnabled(null, false), isFalse);
    expect(maplibreDoubleClickZoomIsEnabled(false, true), isFalse);
    expect(maplibreBearingGestureDelta(math.pi / 2), closeTo(-90, 0.0001));
    expect(maplibreBearingGestureDelta(-math.pi / 2), closeTo(90, 0.0001));
    expect(maplibreTrackpadScaleDelta(1.2, 1), closeTo(1.2, 0.0001));
    expect(maplibreTrackpadScaleDelta(1.2, 1.1), closeTo(1.0909, 0.0001));
    expect(maplibreTrackpadScaleDelta(0, 1), 1);
    expect(maplibreTrackpadScaleDelta(double.nan, 1), 1);

    var rotation = maplibreRotationGestureUpdate(
      frameRotationDelta: math.pi / 180,
      accumulatedRotation: 0,
      active: false,
    );
    expect(rotation.active, isFalse);
    expect(rotation.rotationDelta, 0);
    rotation = maplibreRotationGestureUpdate(
      frameRotationDelta: math.pi / 180,
      accumulatedRotation: rotation.accumulatedRotation,
      active: rotation.active,
    );
    rotation = maplibreRotationGestureUpdate(
      frameRotationDelta: math.pi / 180,
      accumulatedRotation: rotation.accumulatedRotation,
      active: rotation.active,
    );
    expect(rotation.active, isTrue);
    expect(rotation.rotationDelta, 0);
    rotation = maplibreRotationGestureUpdate(
      frameRotationDelta: math.pi / 180,
      accumulatedRotation: rotation.accumulatedRotation,
      active: rotation.active,
    );
    expect(rotation.rotationDelta, closeTo(math.pi / 180, 0.000001));

    var jitter = maplibreRotationGestureUpdate(
      frameRotationDelta: math.pi / 180,
      accumulatedRotation: 0,
      active: false,
    );
    jitter = maplibreRotationGestureUpdate(
      frameRotationDelta: -math.pi / 180,
      accumulatedRotation: jitter.accumulatedRotation,
      active: jitter.active,
    );
    expect(jitter.accumulatedRotation, closeTo(0, 0.000001));
    expect(jitter.active, isFalse);

    expect(
      maplibreTiltGestureDelta(
        focalPointDelta: const Offset(0, -6),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
      ),
      3,
    );
    expect(
      maplibreTiltGestureDelta(
        focalPointDelta: const Offset(0, -6),
        scaleDelta: 1.1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
      ),
      isNull,
    );
    expect(
      maplibreTiltGestureDelta(
        focalPointDelta: const Offset(0, -6),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: false,
      ),
      isNull,
    );
    expect(
      maplibreTiltGestureDelta(
        focalPointDelta: const Offset(4, -6),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
      ),
      isNull,
    );
    expect(
      maplibreTiltFingersApproximatelyHorizontal(const [
        Offset(10, 20),
        Offset(30, 25),
      ]),
      isTrue,
    );
    expect(
      maplibreTiltFingersApproximatelyHorizontal(const [
        Offset(10, 20),
        Offset(15, 40),
      ]),
      isFalse,
    );
    expect(
      maplibreTiltGestureDelta(
        focalPointDelta: const Offset(0.5, -4),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
        minimumVerticalDelta: 4,
      ),
      2,
    );
    expect(
      maplibreTiltGestureDelta(
        focalPointDelta: const Offset(0.05, -0.5),
        scaleDelta: 1,
        rotationDelta: 0,
        fingersApproximatelyHorizontal: true,
        minimumVerticalDelta: 0,
      ),
      0.25,
    );
  });
}
