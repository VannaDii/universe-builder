import 'dart:ffi';

const _asset = 'package:ub_store/src/native_ownership.dart';

@Native<Int32 Function(Pointer<Char>)>(
  symbol: 'ub_private_dir',
  assetId: _asset,
)
external int nativePrivateDirectory(Pointer<Char> path);

@Native<Int32 Function(Pointer<Char>, Int32)>(
  symbol: 'ub_protected_file',
  assetId: _asset,
)
external int nativeProtectedFile(Pointer<Char> path, int create);

@Native<Pointer<Void> Function(Pointer<Char>, Pointer<Int32>)>(
  symbol: 'ub_lock_acquire',
  assetId: _asset,
)
external Pointer<Void> nativeAcquireLock(
  Pointer<Char> path,
  Pointer<Int32> error,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ub_lock_release',
  assetId: _asset,
)
external void nativeReleaseLock(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Char>, Pointer<Char>)>(
  symbol: 'ub_sync_private',
  assetId: _asset,
)
external int nativeSyncPrivate(Pointer<Char> path, Pointer<Char> directory);

@Native<Int32 Function(Pointer<Char>, Pointer<Char>, Pointer<Char>)>(
  symbol: 'ub_file_identity',
  assetId: _asset,
)
external int nativeFileIdentity(
  Pointer<Char> path,
  Pointer<Char> device,
  Pointer<Char> inode,
);
