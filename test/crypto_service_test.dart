import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pfa_mobile/core/crypto/crypto_keys.dart';
import 'package:pfa_mobile/core/crypto/crypto_service.dart';
import 'package:pfa_mobile/core/crypto/key_store.dart';

/// KeyStore en mémoire pour les tests (pas de plugin natif sous la VM Dart).
class _InMemoryKeyStore implements KeyStore {
  StoredKeys? _keys;

  @override
  Future<void> saveKeys(StoredKeys keys) async => _keys = keys;

  @override
  Future<StoredKeys?> loadKeys() async => _keys;

  @override
  Future<void> deleteKeys() async => _keys = null;

  @override
  Future<bool> hasKeys() async => _keys != null;
}

Future<CryptoService> _serviceWith(StoredKeys keys) async {
  final store = _InMemoryKeyStore();
  await store.saveKeys(keys);
  return CryptoService(store);
}

void main() {
  test('génère des clés Ed25519/X25519 de 32 octets et un bundle valide', () async {
    final svc = CryptoService(_InMemoryKeyStore());
    final keys = await svc.generateKeys();

    expect(keys.edPublic.length, 32);
    expect(keys.xPublic.length, 32);
    expect(keys.edPrivateSeed.length, 32);
    expect(keys.xPrivateSeed.length, 32);

    final encoded = keys.bundle.encode();
    expect(encoded.startsWith('pfa:v1:'), isTrue);
    expect(PublicKeyBundle.isE2ECapable(encoded), isTrue);
    expect(PublicKeyBundle.isE2ECapable('ed25519:deadbeef'), isFalse);
  });

  test('Alice -> Bob : chiffrement E2E, hash cohérent, déchiffrement OK', () async {
    final gen = CryptoService(_InMemoryKeyStore());
    final aliceKeys = await gen.generateKeys();
    final bobKeys = await gen.generateKeys();

    final alice = await _serviceWith(aliceKeys);
    final bob = await _serviceWith(bobKeys);

    const clear = 'Rendez-vous à la passerelle EPO à 14h.';
    final payload = await alice.encryptFor(clear, bobKeys.bundle.encode());

    // Le contentHash doit être le SHA-256 des octets base64-décodés (règle passerelle).
    final envelope = base64.decode(payload.ciphertextBase64);
    expect(payload.contentHash, alice.sha256Hex(envelope));

    // Bob déchiffre avec la clé publique d'Alice.
    final decrypted = await bob.decryptFrom(
      payload.ciphertextBase64,
      aliceKeys.bundle.encode(),
    );
    expect(decrypted, clear);
  });

  test('déchiffrement à l\'aveugle identifie le bon expéditeur', () async {
    final gen = CryptoService(_InMemoryKeyStore());
    final aliceKeys = await gen.generateKeys();
    final bobKeys = await gen.generateKeys();
    final eveKeys = await gen.generateKeys();

    final alice = await _serviceWith(aliceKeys);
    final bob = await _serviceWith(bobKeys);

    final payload = await alice.encryptFor('secret', bobKeys.bundle.encode());

    final result = await bob.decryptTrying(
      payload.ciphertextBase64,
      [eveKeys.bundle.encode(), aliceKeys.bundle.encode()],
    );

    expect(result, isNotNull);
    expect(result!.text, 'secret');
    expect(result.peerBundle, aliceKeys.bundle.encode());
  });

  test('signature Ed25519 vérifiable par le pair', () async {
    final gen = CryptoService(_InMemoryKeyStore());
    final aliceKeys = await gen.generateKeys();
    final alice = await _serviceWith(aliceKeys);
    final verifier = CryptoService(_InMemoryKeyStore());

    const msg = 'preuve-d-origine';
    final sig = await alice.sign(msg);

    expect(await verifier.verify(msg, sig, aliceKeys.bundle.encode()), isTrue);
    expect(await verifier.verify('autre', sig, aliceKeys.bundle.encode()), isFalse);
  });

  test('une clé publique non-E2E est rejetée au chiffrement', () async {
    final gen = CryptoService(_InMemoryKeyStore());
    final keys = await gen.generateKeys();
    final svc = await _serviceWith(keys);

    expect(
      () => svc.encryptFor('x', 'ed25519:deadbeef'),
      throwsA(isA<CryptoException>()),
    );
  });
}
