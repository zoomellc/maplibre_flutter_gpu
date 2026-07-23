// Enum constants shared with fluttergpu::DrawCommand (see draw_command.hpp).
// The struct itself is parsed field-by-field in gpu_renderer.dart via raw
// ByteData offsets — there is no Dart-side struct class.

/// Shader type enum — matches fluttergpu::ShaderType
class ShaderType {
  static const int fill = 0;
  static const int fillOutline = 1;
  static const int line = 2;
  static const int background = 3;
  static const int fillExtrusion = 4;
  static const int lineSDF = 5; // dashed lines (line-dasharray)
  static const int lineGradient = 6; // line-gradient
  static const int linePattern = 7; // line-pattern
  static const int circle = 8; // circle layer (POIs, dots)
  static const int raster = 9; // raster tiles (satellite imagery etc.)
  static const int fillOutlineTriangulated = 10; // 2px antialiased fill edge
  static const int clippingMask = 11; // projected tile quad; stencil only
  static const int backgroundPattern = 12; // repeating background atlas
  static const int unknown = 255;
}

/// Resolved stencil behavior — matches fluttergpu::StencilModeType.
class StencilModeType {
  static const int disabled = 0;
  static const int clippingMask = 1; // Always + Replace, write 0xff
  static const int clippingTest = 2; // Equal, write 0x00
  static const int fillExtrusion = 3; // NotEqual + Replace, write 0xff
  static const int clear = 4; // ordered attachment clear control
}

/// Draw mode enum — matches fluttergpu::DrawModeType
class DrawModeType {
  static const int triangles = 0;
  static const int lines = 1;
  static const int lineStrip = 2;
  static const int points = 3;
}

/// Texture sampler filter — matches fluttergpu::TextureFilterType.
class TextureFilterType {
  static const int nearest = 0;
  static const int linear = 1;
}
