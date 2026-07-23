import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/gpu_renderer.dart';
import 'package:maplibre_flutter_gpu/src/maplibre_map.dart';
import 'package:maplibre_flutter_gpu/src/native/draw_command.dart';

void main() {
  test('MapLibre alpha blending uses premultiplied source colors', () {
    final blend = maplibreAlphaBlendEquation();

    expect(blend.colorBlendOperation, gpu.BlendOperation.add);
    expect(blend.sourceColorBlendFactor, gpu.BlendFactor.one);
    expect(
      blend.destinationColorBlendFactor,
      gpu.BlendFactor.oneMinusSourceAlpha,
    );
    expect(blend.alphaBlendOperation, gpu.BlendOperation.add);
    expect(blend.sourceAlphaBlendFactor, gpu.BlendFactor.one);
    expect(
      blend.destinationAlphaBlendFactor,
      gpu.BlendFactor.oneMinusSourceAlpha,
    );
  });

  test('line dash atlas repeats horizontally', () {
    final dash = lineSamplerOptions(ShaderType.lineSDF);
    final gradient = lineSamplerOptions(ShaderType.lineGradient);
    final pattern = lineSamplerOptions(ShaderType.linePattern);

    expect(dash.widthAddressMode, gpu.SamplerAddressMode.repeat);
    expect(dash.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(gradient.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(pattern.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
  });

  test('raster sampler follows exported nearest or linear filter', () {
    final nearest = rasterSamplerOptions(TextureFilterType.nearest);
    final linear = rasterSamplerOptions(TextureFilterType.linear);
    final unknown = rasterSamplerOptions(99);

    expect(nearest.minFilter, gpu.MinMagFilter.nearest);
    expect(nearest.magFilter, gpu.MinMagFilter.nearest);
    expect(linear.minFilter, gpu.MinMagFilter.linear);
    expect(linear.magFilter, gpu.MinMagFilter.linear);
    expect(unknown.minFilter, gpu.MinMagFilter.linear);
    expect(nearest.widthAddressMode, gpu.SamplerAddressMode.clampToEdge);
    expect(nearest.heightAddressMode, gpu.SamplerAddressMode.clampToEdge);
  });

  test('map global uniforms preserve logical and physical viewport sizes', () {
    final values = mapGlobalUniformValues(
      logicalWidth: 333,
      logicalHeight: 211,
      physicalWidth: 499,
      physicalHeight: 316,
    );

    expect(values.unitsX, 166.5);
    expect(values.unitsY, -105.5);
    expect(values.worldWidth, 499);
    expect(values.worldHeight, 316);
  });

  test('uniform offsets honor backend alignment', () {
    expect(alignUniformOffset(0, 256), 0);
    expect(alignUniformOffset(1, 256), 256);
    expect(alignUniformOffset(255, 256), 256);
    expect(alignUniformOffset(256, 256), 256);
    expect(alignUniformOffset(257, 256), 512);
    expect(alignUniformOffset(17, 24), 24);
  });

  test('GPU vertex strides account for float-expanded attributes', () {
    expect(gpuVertexStride(ShaderType.fill, 0), 8);
    expect(gpuVertexStride(ShaderType.fill, 1 << 2), 32);
    expect(gpuVertexStride(ShaderType.circle, 0), 8);
    expect(gpuVertexStride(ShaderType.circle, 1 << 5), 80);
    expect(gpuVertexStride(ShaderType.fillExtrusion, 0), 24);
    expect(gpuVertexStride(ShaderType.fillExtrusion, 1 << 1), 56);
    expect(gpuVertexStride(ShaderType.line, 0), 24);
    expect(gpuVertexStride(ShaderType.linePattern, 1 << 19), 120);
    expect(gpuVertexStride(ShaderType.fillOutlineTriangulated, 0), 24);
    expect(gpuVertexStride(ShaderType.fillOutlineTriangulated, 1 << 20), 48);
    expect(gpuVertexStride(ShaderType.raster, 0), 16);
  });

  test('packed signed-short positions become numeric float attributes', () {
    final source = Uint8List(8);
    final input = ByteData.sublistView(source);
    input
      ..setInt16(0, -32768, Endian.little)
      ..setInt16(2, 32767, Endian.little)
      ..setInt16(4, 7, Endian.little)
      ..setInt16(6, -9, Endian.little);

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 2,
      sourceStride: 4,
      shader: ShaderType.fill,
      flags: 0,
    );
    final output = ByteData.sublistView(result);

    expect(result.lengthInBytes, 16);
    expect(
      [
        for (var offset = 0; offset < 16; offset += 4)
          output.getFloat32(offset, Endian.little),
      ],
      [-32768.0, 32767.0, 7.0, -9.0],
    );
  });

  test('line layout expands short2 and uchar4 to six floats', () {
    final source = Uint8List(8);
    final input = ByteData.sublistView(source);
    input
      ..setInt16(0, -2, Endian.little)
      ..setInt16(2, 4095, Endian.little)
      ..setUint8(4, 0)
      ..setUint8(5, 127)
      ..setUint8(6, 128)
      ..setUint8(7, 255);

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 8,
      shader: ShaderType.line,
      flags: 0,
    );
    final output = ByteData.sublistView(result);

    expect(result.lengthInBytes, 24);
    expect(
      [
        for (var offset = 0; offset < 24; offset += 4)
          output.getFloat32(offset, Endian.little),
      ],
      [-2.0, 4095.0, 0.0, 127.0, 128.0, 255.0],
    );
  });

  test(
    'raster preserves signed positions and unsigned texture coordinates',
    () {
      final rasterSource = Uint8List(8);
      final rasterInput = ByteData.sublistView(rasterSource);
      rasterInput
        ..setInt16(0, -32768, Endian.little)
        ..setInt16(2, 32767, Endian.little)
        ..setUint16(4, 32768, Endian.little)
        ..setUint16(6, 65535, Endian.little);
      final raster = repackVertexDataForGpu(
        rasterSource,
        vertexCount: 1,
        sourceStride: 8,
        shader: ShaderType.raster,
        flags: 0,
      );
      final rasterOutput = ByteData.sublistView(raster);
      expect(
        [
          for (var offset = 0; offset < 16; offset += 4)
            rasterOutput.getFloat32(offset, Endian.little),
        ],
        [-32768.0, 32767.0, 32768.0, 65535.0],
      );
    },
  );

  test('extrusion layout expands every signed short', () {
    final extrusionSource = Uint8List(12);
    final extrusionInput = ByteData.sublistView(extrusionSource);
    for (var i = 0; i < 6; i++) {
      extrusionInput.setInt16(i * 2, i - 3, Endian.little);
    }
    final extrusion = repackVertexDataForGpu(
      extrusionSource,
      vertexCount: 1,
      sourceStride: 12,
      shader: ShaderType.fillExtrusion,
      flags: 0,
    );
    final extrusionOutput = ByteData.sublistView(extrusion);
    expect(
      [
        for (var offset = 0; offset < 24; offset += 4)
          extrusionOutput.getFloat32(offset, Endian.little),
      ],
      [-3.0, -2.0, -1.0, 0.0, 1.0, 2.0],
    );
  });

  test('DD line preserves float ranges and expands ushort4 patterns', () {
    final source = Uint8List(88);
    final input = ByteData.sublistView(source);
    input
      ..setInt16(0, -17, Endian.little)
      ..setInt16(2, 42, Endian.little)
      ..setUint8(4, 1)
      ..setUint8(5, 2)
      ..setUint8(6, 3)
      ..setUint8(7, 4);
    for (var offset = 8; offset < 72; offset += 4) {
      input.setFloat32(offset, offset / 8, Endian.little);
    }
    const patternFrom = [0, 1, 32768, 65535];
    const patternTo = [65535, 32767, 2, 0];
    for (var i = 0; i < 4; i++) {
      input
        ..setUint16(72 + i * 2, patternFrom[i], Endian.little)
        ..setUint16(80 + i * 2, patternTo[i], Endian.little);
    }

    final result = repackVertexDataForGpu(
      source,
      vertexCount: 1,
      sourceStride: 88,
      shader: ShaderType.linePattern,
      flags: 1 << 19,
    );
    final output = ByteData.sublistView(result);

    expect(result.lengthInBytes, 120);
    expect(
      [
        for (var offset = 0; offset < 24; offset += 4)
          output.getFloat32(offset, Endian.little),
      ],
      [-17.0, 42.0, 1.0, 2.0, 3.0, 4.0],
    );
    expect(result.sublist(24, 88), orderedEquals(source.sublist(8, 72)));
    expect([
      for (var offset = 88; offset < 104; offset += 4)
        output.getFloat32(offset, Endian.little),
    ], patternFrom.map((value) => value.toDouble()));
    expect([
      for (var offset = 104; offset < 120; offset += 4)
        output.getFloat32(offset, Endian.little),
    ], patternTo.map((value) => value.toDouble()));
  });

  test('pipeline runs group only adjacent entries and preserve draw order', () {
    final fillPipeline = Object();
    final linePipeline = Object();
    final entries = <({String draw, Object pipeline})>[
      (draw: 'fill-0', pipeline: fillPipeline),
      (draw: 'fill-1', pipeline: fillPipeline),
      (draw: 'line-0', pipeline: linePipeline),
      (draw: 'fill-2', pipeline: fillPipeline),
      (draw: 'line-1', pipeline: linePipeline),
      (draw: 'line-2', pipeline: linePipeline),
    ];

    final runs = maximalAdjacentIdentityRuns(
      entries,
      (entry) => entry.pipeline,
    );

    expect(runs, [
      (start: 0, end: 2),
      (start: 2, end: 3),
      (start: 3, end: 4),
      (start: 4, end: 6),
    ]);
    expect(
      [
        for (final run in runs)
          ...entries.sublist(run.start, run.end).map((entry) => entry.draw),
      ],
      ['fill-0', 'fill-1', 'line-0', 'fill-2', 'line-1', 'line-2'],
    );
  });

  test('render target uses MapLibre premultiplied clear color', () {
    final clear = maplibreClearValue((
      red: 0.1,
      green: 0.2,
      blue: 0.3,
      alpha: 0.4,
    ));
    final fallback = maplibreClearValue(null);

    expect(clear.x, closeTo(0.1, 1e-6));
    expect(clear.y, closeTo(0.2, 1e-6));
    expect(clear.z, closeTo(0.3, 1e-6));
    expect(clear.w, closeTo(0.4, 1e-6));
    expect([fallback.x, fallback.y, fallback.z, fallback.w], [0, 0, 0, 0]);
  });

  test('label refresh follows the native placement snapshot version', () {
    expect(maplibreLabelSnapshotChanged(-1, 0), isTrue);
    expect(maplibreLabelSnapshotChanged(4, 5), isTrue);
    expect(maplibreLabelSnapshotChanged(5, 5), isFalse);
  });

  test(
    'GPU cache retires superseded generations before generic LRU entries',
    () {
      expect(
        gpuCacheEntryExpired(frame: 10, lastUsed: 10, superseded: true),
        isFalse,
      );
      expect(
        gpuCacheEntryExpired(frame: 13, lastUsed: 10, superseded: true),
        isFalse,
      );
      expect(
        gpuCacheEntryExpired(frame: 14, lastUsed: 10, superseded: true),
        isTrue,
      );
      expect(
        gpuCacheEntryExpired(frame: 69, lastUsed: 10, superseded: false),
        isFalse,
      );
      expect(
        gpuCacheEntryExpired(frame: 70, lastUsed: 10, superseded: false),
        isTrue,
      );
    },
  );

  test('GPU cache byte budget evicts oldest inactive entries only', () {
    final victims = gpuCacheBudgetVictims(
      {
        'old-small': (lastUsed: 1, bytes: 4),
        'old-large': (lastUsed: 1, bytes: 8),
        'recent': (lastUsed: 2, bytes: 4),
        'current': (lastUsed: 3, bytes: 100),
      },
      currentFrame: 3,
      maxBytes: 104,
    );

    expect(victims, ['old-large', 'old-small']);
    expect(victims, isNot(contains('current')));
  });

  test('symbol screen offsets stay independent from map projection', () {
    expect(
      maplibreSymbolScreenPosition(const Offset(120, 80), 3.5, -6.25),
      const Offset(123.5, 73.75),
    );
    expect(
      maplibreSymbolScreenPosition(const Offset(240, 160), 3.5, -6.25),
      const Offset(243.5, 153.75),
    );
  });
}
