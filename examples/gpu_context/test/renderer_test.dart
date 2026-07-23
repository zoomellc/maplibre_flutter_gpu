import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu_context_example/gpu/triangle_overlay_renderer.dart';

void main() {
  test('overlay shader manifest contains the vertex and fragment pair', () {
    final manifest =
        jsonDecode(
              File(
                'shaders/OverlayShaders.shaderbundle.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(
      manifest.keys,
      containsAll(<String>['OverlayVertex', 'OverlayFragment']),
    );
  });

  test('renderer can release empty resource references', () {
    TriangleOverlayRenderer().releaseReferences();
  });
}
