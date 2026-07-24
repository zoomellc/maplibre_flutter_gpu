# maplibre_flutter_gpu

MapLibre maps for Flutter, rendered with **Flutter GPU** instead of a platform
view.

## Status / disclaimer

**This repository is not production-ready and is not intended for real-world
use yet.**

This repository is an experimental SDK snapshot used for GitHub-hosted CI.
APIs and native binary compatibility may change without notice. Current
version: **`0.0.1-dev`**.

The Dart implementation, Flutter GPU shaders, examples, and prebuilt native
libraries are included. The bridge sources and native build tooling are being
kept in the private development repository until the initial public release.

> Requires a Flutter SDK with Flutter GPU enabled. Currently exercised on
> Android API 29+ (Impeller/OpenGLES, `arm64-v8a` and `x86_64`), iOS and
> macOS (Metal), plus Linux (OpenGL bridge).

## Usage

```dart
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

MapLibreMap(
  styleString: MapLibreStyles.openFreeMapLiberty,
  initialCameraPosition: const CameraPosition(
    target: LatLng(35.6812, 139.7671),
    zoom: 13,
  ),
  onMapCreated: (controller) {
    // controller.moveCamera(...);
  },
)
```

The native bridge currently supports **one active `MapLibreMap` per process**.
If a second map is mounted, it shows an initialization error without disturbing
the active map. Remove the active map and remount the other widget to initialize
it.

### `maplibre_gl` constructor compatibility

The core map options use the same names and defaults as `maplibre_gl`, including
camera bounds and zoom limits, rotate/pan/zoom/tilt/double-tap gestures, camera
tracking, map tap/long-press callbacks, and `foregroundLoadColor`. Camera
position preserves target, zoom, bearing, and tilt.

`styleString` accepts a remote URL, a Flutter asset path, an absolute/file URL,
or raw style JSON. `onStyleLoadedCallback` runs after MapLibre reports that the
style document has loaded, not immediately after native initialization.

`dragEnabled` is intentionally absent: in `maplibre_gl` it controls draggable
annotations rather than map panning, and this package does not yet expose the
annotation API. Use `scrollGesturesEnabled` for map panning.

Compass, logo, attribution, and scale-control options also use the matching
`maplibre_gl` names, defaults, position enums, and logical-pixel margins. They
render as deterministic Flutter overlays; their visuals are therefore
consistent across platforms rather than pixel-identical to each native SDK.
`attributionButtonEnabled` additionally exposes the native visibility concept
that `maplibre_gl` does not surface through its Flutter widget API.

This covers the recommended 30 of 45 constructor arguments. The remaining
options depend on location services, annotations, platform views, or a specific
web/iOS/Android implementation and are intentionally outside this GPU widget's
current compatibility profile.

### Custom symbols and Flutter GPU drawing

Placed symbols can replace their icon or text-label widgets while retaining
MapLibre placement and collision decisions:

```dart
MapLibreMap(
  symbolIconBuilder: (context, symbol) => MyMarker(symbol: symbol),
  symbolTextBuilder: (context, symbol) => Text(symbol.data.text),
)
```

Additional Flutter GPU commands can be recorded after the map. Create and cache
the pipeline and buffers outside the callback; the map owns command submission:

```dart
MapLibreMap(
  gpuRenderCallback: (frame) {
    frame.renderPass
      ..bindPipeline(myPipeline)
      ..bindVertexBuffer(myVertices, vertexCount)
      ..draw();
  },
  gpuRepaint: animation, // optional Listenable for animated GPU content
)
```

The callback uses the same Flutter GPU context and color target as the map, in
a dedicated final render pass. MapLibre depth/stencil sharing and insertion
between style layers are not supported yet.

## Examples

Three standalone apps live under [`examples/`](examples/). Android bridge
libraries for both supported 64-bit ABIs are checked in, so an Android sample
can run without rebuilding native code:

```bash
cd examples/flutter_markers # or controller_api / gpu_context
flutter run -d <android-device-id>
```

The matching macOS and iOS archives are also checked in:

```bash
cd examples/flutter_markers # or controller_api / gpu_context
flutter run -d macos
```

The samples cover Flutter markers, the supported controller API, and custom
draw calls through the public Flutter GPU context.

## Prebuilt native libraries

The repository includes prebuilts for Android `arm64-v8a` and `x86_64`, Linux
`x86_64`, iOS device and Apple Silicon Simulator, and universal macOS. Their
SHA-256 checksums are recorded in
[`NATIVE_ARTIFACTS.sha256`](NATIVE_ARTIFACTS.sha256).

The libraries link against the public
[MapLibre Native Command Export fork](https://github.com/zoomellc/maplibre-native).
Native bridge sources and build scripts will be added with the initial public
release.

## Package layout

| Path | Role |
|------|------|
| `lib/` | Publishable Dart API (`MapLibreMap`, …) |
| `lib/src/` | Implementation (GPU renderer, FFI, overlays) |
| `native/` | Prebuilt Linux and iOS bridge libraries |
| `android/src/main/jniLibs/` | Prebuilt Android bridge libraries |
| `examples/_shared/` | Prebuilt Apple libraries and linker configuration |
| `shaders/` | Flutter GPU shader sources |
| `examples/` | Standalone Flutter example applications |

## License

BSD-2-Clause. See [LICENSE](LICENSE). MapLibre Native and its vendors remain
under their respective licenses in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES/).
