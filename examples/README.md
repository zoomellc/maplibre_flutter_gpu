# Examples

Each app directory listed below is a standalone Flutter project. Run one
project at a time; the native bridge currently supports one active
`MapLibreMap` per process.

| Project | Demonstrates |
|---|---|
| [`flutter_markers/`](flutter_markers/) | Existing map with Flutter widget markers |
| [`controller_api/`](controller_api/) | Camera, source, layer, and feature-query controller APIs |
| [`gpu_context/`](gpu_context/) | Custom draw calls through the public Flutter GPU context |

Current native targets are Android API 29+, iOS, macOS, and Linux. Android
supports 64-bit `arm64-v8a` devices and `x86_64` emulators. Its checked-in
bridge libraries let every sample run directly:

```bash
cd examples/flutter_markers # or controller_api / gpu_context
flutter run -d <android-device-id>
```

All macOS projects link the checked-in universal archives under
`_shared/macos/`:

```bash
cd examples/flutter_markers # or controller_api / gpu_context
flutter run -d macos
```

All iOS projects link the checked-in device and Apple Silicon Simulator
archives under `_shared/ios/`:

```bash
cd examples/flutter_markers # or controller_api / gpu_context
flutter run
```

Linux uses the checked-in shared library under `native/`:

```bash
cd examples/controller_api # choose any project
flutter run -d linux
```
