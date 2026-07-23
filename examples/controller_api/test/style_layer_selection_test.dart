import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu_controller_api_example/style_layer_selection.dart';

void main() {
  test('prefers the highest label or place layer', () {
    expect(
      chooseToggleLayer(<String>[
        'background',
        'place-label-city',
        'org.maplibre.annotations.points',
      ]),
      'place-label-city',
    );
  });

  test('falls back to the highest layer', () {
    expect(chooseToggleLayer(<String>['background', 'roads']), 'roads');
  });

  test('returns null for a style without layers', () {
    expect(chooseToggleLayer(const <String>[]), isNull);
  });
}
