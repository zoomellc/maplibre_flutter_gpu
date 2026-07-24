## 0.0.1-dev

* Scaffold package layout for `maplibre_flutter_gpu` (development only).
* Flutter GPU renderer backed by MapLibre Command Export for fill / line /
  circle / raster / fill-extrusion layers, plus Flutter-widget symbol overlay.
* Optional attribution-button visibility and a compact attribution control.
* Map rotation gestures now follow the fingers' rotation direction.
* Pinch zoom suppresses incidental rotation until the native 3° threshold.
* Tilt uses an exclusive three-finger vertical drag; two fingers are reserved
  for pinch zoom and rotation.
* Standalone examples under `examples/` for Flutter markers, controller APIs,
  and custom Flutter GPU drawing.
* Android API 29+ support through Impeller/OpenGLES, with `arm64-v8a` and
  `x86_64` bridge prebuilts, a reproducible native build script, and Android
  projects for all three examples.
* macOS desktop support with shared universal arm64/x86_64 native archives.
* **Not a production release.** This repository is public primarily so GitHub
  Actions can run against it. A real public release will use a new repository
  with a cleaned-up commit history.
