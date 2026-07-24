import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

const String visualE2eSceneId = String.fromEnvironment(
  'VISUAL_E2E_SCENE',
  defaultValue: 'geometry',
);

const String visualE2eReadyPrefix = 'VISUAL_E2E_READY';

typedef VisualMapBuilder =
    Widget Function(VisualScene scene, VoidCallback onMapIdle);

@immutable
class VisualCamera {
  const VisualCamera({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.bearing,
    required this.tilt,
  });

  final double latitude;
  final double longitude;
  final double zoom;
  final double bearing;
  final double tilt;
}

@immutable
class VisualScene {
  const VisualScene({
    required this.id,
    required this.styleJson,
    required this.camera,
    required this.backgroundColor,
  });

  final String id;
  final String styleJson;
  final VisualCamera camera;
  final Color backgroundColor;
}

class VisualTestStatus {
  VisualTestStatus._();

  static final ValueNotifier<bool> ready = ValueNotifier<bool>(false);
  static Timer? _settleTimer;

  static void reset() {
    _settleTimer?.cancel();
    _settleTimer = null;
    ready.value = false;
  }

  static void mapIdle({
    required String implementation,
    required String sceneId,
  }) {
    if (ready.value) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(milliseconds: 750), () {
      _settleTimer = null;
      ready.value = true;
      debugPrint('$visualE2eReadyPrefix|$implementation|$sceneId');
    });
  }
}

Future<VisualScene> loadVisualScene() async {
  if (visualE2eSceneId != 'geometry') {
    throw ArgumentError.value(
      visualE2eSceneId,
      'VISUAL_E2E_SCENE',
      'unknown visual E2E scene',
    );
  }

  final styleJson = await rootBundle.loadString(
    'packages/visual_e2e_shared/assets/scenes/geometry.json',
  );
  return VisualScene(
    id: visualE2eSceneId,
    styleJson: styleJson,
    camera: const VisualCamera(
      latitude: 35.6812,
      longitude: 139.7671,
      zoom: 13.25,
      bearing: 17,
      tilt: 28,
    ),
    backgroundColor: const Color(0xffe7edf3),
  );
}

Future<void> runVisualE2eApp({
  required String implementation,
  required VisualMapBuilder mapBuilder,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0x00000000),
      systemNavigationBarColor: Color(0x00000000),
    ),
  );

  VisualTestStatus.reset();
  final scene = await loadVisualScene();
  runApp(
    _VisualE2eApp(
      implementation: implementation,
      scene: scene,
      mapBuilder: mapBuilder,
    ),
  );
}

class _VisualE2eApp extends StatelessWidget {
  const _VisualE2eApp({
    required this.implementation,
    required this.scene,
    required this.mapBuilder,
  });

  final String implementation;
  final VisualScene scene;
  final VisualMapBuilder mapBuilder;

  @override
  Widget build(BuildContext context) {
    return WidgetsApp(
      color: scene.backgroundColor,
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: _buildPageRoute,
      home: ColoredBox(
        color: scene.backgroundColor,
        child: _VisualViewport(
          implementation: implementation,
          scene: scene,
          mapBuilder: mapBuilder,
        ),
      ),
    );
  }
}

PageRoute<T> _buildPageRoute<T>(RouteSettings settings, WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    settings: settings,
    pageBuilder:
        (
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
        ) => builder(context),
  );
}

class _VisualViewport extends StatelessWidget {
  const _VisualViewport({
    required this.implementation,
    required this.scene,
    required this.mapBuilder,
  });

  static const double _controlOverscan = 64;

  final String implementation;
  final VisualScene scene;
  final VisualMapBuilder mapBuilder;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          Positioned(
            left: -_controlOverscan,
            top: -_controlOverscan,
            right: -_controlOverscan,
            bottom: -_controlOverscan,
            child: mapBuilder(
              scene,
              () => VisualTestStatus.mapIdle(
                implementation: implementation,
                sceneId: scene.id,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
