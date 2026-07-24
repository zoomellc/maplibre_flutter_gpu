import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:visual_e2e_shared/visual_e2e_shared.dart';

import 'package:visual_e2e_maplibre_gl/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture maplibre_gl geometry scene', (tester) async {
    await app.main();
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await _waitForMapIdle(tester);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await tester.pump();

    final png = await binding.takeScreenshot('maplibre_gl');
    expect(png, isNotEmpty);
  });
}

Future<void> _waitForMapIdle(WidgetTester tester) async {
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (!VisualTestStatus.ready.value) {
    if (DateTime.now().isAfter(deadline)) {
      fail('maplibre_gl did not become idle within 60 seconds');
    }
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
