// DrawCommand-based GPU renderer. Fill + Line (simple/SDF/gradient/pattern)
// + FillExtrusion.
import 'dart:ffi' hide Size;

import 'package:flutter/foundation.dart';
import 'package:flutter_gpu/gpu.dart' as gpu;

import 'native/abi_generated.dart';
import 'native/draw_command.dart';
import 'native/maplibre_ffi.dart';
import 'shaders.dart';

// DrawCommand struct offsets — generated from the C++ ABI locks
// (FGPU_ABI_OFFSET in draw_command.hpp, see tool/gen_abi.dart). These
// aliases keep the render loop readable and can never drift from C++.
const _oShaderType = DrawCommandAbi.shaderType;
const _oDrawMode = DrawCommandAbi.drawMode;
const _oVertexDataPtr = DrawCommandAbi.vertexData;
const _oVertexCount = DrawCommandAbi.vertexCount;
const _oVertexStride = DrawCommandAbi.vertexStride;
const _oIndexDataPtr = DrawCommandAbi.indexData;
const _oIndexCount = DrawCommandAbi.indexCount;
const _oFlags = DrawCommandAbi.flags;
const _oDrawableUBO = DrawCommandAbi.drawableUBO;
const _oPropsUBO = DrawCommandAbi
    .propsUBO; // 96 bytes (FillExtrusionPropsUBO=80 is the largest)
const _oPropsUBOSize = DrawCommandAbi.propsUBOSize;
const _oLayerIndex = DrawCommandAbi.layerIndex;
const _oBufferId = DrawCommandAbi.bufferId;
const _oBufferVersion = DrawCommandAbi.bufferVersion;
const _oTexChannels = DrawCommandAbi.texChannels;
const _oTexDataPtr = DrawCommandAbi.texData;
const _oTexWidth = DrawCommandAbi.texWidth;
const _oTexHeight = DrawCommandAbi.texHeight;
const _oTexId = DrawCommandAbi.texId;
const _oTexVersion = DrawCommandAbi.texVersion;
const _oTexFilter = DrawCommandAbi.texFilter;
const _oTilePropsUBO = DrawCommandAbi.tilePropsUBO;
const _oTilePropsUBOSize = DrawCommandAbi.tilePropsUBOSize;
const _oCameraDistance = DrawCommandAbi.cameraDistance;
const _oStencilReference = DrawCommandAbi.stencilReference;
const _oStencilMode = DrawCommandAbi.stencilMode;
const _cmdStruct = DrawCommandAbi.size;

// DrawCommand::flags mirrors mbgl::fluttergpu::DrawCommandFlags.
const _flagCrossTileMerged = 1 << 0;
const _flagFillExtrusionDataDriven = 1 << 1;
const _flagFillColorDataDriven = 1 << 2;
const _flagFillOpacityDataDriven = 1 << 3;
const _flagFillExtrusionColorDataDriven = 1 << 4;
const _flagCircleColorDataDriven = 1 << 5;
const _flagCircleRadiusDataDriven = 1 << 6;
const _flagCircleBlurDataDriven = 1 << 7;
const _flagCircleOpacityDataDriven = 1 << 8;
const _flagCircleStrokeColorDataDriven = 1 << 9;
const _flagCircleStrokeWidthDataDriven = 1 << 10;
const _flagCircleStrokeOpacityDataDriven = 1 << 11;
const _flagLineColorDataDriven = 1 << 12;
const _flagLineBlurDataDriven = 1 << 13;
const _flagLineOpacityDataDriven = 1 << 14;
const _flagLineGapWidthDataDriven = 1 << 15;
const _flagLineOffsetDataDriven = 1 << 16;
const _flagLineWidthDataDriven = 1 << 17;
const _flagLineFloorWidthDataDriven = 1 << 18;
const _flagLinePatternDataDriven = 1 << 19;
const _flagFillOutlineColorDataDriven = 1 << 20;
const _flagFillOutlineOpacityDataDriven = 1 << 21;
const _flagDepthTest = 1 << 22;
const _flagDepthWrite = 1 << 23;
const _flagFillDataDrivenMask =
    _flagFillColorDataDriven | _flagFillOpacityDataDriven;
const _flagFillOutlineDataDrivenMask =
    _flagFillOutlineColorDataDriven | _flagFillOutlineOpacityDataDriven;
const _flagCircleDataDrivenMask =
    _flagCircleColorDataDriven |
    _flagCircleRadiusDataDriven |
    _flagCircleBlurDataDriven |
    _flagCircleOpacityDataDriven |
    _flagCircleStrokeColorDataDriven |
    _flagCircleStrokeWidthDataDriven |
    _flagCircleStrokeOpacityDataDriven;
const _flagLineDataDrivenMask =
    _flagLineColorDataDriven |
    _flagLineBlurDataDriven |
    _flagLineOpacityDataDriven |
    _flagLineGapWidthDataDriven |
    _flagLineOffsetDataDriven |
    _flagLineWidthDataDriven |
    _flagLineFloorWidthDataDriven |
    _flagLinePatternDataDriven;

/// Effective MapLibre depth state resolved natively after opaquePassCutoff.
@visibleForTesting
bool drawCommandUsesDepth(int flags) => (flags & _flagDepthTest) != 0;

@visibleForTesting
bool drawCommandWritesDepth(int flags) => (flags & _flagDepthWrite) != 0;

/// Flutter GPU stencil state matching MapLibre's resolved native modes.
@visibleForTesting
gpu.StencilConfig stencilConfigFor(int mode) => switch (mode) {
  StencilModeType.disabled => gpu.StencilConfig(
    compareFunction: gpu.CompareFunction.always,
    stencilFailureOperation: gpu.StencilOperation.keep,
    depthFailureOperation: gpu.StencilOperation.keep,
    depthStencilPassOperation: gpu.StencilOperation.keep,
    readMask: 0xff,
    writeMask: 0x00,
  ),
  StencilModeType.clippingMask => gpu.StencilConfig(
    compareFunction: gpu.CompareFunction.always,
    stencilFailureOperation: gpu.StencilOperation.keep,
    depthFailureOperation: gpu.StencilOperation.keep,
    depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
    readMask: 0xff,
    writeMask: 0xff,
  ),
  StencilModeType.clippingTest => gpu.StencilConfig(
    compareFunction: gpu.CompareFunction.equal,
    stencilFailureOperation: gpu.StencilOperation.keep,
    depthFailureOperation: gpu.StencilOperation.keep,
    depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
    readMask: 0xff,
    writeMask: 0x00,
  ),
  StencilModeType.fillExtrusion => gpu.StencilConfig(
    compareFunction: gpu.CompareFunction.notEqual,
    stencilFailureOperation: gpu.StencilOperation.keep,
    depthFailureOperation: gpu.StencilOperation.keep,
    depthStencilPassOperation: gpu.StencilOperation.setToReferenceValue,
    readMask: 0xff,
    writeMask: 0xff,
  ),
  _ => throw StateError('No draw config for stencil mode $mode'),
};

/// Whether a fill command needs the normalized 28-byte data-driven pipeline.
@visibleForTesting
bool fillUsesDataDrivenPipeline(int flags) =>
    (flags & _flagFillDataDrivenMask) != 0;

/// Two-bit mask consumed by FillDDVertex (bit0=color, bit1=opacity).
@visibleForTesting
int fillDataDrivenMask(int flags) => (flags & _flagFillDataDrivenMask) >> 2;

/// Exported fill vertex stride for the command flags.
@visibleForTesting
int fillVertexStride(int flags) => fillUsesDataDrivenPipeline(flags) ? 28 : 4;

/// Whether a triangulated fill-outline command carries normalized paint
/// attributes in addition to its native 8-byte line-layout vertex.
@visibleForTesting
bool fillOutlineUsesDataDrivenPipeline(int flags) =>
    (flags & _flagFillOutlineDataDrivenMask) != 0;

/// Two-bit mask consumed by FillOutlineTriangulatedDDVertex
/// (bit0=outline-color, bit1=opacity).
@visibleForTesting
int fillOutlineDataDrivenMask(int flags) =>
    (flags & _flagFillOutlineDataDrivenMask) >> 20;

/// Exported triangulated fill-outline stride. The DD layout appends the
/// outline-color and opacity ranges at byte offsets 8 and 24.
@visibleForTesting
int fillOutlineVertexStride(int flags) =>
    fillOutlineUsesDataDrivenPipeline(flags) ? 32 : 8;

/// One-bit mask consumed by FillExtrusionDDVertex (bit0=color).
@visibleForTesting
int fillExtrusionDataDrivenMask(int flags) =>
    (flags & _flagFillExtrusionColorDataDriven) >> 4;

/// Exported fill-extrusion stride. The normalized DD layout always contains
/// base, height, and packed-color ranges even when only one is data-driven.
@visibleForTesting
int fillExtrusionVertexStride(int flags) =>
    (flags & _flagFillExtrusionDataDriven) != 0 ? 44 : 12;

/// MapLibre skips the fill-extrusion depth prepass only for fully opaque
/// layers. NaN is conservatively treated as translucent, like `!opacity >= 1`.
@visibleForTesting
bool fillExtrusionNeedsDepthPrepass(double opacity) => !(opacity >= 1.0);

/// Whether a circle command needs the normalized 76-byte pipeline.
@visibleForTesting
bool circleUsesDataDrivenPipeline(int flags) =>
    (flags & _flagCircleDataDrivenMask) != 0;

/// Seven-bit mask consumed by CircleDD shaders, ordered like MapLibre's
/// shader attributes: color through stroke-opacity.
@visibleForTesting
int circleDataDrivenMask(int flags) => (flags & _flagCircleDataDrivenMask) >> 5;

/// Exported circle vertex stride for the command flags.
@visibleForTesting
int circleVertexStride(int flags) =>
    circleUsesDataDrivenPipeline(flags) ? 76 : 4;

/// Whether a line-family command needs the normalized 88-byte pipeline.
@visibleForTesting
bool lineUsesDataDrivenPipeline(int flags) =>
    (flags & _flagLineDataDrivenMask) != 0;

/// Eight-bit mask consumed by Line DD shaders, ordered color, blur, opacity,
/// gap-width, offset, width, floor-width, and pattern.
@visibleForTesting
int lineDataDrivenMask(int flags) => (flags & _flagLineDataDrivenMask) >> 12;

/// Exported line-family vertex stride for the command flags.
@visibleForTesting
int lineVertexStride(int flags) => lineUsesDataDrivenPipeline(flags) ? 88 : 8;

/// Vertex stride consumed by Flutter GPU after packed integer attributes have
/// been expanded to numeric floats for Impeller's OpenGLES backend.
@visibleForTesting
int gpuVertexStride(int shader, int flags) => switch (shader) {
  ShaderType.fill => fillVertexStride(flags) + 4,
  ShaderType.fillOutline ||
  ShaderType.background ||
  ShaderType.clippingMask ||
  ShaderType.backgroundPattern => 8,
  ShaderType.circle => circleVertexStride(flags) + 4,
  ShaderType.fillExtrusion =>
    (flags & _flagFillExtrusionDataDriven) != 0 ? 56 : 24,
  ShaderType.line ||
  ShaderType.lineSDF ||
  ShaderType.lineGradient ||
  ShaderType.linePattern => lineUsesDataDrivenPipeline(flags) ? 120 : 24,
  ShaderType.fillOutlineTriangulated =>
    fillOutlineUsesDataDrivenPipeline(flags) ? 48 : 24,
  ShaderType.raster => 16,
  _ => throw ArgumentError.value(shader, 'shader', 'Unsupported shader type'),
};

