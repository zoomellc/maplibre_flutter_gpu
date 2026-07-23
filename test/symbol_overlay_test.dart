import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/sprite_atlas.dart';

LabelData _label(String text, double fontSize, {int crossTileId = 0}) =>
    LabelData(
      crossTileId: crossTileId,
      lat: 0,
      lon: 0,
      fontSize: fontSize,
      textR: 0,
      textG: 0,
      textB: 0,
      textA: 1,
      haloR: 0,
      haloG: 0,
      haloB: 0,
      haloA: 0,
      haloWidth: 0,
      textPlaced: true,
      text: text,
      layer: 'labels',
    );

class _IdentityProbe extends StatefulWidget {
  final String value;

  const _IdentityProbe(this.value);

  @override
  State<_IdentityProbe> createState() => _IdentityProbeState();
}

class _IdentityProbeState extends State<_IdentityProbe> {
  @override
  Widget build(BuildContext context) => Text(widget.value);
}

void main() {
  test('SDF sprite opacity is applied once through its tint', () {
    final tinted = spritePaintColors(0.5, const Color(0x80FF0000));
    final plain = spritePaintColors(0.5, null);

    expect(tinted.imageColor.a, 1);
    expect(tinted.filterColor?.a, closeTo(0.25, 0.001));
    expect(plain.imageColor.a, closeTo(0.5, 0.001));
    expect(plain.filterColor, isNull);
  });

  test('relative sprite assets resolve against the style URL', () {
    expect(
      spriteAssetUri(
        'https://tiles.example/styles/basic/style.json',
        '../../sprites/basic?key=abc',
        '@2x',
        'json',
      ).toString(),
      'https://tiles.example/sprites/basic@2x.json?key=abc',
    );
    expect(
      spriteAssetUri(
        'https://tiles.example/styles/basic/style.json',
        'https://cdn.example/sprite',
        '',
        'png',
      ).toString(),
      'https://cdn.example/sprite.png',
    );
  });

  testWidgets('symbol text keeps the MapLibre evaluated font size', (
    tester,
  ) async {
    final symbols = [
      MapSymbol(
        key: 'small',
        data: _label('small', 4),
        textPos: const Offset(50, 50),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
      MapSymbol(
        key: 'large',
        data: _label('large', 64),
        textPos: const Offset(150, 150),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: symbols,
          screenSize: const Size(200, 200),
          onFadedOut: (_) {},
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('small')).style?.fontSize, 4);
    expect(tester.widget<Text>(find.text('large')).style?.fontSize, 64);
  });

  testWidgets('stable symbol key preserves widget state while data moves', (
    tester,
  ) async {
    Future<void> pump(MapSymbol symbol) => tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [symbol],
          screenSize: const Size(200, 200),
          fadeDuration: Duration.zero,
          onFadedOut: (_) {},
          textBuilder: (_, symbol) => _IdentityProbe(symbol.data.text),
        ),
      ),
    );

    await pump(
      MapSymbol(
        key: 'roads:42',
        data: _label('old', 12, crossTileId: 42),
        textPos: const Offset(20, 30),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    );
    final originalState = tester.state<_IdentityProbeState>(
      find.byType(_IdentityProbe),
    );

    await pump(
      MapSymbol(
        key: 'roads:42',
        data: _label('new', 12, crossTileId: 42),
        textPos: const Offset(120, 130),
        iconPos: null,
        icon: null,
        visible: true,
        fadeIn: false,
      ),
    );

    expect(
      identical(
        tester.state<_IdentityProbeState>(find.byType(_IdentityProbe)),
        originalState,
      ),
      isTrue,
    );
    expect(find.text('new'), findsOneWidget);
    final positioned = tester.widget<Positioned>(
      find.ancestor(
        of: find.byType(_IdentityProbe),
        matching: find.byType(Positioned),
      ),
    );
    expect(positioned.left, 120);
    expect(positioned.top, 130);
  });

  testWidgets('culled hidden symbols complete removal without a fade widget', (
    tester,
  ) async {
    final fadedKeys = <String>[];
    final hidden = MapSymbol(
      key: 'labels:gone',
      data: _label('gone', 12, crossTileId: 7),
      textPos: const Offset(-1000, -1000),
      iconPos: null,
      icon: null,
      visible: false,
      fadeIn: false,
    );
    final visible = MapSymbol(
      key: 'labels:visible',
      data: _label('visible', 12, crossTileId: 8),
      textPos: const Offset(-1000, -1000),
      iconPos: null,
      icon: null,
      visible: true,
      fadeIn: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MapSymbolOverlay(
          symbols: [hidden, visible],
          screenSize: const Size(200, 200),
          onFadedOut: fadedKeys.add,
        ),
      ),
    );
    await tester.pump();

    expect(fadedKeys, contains('labels:gone'));
    expect(fadedKeys, isNot(contains('labels:visible')));
    expect(find.text('gone'), findsNothing);
  });
}
