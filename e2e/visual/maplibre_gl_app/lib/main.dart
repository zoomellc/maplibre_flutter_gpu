import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart' as reference;
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

Future<void> main() {
  return runVisualE2eApp(
    implementation: 'maplibre_gl',
    mapBuilder: (VisualScene scene, VoidCallback onMapIdle) {
      final camera = scene.camera;
      return reference.MapLibreMap(
        styleString: scene.styleJson,
        initialCameraPosition: reference.CameraPosition(
          target: reference.LatLng(camera.latitude, camera.longitude),
          zoom: camera.zoom,
          bearing: camera.bearing,
          tilt: camera.tilt,
        ),
        rotateGesturesEnabled: false,
        scrollGesturesEnabled: false,
        zoomGesturesEnabled: false,
        tiltGesturesEnabled: false,
        doubleClickZoomEnabled: false,
        dragEnabled: false,
        compassEnabled: false,
        logoEnabled: false,
        scaleControlEnabled: false,
        myLocationEnabled: false,
        foregroundLoadColor: scene.backgroundColor,
        translucentTextureSurface: false,
        onMapIdle: onMapIdle,
      );
    },
  );
}
