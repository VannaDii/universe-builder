import 'dart:ffi';

const _asset = 'package:ub_service/src/native_credentials.dart';

@Native<Int32 Function(Pointer<Char>, Pointer<Uint8>)>(
  symbol: 'ub_key_create',
  assetId: _asset,
)
external int nativeKeyCreate(Pointer<Char> reference, Pointer<Uint8> key);

@Native<Int32 Function(Pointer<Char>, Pointer<Uint8>)>(
  symbol: 'ub_key_read',
  assetId: _asset,
)
external int nativeKeyRead(Pointer<Char> reference, Pointer<Uint8> key);

@Native<Int32 Function(Pointer<Char>)>(symbol: 'ub_key_delete', assetId: _asset)
external int nativeKeyDelete(Pointer<Char> reference);
