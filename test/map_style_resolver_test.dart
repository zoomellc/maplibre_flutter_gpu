import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/map_style_resolver.dart';

void main() {
  test('raw JSON and URLs pass through unchanged', () async {
    const raw = '  {"version":8,"sources":{},"layers":[]}';
    const url = 'https://tiles.example/style.json';

    expect(await resolveMapStyleString(raw), raw);
    expect(await resolveMapStyleString(url), url);
  });

  test('relative paths load from the Flutter asset loader', () async {
    String? loadedPath;
    final result = await resolveMapStyleString(
      'assets/map/style.json',
      assetLoader: (path) async {
        loadedPath = path;
        return '{"version":8}';
      },
    );

    expect(loadedPath, 'assets/map/style.json');
    expect(result, '{"version":8}');
  });

  test('file URIs pass through and absolute paths become file URLs', () async {
    expect(
      await resolveMapStyleString('file:///tmp/map-style.json'),
      'file:///tmp/map-style.json',
    );
    expect(
      await resolveMapStyleString('/tmp/other-style.json'),
      'file:///tmp/other-style.json',
    );
  });

  test('empty styles are rejected', () async {
    await expectLater(resolveMapStyleString('  '), throwsArgumentError);
  });
}
