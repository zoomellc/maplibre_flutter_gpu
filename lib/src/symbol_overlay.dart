// Symbol overlay: reproduces MapLibre symbol rendering (icons + text) with
// Flutter widgets. Placement and collision come from MapLibre (C++ placement
// exports placed symbols only); rendering is fully customizable from Flutter
// via [SymbolWidgetBuilder]s.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'native/maplibre_ffi.dart';
import 'sprite_atlas.dart';

/// A placed symbol resolved to screen coordinates, handed to builders.
class MapSymbol {
  /// Stable identity across frames (`layerID:crossTileID`).
  final String key;

  /// Style-evaluated symbol data from MapLibre (text, colors, sizes...).
  final LabelData data;

  /// Screen position of the text anchor (null when no text was placed).
  final Offset? textPos;

  /// Screen position of the icon anchor (null when no icon was placed).
  final Offset? iconPos;

  /// Resolved sprite icon (null when the sprite is missing or still loading).
  final SpriteIcon? icon;

  /// False while fading out (symbol vanished from the latest placement).
  final bool visible;

  /// True only on first appearance: fade in. Symbols re-entering the screen
  /// during a pan (after being culled) appear at full opacity, like MapLibre.
  final bool fadeIn;

  const MapSymbol({
    required this.key,
    required this.data,
    required this.textPos,
    required this.iconPos,
    required this.icon,
    required this.visible,
    this.fadeIn = true,
  });

  /// Anchor used for culling: text anchor when present, else icon anchor.
  Offset? get anchor => textPos ?? iconPos;
}

/// Builds a widget for [symbol]; return null to fall back to the default
/// MapLibre-look rendering.
typedef SymbolWidgetBuilder =
    Widget? Function(BuildContext context, MapSymbol symbol);

/// Renders all placed symbols as positioned widgets inside a Stack.
///
/// Customization points:
///  * [iconBuilder] — replaces only the icon; default sprite otherwise.
///  * [textBuilder] — replaces only the text; default MapLibre-style text
///    (font size / color / halo from the style) otherwise.
class MapSymbolOverlay extends StatelessWidget {
  final List<MapSymbol> symbols;
  final Size screenSize;
  final SymbolWidgetBuilder? iconBuilder;
  final SymbolWidgetBuilder? textBuilder;
  final void Function(String key) onFadedOut;
  final Duration fadeDuration;

  const MapSymbolOverlay({
    super.key,
    required this.symbols,
    required this.screenSize,
    required this.onFadedOut,
    this.iconBuilder,
    this.textBuilder,
    this.fadeDuration = const Duration(milliseconds: 150),
  });

  @override
  Widget build(BuildContext context) {
    final widgets = <Widget>[];
    for (final s in symbols) {
      final a = s.anchor;
      if (a == null) {
        _completeCulledFade(s);
        continue;
      }
      if (a.dx < -120 ||
          a.dx > screenSize.width + 120 ||
          a.dy < -60 ||
          a.dy > screenSize.height + 60) {
        _completeCulledFade(s);
        continue;
      }
      // Icon and text parts stay independently positioned. Both fade
      // together; onFadedOut removal is idempotent.
      final iconWidget = iconBuilder?.call(context, s) ?? _defaultIcon(s);
      if (iconWidget != null && s.iconPos != null) {
        widgets.add(_positioned(s.iconPos!, s, '${s.key}#icon', iconWidget));
      }
      final textWidget = textBuilder?.call(context, s) ?? _defaultText(s);
      if (textWidget != null && s.textPos != null) {
        widgets.add(_positioned(s.textPos!, s, '${s.key}#text', textWidget));
      }
    }
    return Stack(clipBehavior: Clip.none, children: widgets);
  }

