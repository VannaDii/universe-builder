/// Fixed encrypted endpoint columns. This value contains no plaintext or key.
final class EncryptedPostgresEndpoint {
  EncryptedPostgresEndpoint({
    required this.keyReference,
    required List<int> ciphertext,
    required List<int> nonce,
    required List<int> tag,
  }) : ciphertext = List<int>.unmodifiable(ciphertext),
       nonce = List<int>.unmodifiable(nonce),
       tag = List<int>.unmodifiable(tag) {
    if (keyReference.isEmpty ||
        keyReference.contains('\u0000') ||
        keyReference.runes.any((r) => r >= 0xd800 && r <= 0xdfff) ||
        nonce.length != 12 ||
        tag.length != 16 ||
        [
          this.ciphertext,
          this.nonce,
          this.tag,
        ].any((bytes) => bytes.any((b) => b < 0 || b > 255))) {
      throw const FormatException('Invalid encrypted endpoint columns.');
    }
  }

  final String keyReference;
  final List<int> ciphertext;
  final List<int> nonce;
  final List<int> tag;

  @override
  String toString() => 'EncryptedPostgresEndpoint([redacted])';
}

/// Installation settings contain no plaintext endpoint or encryption key.
final class SavedLocalSettings {
  const SavedLocalSettings({
    required this.installationId,
    required this.usePostgres,
    required this.endpoint,
  });
  final String installationId;
  final bool usePostgres;
  final EncryptedPostgresEndpoint? endpoint;

  @override
  String toString() =>
      'SavedLocalSettings(usePostgres: $usePostgres, endpoint: [redacted])';
}
