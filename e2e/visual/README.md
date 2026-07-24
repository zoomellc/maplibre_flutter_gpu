# Android visual parity E2E

This suite renders one deterministic scene with two separate Android apps:

1. `maplibre_gl` 0.26.2, used as the reference image.
2. The local `maplibre_flutter_gpu` package, used as the actual image.

Separate APKs are intentional. Both packages currently provide the Android
class `org.maplibre.android.http.NativeHttpRequest`, so putting them in one APK
can cause duplicate-class and JNI conflicts.

## What the first scene covers

`shared/assets/scenes/geometry.json` is an offline style with inline GeoJSON. It
contains background, fill, line, and circle layers. It has no remote tiles,
sprites, glyphs, labels, or other network dependencies.

Both apps load the same style and use the same camera target, zoom, bearing,
tilt, gesture settings, and viewport. A symmetric 64 logical-pixel overscan
keeps native map controls outside the captured viewport. The raw screenshots
therefore compare map rendering rather than different control implementations.

## Run

Requirements:

- Flutter 3.44.6 or a compatible SDK
- Java 21
- one connected Android API 29+ device or emulator
- `arm64-v8a` or `x86_64`

From the repository root:

```bash
./e2e/visual/run_android.sh
```

When more than one device is connected:

```bash
./e2e/visual/run_android.sh --device emulator-5554
```

Useful options:

```text
--minimum-similarity 0.998
--color-threshold 0.05
--include-antialiasing
--output path/to/report
--skip-drive
```

The runner returns:

- `0` when the similarity gate passes
- `1` when screenshots were produced but similarity is below the gate
- `2` for build, device, capture, or report infrastructure failures

## Result

Default output is `e2e/visual/report/`:

```text
index.html
results.json
images/
  maplibre_gl.png
  gpu.png
  diff.png
logs/
```

`index.html` shows both screenshots, an interactive overlay, the difference
image, the similarity gate, and device/build metadata.

The comparator adapts the perceptual comparison used by MapLibre Native render
tests, with stricter defaults for this sparse fixture:

- perceptual YIQ color threshold: `0.05`
- anti-aliased edge differences excluded only when both images have a local
  edge, so a seam present in only one renderer still fails
- substantial-pixel similarity:
  `1 - substantialMismatchPixels / comparedPixels`
- default pass threshold: `99.8%`

The report also shows strict similarity, which counts the detected anti-alias
pixels. In the difference image, red means a substantial mismatch and blue
means a shared-edge anti-alias difference excluded from the main gate.

## CI

Use one fixed `x86_64` emulator and run both apps sequentially. Keep API level,
screen size, density, locale, orientation, animation scales, and graphics
backend fixed. Upload `e2e/visual/report/` with an `always()` condition so a
failed similarity gate still exposes both screenshots and the HTML report.

The public repository owns its `.github/workflows/` files. Add the emulator job
there after exporting this shared E2E tree from the private source repository.
A ready, SHA-pinned workflow is provided at
`ci/android-visual-parity.yml`. From the public checkout:

```bash
cp e2e/visual/ci/android-visual-parity.yml \
  .github/workflows/android-visual-parity.yml
```

The job uses JDK 21 and one API 36 `x86_64` emulator from the stable channel
with the SwiftShader OpenGL ES backend and Vulkan disabled, then uploads the
report even when the similarity gate fails. The Actions job summary shows the
comparison metrics and links to the downloadable artifact, which contains the
self-contained HTML report, both screenshots, the diff, and capture logs.
The GPU fixture also selects Impeller's OpenGL ES backend explicitly in debug
and profile builds so emulator runs cannot auto-select Vulkan.
