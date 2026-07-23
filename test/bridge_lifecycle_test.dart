import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_flutter_gpu/src/native/bridge_lifecycle.dart';

void main() {
  test('successful owner destroys native session and local resources once', () {
    final lifecycle = BridgeSessionLifecycle();
    var nativeInitCalls = 0;
    var nativeDestroyCalls = 0;
    var localReleaseCalls = 0;

    expect(
      lifecycle.initialize(() {
        nativeInitCalls++;
        return maplibreInitSuccess;
      }),
      maplibreInitSuccess,
    );
    expect(lifecycle.ownsNativeSession, isTrue);
    expect(lifecycle.ensureActive, returnsNormally);
    expect(
      () => lifecycle.initialize(() => maplibreInitSuccess),
      throwsStateError,
    );

    void dispose() => lifecycle.dispose(
      destroyNativeSession: () => nativeDestroyCalls++,
      releaseLocalResources: () => localReleaseCalls++,
    );

    dispose();
    dispose();

    expect(nativeInitCalls, 1);
    expect(nativeDestroyCalls, 1);
    expect(localReleaseCalls, 1);
    expect(lifecycle.isDisposed, isTrue);
    expect(lifecycle.ensureActive, throwsStateError);
    expect(
      () => lifecycle.initialize(() => maplibreInitSuccess),
      throwsStateError,
    );
  });

  test('busy or failed non-owner disposal never destroys active session', () {
    var nativeSessionActive = false;
    var nativeDestroyCalls = 0;
    var localReleaseCalls = 0;

    int initializeNative() {
      if (nativeSessionActive) return maplibreInitBusy;
      nativeSessionActive = true;
      return maplibreInitSuccess;
    }

    void destroyNative() {
      nativeDestroyCalls++;
      nativeSessionActive = false;
    }

    final owner = BridgeSessionLifecycle();
    final busy = BridgeSessionLifecycle();
    final failed = BridgeSessionLifecycle();

    expect(owner.initialize(initializeNative), maplibreInitSuccess);
    expect(busy.initialize(initializeNative), maplibreInitBusy);
    expect(failed.initialize(() => maplibreInitFailure), maplibreInitFailure);
    expect(busy.ensureActive, throwsStateError);
    expect(failed.ensureActive, throwsStateError);

    busy.dispose(
      destroyNativeSession: destroyNative,
      releaseLocalResources: () => localReleaseCalls++,
    );
    failed.dispose(
      destroyNativeSession: destroyNative,
      releaseLocalResources: () => localReleaseCalls++,
    );

    expect(nativeSessionActive, isTrue);
    expect(nativeDestroyCalls, 0);
    expect(localReleaseCalls, 2);
    expect(owner.ensureActive, returnsNormally);

    owner.dispose(
      destroyNativeSession: destroyNative,
      releaseLocalResources: () => localReleaseCalls++,
    );
    expect(nativeSessionActive, isFalse);
    expect(nativeDestroyCalls, 1);
    expect(localReleaseCalls, 3);
  });

  test('local resources are released when native destruction throws', () {
    final lifecycle = BridgeSessionLifecycle();
    var localReleaseCalls = 0;
    lifecycle.initialize(() => maplibreInitSuccess);

    expect(
      () => lifecycle.dispose(
        destroyNativeSession: () => throw StateError('native failure'),
        releaseLocalResources: () => localReleaseCalls++,
      ),
      throwsStateError,
    );
    lifecycle.dispose(
      destroyNativeSession: () => fail('must remain idempotent'),
      releaseLocalResources: () => fail('must remain idempotent'),
    );

    expect(localReleaseCalls, 1);
    expect(lifecycle.isDisposed, isTrue);
  });
}
