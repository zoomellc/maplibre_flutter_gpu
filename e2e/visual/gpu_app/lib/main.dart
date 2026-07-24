import 'package:flutter/widgets.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

Future<void> main() {
  return runVisualE2eApp(
    implementation: 'maplibre_flutter_gpu',
    mapBuilder: (VisualScene scene, VoidCallback onMapIdle) {
      final camera = scene.camera;
      return gpu.MapLibreMap(
        styleString: scene.styleJson,
        initialCameraPosition: gpu.CameraPosition(
          target: gpu.LatLng(camera.latitude, camera.longitude),
          zoom: camera.zoom,
          bearing: camera.bearing,
          tilt: camera.tilt,
        ),
        rotateGesturesEnabled: false,
        scrollGesturesEnabled: false,
        zoomGesturesEnabled: false,
        tiltGesturesEnabled: false,
        doubleClickZoomEnabled: false,
        compassEnabled: false,
        logoEnabled: false,
        scaleControlEnabled: false,
        foregroundLoadColor: scene.backgroundColor,
        onMapIdle: onMapIdle,
      );
    },
  );
}
