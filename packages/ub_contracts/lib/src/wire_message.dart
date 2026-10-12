import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'protocol_error.dart';
import 'request.dart';
import 'response.dart';
import 'wire.dart';

/// Declared handshake fields. Compatibility and instance authentication are
/// service responsibilities; decoding a handshake grants neither.
final class Hello {
  const Hello({required this.protocolVersion, required this.fixture});
  final String protocolVersion;
  final bool fixture;
  factory Hello.decode(Uint8List bytes) =>
      Hello.fromWire(decodeWireFrame(bytes));
  factory Hello.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'protocol_version', 'fixture'});
    return Hello(
      protocolVersion: f.string('protocol_version'),
      fixture: f.boolean('fixture'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('protocol_version', CanonicalString(protocolVersion)),
    MapEntry('fixture', CanonicalBool(fixture)),
  ]);
}

final class HelloReply {
  HelloReply({
    required this.protocolVersion,
    required this.fixture,
    required BigInt maxFrameBytes,
    required BigInt maxInFlight,
  }) : maxFrameBytes = checkedU64(maxFrameBytes),
       maxInFlight = checkedU64(maxInFlight);
  final String protocolVersion;
  final bool fixture;
  // The owning protocol uses usize on 64-bit native engines. Retain exact
  // unsigned limits in web clients rather than converting to a JS number.
  final BigInt maxFrameBytes, maxInFlight;
  factory HelloReply.decode(Uint8List bytes) =>
      HelloReply.fromWire(decodeWireFrame(bytes));
  factory HelloReply.fromWire(CanonicalValue value) {
    final f = WireFields(value, {
      'protocol_version',
      'fixture',
      'max_frame_bytes',
      'max_in_flight',
    });
    return HelloReply(
      protocolVersion: f.string('protocol_version'),
      fixture: f.boolean('fixture'),
      maxFrameBytes: f.u64('max_frame_bytes'),
      maxInFlight: f.u64('max_in_flight'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('protocol_version', CanonicalString(protocolVersion)),
    MapEntry('fixture', CanonicalBool(fixture)),
    MapEntry('max_frame_bytes', CanonicalNumber(maxFrameBytes.toString())),
    MapEntry('max_in_flight', CanonicalNumber(maxInFlight.toString())),
  ]);
}

sealed class ClientMessage {
  ClientMessage(BigInt id) : id = checkedU64(id);
  final BigInt id;
  CanonicalObject toWire();
  static ClientMessage decode(Uint8List bytes) =>
      fromWire(decodeWireFrame(bytes));
  static ClientMessage fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'id', 'request'});
    return switch (f.string('kind')) {
      'request' => ClientRequestMessage.fromWire(value),
      'cancel' => ClientCancelMessage.fromWire(value),
      _ => throw const FormatException('Unknown client message'),
    };
  }
}

final class ClientRequestMessage extends ClientMessage {
  ClientRequestMessage({required BigInt id, required this.request}) : super(id);
  final Request request;
  factory ClientRequestMessage.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'id', 'request'});
    if (f.string('kind') != 'request') {
      throw const FormatException('Wrong client message kind');
    }
    return ClientRequestMessage(
      id: f.u64('id'),
      request: Request.fromWire(f.require('request')),
    );
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('request')),
    MapEntry('id', CanonicalNumber(id.toString())),
    MapEntry('request', request.toWire()),
  ]);
}

final class ClientCancelMessage extends ClientMessage {
  ClientCancelMessage({required BigInt id}) : super(id);
  factory ClientCancelMessage.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'kind', 'id'});
    if (f.string('kind') != 'cancel') {
      throw const FormatException('Wrong client message kind');
    }
    return ClientCancelMessage(id: f.u64('id'));
  }
  @override
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('kind', CanonicalString('cancel')),
    MapEntry('id', CanonicalNumber(id.toString())),
  ]);
}

sealed class ResponseResult {
  const ResponseResult();
  CanonicalObject toWire();
  static ResponseResult fromWire(CanonicalValue value) {
    final f = WireFields(value, {'Ok', 'Err'});
    if (f.values.length != 1) {
      throw const FormatException('Expected exactly one response result');
    }
    if (f.values.containsKey('Ok')) {
      return ResponseSuccess(Response.fromWire(f.require('Ok')));
    }
    return ResponseFailure(ProtocolError.fromWire(f.require('Err')));
  }
}

final class ResponseSuccess extends ResponseResult {
  const ResponseSuccess(this.response);
  final Response response;
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('Ok', response.toWire())]);
}

final class ResponseFailure extends ResponseResult {
  const ResponseFailure(this.error);
  final ProtocolError error;
  @override
  CanonicalObject toWire() =>
      CanonicalObject([MapEntry('Err', error.toWire())]);
}

final class ServerMessage {
  ServerMessage({required BigInt id, required this.result})
    : id = checkedU64(id);
  final BigInt id;
  final ResponseResult result;
  factory ServerMessage.decode(Uint8List bytes) =>
      ServerMessage.fromWire(decodeWireFrame(bytes));
  factory ServerMessage.fromWire(CanonicalValue value) {
    final f = WireFields(value, {'id', 'result'});
    return ServerMessage(
      id: f.u64('id'),
      result: ResponseResult.fromWire(f.require('result')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('id', CanonicalNumber(id.toString())),
    MapEntry('result', result.toWire()),
  ]);
}
