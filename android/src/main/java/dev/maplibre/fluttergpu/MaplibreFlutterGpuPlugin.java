package dev.maplibre.fluttergpu;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/** Loads the FFI bridge through the JVM so JNI_OnLoad receives Android's JavaVM. */
public final class MaplibreFlutterGpuPlugin implements FlutterPlugin {
  static {
    System.loadLibrary("maplibre_bridge");
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    // Rendering and API calls use dart:ffi. Plugin registration only guarantees
    // that the bridge is loaded before Dart constructs MaplibreBridge.
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}
