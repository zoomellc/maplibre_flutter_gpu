// Sprite atlas loader: fetches the style's sprite sheet (JSON + PNG) over
// HTTP and provides per-icon crop regions for widget rendering.
//
// The atlas is resolved from the style URL itself (the style JSON's "sprite"
// field), so any MapLibre style works without native-side changes. Apps can
// substitute their own icons via MapLibreMap.symbolIconBuilder.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

@visibleForTesting
({Color imageColor, Color? filterColor}) spritePaintColors(
  double opacity,
  Color? tint,
) {
  final clampedOpacity = opacity.clamp(0.0, 1.0);
  if (tint != null) {
    return (
      imageColor: const Color(0xFFFFFFFF),
      filterColor: tint.withValues(alpha: tint.a * clampedOpacity),
    );
  }
  return (
    imageColor: Color.fromRGBO(255, 255, 255, clampedOpacity),
    filterColor: null,
  );
}

@visibleForTesting
Uri spriteAssetUri(
  String styleUrl,
  String spriteBase,
  String suffix,
  String extension,
) {
  final spriteUri = Uri.parse(spriteBase);
  final base = spriteUri.hasScheme || styleUrl.trimLeft().startsWith('{')
      ? spriteUri
      : Uri.parse(styleUrl).resolveUri(spriteUri);
  return base.replace(path: '${base.path}$suffix.$extension');
}

/// One icon in the sprite sheet.
class SpriteIcon {
  final ui.Image atlas;
  final double x, y, width, height; // crop region in atlas pixels
  final double pixelRatio; // atlas pixel ratio (usually 2)
  final bool sdf; // SDF icons are tinted with icon-color

  const SpriteIcon({
    required this.atlas,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.pixelRatio,
    required this.sdf,
  });

  /// Display size in logical pixels at icon-size 1.0.
  Size get displaySize => Size(width / pixelRatio, height / pixelRatio);
}

/// Sprite sheet for a style: name → crop region.
class SpriteAtlas {
  final Map<String, SpriteIcon> _icons;
  final ui.Image _image;
  bool _disposed = false;

  SpriteAtlas._(this._icons, this._image);

  SpriteIcon? operator [](String name) => _icons[name];
  int get length => _icons.length;

  /// Loads the sprite atlas referenced by [styleSource]. Prefers the @2x
  /// variant; falls back to 1x. [styleSource] may be a URL or raw JSON.
  static Future<SpriteAtlas?> load(
    String styleSource, {
    String? baseStyleUrl,
  }) async {
    try {
      final isRawJson = styleSource.trimLeft().startsWith('{');
      final styleJson =
          json.decode(
                isRawJson
                    ? styleSource
                    : await _fetchString(Uri.parse(styleSource)),
              )
              as Map<String, dynamic>;
      final resolutionBase = baseStyleUrl ?? styleSource;
      final sprite = styleJson['sprite'];
      // "sprite" is either a URL string or a list of {id, url} (style spec v8+)
      String? spriteBase;
      if (sprite is String) {
        spriteBase = sprite;
      } else if (sprite is List && sprite.isNotEmpty) {
        final first = sprite.first;
        if (first is Map && first['url'] is String) {
          spriteBase = first['url'] as String;
        }
      }
      if (spriteBase == null) return null;

      for (final suffix in ['@2x', '']) {
        try {
          final manifestUri = spriteAssetUri(
            resolutionBase,
            spriteBase,
            suffix,
            'json',
          );
          final pngUri = spriteAssetUri(
            resolutionBase,
            spriteBase,
            suffix,
            'png',
          );
          final manifest =
              json.decode(await _fetchString(manifestUri))
                  as Map<String, dynamic>;
          final pngBytes = await _fetchBytes(pngUri);
          final codec = await ui.instantiateImageCodec(pngBytes);
          late final ui.Image atlas;
          try {
            atlas = (await codec.getNextFrame()).image;
          } finally {
            codec.dispose();
          }

          try {
            final icons = <String, SpriteIcon>{};
            manifest.forEach((name, dynamic entry) {
              if (entry is! Map) return;
              final e = entry.cast<String, dynamic>();
              icons[name] = SpriteIcon(
                atlas: atlas,
                x: (e['x'] as num?)?.toDouble() ?? 0,
                y: (e['y'] as num?)?.toDouble() ?? 0,
                width: (e['width'] as num?)?.toDouble() ?? 0,
                height: (e['height'] as num?)?.toDouble() ?? 0,
                pixelRatio: (e['pixelRatio'] as num?)?.toDouble() ?? 1,
                sdf: e['sdf'] == true,
              );
            });
            debugPrint(
              '[SpriteAtlas] loaded ${icons.length} icons '
              '(${suffix.isEmpty ? '1x' : suffix})',
            );
            return SpriteAtlas._(icons, atlas);
          } catch (_) {
            atlas.dispose();
            rethrow;
          }
        } catch (_) {
          // try next variant
        }
      }
      return null;
    } catch (e) {
      debugPrint('[SpriteAtlas] failed to load sprite for $styleSource: $e');
      return null;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _icons.clear();
    _image.dispose();
  }

  static Future<String> _fetchString(Uri uri) async =>
      utf8.decode(await _fetchBytes(uri));

  static Future<Uint8List> _fetchBytes(Uri uri) async {
    if (uri.scheme == 'file') return File.fromUri(uri).readAsBytes();
    if (uri.scheme.isEmpty) {
      if (File(uri.path).isAbsolute) return File(uri.path).readAsBytes();
      final data = await rootBundle.load(uri.path);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $uri');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    } finally {
      client.close();
    }
  }
}

/// Draws a cropped sprite icon, optionally tinted (SDF icons).
class SpriteIconWidget extends StatelessWidget {
  final SpriteIcon icon;
  final double scale; // evaluated icon-size
  final double opacity;
  final Color? tint; // used only for SDF icons

  const SpriteIconWidget({
    super.key,
    required this.icon,
    this.scale = 1.0,
    this.opacity = 1.0,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final size = icon.displaySize * scale;
    return CustomPaint(
      size: size,
      painter: _SpritePainter(icon, opacity, icon.sdf ? tint : null),
    );
  }
}

class _SpritePainter extends CustomPainter {
  final SpriteIcon icon;
  final double opacity;
  final Color? tint;

  _SpritePainter(this.icon, this.opacity, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    final colors = spritePaintColors(opacity, tint);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = colors.imageColor;
    if (colors.filterColor != null) {
      paint.colorFilter = ColorFilter.mode(
        colors.filterColor!,
        BlendMode.srcIn,
      );
    }
    canvas.drawImageRect(
      icon.atlas,
      Rect.fromLTWH(icon.x, icon.y, icon.width, icon.height),
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SpritePainter old) =>
      old.icon != icon || old.opacity != opacity || old.tint != tint;
}
