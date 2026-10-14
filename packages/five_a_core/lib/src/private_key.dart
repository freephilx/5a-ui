import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:pointycastle/export.dart';

// dartssh2 handles OpenSSH, PKCS#1 and SEC1. Convert PKCS#8 locally, including
// OpenSSL's PBES2/PBKDF2 + AES-CBC encrypted form, without spawning openssl.
String normalizePrivateKey(String pem, String? passphrase) {
  if (!pem.contains('BEGIN PRIVATE KEY') &&
      !pem.contains('BEGIN ENCRYPTED PRIVATE KEY')) {
    return pem;
  }
  var der = base64Decode(
    pem.split('\n').where((line) => !line.startsWith('-----')).join(),
  );
  if (pem.contains('BEGIN ENCRYPTED PRIVATE KEY')) {
    if (passphrase == null || passphrase.isEmpty) {
      throw const FormatException('Passphrase required');
    }
    final outer = ASN1Parser(der).nextObject() as ASN1Sequence;
    final algorithm = outer.elements[0] as ASN1Sequence;
    if ((algorithm.elements[0] as ASN1ObjectIdentifier).identifier !=
        '1.2.840.113549.1.5.13') {
      throw const FormatException('Unsupported encryption');
    }
    final params = algorithm.elements[1] as ASN1Sequence;
    final kdf = params.elements[0] as ASN1Sequence;
    if ((kdf.elements[0] as ASN1ObjectIdentifier).identifier !=
        '1.2.840.113549.1.5.12') {
      throw const FormatException('Unsupported KDF');
    }
    final kdfParams = (kdf.elements[1] as ASN1Sequence).elements;
    final salt = (kdfParams[0] as ASN1OctetString).octets;
    final iterations = (kdfParams[1] as ASN1Integer).intValue;
    if (iterations < 1 || iterations > 2000000) {
      throw const FormatException('Invalid iteration count');
    }
    String prf = '1.2.840.113549.2.7';
    for (final parameter in kdfParams.skip(2)) {
      if (parameter is ASN1Sequence) {
        prf = (parameter.elements[0] as ASN1ObjectIdentifier).identifier ?? '';
      }
    }
    final digest = switch (prf) {
      '1.2.840.113549.2.7' => SHA1Digest(),
      '1.2.840.113549.2.9' => SHA256Digest(),
      '1.2.840.113549.2.10' => SHA384Digest(),
      '1.2.840.113549.2.11' => SHA512Digest(),
      _ => throw const FormatException('Unsupported PRF'),
    };
    final cipherParams = params.elements[1] as ASN1Sequence;
    final keyLength =
        switch ((cipherParams.elements[0] as ASN1ObjectIdentifier).identifier) {
          '2.16.840.1.101.3.4.1.2' => 16,
          '2.16.840.1.101.3.4.1.22' => 24,
          '2.16.840.1.101.3.4.1.42' => 32,
          _ => throw const FormatException('Unsupported cipher'),
        };
    final derivator = PBKDF2KeyDerivator(HMac(digest, digest.byteLength))
      ..init(Pbkdf2Parameters(salt, iterations, keyLength));
    final key = derivator.process(Uint8List.fromList(utf8.encode(passphrase)));
    final iv = (cipherParams.elements[1] as ASN1OctetString).octets;
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters(
              ParametersWithIV(KeyParameter(key), iv),
              null,
            ),
          );
    der = cipher.process((outer.elements[1] as ASN1OctetString).octets);
  }
  final info = ASN1Parser(der).nextObject() as ASN1Sequence;
  final algorithm = info.elements[1] as ASN1Sequence;
  final oid = (algorithm.elements[0] as ASN1ObjectIdentifier).identifier;
  var key = (info.elements[2] as ASN1OctetString).octets;
  String label;
  if (oid == '1.2.840.113549.1.1.1') {
    label = 'RSA PRIVATE KEY';
  } else if (oid == '1.2.840.10045.2.1') {
    label = 'EC PRIVATE KEY';
    final ec = ASN1Parser(key).nextObject() as ASN1Sequence;
    if (!ec.elements.any((element) => element.tag == 0xa0)) {
      final curve = algorithm.elements[1].encodedBytes;
      ec.add(
        ASN1Object.fromBytes(
          Uint8List.fromList([0xa0, curve.length, ...curve]),
        ),
      );
      key = ec.encodedBytes;
    }
  } else {
    throw const FormatException('Unsupported key');
  }
  final encoded = base64Encode(key);
  final lines = [
    for (var i = 0; i < encoded.length; i += 64)
      encoded.substring(i, i + 64 > encoded.length ? encoded.length : i + 64),
  ];
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}