void _writeShortsAsFloats(
  ByteData source,
  int sourceOffset,
  ByteData target,
  int targetOffset,
  int count,
) {
  for (var i = 0; i < count; i++) {
    target.setFloat32(
      targetOffset + i * 4,
      source.getInt16(sourceOffset + i * 2, Endian.little).toDouble(),
      Endian.little,
    );
  }
}

void _writeBytesAsFloats(
  ByteData source,
  int sourceOffset,
  ByteData target,
  int targetOffset,
  int count,
) {
  for (var i = 0; i < count; i++) {
    target.setFloat32(
      targetOffset + i * 4,
      source.getUint8(sourceOffset + i).toDouble(),
      Endian.little,
    );
  }
}

void _writeUnsignedShortsAsFloats(
  ByteData source,
  int sourceOffset,
  ByteData target,
  int targetOffset,
  int count,
) {
  for (var i = 0; i < count; i++) {
    target.setFloat32(
      targetOffset + i * 4,
      source.getUint16(sourceOffset + i * 2, Endian.little).toDouble(),
      Endian.little,
    );
  }
}

/// Converts MapLibre's compact short/byte vertex layouts to float-only stage
/// inputs. Impeller OpenGLES binds attributes with `glVertexAttribPointer` and
/// does not support 32-bit integer stage inputs, so passing packed words as
/// float bit patterns would be unsafe for NaN and subnormal encodings.
@visibleForTesting
Uint8List repackVertexDataForGpu(
  Uint8List source, {
  required int vertexCount,
  required int sourceStride,
  required int shader,
  required int flags,
}) {
  final sourceLength = vertexCount * sourceStride;
  if (vertexCount < 0 ||
      sourceStride <= 0 ||
      sourceLength > source.lengthInBytes) {
    throw RangeError('Invalid source vertex range');
  }

  final targetStride = gpuVertexStride(shader, flags);
  final target = Uint8List(vertexCount * targetStride);
  final sourceData = ByteData.sublistView(source, 0, sourceLength);
  final targetData = ByteData.sublistView(target);

  for (var vertex = 0; vertex < vertexCount; vertex++) {
    final sourceOffset = vertex * sourceStride;
    final targetOffset = vertex * targetStride;

    if (shader == ShaderType.fillExtrusion) {
      _writeShortsAsFloats(
        sourceData,
        sourceOffset,
        targetData,
        targetOffset,
        6,
      );
      if (sourceStride > 12) {
        target.setRange(
          targetOffset + 24,
          targetOffset + targetStride,
          source,
          sourceOffset + 12,
        );
      }
      continue;
    }

    if (_isLineShaderValue(shader) ||
        shader == ShaderType.fillOutlineTriangulated) {
      _writeShortsAsFloats(
        sourceData,
        sourceOffset,
        targetData,
        targetOffset,
        2,
      );
      _writeBytesAsFloats(
        sourceData,
        sourceOffset + 4,
        targetData,
        targetOffset + 8,
        4,
      );

      if (shader == ShaderType.fillOutlineTriangulated) {
        if (sourceStride > 8) {
          target.setRange(
            targetOffset + 24,
            targetOffset + targetStride,
            source,
            sourceOffset + 8,
          );
        }
        continue;
      }

      if (sourceStride > 8) {
        // Color plus six scalar ranges are already float data.
        target.setRange(
          targetOffset + 24,
          targetOffset + 88,
          source,
          sourceOffset + 8,
        );
        _writeUnsignedShortsAsFloats(
          sourceData,
          sourceOffset + 72,
          targetData,
          targetOffset + 88,
          4,
        );
        _writeUnsignedShortsAsFloats(
          sourceData,
          sourceOffset + 80,
          targetData,
          targetOffset + 104,
          4,
        );
      }
      continue;
    }

    if (shader == ShaderType.raster) {
      _writeShortsAsFloats(
        sourceData,
        sourceOffset,
        targetData,
        targetOffset,
        2,
      );
      _writeUnsignedShortsAsFloats(
        sourceData,
        sourceOffset + 4,
        targetData,
        targetOffset + 8,
        2,
      );
      continue;
    }

    // Fill, outline, background, circle, clipping mask, and background
    // pattern all begin with one packed signed-short pair.
    _writeShortsAsFloats(sourceData, sourceOffset, targetData, targetOffset, 2);
    if (sourceStride > 4) {
      target.setRange(
        targetOffset + 8,
        targetOffset + targetStride,
        source,
        sourceOffset + 4,
      );
    }
  }
  return target;
}

bool _isLineShaderValue(int shader) =>
    shader == ShaderType.line ||
    shader == ShaderType.lineSDF ||
    shader == ShaderType.lineGradient ||
    shader == ShaderType.linePattern;

/// Aligns a uniform-buffer offset to the backend's binding requirement.
@visibleForTesting
int alignUniformOffset(int offset, int alignment) {
  assert(offset >= 0);
  assert(alignment > 0);
  return ((offset + alignment - 1) ~/ alignment) * alignment;
}

/// Half-open index ranges for maximal adjacent runs that share the exact same
/// key object. Keeping separated equal-key entries in separate runs is what
/// preserves MapLibre's native draw order when pipelines recur later.
@visibleForTesting
List<({int start, int end})> maximalAdjacentIdentityRuns<T, K extends Object>(
  List<T> entries,
  K Function(T entry) keyOf,
) {
  if (entries.isEmpty) return const [];
  final runs = <({int start, int end})>[];
  var start = 0;
  var key = keyOf(entries.first);
  for (var i = 1; i < entries.length; i++) {
    final nextKey = keyOf(entries[i]);
    if (!identical(nextKey, key)) {
      runs.add((start: start, end: i));
      start = i;
      key = nextKey;
    }
  }
  runs.add((start: start, end: entries.length));
  return runs;
}

/// Blend equation used by MapLibre's alpha-blended drawables. MapLibre colors,
/// sampled textures, and shader outputs are premultiplied.
@visibleForTesting
gpu.ColorBlendEquation maplibreAlphaBlendEquation() => gpu.ColorBlendEquation(
  sourceColorBlendFactor: gpu.BlendFactor.one,
  destinationColorBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
  sourceAlphaBlendFactor: gpu.BlendFactor.one,
  destinationAlphaBlendFactor: gpu.BlendFactor.oneMinusSourceAlpha,
);

/// Texture sampling convention for line pipelines. Dash atlases repeat along
/// the line (U) while gradient ramps and sprite atlases clamp at their edges.
@visibleForTesting
gpu.SamplerOptions lineSamplerOptions(int shaderType) => gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: shaderType == ShaderType.lineSDF
      ? gpu.SamplerAddressMode.repeat
      : gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// MapLibre pattern atlases are sampled linearly inside their packed sprite
/// rectangles; atlas edges clamp rather than repeating neighboring sprites.
@visibleForTesting
gpu.SamplerOptions patternAtlasSamplerOptions() => gpu.SamplerOptions(
  minFilter: gpu.MinMagFilter.linear,
  magFilter: gpu.MinMagFilter.linear,
  widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
  heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
);

/// Texture sampling configured by MapLibre's raster-resampling property.
/// Unknown values use linear, matching the style property's default and the
/// renderer's behavior before sampler metadata was exported.
@visibleForTesting
gpu.SamplerOptions rasterSamplerOptions(int textureFilter) {
  final filter = textureFilter == TextureFilterType.nearest
      ? gpu.MinMagFilter.nearest
      : gpu.MinMagFilter.linear;
  return gpu.SamplerOptions(
    minFilter: filter,
    magFilter: filter,
    widthAddressMode: gpu.SamplerAddressMode.clampToEdge,
    heightAddressMode: gpu.SamplerAddressMode.clampToEdge,
  );
}

/// Values mirrored from MapLibre's `GlobalPaintParamsUBO` for shaders that
/// need viewport-space calculations. `units_to_pixels` uses the logical map
/// size; `world_size` uses the physical render target size.
@visibleForTesting
({double unitsX, double unitsY, double worldWidth, double worldHeight})
mapGlobalUniformValues({
  required double logicalWidth,
  required double logicalHeight,
  required int physicalWidth,
  required int physicalHeight,
}) => (
  unitsX: logicalWidth / 2.0,
  unitsY: -logicalHeight / 2.0,
  worldWidth: physicalWidth.toDouble(),
  worldHeight: physicalHeight.toDouble(),
);

class _Buf {
  final gpu.DeviceBuffer buffer;
  final int lengthInBytes;
  int lastUsed = 0;
  _Buf(this.buffer, this.lengthInBytes);
}

class _Tex {
  final gpu.Texture texture;
  final int lengthInBytes;
  int lastUsed = 0;
  _Tex(this.texture, this.lengthInBytes);
}

const _gpuFramesInFlight = 4;
const _gpuUnusedRetentionFrames = 60;
const _gpuBufferCacheBudgetBytes = 64 * 1024 * 1024;
const _gpuTextureCacheBudgetBytes = 64 * 1024 * 1024;

@visibleForTesting
bool gpuCacheEntryExpired({
  required int frame,
  required int lastUsed,
  required bool superseded,
}) {
  final age = frame - lastUsed;
  return age >= _gpuUnusedRetentionFrames ||
      (superseded && age >= _gpuFramesInFlight);
}

@visibleForTesting
List<K> gpuCacheBudgetVictims<K>(
  Map<K, ({int lastUsed, int bytes})> entries, {
  required int currentFrame,
  required int maxBytes,
}) {
  var totalBytes = entries.values.fold<int>(
    0,
    (total, entry) => total + entry.bytes,
  );
  if (totalBytes <= maxBytes) return <K>[];

  final candidates =
      entries.entries
          .where((entry) => entry.value.lastUsed < currentFrame)
          .toList(growable: false)
        ..sort((a, b) {
          final ageOrder = a.value.lastUsed.compareTo(b.value.lastUsed);
          if (ageOrder != 0) return ageOrder;
          return b.value.bytes.compareTo(a.value.bytes);
        });
  final victims = <K>[];
  for (final candidate in candidates) {
    if (totalBytes <= maxBytes) break;
    victims.add(candidate.key);
    totalBytes -= candidate.value.bytes;
  }
  return victims;
}

class _E {
  final int o; // cmd offset
  final int shader;
  final int drawMode;
  final int fl; // DrawCommandFlags bitset
  final int layer;
  final _Buf? vb, ib;
  final int vCount, iCount;
  final gpu.Texture?
  tex; // dash atlas / gradient ramp / pattern atlas / raster tile
  final int texFilter;
  final int stencilReference;
  final int stencilMode;
  int uo = 0, ul = 0, po = 0, pl = 0, to = 0, tl = 0;

  _E(
    this.o,
    this.shader,
    this.drawMode,
    this.fl,
    this.layer,
    this.vCount,
    this.iCount,
    this.vb,
    this.ib,
    this.tex,
    this.texFilter,
    this.stencilReference,
    this.stencilMode,
  );
}

