import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

import 'native_ownership.dart';

void _pathCheck(String path) {
  if (path.isEmpty ||
      path.contains('\u0000') ||
      path.runes.any((c) => c >= 0xd800 && c <= 0xdfff)) {
    throw const FormatException('Invalid protected path');
  }
  if (Platform.isWindows) {
    throw UnsupportedError('Windows native ownership port is not implemented');
  }
}

void _checkError(int error, String operation, String path) {
  if (error != 0) {
    throw FileSystemException(
      operation,
      path,
      OSError('OS ownership refusal', error),
    );
  }
}

/// Never repairs the permissions of an existing directory implicitly.
String privateDirectory(String path) {
  _pathCheck(path);
  if (FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.notFound) {
    Directory(path).parent.createSync(recursive: true);
  }
  using(
    (arena) => _checkError(
      nativePrivateDirectory(path.toNativeUtf8(allocator: arena).cast()),
      'Private directory ownership/mode required',
      path,
    ),
  );
  return Directory(path).resolveSymbolicLinksSync();
}

/// Validate the opened descriptor, including regular type, owner and link count.
/// New files use 0600; createNew refuses an existing path rather than truncating it.
void protectedFile(String path, {bool create = false, bool createNew = false}) {
  _pathCheck(path);
  using(
    (arena) => _checkError(
      nativeProtectedFile(
        path.toNativeUtf8(allocator: arena).cast(),
        createNew
            ? 2
            : create
            ? 1
            : 0,
      ),
      'Protected file ownership/mode required',
      path,
    ),
  );
}

/// Descriptor-owned flock, compatible with the original POSIX runtime and
/// exclusive across both processes and isolates. No PID file grants ownership.
final class OwnedFileLock implements Finalizable {
  OwnedFileLock._(this._handle) {
    _finalizer.attach(this, _handle, detach: this);
  }
  static final _finalizer = NativeFinalizer(
    Native.addressOf(nativeReleaseLock),
  );
  Pointer<Void> _handle;

  factory OwnedFileLock.acquire(String path) {
    _pathCheck(path);
    privateDirectory(File(path).parent.path);
    return using((arena) {
      final error = arena<Int32>();
      final handle = nativeAcquireLock(
        path.toNativeUtf8(allocator: arena).cast(),
        error,
      );
      _checkError(
        error.value,
        'Writer already owned or protected lock refused',
        path,
      );
      if (handle == nullptr) throw StateError('Native lock returned no handle');
      return OwnedFileLock._(handle);
    });
  }

  void close() {
    if (_handle == nullptr) return;
    _finalizer.detach(this);
    nativeReleaseLock(_handle);
    _handle = nullptr;
  }
}
