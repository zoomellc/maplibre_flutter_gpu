import 'package:flutter_gpu/gpu.dart' as gpu;

gpu.ShaderLibrary? _mapShaderLibrary;

/// Asset path that works both as a path dependency and after pub publish.
const _shaderBundleAsset =
    'packages/maplibre_flutter_gpu/build/shaderbundles/MapShaders.shaderbundle';

gpu.ShaderLibrary get mapShaderLibrary {
  _mapShaderLibrary ??= gpu.ShaderLibrary.fromAsset(_shaderBundleAsset);
  if (_mapShaderLibrary == null) {
    throw Exception(
      'Failed to load MapShaders bundle from $_shaderBundleAsset',
    );
  }
  return _mapShaderLibrary!;
}