/// Uniform slots for one line-variant pipeline. All line variants bind the
/// evaluated props UBO in BOTH stages (the vertex shader needs width/gapwidth/
/// offset); SDF/pattern additionally bind tile props and a texture.
class _LinePipe {
  final gpu.RenderPipeline p;
  final gpu.UniformSlot vsDrawable;
  final gpu.UniformSlot vsProps;
  final gpu.UniformSlot fsProps;
  final gpu.UniformSlot? vsGlobal;
  final gpu.UniformSlot? vsTileProps; // pattern (DPR comes from scale.x)
  final gpu.UniformSlot? fsTileProps; // SDF + pattern
  final gpu.UniformSlot? fsImage; // sampler
  _LinePipe(
    this.p,
    this.vsDrawable,
    this.vsProps,
    this.fsProps, {
    this.vsGlobal,
    this.vsTileProps,
    this.fsTileProps,
    this.fsImage,
  });
}

/// Pipeline shape for `background-pattern`. Its drawable and evaluated-props
/// UBOs are consumed in both stages; the fragment also samples the pattern
/// atlas. Keeping the drawable UBO in the fragment lets Dart place the atlas
/// dimensions in MapLibre's otherwise-unused padding without extending FFI.
class _BackgroundPatternPipe {
  final gpu.RenderPipeline p;
  final gpu.UniformSlot vsDrawable;
  final gpu.UniformSlot vsProps;
  final gpu.UniformSlot fsDrawable;
  final gpu.UniformSlot fsProps;
  final gpu.UniformSlot fsImage;

  _BackgroundPatternPipe(
    this.p,
    this.vsDrawable,
    this.vsProps,
    this.fsDrawable,
    this.fsProps,
    this.fsImage,
  );
}

class GpuFrameRenderer {
  final MaplibreBridge bridge;
  gpu.RenderPipeline? _fP,
      _fDDP,
      _feP,
      _feDDP,
      _feDepthP,
      _feDDDepthP,
      _foP,
      _fotP,
      _fotDDP,
      _fmP,
      _clipP;
  gpu.UniformSlot? _fVS,
      _fFS,
      _fDDVS,
      _fDDFS,
      _feVS,
      _feFS,
      _feDDVS,
      _feDDFS,
      _feDepthVS,
      _feDepthProps,
      _feDDDepthVS,
      _feDDDepthProps,
      _foVS,
      _foFS,
      _fotVS,
      _fotGlobal,
      _fotFS,
      _fotDDVS,
      _fotDDProps,
      _fotDDGlobal,
      _fmVS,
      _fmFS,
      _clipVS;
  _LinePipe? _lSimple,
      _lSimpleDD,
      _lSdf,
      _lSdfDD,
      _lGradient,
      _lGradientDD,
      _lPattern,
      _lPatternDD,
      _cPipe,
      _cDDPipe,
      _rPipe;
  _BackgroundPatternPipe? _backgroundPatternPipe;
  // Vertex cache includes every value that can alter the repacked bytes.
  // A raw pointer alone is unsafe: freed tile memory can be reallocated at
  // the same address, and one native buffer generation can be presented
  // through a different shader layout without changing its pointer.
  final Map<(int, int, int, int, int, int, int), _Buf> _vc = {};
  final Map<(int, int, int), _Buf> _ic = {};
  // GPU texture cache keyed by (texId, texVersion); texVersion bumps on
  // every C++-side (re)upload, so stale atlas contents are never reused.
  final Map<(int, int), _Tex> _tc = {};
  gpu.HostBuffer? _transientUniforms;
  gpu.Texture? _mainDepthStencilTexture;
  int _mainDepthStencilWidth = 0;
  int _mainDepthStencilHeight = 0;
  Uint8List _ub = Uint8List(0);
  int _frame = 0;
  int cppRenderUs = 0, cppMergeUs = 0;
  int lastDartUs = 0, lastDraws = 0, lastVerts = 0, lastLines = 0;
  double zoom = 0;
  int frameSeq = 0;
  gpu.CommandBuffer? cmdBuf; // set by caller before renderFrame; consumed by it
  final _logSw = Stopwatch()..start();

  GpuFrameRenderer({required this.bridge});

  gpu.RenderPipeline get _fill =>
      _fP ??= _mk('FillVertex', 'FillFragment', (v, f) {
        _fVS = v.getUniformSlot('FillDrawableUBO');
        _fFS = f.getUniformSlot('FillEvaluatedPropsUBO');
      });
  // Data-driven color/opacity variant. Both UBOs are consumed in the vertex
  // stage because the fragment receives the already evaluated paint values.
  gpu.RenderPipeline get _fillDD =>
      _fDDP ??= _mk('FillDDVertex', 'FillDDFragment', (v, f) {
        _fDDVS = v.getUniformSlot('FillDrawableUBO');
        _fDDFS = v.getUniformSlot('FillEvaluatedPropsUBO');
      });
  // NOTE: both FE UBOs live in the VERTEX shader (lighting is per-vertex;
  // the fragment shader has no uniforms) — binding a fragment slot throws.
  gpu.RenderPipeline get _fillExtrusion =>
      _feP ??= _mk('FillExtrusionVertex', 'FillExtrusionFragment', (v, f) {
        _feVS = v.getUniformSlot('FillExtrusionDrawableUBO');
        _feFS = v.getUniformSlot('FillExtrusionPropsUBO');
      });
  // Data-driven base/height/color variant (44-byte verts, flags bit1)
  gpu.RenderPipeline get _fillExtrusionDD =>
      _feDDP ??= _mk('FillExtrusionDDVertex', 'FillExtrusionFragment', (v, f) {
        _feDDVS = v.getUniformSlot('FillExtrusionDrawableUBO');
        _feDDFS = v.getUniformSlot('FillExtrusionPropsUBO');
      });
  // MapLibre renders translucent extrusions depth-only before their color
  // pass. A transparent premultiplied output leaves the color attachment
  // unchanged while Flutter GPU records the same depth prepass.
  gpu.RenderPipeline get _fillExtrusionDepth => _feDepthP ??= _mk(
    'FillExtrusionVertex',
    'FillExtrusionDepthFragment',
    (v, f) {
      _feDepthVS = v.getUniformSlot('FillExtrusionDrawableUBO');
      _feDepthProps = v.getUniformSlot('FillExtrusionPropsUBO');
    },
  );
  gpu.RenderPipeline get _fillExtrusionDDDepth => _feDDDepthP ??= _mk(
    'FillExtrusionDDVertex',
    'FillExtrusionDepthFragment',
    (v, f) {
      _feDDDepthVS = v.getUniformSlot('FillExtrusionDrawableUBO');
      _feDDDepthProps = v.getUniformSlot('FillExtrusionPropsUBO');
    },
  );
  gpu.RenderPipeline get _fillOutline =>
      _foP ??= _mk('FillOutlineVertex', 'FillOutlineFragment', (v, f) {
        _foVS = v.getUniformSlot('FillDrawableUBO');
        _foFS = f.getUniformSlot('FillEvaluatedPropsUBO');
      });
  gpu.RenderPipeline get _fillOutlineTriangulated => _fotP ??= _mk(
    'FillOutlineTriangulatedVertex',
    'FillOutlineTriangulatedFragment',
    (v, f) {
      _fotVS = v.getUniformSlot('FillOutlineTriangulatedDrawableUBO');
      _fotGlobal = v.getUniformSlot('MapGlobalUBO');
      _fotFS = f.getUniformSlot('FillEvaluatedPropsUBO');
    },
  );
  // Data-driven triangulated outline. MapLibre's LineLayoutVertex geometry
  // is followed by normalized outline-color/opacity ranges, while the
  // fragment receives already evaluated paint values from the vertex stage.
  gpu.RenderPipeline get _fillOutlineTriangulatedDD => _fotDDP ??= _mk(
    'FillOutlineTriangulatedDDVertex',
    'FillOutlineTriangulatedDDFragment',
    (v, f) {
      _fotDDVS = v.getUniformSlot('FillOutlineTriangulatedDrawableUBO');
      _fotDDProps = v.getUniformSlot('FillEvaluatedPropsUBO');
      _fotDDGlobal = v.getUniformSlot('MapGlobalUBO');
    },
  );
  // Merged fills use screen-space vertices and never carry tile stencil state.
  gpu.RenderPipeline get _fillMerged =>
      _fmP ??= _mk('FillMergedVertex', 'FillMergedFragment', (v, f) {
        _fmVS = v.getUniformSlot('FillDrawableUBO');
        _fmFS = f.getUniformSlot('FillEvaluatedPropsUBO');
      });
  gpu.RenderPipeline get _clippingMask =>
      _clipP ??= _mk('ClippingMaskVertex', 'ClippingMaskFragment', (v, f) {
        _clipVS = v.getUniformSlot('ClippingMaskDrawableUBO');
      });

  _LinePipe get _lineSimple => _lSimple ??= _mkLine(
    'LineVertex',
    'LineFragment',
    'LineDrawableUBO',
    mapGlobal: true,
  );
  _LinePipe get _lineSimpleDD => _lSimpleDD ??= _mkLine(
    'LineDDVertex',
    'LineDDFragment',
    'LineDrawableUBO',
    mapGlobal: true,
  );
  _LinePipe get _lineSdf => _lSdf ??= _mkLine(
    'LineSDFVertex',
    'LineSDFFragment',
    'LineSDFDrawableUBO',
    tileProps: 'LineSDFTilePropsUBO',
    image: true,
    mapGlobal: true,
  );
  _LinePipe get _lineSdfDD => _lSdfDD ??= _mkLine(
    'LineSDFDDVertex',
    'LineSDFDDFragment',
    'LineSDFDrawableUBO',
    tileProps: 'LineSDFTilePropsUBO',
    image: true,
    mapGlobal: true,
  );
  _LinePipe get _lineGradient => _lGradient ??= _mkLine(
    'LineGradientVertex',
    'LineGradientFragment',
    'LineGradientDrawableUBO',
    image: true,
    mapGlobal: true,
  );
  _LinePipe get _lineGradientDD => _lGradientDD ??= _mkLine(
    'LineGradientDDVertex',
    'LineGradientDDFragment',
    'LineGradientDrawableUBO',
    image: true,
    mapGlobal: true,
  );
  _LinePipe get _linePattern => _lPattern ??= _mkLine(
    'LinePatternVertex',
    'LinePatternFragment',
    'LinePatternDrawableUBO',
    tileProps: 'LinePatternTilePropsUBO',
    image: true,
    vsTileProps: true,
    mapGlobal: true,
  );
  _LinePipe get _linePatternDD => _lPatternDD ??= _mkLine(
    'LinePatternDDVertex',
    'LinePatternDDFragment',
    'LinePatternDrawableUBO',
    tileProps: 'LinePatternTilePropsUBO',
    image: true,
    vsTileProps: true,
    mapGlobal: true,
  );
  // Circle reuses the _LinePipe shape: drawable UBO in VS, props in VS+FS
  _LinePipe get _circle => _cPipe ??= _mkLine(
    'CircleVertex',
    'CircleFragment',
    'CircleDrawableUBO',
    propsName: 'CircleEvaluatedPropsUBO',
  );
  _LinePipe get _circleDD => _cDDPipe ??= _mkLine(
    'CircleDDVertex',
    'CircleDDFragment',
    'CircleDrawableUBO',
    propsName: 'CircleEvaluatedPropsUBO',
  );
  // Raster: drawable UBO (matrix) in VS, props in VS+FS, tile texture in FS.
  // Drawn inside the main pass so raster layers keep their style order
  // relative to background/fill layers.
  _LinePipe get _raster => _rPipe ??= _mkLine(
    'RasterVertex',
    'RasterFragment',
    'RasterDrawableUBO',
    propsName: 'RasterEvaluatedPropsUBO',
    image: true,
  );

