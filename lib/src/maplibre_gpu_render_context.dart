import 'dart:ui' show Size;

import 'package:flutter_gpu/gpu.dart' as gpu;

/// Records additional Flutter GPU draw commands after MapLibre has rendered.
///
/// The callback runs synchronously during paint. Bind a pipeline, buffers,
/// uniforms, and textures to [MapLibreGpuRenderContext.renderPass], then call
/// `draw()`. The map owns and submits the command buffer.
typedef MapLibreGpuRenderCallback =
    void Function(MapLibreGpuRenderContext context);

/// Flutter GPU objects and viewport metadata for an additional map draw pass.
///
/// The pass targets the same color texture and uses the same [gpu.GpuContext]
/// as MapLibre's Flutter GPU renderer. Its color attachment is loaded after
/// the map, so commands appear above the map. Depth and stencil are not shared
/// with MapLibre yet.
///
/// This object and [renderPass] are valid only while the callback is running.
/// Do not retain or submit them. GPU resources created through [gpuContext]
/// remain owned by the application and should be cached and released there.
final class MapLibreGpuRenderContext {
  const MapLibreGpuRenderContext({
    required this.gpuContext,
    required this.renderPass,
    required this.logicalSize,
    required this.physicalSize,
    required this.devicePixelRatio,
    required this.frameSequence,
  });

  /// The exact Flutter GPU context used by the map renderer.
  final gpu.GpuContext gpuContext;

  /// A load-preserving pass targeting the map's color texture.
  final gpu.RenderPass renderPass;

  /// Map viewport size in Flutter logical pixels.
  final Size logicalSize;

  /// Map render-target size in physical pixels.
  final Size physicalSize;

  /// Device pixel ratio used when the map render target was created.
  final double devicePixelRatio;

  /// Monotonically increasing MapLibre frame sequence.
  final int frameSequence;
}
