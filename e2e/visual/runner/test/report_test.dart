import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:test/test.dart';
import 'package:visual_e2e_runner/visual_e2e_runner.dart';

void main() {
  test('report contains both screenshots, diff, and similarity', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'visual-e2e-report-test.',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final images = Directory(
      '${temporary.path}${Platform.pathSeparator}images',
    );
    await images.create();
    final png = Uint8List.fromList(
      image.encodePng(image.Image(width: 2, height: 2)),
    );
    await File(
      '${images.path}${Platform.pathSeparator}maplibre_gl.png',
    ).writeAsBytes(png);
    await File(
      '${images.path}${Platform.pathSeparator}gpu.png',
    ).writeAsBytes(png);
    final comparison = comparePngBytes(referencePng: png, actualPng: png);

    await writeVisualReport(
      outputDirectory: temporary,
      comparison: comparison,
      minimumSimilarity: 0.998,
      sceneId: 'geometry',
      metadata: const <String, Object?>{
        'androidApi': '35',
        'maplibreGlVersion': '0.26.2',
      },
    );

    final html = await File(
      '${temporary.path}${Platform.pathSeparator}index.html',
    ).readAsString();
    expect(html, contains('maplibre_gl.png'));
    expect(html, contains('gpu.png'));
    expect(html, contains('diff.png'));
    expect(html, contains('100.000%'));
    expect(html, contains('Strict similarity · AA counted'));
    expect(html, contains('YIQ threshold 0.0500'));
    expect(html, contains('maplibre_gl 0.26.2 · reference'));
    expect(html, contains('overflow-wrap: anywhere'));
    expect(html, isNot(contains('swatch mask')));
    expect(
      File(
        '${temporary.path}${Platform.pathSeparator}results.json',
      ).existsSync(),
      isTrue,
    );
  });

  test('failed report escapes metadata and records the strict score', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'visual-e2e-failed-report-test.',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final reference = image.Image(width: 2, height: 2);
    final actual = image.Image(width: 2, height: 2);
    for (final pixel in reference) {
      pixel.setRgba(0, 0, 0, 255);
    }
    for (final pixel in actual) {
      pixel.setRgba(255, 255, 255, 255);
    }
    final referencePng = Uint8List.fromList(image.encodePng(reference));
    final actualPng = Uint8List.fromList(image.encodePng(actual));
    final images = Directory(
      '${temporary.path}${Platform.pathSeparator}images',
    );
    await images.create();
    await File(
      '${images.path}${Platform.pathSeparator}maplibre_gl.png',
    ).writeAsBytes(referencePng);
    await File(
      '${images.path}${Platform.pathSeparator}gpu.png',
    ).writeAsBytes(actualPng);
    final comparison = comparePngBytes(
      referencePng: referencePng,
      actualPng: actualPng,
      options: const PixelMatchOptions(includeAntiAlias: true),
    );

    await writeVisualReport(
      outputDirectory: temporary,
      comparison: comparison,
      minimumSimilarity: 0.998,
      sceneId: 'geometry',
      metadata: const <String, Object?>{
        'maplibreGlVersion': '<unsafe & version>',
      },
    );

    final html = await File(
      '${temporary.path}${Platform.pathSeparator}index.html',
    ).readAsString();
    final result =
        jsonDecode(
              await File(
                '${temporary.path}${Platform.pathSeparator}results.json',
              ).readAsString(),
            )
            as Map<String, Object?>;
    final comparisonJson = result['comparison'] as Map<String, Object?>;

    expect(html, contains('FAIL'));
    expect(html, contains('&lt;unsafe &amp; version&gt;'));
    expect(html, isNot(contains('<unsafe & version>')));
    expect(html, contains('Strict similarity · AA counted · Required'));
    expect(html, contains('<dt>AA handling</dt><dd>No exclusion</dd>'));
    expect(html, isNot(contains('aria-label="GPU overlay amount"')));
    expect(html, contains('.swatch.antialias { background: #2563eb; }'));
    expect(result['status'], 'failed');
    expect(comparisonJson['strictSimilarity'], 0);
    expect(comparisonJson['antiAliasAdjustedSimilarity'], 0);
  });
}
