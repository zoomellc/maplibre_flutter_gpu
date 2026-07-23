import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/maplibre_map.dart';

void main() {
  group('MapLibreMap viewport sizing', () {
    test('uses finite LayoutBuilder constraints as logical map size', () {
      const constraints = BoxConstraints.tightFor(width: 200, height: 100);

      expect(maplibreLayoutSize(constraints), const Size(200, 100));
    });

    test('rejects unbounded and empty layouts', () {
      expect(maplibreLayoutSize(const BoxConstraints()), isNull);
      expect(
        maplibreLayoutSize(const BoxConstraints.tightFor(width: 0, height: 0)),
        isNull,
      );
    });

    test('matches native logical and physical viewport dimensions', () {
      final dimensions = maplibreViewportDimensions(
        const Size(200.75, 100.25),
        1.5,
      );

      expect(dimensions.logicalWidth, 200);
      expect(dimensions.logicalHeight, 100);
      expect(dimensions.physicalWidth, 300);
      expect(dimensions.physicalHeight, 150);
    });

    test('uses a safe DPR fallback', () {
      final dimensions = maplibreViewportDimensions(const Size(200, 100), 0);

      expect(dimensions.physicalWidth, 200);
      expect(dimensions.physicalHeight, 100);
    });
  });
}
