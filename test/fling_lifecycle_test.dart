import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fling reuses one AnimationController for the State lifetime', () {
    final source = File('lib/src/maplibre_map.dart').readAsStringSync();

    expect(
      source,
      contains('late final AnimationController _flingController;'),
    );
    expect(RegExp(r'AnimationController\(').allMatches(source), hasLength(1));
    expect(source, contains('..addListener(_onFlingTick)'));
    expect(source, contains('..addStatusListener(_onFlingStatus)'));

    final start = source.indexOf('void _startFling(Offset velocity)');
    final tick = source.indexOf('void _onFlingTick()', start);
    expect(start, greaterThanOrEqualTo(0));
    expect(tick, greaterThan(start));
    final startFling = source.substring(start, tick);
    expect(startFling, isNot(contains('AnimationController(')));
    expect(startFling, isNot(contains('.dispose()')));
    expect(startFling, isNot(contains('addListener')));
    expect(startFling, isNot(contains('addStatusListener')));
    expect(startFling, contains('_previousFlingProgress = 0.0'));
    expect(startFling, contains('_flingController.forward(from: 0.0)'));

    final status = source.indexOf('void _onFlingStatus(', tick);
    expect(status, greaterThan(tick));
    final tickCallback = source.substring(tick, status);
    expect(
      tickCallback,
      contains('!mounted || !_initialized || _bridge == null'),
    );
    final statusEnd = source.indexOf('void _onScaleUpdate(', status);
    expect(statusEnd, greaterThan(status));
    final statusCallback = source.substring(status, statusEnd);
    expect(statusCallback, contains('!mounted'));
    expect(statusCallback, contains('!_initialized'));
    expect(statusCallback, contains('_bridge == null'));
    // Fling end renders once; placement-version synchronization happens inside
    // the common render path.
    expect(statusCallback, isNot(contains('requestLabelExtraction')));
    expect(statusCallback, contains('_ensureRepaintLoop()'));

    final disposeStart = source.indexOf('void dispose() {');
    final disposeEnd = source.indexOf('void _onPointerSignal(', disposeStart);
    expect(disposeStart, greaterThanOrEqualTo(0));
    expect(disposeEnd, greaterThan(disposeStart));
    final dispose = source.substring(disposeStart, disposeEnd);
    expect(dispose, contains('_flingController.dispose()'));
    expect(
      dispose.indexOf('_flingController.dispose()'),
      lessThan(dispose.indexOf('_bridge = null')),
    );
    expect(
      dispose.indexOf('_flingController.dispose()'),
      lessThan(dispose.indexOf('bridge?.destroy()')),
    );
    expect(source, isNot(contains('_flingController?.')));
  });

  test('pan and fling consume native placement snapshots through render', () {
    final source = File('lib/src/maplibre_map.dart').readAsStringSync();

    final scaleEnd = source.indexOf(
      'void _onScaleEnd(ScaleEndDetails details)',
    );
    final startFling = source.indexOf(
      'void _startFling(Offset velocity)',
      scaleEnd,
    );
    expect(scaleEnd, greaterThanOrEqualTo(0));
    expect(startFling, greaterThan(scaleEnd));
    final scaleEndBody = source.substring(scaleEnd, startFling);
    expect(scaleEndBody, isNot(contains('requestLabelExtraction')));
    expect(scaleEndBody, isNot(contains('_syncLabelsFromCpp')));
    expect(scaleEndBody, contains('_renderGesture()'));
    expect(scaleEndBody, contains('startedFling'));
    // Idle/extract only when motion actually ended without a fling.
    expect(scaleEndBody, contains('if (!startedFling)'));
    expect(scaleEndBody, contains('_ensureRepaintLoop()'));

    final tick = source.indexOf('void _onFlingTick()', startFling);
    final status = source.indexOf('void _onFlingStatus(', tick);
    final tickBody = source.substring(tick, status);
    expect(tickBody, contains('_renderGesture()'));
    expect(tickBody, isNot(contains('requestLabelExtraction')));

    final loop = source.indexOf('void _ensureRepaintLoop()');
    final programmatic = source.indexOf(
      'void _onProgrammaticCameraChange()',
      loop,
    );
    expect(loop, greaterThanOrEqualTo(0));
    expect(programmatic, greaterThan(loop));
    final loopBody = source.substring(loop, programmatic);
    expect(
      loopBody.indexOf('_renderGesture()'),
      lessThan(loopBody.indexOf('isMapIdle()')),
    );
    expect(loopBody, contains('isMapIdle()'));
    expect(loopBody, contains('!_flingController.isAnimating'));
    expect(loopBody, isNot(contains('requestLabelExtraction()')));

    final sync = source.indexOf('bool _syncLabelsFromCpp()');
    final fadedOut = source.indexOf('void _onLabelFadedOut(', sync);
    expect(sync, greaterThanOrEqualTo(0));
    expect(fadedOut, greaterThan(sync));
    final syncBody = source.substring(sync, fadedOut);
    expect(syncBody, contains('getLabelsVersion()'));
    expect(syncBody, contains('maplibreLabelSnapshotChanged'));

    final render = source.indexOf('void _renderGesture()');
    final cache = source.indexOf('void _cacheSymbolPositions()', render);
    expect(render, greaterThanOrEqualTo(0));
    expect(cache, greaterThan(render));
    expect(source.substring(render, cache), contains('_syncLabelsFromCpp();'));
  });
}
