import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:ffi/ffi.dart';

import 'endpoint_encryption.dart';
import 'native_credentials.dart';

enum InstallationKeyFailure {
  unavailable,
  invalidReference,
  unsupportedPlatform,
}

final class InstallationKeyException implements Exception {
  const InstallationKeyException(this.failure);
  final InstallationKeyFailure failure;
  @override
  String toString() => 'InstallationKeyException(${failure.name})';
}

/// OS-stored random installation keys. Missing keys never regenerate on read.
/// Native calls run away from the Flutter/UI isolate and do not prompt.
final class NativeInstallationKeyStore {
  const NativeInstallationKeyStore();

  static final _referencePattern = RegExp(
    r'^ub-installation-key-v1-[0-9a-f]{32}$',
  );
  static void _check(String reference) {
    if (reference.length != 'ub-installation-key-v1-'.length + 32 ||
        !_referencePattern.hasMatch(reference)) {
      throw const InstallationKeyException(
        InstallationKeyFailure.invalidReference,
      );
    }
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw const InstallationKeyException(
        InstallationKeyFailure.unsupportedPlatform,
      );
    }
  }

  Future<String> storeNew(InstallationEncryptionKey key) async {
    if (!Platform.isMacOS && !Platform.isLinux) {
      throw const InstallationKeyException(
        InstallationKeyFailure.unsupportedPlatform,
      );
    }
    final random = Random.secure();
    final reference =
        'ub-installation-key-v1-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final bytes = await key.exportForCredentialStore();
    try {
      await Isolate.run(() {
        using((arena) {
          final buffer = arena<Uint8>(32);
          buffer.asTypedList(32).setAll(0, bytes);
          try {
            final status = nativeKeyCreate(
              reference.toNativeUtf8(allocator: arena).cast(),
              buffer,
            );
            if (status != 0) {
              throw const InstallationKeyException(
                InstallationKeyFailure.unavailable,
              );
            }
          } finally {
            buffer.asTypedList(32).fillRange(0, 32, 0);
          }
        });
      });
      return reference;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<InstallationEncryptionKey?> read(String reference) async {
    _check(reference);
    final bytes = await Isolate.run(
      () => using((arena) {
        final buffer = arena<Uint8>(32);
        try {
          final status = nativeKeyRead(
            reference.toNativeUtf8(allocator: arena).cast(),
            buffer,
          );
          if (status == -25300)
            return null; // Native adapter's not-found result.
          if (status != 0) {
            throw const InstallationKeyException(
              InstallationKeyFailure.unavailable,
            );
          }
          return List<int>.of(buffer.asTypedList(32));
        } finally {
          buffer.asTypedList(32).fillRange(0, 32, 0);
        }
      }),
    );
    if (bytes == null) return null;
    try {
      return InstallationEncryptionKey.fromBytes(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Explicit key deletion for setup cleanup. Does not remove saved settings.
  Future<bool> remove(String reference) async {
    _check(reference);
    return Isolate.run(
      () => using((arena) {
        final status = nativeKeyDelete(
          reference.toNativeUtf8(allocator: arena).cast(),
        );
        if (status == -25300) return false;
        if (status != 0) {
          throw const InstallationKeyException(
            InstallationKeyFailure.unavailable,
          );
        }
        return true;
      }),
    );
  }
}