  _BackgroundPatternPipe get _backgroundPattern =>
      _backgroundPatternPipe ??= _mkBackgroundPattern();

  _BackgroundPatternPipe _mkBackgroundPattern() {
    final v = mapShaderLibrary['BackgroundPatternVertex'];
    if (v == null) throw Exception('Shader not found: BackgroundPatternVertex');
    final f = mapShaderLibrary['BackgroundPatternFragment'];
    if (f == null) {
      throw Exception('Shader not found: BackgroundPatternFragment');
    }
    return _BackgroundPatternPipe(
      gpu.gpuContext.createRenderPipeline(v, f),
      v.getUniformSlot('BackgroundPatternDrawableUBO'),
      v.getUniformSlot('BackgroundPatternPropsUBO'),
      f.getUniformSlot('BackgroundPatternDrawableUBO'),
      f.getUniformSlot('BackgroundPatternPropsUBO'),
      f.getUniformSlot('u_image'),
    );
  }

  gpu.RenderPipeline _mk(
    String vn,
    String fn,
    void Function(gpu.Shader, gpu.Shader) cb,
  ) {
    final v = mapShaderLibrary[vn];
    if (v == null) throw Exception('Shader not found: $vn');
    final f = mapShaderLibrary[fn];
    if (f == null) throw Exception('Shader not found: $fn');
    final p = gpu.gpuContext.createRenderPipeline(v, f);
    cb(v, f);
    return p;
  }

  _LinePipe _mkLine(
    String vn,
    String fn,
    String drawableName, {
    String? tileProps,
    bool image = false,
    bool vsTileProps = false,
    bool mapGlobal = false,
    String propsName = 'LineEvaluatedPropsUBO',
  }) {
    final v = mapShaderLibrary[vn];
    if (v == null) throw Exception('Shader not found: $vn');
    final f = mapShaderLibrary[fn];
    if (f == null) throw Exception('Shader not found: $fn');
    final p = gpu.gpuContext.createRenderPipeline(v, f);
    return _LinePipe(
      p,
      v.getUniformSlot(drawableName),
      v.getUniformSlot(propsName),
      f.getUniformSlot(propsName),
      vsGlobal: mapGlobal ? v.getUniformSlot('MapGlobalUBO') : null,
      vsTileProps: vsTileProps && tileProps != null
          ? v.getUniformSlot(tileProps)
          : null,
      fsTileProps: tileProps != null ? f.getUniformSlot(tileProps) : null,
      fsImage: image ? f.getUniformSlot('u_image') : null,
    );
  }

  /// Pipeline + (vertex, fragment) uniform slots for a main-pass fill entry
  /// (fill / merged fill / background). FillExtrusion is handled separately.
  (gpu.RenderPipeline, gpu.UniformSlot, gpu.UniformSlot) _fillPipeFor(_E e) {
    if ((e.fl & _flagCrossTileMerged) != 0) {
      final p = _fillMerged;
      return (p, _fmVS!, _fmFS!);
    }
    if (e.shader == ShaderType.fill && fillUsesDataDrivenPipeline(e.fl)) {
      final p = _fillDD;
      return (p, _fDDVS!, _fDDFS!);
    }
    final p = _fill;
    return (p, _fVS!, _fFS!);
  }