  // Culled symbols never build _SymbolFade, so no AnimatedOpacity completion
  // can remove their reconciliation entries. Complete hidden symbols after the
  // frame; the owner rechecks visibility in case the key was revived.
  void _completeCulledFade(MapSymbol symbol) {
    if (symbol.visible) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onFadedOut(symbol.key);
    });
  }

  /// Positions [child] centered on [pos] (FractionalTranslation avoids
  /// needing the widget's size up front) with fade in/out handling.
  ///
  /// The key MUST be on the Positioned itself: Stack diffs its direct
  /// children, and without keys there the matching is positional — one
  /// culled symbol would shift every following child onto the wrong
  /// element, recreating their fade state (visible as flicker during pans).
  Widget _positioned(Offset pos, MapSymbol s, String widgetKey, Widget child) =>
      Positioned(
        key: ValueKey(widgetKey),
        left: pos.dx,
        top: pos.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: _SymbolFade(
            visible: s.visible,
            fadeIn: s.fadeIn,
            duration: fadeDuration,
            onFadedOut: () => onFadedOut(s.key),
            child: child,
          ),
        ),
      );

  Widget? _defaultIcon(MapSymbol s) {
    final icon = s.icon;
    if (icon == null || s.iconPos == null) return null;
    return SpriteIconWidget(
      icon: icon,
      scale: s.data.iconScale,
      opacity: s.data.iconOpacity,
      tint: s.data.iconColor,
    );
  }

  Widget? _defaultText(MapSymbol s) {
    final d = s.data;
    if (!d.textPlaced || d.text.isEmpty) return null;
    final fontSize = d.fontSize;
    final shadows = d.haloWidth > 0
        ? [Shadow(color: d.haloColor, blurRadius: d.haloWidth * 2)]
        : const <Shadow>[];
    // Constrain to the collision box width (plus a small margin for the
    // difference between measured shaping and Flutter's text layout).
    // Line-placed labels use the diagonal of the (rotated) collision-chain
    // bounding box as the approximate label length.
    final boxW = d.alongLine && d.textW > 0
        ? math.sqrt(d.textW * d.textW + d.textH * d.textH)
        : d.textW;
    final maxWidth = boxW > 0 ? boxW + fontSize : fontSize * 8;
    final text = SizedBox(
      width: maxWidth,
      child: Text(
        d.text,
        style: TextStyle(
          fontSize: fontSize,
          color: d.textColor,
          shadows: shadows,
          height: 1.1,
        ),
        textAlign: TextAlign.center,
        maxLines: d.alongLine ? 1 : 2,
        overflow: TextOverflow.visible,
      ),
    );
    if (!d.alongLine || d.angle == 0) return text;
    // Rotate street names along their line; flip angles beyond ±90° so the
    // text stays upright (same as MapLibre's keep-upright behavior).
    var angle = d.angle;
    if (angle > math.pi / 2) angle -= math.pi;
    if (angle < -math.pi / 2) angle += math.pi;
    return Transform.rotate(angle: angle, child: text);
  }
}

/// Fade-in on appearance, fade-out (then [onFadedOut]) on disappearance —
/// approximates MapLibre's placement crossfade.
class _SymbolFade extends StatefulWidget {
  final bool visible;
  final bool fadeIn;
  final Widget child;
  final Duration duration;
  final VoidCallback onFadedOut;

  const _SymbolFade({
    required this.visible,
    required this.fadeIn,
    required this.child,
    required this.duration,
    required this.onFadedOut,
  });

  @override
  State<_SymbolFade> createState() => _SymbolFadeState();
}

class _SymbolFadeState extends State<_SymbolFade> {
  late double _opacity;

  @override
  void initState() {
    super.initState();
    // Already-established symbols (re-entering after being culled offscreen)
    // appear immediately; only genuinely new placements fade in.
    _opacity = widget.visible && !widget.fadeIn ? 1.0 : 0.0;
    if (widget.fadeIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.visible) setState(() => _opacity = 1.0);
      });
    }
  }

  @override
  void didUpdateWidget(_SymbolFade old) {
    super.didUpdateWidget(old);
    _opacity = widget.visible ? 1.0 : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: _opacity,
        duration: widget.duration,
        onEnd: () {
          if (_opacity == 0.0) widget.onFadedOut();
        },
        child: widget.child,
      ),
    );
  }
}
