import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';
import 'package:maplibre_flutter_gpu/src/maplibre_map_controls.dart';

void main() {
  test('control enum order matches maplibre_gl', () {
    expect(CompassViewPosition.values.map((value) => value.name), [
      'topLeft',
      'topRight',
      'bottomLeft',
      'bottomRight',
    ]);
    expect(AttributionButtonPosition.values.length, 4);
    expect(LogoViewPosition.values.length, 4);
    expect(ScaleControlPosition.values.length, 4);
    expect(ScaleControlUnit.values.map((value) => value.name), [
      'metric',
      'imperial',
      'nautical',
    ]);
  });

  test('distance and scale helpers produce geographic scale values', () {
    expect(
      maplibreDistanceMeters(const LatLng(0, 0), const LatLng(0, 1)),
      closeTo(111195, 2),
    );

    final metric = maplibreScaleBarValue(1250, ScaleControlUnit.metric);
    expect(metric.label, '1 km');
    expect(metric.width, closeTo(64, 0.001));

    final imperial = maplibreScaleBarValue(1000, ScaleControlUnit.imperial);
    expect(imperial.label, '2000 ft');
    expect(imperial.width, closeTo(48.768, 0.01));

    final nautical = maplibreScaleBarValue(18520, ScaleControlUnit.nautical);
    expect(nautical.label, '10 nm');
    expect(nautical.width, 80);
  });

  testWidgets('logo and attribution controls honor configured corners', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: MapLibreMapControls(
            mapSize: Size(300, 200),
            controller: null,
            compassEnabled: false,
            logoEnabled: true,
            logoViewPosition: LogoViewPosition.topLeft,
            logoViewMargins: Point(12, 14),
            compassViewPosition: null,
            compassViewMargins: null,
            attributionButtonEnabled: true,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            attributionButtonMargins: Point(9, 11),
            scaleControlEnabled: false,
            scaleControlPosition: ScaleControlPosition.bottomLeft,
            scaleControlUnit: ScaleControlUnit.metric,
          ),
        ),
      ),
    );

    final logoPosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.text('MapLibre'),
        matching: find.byType(Positioned),
      ),
    );
    expect(logoPosition.left, 12);
    expect(logoPosition.top, 14);

    final attributionPosition = tester.widget<Positioned>(
      find.ancestor(
        of: find.byTooltip('Map attribution'),
        matching: find.byType(Positioned),
      ),
    );
    expect(attributionPosition.right, 9);
    expect(attributionPosition.bottom, 11);
    expect(tester.getSize(find.byType(IconButton)), const Size.square(24));

    await tester.tap(find.byTooltip('Map attribution'));
    await tester.pumpAndSettle();
    expect(find.text('Map attribution'), findsWidgets);
  });

  testWidgets('attribution control can be disabled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 300,
          height: 200,
          child: MapLibreMapControls(
            mapSize: Size(300, 200),
            controller: null,
            compassEnabled: false,
            logoEnabled: false,
            logoViewPosition: null,
            logoViewMargins: null,
            compassViewPosition: null,
            compassViewMargins: null,
            attributionButtonEnabled: false,
            attributionButtonPosition: AttributionButtonPosition.bottomRight,
            attributionButtonMargins: null,
            scaleControlEnabled: false,
            scaleControlPosition: ScaleControlPosition.bottomLeft,
            scaleControlUnit: ScaleControlUnit.metric,
          ),
        ),
      ),
    );

    expect(find.byTooltip('Map attribution'), findsNothing);
  });
}
