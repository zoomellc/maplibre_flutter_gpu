# Public Flutter GPU context example

Standalone app recording one animated triangle after MapLibre renders.

`TriangleOverlayRenderer` uses the public `MapLibreGpuRenderContext`:

1. Create and cache its pipeline, static vertex buffer, and uniform host buffer
   through `frame.gpuContext` on first use.
2. Update one uniform through `gpuRepaint` on later frames.
3. Bind resources to `frame.renderPass` and call `draw()`.

The callback does not create or submit a command buffer. The map owns command
submission. Its render pass is callback-scoped and must not be retained.
The custom pass draws above the full map and does not share MapLibre
depth/stencil.

The app build hook compiles `shaders/OverlayShaders.shaderbundle.json` with the
`impellerc` from the active Flutter SDK, including the GLES 3 shader used on
Android. No manual shader build step is needed.

Android (API 29+, `arm64-v8a` device or `x86_64` emulator):

```bash
cd examples/gpu_context
flutter run -d <android-device-id>
```

Apple platforms:

```bash
# macOS
cd examples/gpu_context
flutter run -d macos

# iOS Simulator alternative:
flutter run
```
