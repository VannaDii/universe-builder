import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_ownership.dart';
import 'ownership.dart';

/// Check the connected socket's OS credentials before transmitting or decoding
/// a profile handshake. Unsupported platforms and TCP sockets fail closed.
void validateLocalSocketPeer(Socket socket) {
  if (socket.address.type != InternetAddressType.unix) {
    throw const FormatException('Local Unix socket required');
  }
  using((arena) {
    final level = arena<Int32>(),
        option = arena<Int32>(),
        length = arena<Int32>();
    if (nativePeerOptions(level, option, length) != 0 ||
        length.value <= 0 ||
        length.value > 256) {
      throw const FormatException('Local socket peer validation unavailable');
    }
    final bytes = socket.getRawOption(
      RawSocketOption(level.value, option.value, Uint8List(length.value)),
    );
    if (bytes.length != length.value) {
      throw const FormatException('Invalid local peer credentials');
    }
    final raw = arena<Uint8>(bytes.length)
      ..asTypedList(bytes.length).setAll(0, bytes);
    if (nativePeerMatches(raw, bytes.length) != 0) {
      throw const FormatException('Local socket peer identity mismatch');
    }
  });
}

void _path(String path, int action) {
  if (path.isEmpty ||
      path.contains('\u0000') ||
      path.runes.any((r) => r >= 0xd800 && r <= 0xdfff)) {
    throw const FormatException('Invalid local socket path');
  }
  final parent = File(path).absolute.parent;
  if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const FormatException('Existing private endpoint directory required');
  }
  privateDirectory(parent.path);
  using((arena) {
    final error = nativeSocketPath(
      path.toNativeUtf8(allocator: arena).cast(),
      action,
    );
    if (error != 0) {
      throw FileSystemException(
        'Local endpoint ownership refusal',
        path,
        OSError('OS ownership refusal', error),
      );
    }
  });
}

void checkLocalSocketEndpoint(String path) => _path(path, 0);

/// Apply 0600 only to the new owned socket, never to an existing regular file.
void protectLocalSocketEndpoint(String path) => _path(path, 1);

/// The engine must already hold its installation service lock before removing
/// an owned stale endpoint. This operation never follows or removes a link/file.
void removeLocalSocketEndpoint(String path) => _path(path, 2);

/// Cleanup is bound to the endpoint created by this server, never a replacement.
final class OwnedLocalSocketEndpoint {
  OwnedLocalSocketEndpoint._(this.path, this._device, this._inode);
  final String path, _device, _inode;
  static OwnedLocalSocketEndpoint capture(String path) => using((arena) {
    final device = arena<Char>(21), inode = arena<Char>(21);
    final error = nativeOwnedSocket(
      path.toNativeUtf8(allocator: arena).cast(),
      device,
      inode,
      0,
    );
    if (error != 0) {
      throw FileSystemException('Socket identity unavailable', path);
    }
    return OwnedLocalSocketEndpoint._(
      path,
      device.cast<Utf8>().toDartString(),
      inode.cast<Utf8>().toDartString(),
    );
  });
  void remove() => using((arena) {
    final error = nativeOwnedSocket(
      path.toNativeUtf8(allocator: arena).cast(),
      _device.toNativeUtf8(allocator: arena).cast(),
      _inode.toNativeUtf8(allocator: arena).cast(),
      1,
    );
    if (error != 0) {
      throw FileSystemException(
        'Socket identity changed; endpoint retained',
        path,
      );
    }
  });
}

/// Link/unlink publication refuses an occupied destination atomically.
void publishLocalSocketEndpoint(String source, String destination) =>
    using((arena) {
      final error = nativePublishSocket(
        source.toNativeUtf8(allocator: arena).cast(),
        destination.toNativeUtf8(allocator: arena).cast(),
      );
      if (error != 0) {
        throw FileSystemException(
          'Fixture endpoint publication refused',
          destination,
        );
      }
    });
