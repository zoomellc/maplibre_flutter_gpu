const int maplibreInitSuccess = 0;
const int maplibreInitFailure = -1;
const int maplibreInitBusy = -2;

/// Tracks ownership of the process-wide native MapLibre session.
///
/// This is separate from the FFI bindings so its failure and disposal behavior
/// can be unit-tested without loading a platform library.
class BridgeSessionLifecycle {
  bool _ownsNativeSession = false;
  bool _disposed = false;

  bool get ownsNativeSession => _ownsNativeSession;
  bool get isDisposed => _disposed;

  int initialize(int Function() initializeNativeSession) {
    if (_disposed) {
      throw StateError('MaplibreBridge initialized after dispose');
    }
    if (_ownsNativeSession) {
      throw StateError('MaplibreBridge is already initialized');
    }

    final result = initializeNativeSession();
    if (result == maplibreInitSuccess) {
      _ownsNativeSession = true;
    }
    return result;
  }

  void ensureActive() {
    if (_disposed) {
      throw StateError('MaplibreBridge used after dispose');
    }
    if (!_ownsNativeSession) {
      throw StateError('MaplibreBridge does not own the native map session');
    }
  }

  void dispose({
    required void Function() destroyNativeSession,
    required void Function() releaseLocalResources,
  }) {
    if (_disposed) return;
    _disposed = true;

    final shouldDestroyNativeSession = _ownsNativeSession;
    _ownsNativeSession = false;
    try {
      if (shouldDestroyNativeSession) {
        destroyNativeSession();
      }
    } finally {
      releaseLocalResources();
    }
  }
}
