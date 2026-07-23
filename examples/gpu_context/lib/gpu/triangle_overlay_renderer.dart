import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'overlay_shader_library.dart';

/// Caches app-owned GPU resources and records one triangle draw per callback.
class TriangleOverlayRenderer {
  gpu.GpuContext? _gpuContext;
  gpu.RenderPipeline? _pipeline;
  gpu.DeviceBuffer? _vertices;
  gpu.HostBuffer? _uniforms;
  gpu.UniformSlot? _uniformSlot;

  static final ByteData _vertexData = ByteData.sublistView(
    Float32List.fromList(<double>[
      // x, y, red, green, blue, alpha
      0, -0.34, 0.02, 0.78, 0.88, 0.86,
      0.34, 0.28, 0.96, 0.42, 0.18, 0.86,
      -0.34, 0.28, 0.45, 0.24, 0.92, 0.86,
    ]),
  );

  void draw(MapLibreGpuRenderContext frame, {required double progress}) {
    _ensureResources(frame.gpuContext);

    final safeWidth = math.max(frame.physicalSize.width, 1.0);
    final aspectCorrection = frame.physicalSize.height / safeWidth;
    final pulse = 0.88 + 0.12 * math.sin(progress * math.pi * 2);
    final values = ByteData.sublistView(
      Float32List.fromList(<double>[
        progress * math.pi * 2,
        aspectCorrection,
        pulse,
        0,
      ]),
    );

    final uniforms = _uniforms!..reset();
    final uniformView = uniforms.emplace(values);
    final renderPass = frame.renderPass;
    renderPass
      ..setPrimitiveType(gpu.PrimitiveType.triangle)
      ..setColorBlendEnable(true)
      ..setColorBlendEquation(gpu.ColorBlendEquation())
      ..bindPipeline(_pipeline!)
      ..bindVertexBuffer(
        gpu.BufferView(
          _vertices!,
          offsetInBytes: 0,
          lengthInBytes: _vertexData.lengthInBytes,
        ),
        3,
      )
      ..bindUniform(_uniformSlot!, uniformView)
      ..draw();
  }

  void _ensureResources(gpu.GpuContext context) {
    if (identical(_gpuContext, context)) return;

    final vertexShader = overlayShaderLibrary['OverlayVertex'];
    final fragmentShader = overlayShaderLibrary['OverlayFragment'];
    if (vertexShader == null || fragmentShader == null) {
      throw StateError('Overlay shaders are missing from the shader bundle');
    }

    _gpuContext = context;
    _pipeline = context.createRenderPipeline(vertexShader, fragmentShader);
    _vertices = context.createDeviceBufferWithCopy(_vertexData);
    _uniforms = context.createHostBuffer(blockLengthInBytes: 256);
    _uniformSlot = vertexShader.getUniformSlot('OverlayUniforms');
  }

  /// Flutter GPU resources have no public dispose API. Dropping references
  /// lets their native wrappers be reclaimed after this app closes.
  void releaseReferences() {
    _uniformSlot = null;
    _uniforms = null;
    _vertices = null;
    _pipeline = null;
    _gpuContext = null;
  }
}
