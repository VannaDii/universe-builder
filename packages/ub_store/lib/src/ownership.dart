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

/// Create a fresh 0700 directory atomically, independent of the process umask.
Directory privateTemporaryDirectory(String parent, String prefix) {
  if (prefix.isEmpty || prefix.contains('/') || prefix.contains('\\')) {
    throw const FormatException('Expected a temporary-directory name prefix');
  }
  final path = '${Directory(parent).absolute.path}/${prefix}XXXXXX';
  _pathCheck(path);
  return using((arena) {
    final buffer = path.toNativeUtf8(allocator: arena);
    _checkError(
      nativePrivateTempDirectory(buffer.cast()),
      'Private temporary directory creation failed',
      path,
    );
    return Directory(buffer.toDartString());
  });
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

/// Exact regular single-link identity for catalog registration and resolution.
({String device, String inode}) fileIdentity(String path) {
  _pathCheck(path);
  return using((arena) {
    final device = arena<Char>(21);
    final inode = arena<Char>(21);
    _checkError(
      nativeFileIdentity(
        path.toNativeUtf8(allocator: arena).cast(),
        device,
        inode,
      ),
      'Regular single-link file identity required',
      path,
    );
    return (
      device: device.cast<Utf8>().toDartString(),
      inode: inode.cast<Utf8>().toDartString(),
    );
  });
}

/// Flush a protected directory after removing an unpublished package.
void syncPrivateDirectory(String path) {
  final directory = privateDirectory(path);
  using(
    (arena) => _checkError(
      nativeSyncDirectory(directory.toNativeUtf8(allocator: arena).cast()),
      'Private directory synchronization failed',
      directory,
    ),
  );
}

/// Flush the private file and its containing directory after database close.
void syncPrivateFileAndDirectory(String path) {
  _pathCheck(path);
  final directory = privateDirectory(File(path).parent.path);
  using(
    (arena) => _checkError(
      nativeSyncPrivate(
        path.toNativeUtf8(allocator: arena).cast(),
        directory.toNativeUtf8(allocator: arena).cast(),
      ),
      'Private file/directory synchronization failed',
      path,
    ),
  );
}

/// Publish one already verified snapshot, without replacing an existing path.
void publishSnapshot(String source, String destination) {
  _pathCheck(source);
  _pathCheck(destination);
  final directory = File(destination).parent.resolveSymbolicLinksSync();
  using(
    (arena) => _checkError(
      nativePublishSnapshot(
        source.toNativeUtf8(allocator: arena).cast(),
        destination.toNativeUtf8(allocator: arena).cast(),
        directory.toNativeUtf8(allocator: arena).cast(),
      ),
      'Snapshot publication refused or durability uncertain',
      destination,
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
