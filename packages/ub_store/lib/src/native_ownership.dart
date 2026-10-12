import 'dart:ffi';

const _asset = 'package:ub_store/src/native_ownership.dart';

@Native<Int32 Function(Pointer<Char>, Pointer<Char>, Pointer<Char>)>(
  symbol: 'ub_publish_conversion_directory',
  assetId: _asset,
)
external int nativePublishConversionDirectory(
  Pointer<Char> source,
  Pointer<Char> destination,
  Pointer<Char> directory,
);

@Native<Pointer<Void> Function(Pointer<Char>, Pointer<Int32>)>(
  symbol: 'ub_original_open',
  assetId: _asset,
)
external Pointer<Void> nativeOriginalOpen(
  Pointer<Char> path,
  Pointer<Int32> error,
);

@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Int32>)>(
  symbol: 'ub_original_read',
  assetId: _asset,
)
external int nativeOriginalRead(
  Pointer<Void> handle,
  Pointer<Uint8> bytes,
  int capacity,
  Pointer<Int32> length,
);

@Native<Void Function(Pointer<Void>)>(
  symbol: 'ub_original_close',
  assetId: _asset,
)
external void nativeOriginalClose(Pointer<Void> handle);

@Native<Int32 Function(Pointer<Char>, Pointer<Char>, Pointer<Char>)>(
  symbol: 'ub_publish_conversion',
  assetId: _asset,
)
external int nativePublishConversion(
  Pointer<Char> source,
  Pointer<Char> destination,
  Pointer<Char> directory,
);

@Native<Int32 Function(Pointer<Char>, Pointer<Uint8>, Int32, Pointer<Int32>)>(
  symbol: 'ub_read_credential',
  assetId: _asset,
)
external int nativeReadCredential(
  Pointer<Char> path,
  Pointer<Uint8> bytes,
  int capacity,
  Pointer<Int32> length,
);

@Native<Int32 Function(Pointer<Char>)>(
  symbol: 'ub_sync_directory',
  assetId: _asset,
)
external int nativeSyncDirectory(Pointer<Char> path);

@Native<Int32 Function(Pointer<Char>, Pointer<Char>, Pointer<Char>)>(
  symbol: 'ub_publish_snapshot',
  assetId: _asset,
)
external int nativePublishSnapshot(
  Pointer<Char> source,
  Pointer<Char> destination,
  Pointer<Char> directory,
);

@Native<Int32 Function(Pointer<Char>, Pointer<Uint8>, Int32, Pointer<Int32>)>(
  symbol: 'ub_read_image',
  assetId: _asset,
)
external int nativeReadImage(
  Pointer<Char> path,
  Pointer<Uint8> bytes,
  int capacity,
  Pointer<Int32> length,
);

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