  _Buf _vx(int id, int ver, int p, int c, int s, int shader, int flags) {
    final k = (id, ver, p, c, s, shader, gpuVertexStride(shader, flags));
    var b = _vc[k];
    if (b != null) {
      b.lastUsed = _frame;
      return b;
    }
    final source = Pointer<Uint8>.fromAddress(p).asTypedList(c * s);
    final vertices = repackVertexDataForGpu(
      source,
      vertexCount: c,
      sourceStride: s,
      shader: shader,
      flags: flags,
    );
    final g = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertices),
    );
    b = _Buf(g, vertices.lengthInBytes)..lastUsed = _frame;
    _vc[k] = b;
    return b;
  }

  _Buf _ix(int id, int ver, int p, int c) {
    final k = (id, ver, p);
    var b = _ic[k];
    if (b != null) {
      b.lastUsed = _frame;
      return b;
    }
    final l = c * 2;
    final g = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Pointer<Uint8>.fromAddress(p).asTypedList(l)),
    );
    b = _Buf(g, l)..lastUsed = _frame;
    _ic[k] = b;
    return b;
  }

  _Buf _fr(int p, int b) {
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(Pointer<Uint8>.fromAddress(p).asTypedList(b)),
    );
    return _Buf(buffer, b);
  }

  _Buf _fv(int p, int c, int s, int shader, int flags) {
    final source = Pointer<Uint8>.fromAddress(p).asTypedList(c * s);
    final vertices = repackVertexDataForGpu(
      source,
      vertexCount: c,
      sourceStride: s,
      shader: shader,
      flags: flags,
    );
    final buffer = gpu.gpuContext.createDeviceBufferWithCopy(
      ByteData.sublistView(vertices),
    );
    return _Buf(buffer, vertices.lengthInBytes);
  }

  /// Get (or create) a GPU texture for exported C++ pixel data.
  /// 1-channel data (dash SDF atlas) uploads as R8; 4-channel as RGBA8.
  gpu.Texture? _tx(int id, int ver, int ptr, int w, int h, int ch) {
    if (ptr == 0 || w <= 0 || h <= 0 || (ch != 1 && ch != 4)) return null;
    final k = (id, ver);
    var t = _tc[k];
    if (t != null) {
      t.lastUsed = _frame;
      return t.texture;
    }
    try {
      final tex = gpu.gpuContext.createTexture(
        gpu.StorageMode.hostVisible,
        w,
        h,
        format: ch == 1
            ? gpu.PixelFormat.r8UNormInt
            : gpu.PixelFormat.r8g8b8a8UNormInt,
        enableRenderTargetUsage: false,
        enableShaderReadUsage: true,
      );
      final bytes = Pointer<Uint8>.fromAddress(ptr).asTypedList(w * h * ch);
      tex.overwrite(ByteData.sublistView(bytes));
      _tc[k] = _Tex(tex, w * h * ch)..lastUsed = _frame;
      return tex;
    } catch (e) {
      debugPrint('[GpuRenderer] texture upload failed ($w x $h ch=$ch): $e');
      return null;
    }
  }

  void _ev() {
    final latestVertexVersion = <int, int>{};
    final latestVertexUse = <int, int>{};
    for (final entry in _vc.entries) {
      final id = entry.key.$1;
      final used = entry.value.lastUsed;
      if (used >= (latestVertexUse[id] ?? -1)) {
        latestVertexUse[id] = used;
        latestVertexVersion[id] = entry.key.$2;
      }
    }
    _vc.removeWhere(
      (key, value) => gpuCacheEntryExpired(
        frame: _frame,
        lastUsed: value.lastUsed,
        superseded: key.$2 != latestVertexVersion[key.$1],
      ),
    );

    final latestIndexVersion = <int, int>{};
    final latestIndexUse = <int, int>{};
    for (final entry in _ic.entries) {
      final id = entry.key.$1;
      final used = entry.value.lastUsed;
      if (used >= (latestIndexUse[id] ?? -1)) {
        latestIndexUse[id] = used;
        latestIndexVersion[id] = entry.key.$2;
      }
    }
    _ic.removeWhere(
      (key, value) => gpuCacheEntryExpired(
        frame: _frame,
        lastUsed: value.lastUsed,
        superseded: key.$2 != latestIndexVersion[key.$1],
      ),
    );

    final latestTextureVersion = <int, int>{};
    final latestTextureUse = <int, int>{};
    for (final entry in _tc.entries) {
      final id = entry.key.$1;
      final used = entry.value.lastUsed;
      if (used >= (latestTextureUse[id] ?? -1)) {
        latestTextureUse[id] = used;
        latestTextureVersion[id] = entry.key.$2;
      }
    }
    _tc.removeWhere(
      (key, value) => gpuCacheEntryExpired(
        frame: _frame,
        lastUsed: value.lastUsed,
        superseded: key.$2 != latestTextureVersion[key.$1],
      ),
    );

    final bufferEntries =
        <
          (bool, int, int, int, int, int, int, int),
          ({int lastUsed, int bytes})
        >{
          for (final entry in _vc.entries)
            (
              true,
              entry.key.$1,
              entry.key.$2,
              entry.key.$3,
              entry.key.$4,
              entry.key.$5,
              entry.key.$6,
              entry.key.$7,
            ): (
              lastUsed: entry.value.lastUsed,
              bytes: entry.value.lengthInBytes,
            ),
          for (final entry in _ic.entries)
            (false, entry.key.$1, entry.key.$2, entry.key.$3, 0, 0, 0, 0): (
              lastUsed: entry.value.lastUsed,
              bytes: entry.value.lengthInBytes,
            ),
        };
    for (final key in gpuCacheBudgetVictims(
      bufferEntries,
      currentFrame: _frame,
      maxBytes: _gpuBufferCacheBudgetBytes,
    )) {
      if (key.$1) {
        _vc.remove((key.$2, key.$3, key.$4, key.$5, key.$6, key.$7, key.$8));
      } else {
        _ic.remove((key.$2, key.$3, key.$4));
      }
    }

    final textureEntries = <(int, int), ({int lastUsed, int bytes})>{
      for (final entry in _tc.entries)
        entry.key: (
          lastUsed: entry.value.lastUsed,
          bytes: entry.value.lengthInBytes,
        ),
    };
    for (final key in gpuCacheBudgetVictims(
      textureEntries,
      currentFrame: _frame,
      maxBytes: _gpuTextureCacheBudgetBytes,
    )) {
      _tc.remove(key);
    }
  }

  static bool _isLineShader(int sh) =>
      sh == ShaderType.line ||
      sh == ShaderType.lineSDF ||
      sh == ShaderType.lineGradient ||
      sh == ShaderType.linePattern;

  static gpu.PrimitiveType _prim(int drawMode) => switch (drawMode) {
    DrawModeType.lines => gpu.PrimitiveType.line,
    DrawModeType.lineStrip => gpu.PrimitiveType.lineStrip,
    DrawModeType.points => gpu.PrimitiveType.point,
    _ => gpu.PrimitiveType.triangle,
  };

  /// True once creating a depth attachment failed — Flutter GPU used to
  /// crash with DepthStencilAttachment (see project notes); when it throws
  /// a catchable error we permanently fall back to depth-less rendering.
  static bool _depthStencilUnsupported = false;

  /// MapLibre shaders produce premultiplied RGBA. Keep the same blend
  /// convention here so every pipeline, including circle and fill-extrusion,
  /// applies opacity exactly once.
  void _setPremultipliedAlphaBlend(gpu.RenderPass rp) {
    rp.setColorBlendEnable(true);
    rp.setColorBlendEquation(maplibreAlphaBlendEquation());
  }

  gpu.Texture? _depthStencilTextureFor(gpu.Texture colorTexture) {
    if (_depthStencilUnsupported) return null;
    final cached = _mainDepthStencilTexture;
    if (cached != null &&
        _mainDepthStencilWidth == colorTexture.width &&
        _mainDepthStencilHeight == colorTexture.height) {
      return cached;
    }
    try {
      final depth = gpu.gpuContext.createTexture(
        gpu.StorageMode.devicePrivate,
        colorTexture.width,
        colorTexture.height,
        format: gpu.gpuContext.defaultDepthStencilFormat,
        enableRenderTargetUsage: true,
      );
      _mainDepthStencilTexture = depth;
      _mainDepthStencilWidth = colorTexture.width;
      _mainDepthStencilHeight = colorTexture.height;
      return depth;
    } catch (e) {
      _depthStencilUnsupported = true;
      _mainDepthStencilTexture = null;
      debugPrint(
        '[GpuRenderer] depth/stencil attachment unavailable, '
        'falling back to unclipped depth-less rendering: $e',
      );
      return null;
    }
  }

  /// Draws [items] on [texture] in a new render pass with LoadAction.load.
  /// Flutter GPU can't reliably switch pipelines mid-pass, so each pipeline
  /// gets its own pass. [bind] binds per-entry uniforms/textures.
  /// [depthStencilTexture] is shared by every depth/stencil pass in the frame.
  /// Both aspects are stored, then loaded by later passes. Attachment presence
  /// is independent from [depthTest] because clipping masks use stencil only.
  /// [cullBackFaces] matches MapLibre's backCCW cull mode.
  int _overlayPass(
    gpu.Texture texture,
    gpu.RenderPipeline pl,
    List<_E> items,
    void Function(gpu.RenderPass, _E) bind, {
    bool setPrimitive = false,
    gpu.Texture? depthStencilTexture,
    bool clearDepth = false,
    bool clearStencil = false,
    bool depthTest = false,
    bool depthWrite = false,
    int stencilMode = StencilModeType.disabled,
    bool cullBackFaces = false,
  }) {
    final cb = gpu.gpuContext.createCommandBuffer();
    final rt = gpu.RenderTarget(
      colorAttachments: [
        gpu.ColorAttachment(texture: texture, loadAction: gpu.LoadAction.load),
      ],
      depthStencilAttachment: depthStencilTexture == null
          ? null
          : gpu.DepthStencilAttachment(
              texture: depthStencilTexture,
              depthLoadAction: clearDepth
                  ? gpu.LoadAction.clear
                  : gpu.LoadAction.load,
              depthStoreAction: gpu.StoreAction.store,
              depthClearValue: 1.0,
              stencilLoadAction: clearStencil
                  ? gpu.LoadAction.clear
                  : gpu.LoadAction.load,
              stencilStoreAction: gpu.StoreAction.store,
              stencilClearValue: 0,
            ),
    );
    final rp = cb.createRenderPass(rt);
    if (depthTest && depthStencilTexture != null) {
      // Flutter 3.38-3.44 ignores the boolean argument and always enables
      // writes. Leave the fresh pass at its default false for ReadOnly mode.
      if (depthWrite) rp.setDepthWriteEnable(true);
      rp.setDepthCompareOperation(gpu.CompareFunction.lessEqual);
    }
    if (depthStencilTexture != null) {
      rp.setStencilConfig(stencilConfigFor(stencilMode));
    }
    if (cullBackFaces) {
      rp.setWindingOrder(gpu.WindingOrder.counterClockwise);
      rp.setCullMode(gpu.CullMode.backFace);
    }
    _setPremultipliedAlphaBlend(rp);
    rp.bindPipeline(pl);
    var dc = 0;
    for (final e in items) {
      if (setPrimitive) rp.setPrimitiveType(_prim(e.drawMode));
      if (stencilMode != StencilModeType.disabled) {
        rp.setStencilReference(e.stencilReference & 0xff);
      }
      rp.bindVertexBuffer(
        gpu.BufferView(
          e.vb!.buffer,
          offsetInBytes: 0,
          lengthInBytes: e.vb!.lengthInBytes,
        ),
        e.vCount,
      );
      rp.bindIndexBuffer(
        gpu.BufferView(
          e.ib!.buffer,
          offsetInBytes: 0,
          lengthInBytes: e.ib!.lengthInBytes,
        ),
        gpu.IndexType.int16,
        e.iCount,
      );
      bind(rp, e);
      rp.draw();
      dc++;
    }
    cb.submit();
    return dc;
  }

  /// Replays MapLibre's ordered mid-frame stencil clear without disturbing
  /// color or an already-populated depth aspect.
  void _clearStencilPass(
    gpu.Texture colorTexture,
    gpu.Texture depthStencilTexture, {
    required bool attachmentInitialized,
    required int clearValue,
  }) {
    final cb = gpu.gpuContext.createCommandBuffer();
    cb.createRenderPass(
      gpu.RenderTarget.singleColor(
        gpu.ColorAttachment(
          texture: colorTexture,
          loadAction: gpu.LoadAction.load,
        ),
        depthStencilAttachment: gpu.DepthStencilAttachment(
          texture: depthStencilTexture,
          depthLoadAction: attachmentInitialized
              ? gpu.LoadAction.load
              : gpu.LoadAction.clear,
          depthStoreAction: gpu.StoreAction.store,
          depthClearValue: 1.0,
          stencilLoadAction: gpu.LoadAction.clear,
          stencilStoreAction: gpu.StoreAction.store,
          stencilClearValue: clearValue & 0xff,
        ),
      ),
    );
    cb.submit();
  }

  /// Binds uniforms + texture for a line-variant entry.
  void _bindLine(
    gpu.RenderPass rp,
    _LinePipe lp,
    gpu.DeviceBuffer ubuf,
    _E e,
    int mapGlobalOffset,
  ) {
    rp.bindUniform(
      lp.vsDrawable,
      gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
    );
    rp.bindUniform(
      lp.vsProps,
      gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
    );
    rp.bindUniform(
      lp.fsProps,
      gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
    );
    if (lp.vsGlobal != null) {
      rp.bindUniform(
        lp.vsGlobal!,
        gpu.BufferView(ubuf, offsetInBytes: mapGlobalOffset, lengthInBytes: 16),
      );
    }
    if (e.tl > 0) {
      final tp = gpu.BufferView(ubuf, offsetInBytes: e.to, lengthInBytes: e.tl);
      if (lp.vsTileProps != null) rp.bindUniform(lp.vsTileProps!, tp);
      if (lp.fsTileProps != null) rp.bindUniform(lp.fsTileProps!, tp);
    }
    if (lp.fsImage != null && e.tex != null) {
      rp.bindTexture(
        lp.fsImage!,
        e.tex!,
        sampler: lineSamplerOptions(e.shader),
      );
    }
  }

  /// Renders one frame. Owns submission of [cmdBuf]: it is submitted exactly
  /// once no matter which path returns — callers must NOT submit it again.
  int renderFrame(
    gpu.RenderPass rp, {
    gpu.Texture? texture,
    double? logicalWidth,
    double? logicalHeight,
  }) {
    try {
      return _renderFrameImpl(
        rp,
        texture: texture,
        logicalWidth: logicalWidth,
        logicalHeight: logicalHeight,
      );
    } catch (e, st) {
      debugPrint('[GpuRenderer] error: $e\n$st');
      return 0;
    } finally {
      // Submit the main command buffer if no path consumed it (early return
      // or exception) so the render target's clear still lands.
      final cb = cmdBuf;
      cmdBuf = null;
      if (cb != null) {
        try {
          cb.submit();
        } catch (e) {
          debugPrint('[GpuRenderer] submit error: $e');
        }
      }
      _ev();
    }
  }

  int _renderFrameImpl(
    gpu.RenderPass rp, {
    gpu.Texture? texture,
    double? logicalWidth,
    double? logicalHeight,
  }) {
    _frame++;
    final uniforms = _transientUniforms;
    if (uniforms == null) {
      _transientUniforms = gpu.gpuContext.createHostBuffer();
    } else {
      uniforms.reset();
    }
    final log = _logSw.elapsedMilliseconds >= 1000;
    if (log) _logSw.reset();
    final sw = Stopwatch()..start();
    final n = bridge.frameGetCommandCount();
    if (n <= 0) return 0;
    final p = bridge.frameGetCommands();
    if (p == nullptr) return 0;
    final stride = bridge.frameGetCommandStride();
    if (stride != _cmdStruct) {
      if (log) {
        debugPrint(
          '[GpuRenderer] ABI mismatch: stride=$stride expected=$_cmdStruct',
        );
      }
      return 0;
    }
    final bd = ByteData.sublistView(p.cast<Uint8>().asTypedList(n * stride));
    final cb = p.cast<Uint8>().asTypedList(n * stride);
    final dpr = bridge.devicePixelRatio;
    final backendAlignment = gpu.gpuContext.minimumUniformByteAlignment;
    final uniformAlignment = backendAlignment < 16 ? 16 : backendAlignment;

    final es = <_E>[];
    int ut = 0;
    int nLines = 0;
    for (var i = 0; i < n; i++) {
      final o = i * stride;
      final sh = bd.getUint32(o + _oShaderType, Endian.little);
      final isLine = _isLineShader(sh);
      final isCircle = sh == ShaderType.circle;
      final isRaster = sh == ShaderType.raster;
      final isTriangulatedOutline = sh == ShaderType.fillOutlineTriangulated;
      final isClippingMask = sh == ShaderType.clippingMask;
      final isBackgroundPattern = sh == ShaderType.backgroundPattern;
      if (sh != ShaderType.fill &&
          sh != ShaderType.fillOutline &&
          !isTriangulatedOutline &&
          sh != ShaderType.fillExtrusion &&
          sh != ShaderType.background &&
          !isLine &&
          !isCircle &&
          !isRaster &&
          !isClippingMask &&
          !isBackgroundPattern) {
        continue;
      }
      final fl = bd.getUint32(o + _oFlags, Endian.little);
      final dm = bd.getUint32(o + _oDrawMode, Endian.little);
      final layer = bd.getUint32(o + _oLayerIndex, Endian.little);
      final stencilReference = bd.getUint32(
        o + _oStencilReference,
        Endian.little,
      );
      final stencilMode = bd.getUint32(o + _oStencilMode, Endian.little);

      // Mid-frame clear is an ordered control command with no geometry.
      // Preserve it before vertex/index validation so overflow handling is
      // not silently discarded.
      if (stencilMode == StencilModeType.clear) {
        es.add(
          _E(
            o,
            sh,
            dm,
            fl,
            layer,
            0,
            0,
            null,
            null,
            null,
            TextureFilterType.linear,
            stencilReference,
            stencilMode,
          ),
        );
        continue;
      }
      final vc = bd.getUint32(o + _oVertexCount, Endian.little);
      final ic = bd.getUint32(o + _oIndexCount, Endian.little);
      if (vc == 0 || ic == 0) continue;
      final vp = bd.getUint64(o + _oVertexDataPtr, Endian.little);
      final ip = bd.getUint64(o + _oIndexDataPtr, Endian.little);
      if (vp == 0 || ip == 0) continue;

      final m0 = bd.getFloat32(o + _oDrawableUBO, Endian.little);
      final m5 = bd.getFloat32(o + _oDrawableUBO + 20, Endian.little);
      if (m0 == 0 && m5 == 0) continue;
      final isFE = sh == ShaderType.fillExtrusion;
      final isSdf = sh == ShaderType.lineSDF;
      final isPattern = sh == ShaderType.linePattern;
      // FE=12 (44 with DD paint), circle=4 (76 with DD paint),
      // line*/raster=8, triangulated-outline=8 (32 with DD paint), fill=4
      // (28 with DD paint), and background/pattern/basic-outline/mask=4.
      final vs = isFE
          ? fillExtrusionVertexStride(fl)
          : sh == ShaderType.fill
          ? fillVertexStride(fl)
          : isCircle
          ? circleVertexStride(fl)
          : isLine
          ? lineVertexStride(fl)
          : isTriangulatedOutline
          ? fillOutlineVertexStride(fl)
          : isRaster
          ? 8
          : 4;
      final exportedVs = bd.getUint32(o + _oVertexStride, Endian.little);
      if (exportedVs != vs) {
        if (log) {
          debugPrint(
            '[GpuRenderer] vertex stride mismatch: shader=$sh flags=$fl '
            'exported=$exportedVs expected=$vs',
          );
        }
        continue;
      }
      // drawable UBO sizes: FE=112, LineSDF=128, other lines=96,
      // circle=112, background-pattern=96, raster/mask=64, fill=80.
      final ul = isClippingMask
          ? 64
          : isBackgroundPattern
          ? 96
          : isFE
          ? 112
          : isSdf
          ? 128
          : isLine
          ? 96
          : isCircle
          ? 112
          : isRaster
          ? 64
          : 80;
      final pll = isClippingMask
          ? 0
          : isBackgroundPattern
          ? 64
          : isFE
          ? 80
          : (isCircle || isRaster)
          ? 64
          : 48; // props: FE=80, circle/raster=64, line*/fill=48
      final tl = isSdf
          ? 16
          : isPattern
          ? 64
          : 0; // tile props: SDF=16, pattern=64
      final bid = bd.getUint32(o + _oBufferId, Endian.little);
      final bver = bd.getUint32(o + _oBufferVersion, Endian.little);
      // Cross-tile merged buffers are frame-owned; all other buffers cache by
      // the native drawable generation, including 28-byte DD fill vertices.
      final isMerged = (fl & _flagCrossTileMerged) != 0;
      final vb = isMerged
          ? _fv(vp, vc, vs, sh, fl)
          : _vx(bid, bver, vp, vc, vs, sh, fl);
      final ib = isMerged ? _fr(ip, ic * 2) : _ix(bid, bver, ip, ic);
      // Texture (dash atlas / gradient ramp / pattern atlas)
      gpu.Texture? tex;
      final tch = bd.getUint32(o + _oTexChannels, Endian.little);
      if (tch > 0) {
        tex = _tx(
          bd.getUint32(o + _oTexId, Endian.little),
          bd.getUint32(o + _oTexVersion, Endian.little),
          bd.getUint64(o + _oTexDataPtr, Endian.little),
          bd.getUint32(o + _oTexWidth, Endian.little),
          bd.getUint32(o + _oTexHeight, Endian.little),
          tch,
        );
        // Texture-backed variants cannot render without their image.
        if (tex == null &&
            (isSdf ||
                isPattern ||
                sh == ShaderType.lineGradient ||
                isRaster ||
                isBackgroundPattern)) {
          continue;
        }
      } else if (isRaster || isBackgroundPattern) {
        continue;
      }
      if (isLine) nLines++;
      final e = _E(
        o,
        sh,
        dm,
        fl,
        layer,
        vc,
        ic,
        vb,
        ib,
        tex,
        bd.getUint32(o + _oTexFilter, Endian.little),
        stencilReference,
        stencilMode,
      );
      e.uo = alignUniformOffset(ut, uniformAlignment);
      e.po = alignUniformOffset(e.uo + ul, uniformAlignment);
      e.ul = ul;
      e.pl = pll;
      var next = e.po + pll;
      if (tl > 0) {
        e.to = alignUniformOffset(next, uniformAlignment);
        e.tl = tl;
        next = e.to + tl;
      }
      ut = next;
      es.add(e);
    }
    if (es.isEmpty) return 0;
    final hasMapGlobal =
        nLines > 0 ||
        es.any((e) => e.shader == ShaderType.fillOutlineTriangulated);
    final mapGlobalOffset = hasMapGlobal
        ? alignUniformOffset(ut, uniformAlignment)
        : 0;
    if (hasMapGlobal) ut = mapGlobalOffset + 16;
    final t1 = sw.elapsedMicroseconds;

    // Pack UBOs
    final us = alignUniformOffset(ut < 16 ? 16 : ut, uniformAlignment);
    if (_ub.length < us) _ub = Uint8List((us * 1.5).toInt());
    _ub.fillRange(0, us, 0);
    final ubd = ByteData.sublistView(_ub);
    if (hasMapGlobal) {
      final physicalWidth = texture?.width ?? 1;
      final physicalHeight = texture?.height ?? 1;
      final safeDpr = dpr.isFinite && dpr > 0 ? dpr : 1.0;
      final global = mapGlobalUniformValues(
        logicalWidth: logicalWidth ?? physicalWidth / safeDpr,
        logicalHeight: logicalHeight ?? physicalHeight / safeDpr,
        physicalWidth: physicalWidth,
        physicalHeight: physicalHeight,
      );
      ubd.setFloat32(mapGlobalOffset, global.unitsX, Endian.little);
      ubd.setFloat32(mapGlobalOffset + 4, global.unitsY, Endian.little);
      ubd.setFloat32(mapGlobalOffset + 8, global.worldWidth, Endian.little);
      ubd.setFloat32(mapGlobalOffset + 12, global.worldHeight, Endian.little);
    }
    for (final e in es) {
      if (e.stencilMode == StencilModeType.clear) continue;
      final o = e.o;
      final isFECmd = e.shader == ShaderType.fillExtrusion;
      final isLineCmd = _isLineShader(e.shader);
      final isCircleCmd = e.shader == ShaderType.circle;
      final isRasterCmd = e.shader == ShaderType.raster;
      final isBackgroundPatternCmd = e.shader == ShaderType.backgroundPattern;
      final isTriangulatedOutlineCmd =
          e.shader == ShaderType.fillOutlineTriangulated;
      _ub.setRange(
        e.uo,
        e.uo + 64,
        cb,
        o + _oDrawableUBO,
      ); // mat4 for all types
      if (e.shader == ShaderType.clippingMask) continue;
      if (isBackgroundPatternCmd) {
        // Preserve MapLibre's 96-byte drawable and 64-byte props UBOs. The
        // native drawable padding at bytes 84/88 carries atlas dimensions to
        // the Flutter fragment shader in place of GlobalPaintParamsUBO.
        _ub.setRange(e.uo + 64, e.uo + 96, cb, o + _oDrawableUBO + 64);
        final ps = bd.getUint32(o + _oPropsUBOSize, Endian.little);
        if (ps > 0) {
          final cl = ps < 64 ? ps : 64;
          _ub.setRange(e.po, e.po + cl, cb, o + _oPropsUBO);
        }
        ubd.setFloat32(e.uo + 84, e.tex!.width.toDouble(), Endian.little);
        ubd.setFloat32(e.uo + 88, e.tex!.height.toDouble(), Endian.little);
      } else if (isRasterCmd) {
        // RasterDrawableUBO is just the matrix (already copied above).
        // RasterEvaluatedPropsUBO (64): spin/tl_parent/scales/opacity...
        final ps = bd.getUint32(o + _oPropsUBOSize, Endian.little);
        if (ps > 0) {
          final cl = ps < 64 ? ps : 64;
          _ub.setRange(e.po, e.po + cl, cb, o + _oPropsUBO);
        }
      } else if (isCircleCmd) {
        // CircleDrawableUBO (112): extrude_scale + interpolation pads.
        _ub.setRange(e.uo + 64, e.uo + 112, cb, o + _oDrawableUBO + 64);
        // Patch camera distance (pad1, byte 100) and DPR (pad2, byte 104) —
        // the circle shader needs both for sizing and antialiasing.
        ubd.setFloat32(
          e.uo + 100,
          bd.getFloat32(o + _oCameraDistance, Endian.little),
          Endian.little,
        );
        ubd.setFloat32(e.uo + 104, dpr, Endian.little);
        // CircleEvaluatedPropsUBO (64): color/stroke/radius/blur/opacity...
        final ps = bd.getUint32(o + _oPropsUBOSize, Endian.little);
        if (ps > 0) {
          final cl = ps < 64 ? ps : 64;
          _ub.setRange(e.po, e.po + cl, cb, o + _oPropsUBO);
        }
        if (circleUsesDataDrivenPipeline(e.fl)) {
          // CircleEvaluatedPropsUBO::pad1 at byte 60 is unused natively.
          // Carry the seven-property runtime mask without changing the
          // MapLibre UBO or DrawCommand ABI.
          ubd.setUint32(e.po + 60, circleDataDrivenMask(e.fl), Endian.little);
        }
      } else if (isFECmd) {
        _ub.setRange(e.uo + 64, e.uo + 112, cb, o + _oDrawableUBO + 64);
        if ((e.fl & _flagFillExtrusionDataDriven) != 0) {
          // Native FillExtrusionDrawableUBO::pad1 at byte 108 is unused by
          // this pipeline. Carry the color attribute mask without changing
          // the native UBO or DrawCommand ABI.
          ubd.setUint32(
            e.uo + 108,
            fillExtrusionDataDrivenMask(e.fl),
            Endian.little,
          );
        }
        final pSize = bd.getUint32(o + _oPropsUBOSize, Endian.little);
        if (pSize > 0) {
          final copyLen = pSize < 80 ? pSize : 80;
          _ub.setRange(e.po, e.po + copyLen, cb, o + _oPropsUBO);
        }
      } else if (isLineCmd) {
        // Copy the full drawable UBO as exported by the C++ tweaker
        // (LineDrawableUBO=96 / LineSDFDrawableUBO=128 / gradient/pattern=96)
        _ub.setRange(e.uo + 64, e.uo + e.ul, cb, o + _oDrawableUBO + 64);
        // Patch the device pixel ratio into the pad field the shaders read
        // (line & gradient: byte 92; SDF: byte 120; pattern uses tileProps
        // scale.x which C++ already fills with the real pixel ratio).
        if (e.shader == ShaderType.line ||
            e.shader == ShaderType.lineGradient) {
          ubd.setFloat32(e.uo + 92, dpr, Endian.little);
        } else if (e.shader == ShaderType.lineSDF) {
          ubd.setFloat32(e.uo + 120, dpr, Endian.little);
        }
        // Line props: color(16)+blur(4)+opacity(4)+gapwidth(4)+offset(4)+width(4)+floorwidth(4)+pad(8)=48
        final ps = bd.getUint32(o + _oPropsUBOSize, Endian.little);
        if (ps > 0) {
          final cl = ps < 48 ? ps : 48;
          _ub.setRange(e.po, e.po + cl, cb, o + _oPropsUBO);
        }
        if (lineUsesDataDrivenPipeline(e.fl)) {
          // LineEvaluatedPropsUBO::expressionMask at byte 40 is unused by
          // this backend's CPU-evaluated fixed path. Carry the eight
          // per-vertex paint-property bits to the DD shaders.
          ubd.setUint32(e.po + 40, lineDataDrivenMask(e.fl), Endian.little);
        }
        // Defaults only when the props UBO was too small to contain the
        // field — a real 0 from the style (opacity/width 0) must stay 0.
        if (ps < 24) ubd.setFloat32(e.po + 20, 1.0, Endian.little); // opacity
        if (ps < 36) ubd.setFloat32(e.po + 32, 1.0, Endian.little); // width
        // Tile props (SDF: sdfgamma/mix, pattern: from/to/scale/texsize/fade)
        if (e.tl > 0) {
          final ts = bd.getUint32(o + _oTilePropsUBOSize, Endian.little);
          if (ts > 0) {
            final ctl = ts < e.tl ? ts : e.tl;
            _ub.setRange(e.to, e.to + ctl, cb, o + _oTilePropsUBO);
          }
        }
      } else {
        if (e.shader == ShaderType.fill && fillUsesDataDrivenPipeline(e.fl)) {
          // Keep MapLibre's exact per-frame color_t/opacity_t values. Replace
          // the otherwise-unused pad1 at byte 72 with the two-bit DD mask.
          _ub.setRange(e.uo + 64, e.uo + 80, cb, o + _oDrawableUBO + 64);
          ubd.setUint32(e.uo + 72, fillDataDrivenMask(e.fl), Endian.little);
        }
        if (isTriangulatedOutlineCmd) {
          _ub.setRange(e.uo + 64, e.uo + 80, cb, o + _oDrawableUBO + 64);
          // FillOutlineTriangulatedDrawableUBO::pad1 (byte 68) carries DPR.
          ubd.setFloat32(e.uo + 68, dpr, Endian.little);
        }
        // Fill/FillOutline/Background props → FillEvaluatedPropsUBO layout.
        // Background's own UBO stores opacity at 16 (no outline_color);
        // fill stores it at 32. Repack both into the fill layout.
        final ps = bd.getUint32(o + _oPropsUBOSize, Endian.little);
        final isBg = e.shader == ShaderType.background;
        final opOff = isBg ? 16 : 32;
        if (ps >= opOff + 4) {
          _ub.setRange(e.po, e.po + 16, cb, o + _oPropsUBO); // color
          if (!isBg) {
            _ub.setRange(
              e.po + 16,
              e.po + 32,
              cb,
              o + _oPropsUBO + 16,
            ); // outline_color
          }
          ubd.setFloat32(
            e.po + 32,
            bd.getFloat32(o + _oPropsUBO + opOff, Endian.little),
            Endian.little,
          );
        } else {
          for (final off in [0, 4, 8, 12]) {
            ubd.setFloat32(e.po + off, 1.0, Endian.little);
          }
          ubd.setFloat32(e.po + 32, 1.0, Endian.little);
        }
        if (isTriangulatedOutlineCmd &&
            fillOutlineUsesDataDrivenPipeline(e.fl)) {
          // FillEvaluatedPropsUBO::fade is unused by unpatterned outlines.
          // Reinterpret its four bytes as the independent color/opacity mask
          // without changing MapLibre's native UBO or DrawCommand ABI.
          ubd.setUint32(
            e.po + 36,
            fillOutlineDataDrivenMask(e.fl),
            Endian.little,
          );
        }
      }
    }
    final t2 = sw.elapsedMicroseconds;
    final uniformBytes = ByteData.sublistView(_ub, 0, us);
    final uniformHost = _transientUniforms!;
    final gpu.DeviceBuffer ubuf;
    if (us <= uniformHost.blockLengthInBytes) {
      final uniformView = uniformHost.emplace(uniformBytes);
      assert(uniformView.offsetInBytes == 0);
      ubuf = uniformView.buffer;
    } else {
      // HostBuffer does not retain oversize allocations in its four-frame
      // ring. Use a one-shot buffer for this rare frame instead.
      ubuf = gpu.gpuContext.createDeviceBufferWithCopy(uniformBytes);
    }

    void bindBackgroundPattern(gpu.RenderPass p, _E e) {
      final bp = _backgroundPattern;
      final drawable = gpu.BufferView(
        ubuf,
        offsetInBytes: e.uo,
        lengthInBytes: e.ul,
      );
      final props = gpu.BufferView(
        ubuf,
        offsetInBytes: e.po,
        lengthInBytes: e.pl,
      );
      p.bindUniform(bp.vsDrawable, drawable);
      p.bindUniform(bp.vsProps, props);
      p.bindUniform(bp.fsDrawable, drawable);
      p.bindUniform(bp.fsProps, props);
      p.bindTexture(bp.fsImage, e.tex!, sampler: patternAtlasSamplerOptions());
    }

    void drawBackgroundPattern(gpu.RenderPass p, _E e) {
      p.bindPipeline(_backgroundPattern.p);
      p.bindVertexBuffer(
        gpu.BufferView(
          e.vb!.buffer,
          offsetInBytes: 0,
          lengthInBytes: e.vb!.lengthInBytes,
        ),
        e.vCount,
      );
      p.bindIndexBuffer(
        gpu.BufferView(
          e.ib!.buffer,
          offsetInBytes: 0,
          lengthInBytes: e.ib!.lengthInBytes,
        ),
        gpu.IndexType.int16,
        e.iCount,
      );
      bindBackgroundPattern(p, e);
      p.draw();
    }

    // Draw one raster tile (own pipeline + texture bind).
    void drawRaster(gpu.RenderPass p, _E e) {
      final rr = _raster;
      p.bindPipeline(rr.p);
      p.bindVertexBuffer(
        gpu.BufferView(
          e.vb!.buffer,
          offsetInBytes: 0,
          lengthInBytes: e.vb!.lengthInBytes,
        ),
        e.vCount,
      );
      p.bindIndexBuffer(
        gpu.BufferView(
          e.ib!.buffer,
          offsetInBytes: 0,
          lengthInBytes: e.ib!.lengthInBytes,
        ),
        gpu.IndexType.int16,
        e.iCount,
      );
      p.bindUniform(
        rr.vsDrawable,
        gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
      );
      p.bindUniform(
        rr.vsProps,
        gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
      );
      p.bindUniform(
        rr.fsProps,
        gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
      );
      p.bindTexture(
        rr.fsImage!,
        e.tex!,
        sampler: rasterSamplerOptions(e.texFilter),
      );
      p.draw();
    }

    // Draw fill / merged-fill / background (and FE fallback when no target
    // texture) into [p], in layer order.
    int drawFills(gpu.RenderPass p) {
      var n = 0;
      for (final e in es) {
        if (e.stencilMode == StencilModeType.clear ||
            e.shader == ShaderType.clippingMask) {
          continue;
        }
        if (_isLineShader(e.shader) ||
            e.shader == ShaderType.fillOutline ||
            e.shader == ShaderType.fillOutlineTriangulated ||
            e.shader == ShaderType.circle ||
            e.shader == ShaderType.raster ||
            e.shader == ShaderType.backgroundPattern) {
          continue;
        }
        // Fill-extrusion renders in its own depth-tested pass when we have the
        // target texture; without it, fall through here (no depth).
        if (e.shader == ShaderType.fillExtrusion && texture != null) continue;
        final isFE = e.shader == ShaderType.fillExtrusion;
        final gpu.RenderPipeline pl;
        final gpu.UniformSlot vs, fs;
        if (isFE && (e.fl & _flagFillExtrusionDataDriven) != 0) {
          pl = _fillExtrusionDD;
          vs = _feDDVS!;
          fs = _feDDFS!;
        } else if (isFE) {
          pl = _fillExtrusion;
          vs = _feVS!;
          fs = _feFS!;
        } else if ((e.fl & _flagCrossTileMerged) != 0) {
          pl = _fillMerged;
          vs = _fmVS!;
          fs = _fmFS!;
        } else if (e.shader == ShaderType.fill &&
            fillUsesDataDrivenPipeline(e.fl)) {
          pl = _fillDD;
          vs = _fDDVS!;
          fs = _fDDFS!;
        } else {
          pl = _fill;
          vs = _fVS!;
          fs = _fFS!;
        }
        p.bindPipeline(pl);
        p.bindVertexBuffer(
          gpu.BufferView(
            e.vb!.buffer,
            offsetInBytes: 0,
            lengthInBytes: e.vb!.lengthInBytes,
          ),
          e.vCount,
        );
        p.bindIndexBuffer(
          gpu.BufferView(
            e.ib!.buffer,
            offsetInBytes: 0,
            lengthInBytes: e.ib!.lengthInBytes,
          ),
          gpu.IndexType.int16,
          e.iCount,
        );
        p.bindUniform(
          vs,
          gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
        );
        p.bindUniform(
          fs,
          gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
        );
        p.draw();
        n++;
      }
      return n;
    }

    _LinePipe linePipeFor(_E e) => switch (e.shader) {
      ShaderType.line =>
        lineUsesDataDrivenPipeline(e.fl) ? _lineSimpleDD : _lineSimple,
      ShaderType.lineSDF =>
        lineUsesDataDrivenPipeline(e.fl) ? _lineSdfDD : _lineSdf,
      ShaderType.lineGradient =>
        lineUsesDataDrivenPipeline(e.fl) ? _lineGradientDD : _lineGradient,
      ShaderType.linePattern =>
        lineUsesDataDrivenPipeline(e.fl) ? _linePatternDD : _linePattern,
      ShaderType.circle =>
        circleUsesDataDrivenPipeline(e.fl) ? _circleDD : _circle,
      _ => throw StateError('Not a line-family shader: ${e.shader}'),
    };

    gpu.RenderPipeline pipelineFor(_E e) => switch (e.shader) {
      ShaderType.fillOutline => _fillOutline,
      ShaderType.fillOutlineTriangulated =>
        fillOutlineUsesDataDrivenPipeline(e.fl)
            ? _fillOutlineTriangulatedDD
            : _fillOutlineTriangulated,
      ShaderType.line ||
      ShaderType.lineSDF ||
      ShaderType.lineGradient ||
      ShaderType.linePattern ||
      ShaderType.circle => linePipeFor(e).p,
      ShaderType.raster => _raster.p,
      ShaderType.backgroundPattern => _backgroundPattern.p,
      ShaderType.clippingMask => _clippingMask,
      ShaderType.fillExtrusion =>
        (e.fl & _flagFillExtrusionDataDriven) != 0
            ? _fillExtrusionDD
            : _fillExtrusion,
      _ => _fillPipeFor(e).$1,
    };

    gpu.RenderPipeline fillExtrusionDepthPipelineFor(_E e) =>
        (e.fl & _flagFillExtrusionDataDriven) != 0
        ? _fillExtrusionDDDepth
        : _fillExtrusionDepth;

    void bindFillExtrusionDepth(gpu.RenderPass pass, _E e) {
      final dataDriven = (e.fl & _flagFillExtrusionDataDriven) != 0;
      pass.bindUniform(
        dataDriven ? _feDDDepthVS! : _feDepthVS!,
        gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
      );
      pass.bindUniform(
        dataDriven ? _feDDDepthProps! : _feDepthProps!,
        gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
      );
    }

    void bindEntry(gpu.RenderPass pass, _E e) {
      if (e.shader == ShaderType.clippingMask) {
        pass.bindUniform(
          _clipVS!,
          gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
        );
        return;
      }
      if (_isLineShader(e.shader) || e.shader == ShaderType.circle) {
        final lp = linePipeFor(e);
        _bindLine(pass, lp, ubuf, e, mapGlobalOffset);
        return;
      }
      if (e.shader == ShaderType.backgroundPattern) {
        bindBackgroundPattern(pass, e);
        return;
      }
      if (e.shader == ShaderType.raster) {
        final rr = _raster;
        pass.bindUniform(
          rr.vsDrawable,
          gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
        );
        pass.bindUniform(
          rr.vsProps,
          gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
        );
        pass.bindUniform(
          rr.fsProps,
          gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
        );
        pass.bindTexture(
          rr.fsImage!,
          e.tex!,
          sampler: rasterSamplerOptions(e.texFilter),
        );
        return;
      }
      if (e.shader == ShaderType.fillOutline) {
        pass.bindUniform(
          _foVS!,
          gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
        );
        pass.bindUniform(
          _foFS!,
          gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
        );
        return;
      }
      if (e.shader == ShaderType.fillOutlineTriangulated) {
        if (fillOutlineUsesDataDrivenPipeline(e.fl)) {
          pass.bindUniform(
            _fotDDVS!,
            gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
          );
          pass.bindUniform(
            _fotDDProps!,
            gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
          );
          pass.bindUniform(
            _fotDDGlobal!,
            gpu.BufferView(
              ubuf,
              offsetInBytes: mapGlobalOffset,
              lengthInBytes: 16,
            ),
          );
          return;
        }
        pass.bindUniform(
          _fotVS!,
          gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
        );
        pass.bindUniform(
          _fotGlobal!,
          gpu.BufferView(
            ubuf,
            offsetInBytes: mapGlobalOffset,
            lengthInBytes: 16,
          ),
        );
        pass.bindUniform(
          _fotFS!,
          gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
        );
        return;
      }
      if (e.shader == ShaderType.fillExtrusion) {
        final dataDriven = (e.fl & _flagFillExtrusionDataDriven) != 0;
        pass.bindUniform(
          dataDriven ? _feDDVS! : _feVS!,
          gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
        );
        pass.bindUniform(
          dataDriven ? _feDDFS! : _feFS!,
          gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
        );
        return;
      }
      final (_, vs, fs) = _fillPipeFor(e);
      pass.bindUniform(
        vs,
        gpu.BufferView(ubuf, offsetInBytes: e.uo, lengthInBytes: e.ul),
      );
      pass.bindUniform(
        fs,
        gpu.BufferView(ubuf, offsetInBytes: e.po, lengthInBytes: e.pl),
      );
    }

    int dc = 0;
    if (texture != null) {
      // The first pass owns only the clear. Every supported command is then
      // replayed in MapLibre's native emission order. Flutter
      // GPU needs a new pass when the pipeline changes, so split only at an
      // adjacent pipeline boundary; never regroup by shader category.
      final clearingBuffer = cmdBuf;
      cmdBuf = null;
      clearingBuffer?.submit();

      // MapLibre retains one combined depth/stencil attachment across the
      // whole frame. Separate Flutter GPU render passes must load/store both
      // aspects so a depth-only pass cannot invalidate tile masks.
      final mainDepthStencilTexture =
          es.any(
            (e) =>
                e.shader == ShaderType.fillExtrusion ||
                drawCommandUsesDepth(e.fl) ||
                e.stencilMode != StencilModeType.disabled,
          )
          ? _depthStencilTextureFor(texture)
          : null;

      var attachmentInitialized = false;
      var cursor = 0;
      while (cursor < es.length) {
        final first = es[cursor];
        if (first.stencilMode == StencilModeType.clear) {
          if (mainDepthStencilTexture != null) {
            _clearStencilPass(
              texture,
              mainDepthStencilTexture,
              attachmentInitialized: attachmentInitialized,
              clearValue: first.stencilReference,
            );
            attachmentInitialized = true;
          }
          cursor++;
          continue;
        }

        if (first.shader != ShaderType.fillExtrusion) {
          final pipeline = pipelineFor(first);
          final depthTest = drawCommandUsesDepth(first.fl);
          final depthWrite = drawCommandWritesDepth(first.fl);
          final stencilMode = first.stencilMode;
          final needsAttachment =
              depthTest || stencilMode != StencilModeType.disabled;
          var end = cursor + 1;
          while (end < es.length &&
              es[end].stencilMode != StencilModeType.clear &&
              es[end].shader != ShaderType.fillExtrusion &&
              identical(pipelineFor(es[end]), pipeline) &&
              drawCommandUsesDepth(es[end].fl) == depthTest &&
              drawCommandWritesDepth(es[end].fl) == depthWrite &&
              es[end].stencilMode == stencilMode) {
            end++;
          }
          dc += _overlayPass(
            texture,
            pipeline,
            es.sublist(cursor, end),
            bindEntry,
            setPrimitive: first.shader == ShaderType.fillOutline,
            depthStencilTexture: needsAttachment
                ? mainDepthStencilTexture
                : null,
            clearDepth:
                needsAttachment &&
                mainDepthStencilTexture != null &&
                !attachmentInitialized,
            clearStencil:
                needsAttachment &&
                mainDepthStencilTexture != null &&
                !attachmentInitialized,
            depthTest: depthTest,
            depthWrite: depthWrite,
            stencilMode: stencilMode,
          );
          if (needsAttachment && mainDepthStencilTexture != null) {
            attachmentInitialized = true;
          }
          cursor = end;
          continue;
        }

        // Commands from one 3D TileLayerGroup invocation are contiguous in
        // MapLibre's native stream. Recreate its depth prepass before the
        // color pass, while retaining depth from earlier extrusion layers.
        var layerEnd = cursor + 1;
        while (layerEnd < es.length &&
            es[layerEnd].shader == ShaderType.fillExtrusion &&
            es[layerEnd].layer == first.layer) {
          layerEnd++;
        }
        final layerEntries = es.sublist(cursor, layerEnd);

        final opacity = ubd.getFloat32(first.po + 60, Endian.little);
        final needsDepthPrepass = fillExtrusionNeedsDepthPrepass(opacity);
        if (mainDepthStencilTexture != null && needsDepthPrepass) {
          final depthPipelines = <gpu.RenderPipeline>[
            for (final e in layerEntries) fillExtrusionDepthPipelineFor(e),
          ];
          final depthRuns = maximalAdjacentIdentityRuns(
            depthPipelines,
            (pipeline) => pipeline,
          );
          for (final run in depthRuns) {
            dc += _overlayPass(
              texture,
              depthPipelines[run.start],
              layerEntries.sublist(run.start, run.end),
              bindFillExtrusionDepth,
              depthStencilTexture: mainDepthStencilTexture,
              clearDepth: !attachmentInitialized,
              clearStencil: !attachmentInitialized,
              depthTest: true,
              depthWrite: true,
              stencilMode: StencilModeType.disabled,
              cullBackFaces: true,
            );
            attachmentInitialized = true;
          }
        }

        var colorCursor = 0;
        while (colorCursor < layerEntries.length) {
          final colorFirst = layerEntries[colorCursor];
          final colorPipeline = pipelineFor(colorFirst);
          final stencilMode = colorFirst.stencilMode;
          var colorEnd = colorCursor + 1;
          while (colorEnd < layerEntries.length &&
              identical(pipelineFor(layerEntries[colorEnd]), colorPipeline) &&
              layerEntries[colorEnd].stencilMode == stencilMode) {
            colorEnd++;
          }
          dc += _overlayPass(
            texture,
            colorPipeline,
            layerEntries.sublist(colorCursor, colorEnd),
            bindEntry,
            depthStencilTexture: mainDepthStencilTexture,
            clearDepth:
                mainDepthStencilTexture != null && !attachmentInitialized,
            clearStencil:
                mainDepthStencilTexture != null && !attachmentInitialized,
            depthTest: mainDepthStencilTexture != null,
            depthWrite: mainDepthStencilTexture != null && !needsDepthPrepass,
            stencilMode: stencilMode,
            cullBackFaces: true,
          );
          if (mainDepthStencilTexture != null) {
            attachmentInitialized = true;
          }
          colorCursor = colorEnd;
        }
        cursor = layerEnd;
      }
    } else {
      // Compatibility fallback for callers without a target texture. The real
      // painter always supplies one, so retain the prior single-pass behavior.
      _setPremultipliedAlphaBlend(rp);
      dc += drawFills(rp);
      for (final e in es) {
        if (e.shader == ShaderType.backgroundPattern && e.tex != null) {
          drawBackgroundPattern(rp, e);
          dc++;
        } else if (e.shader == ShaderType.raster && e.tex != null) {
          drawRaster(rp, e);
          dc++;
        }
      }
      final fallbackBuffer = cmdBuf;
      cmdBuf = null;
      fallbackBuffer?.submit();
    }
    final t4 = sw.elapsedMicroseconds;
    lastDartUs = t4;
    lastDraws = dc;
    lastVerts = es.fold(0, (s, e) => s + e.vCount);
    lastLines = nLines;
    if (log) {
      int nFill = 0,
          nFE = 0,
          nBg = 0,
          nLine = 0,
          nSdf = 0,
          nGrad = 0,
          nPat = 0,
          nCircle = 0,
          nRaster = 0,
          nMerged = 0,
          totalVerts = 0;
      for (final e in es) {
        if (e.shader == ShaderType.fill) {
          nFill++;
        } else if (e.shader == ShaderType.fillExtrusion) {
          nFE++;
        } else if (e.shader == ShaderType.background ||
            e.shader == ShaderType.backgroundPattern) {
          nBg++;
        } else if (e.shader == ShaderType.line) {
          nLine++;
        } else if (e.shader == ShaderType.lineSDF) {
          nSdf++;
        } else if (e.shader == ShaderType.lineGradient) {
          nGrad++;
        } else if (e.shader == ShaderType.linePattern) {
          nPat++;
        } else if (e.shader == ShaderType.circle) {
          nCircle++;
        } else if (e.shader == ShaderType.raster) {
          nRaster++;
        }
        if ((e.fl & _flagCrossTileMerged) != 0) nMerged++;
        totalVerts += e.vCount;
      }
      debugPrint(
        '[GPU] z=${zoom.toStringAsFixed(2)} n=$n draws=$dc bg=$nBg fill=$nFill line=$nLine sdf=$nSdf grad=$nGrad pat=$nPat circle=$nCircle raster=$nRaster fe=$nFE merged=$nMerged verts=${totalVerts ~/ 1000}K ubo=${t2 - t1}us',
      );
    }
    return dc;
  }

  void dispose() {
    _vc.clear();
    _ic.clear();
    _tc.clear();
    _transientUniforms = null;
    _mainDepthStencilTexture = null;
    _mainDepthStencilWidth = 0;
    _mainDepthStencilHeight = 0;
    _ub = Uint8List(0);
    cmdBuf = null;
  }
}
