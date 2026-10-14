import 'dart:io';

/// Disposable CA and server certificate used by TLS functional tests.
Future<({String certificate, String privateKey, String ca})> generateTlsFixture(
  Directory directory,
) async {
  final cert = '${directory.path}/certificate.pem';
  final key = '${directory.path}/key.pem';
  final ca = '${directory.path}/ca.pem';
  final caKey = '${directory.path}/ca-key.pem';
  final csr = '${directory.path}/request.pem';
  final extensions = '${directory.path}/extensions.cnf';
  File(extensions).writeAsStringSync(
    'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost\n',
  );
  for (final arguments in [
    [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=Disposable UB test CA',
      '-addext',
      'basicConstraints=critical,CA:TRUE',
      '-addext',
      'keyUsage=critical,keyCertSign,cRLSign',
      '-keyout',
      caKey,
      '-out',
      ca,
    ],
    [
      'req',
      '-new',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-subj',
      '/CN=localhost',
      '-keyout',
      key,
      '-out',
      csr,
    ],
    [
      'x509',
      '-req',
      '-in',
      csr,
      '-CA',
      ca,
      '-CAkey',
      caKey,
      '-CAcreateserial',
      '-days',
      '1',
      '-extfile',
      extensions,
      '-out',
      cert,
    ],
  ]) {
    final generated = await Process.run('openssl', arguments);
    if (generated.exitCode != 0) {
      throw StateError('Could not generate disposable TLS certificates');
    }
  }
  return (certificate: cert, privateKey: key, ca: ca);
}
