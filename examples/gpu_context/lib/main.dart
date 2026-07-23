import 'package:flutter/material.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart';

import 'gpu/triangle_overlay_renderer.dart';

void main() {
  runApp(const GpuContextExampleApp());
}

class GpuContextExampleApp extends StatelessWidget {
  const GpuContextExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MapLibre Flutter GPU Context',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff6040a8)),
        useMaterial3: true,
      ),
      home: const GpuContextPage(),
    );
  }
}

class GpuContextPage extends StatefulWidget {
  const GpuContextPage({super.key});

  @override
  State<GpuContextPage> createState() => _GpuContextPageState();
}

class _GpuContextPageState extends State<GpuContextPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  final TriangleOverlayRenderer _renderer = TriangleOverlayRenderer();

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animation.dispose();
    _renderer.releaseReferences();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Public Flutter GPU Context')),
      body: Stack(
        children: [
          Positioned.fill(
            child: MapLibreMap(
              styleString: MapLibreStyles.openFreeMapLiberty,
              initialCameraPosition: const CameraPosition(
                target: LatLng(35.6812, 139.7671),
                zoom: 12.5,
              ),
              gpuRepaint: _animation,
              gpuRenderCallback: (frame) {
                _renderer.draw(frame, progress: _animation.value);
              },
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: IgnorePointer(
              child: Card(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.9),
                child: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Triangle = one custom Flutter GPU draw call. '
                    'Resources come from frame.gpuContext; commands are '
                    'recorded into frame.renderPass.',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
