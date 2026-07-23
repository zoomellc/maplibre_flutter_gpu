# Controller API example

Standalone app demonstrating `MapLibreMapController`:

- `animateCamera`, `resetNorth`, and `getVisibleRegion`
- `getStyle`, `getLayerIds`, and `getSourceIds`
- `getLayerVisibility` and `setLayerVisibility`
- geographic coordinates from a map tap

The example loads the OpenFreeMap Liberty basemap, inspects its current style,
and selects a label layer that can be hidden and shown. Network access is
required for map tiles.

Android (API 29+, `arm64-v8a` device or `x86_64` emulator):

```bash
cd examples/controller_api
flutter run -d <android-device-id>
```

Apple platforms:

```bash
# macOS
cd examples/controller_api
flutter run -d macos

# iOS Simulator alternative
flutter run
```
