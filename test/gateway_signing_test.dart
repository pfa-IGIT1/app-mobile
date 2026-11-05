import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pfa_mobile/core/crypto/crypto_keys.dart';
import 'package:pfa_mobile/core/crypto/crypto_service.dart';
import 'package:pfa_mobile/core/crypto/key_store.dart';
import 'package:pfa_mobile/core/network/gateway_client.dart';
import 'package:pfa_mobile/core/network/request_signer.dart';

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

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  // Vecteur de test de l'admin-service (docs/MOBILE_AUTH.md) : graine 0x07 x 32.
  const body =
      '{"senderPublicId":"alice","recipientPublicId":"bob","ciphertext":"aGVsbG8=","contentHash":"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"}';
  const expectedPublicKey =
      'ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c';
  const expectedSignature =
      'ae4c23e0b4c3191afa57428354aa33413977d82d477e822c243bf5ce8a4ce43538e6c628ecb58a9196fd76f9e2ae3bdce360cd61a5711e987739e8e5c2563604';

  test('vecteur de test : clé publique et signature identiques à la passerelle',
      () async {
    final seed = Uint8List.fromList(List.filled(32, 7));
    final pair = await Ed25519().newKeyPairFromSeed(seed);
    final pub = (await pair.extractPublicKey()).bytes;
    expect(_hex(pub), expectedPublicKey);

    final store = _InMemoryKeyStore();
    await store.saveKeys(StoredKeys(
      edPrivateSeed: seed,
      edPublic: Uint8List.fromList(pub),
      xPrivateSeed: Uint8List.fromList(List.filled(32, 1)),
      xPublic: Uint8List.fromList(List.filled(32, 2)),
    ));
    final svc = CryptoService(store);

    final message = buildSigningString(
      method: 'post',
      pathAndQuery: '/api/messages',
      timestamp: 1793800000,
      nonce: '00112233445566778899aabbccddeeff',
      body: utf8.encode(body),
    );
    final signature = base64.decode(await svc.sign(message));
    expect(_hex(signature), expectedSignature);
  });

  test('corps vide : SHA-256 de la chaîne vide', () {
    final message = buildSigningString(
      method: 'GET',
      pathAndQuery: '/api/users/directory',
      timestamp: 1793800000,
      nonce: '00112233445566778899aabbccddeeff',
      body: const [],
    );
    expect(
      message.split('\n').last,
      'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
    );
  });

  test('nonce : 32 caractères hexadécimaux, différent à chaque appel', () {
    final a = newNonce();
    final b = newNonce();
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a, isNot(b));
  });

  group('GatewayClient', () {
    // 2026-11-05 03:00:00 UTC (horloge du téléphone figée).
    final phoneNow = DateTime.utc(2026, 11, 5, 3, 0, 0);
    final phoneEpoch = phoneNow.millisecondsSinceEpoch ~/ 1000;

    GatewayClient build(
      Future<http.Response> Function(http.Request) handler,
      List<String> signed,
    ) {
      final client = GatewayClient(
        httpClient: MockClient(handler),
        host: '10.0.0.3',
        port: 3001,
        clock: () => phoneNow,
      );
      client.configureAuth(
        keyId: () async => 'alice',
        sign: (message) async {
          signed.add(message);
          return 'U0lH';
        },
      );
      return client;
    }

    test('requête signée : en-têtes et message signé', () async {
      final signed = <String>[];
      late http.Request seen;
      final client = build((req) async {
        seen = req;
        return http.Response('[]', 200);
      }, signed);

      await client.fetchInbox('alice');

      expect(seen.method, 'GET');
      expect(seen.url.toString(), 'http://10.0.0.3:3001/api/messages/inbox/alice');
      expect(seen.headers['X-Key-Id'], 'alice');
      expect(seen.headers['X-Timestamp'], '$phoneEpoch');
      expect(seen.headers['X-Nonce'], matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(seen.headers['X-Signature'], 'U0lH');
      expect(seen.headers.containsKey('X-Enroll-Code'), isFalse);

      final lines = signed.single.split('\n');
      expect(lines[0], 'GET');
      expect(lines[1], '/api/messages/inbox/alice');
      expect(lines[2], '$phoneEpoch');
      expect(lines[3], seen.headers['X-Nonce']);
    });

    test('annuaire : GET /users/directory signé', () async {
      final signed = <String>[];
      late http.Request seen;
      final client = build((req) async {
        seen = req;
        return http.Response('[]', 200);
      }, signed);

      await client.fetchUsers();

      expect(seen.url.path, '/api/users/directory');
      expect(seen.headers['X-Key-Id'], 'alice');
    });

    test('corps : les octets signés sont ceux qui sont envoyés', () async {
      final signed = <String>[];
      late http.Request seen;
      final client = build((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'publicId': 'm1',
            'senderId': 's',
            'ciphertext': 'aGVsbG8=',
            'contentHash': 'h',
            'status': 'sent',
          }),
          201,
        );
      }, signed);

      await client.sendMessage(
        senderPublicId: 'alice',
        recipientPublicId: 'bob',
        ciphertextBase64: 'aGVsbG8=',
        contentHash: 'h',
      );

      final expected = buildSigningString(
        method: 'POST',
        pathAndQuery: '/api/messages',
        timestamp: phoneEpoch,
        nonce: seen.headers['X-Nonce']!,
        body: seen.bodyBytes,
      );
      expect(signed.single, expected);
      expect(seen.headers['Content-Type'], startsWith('application/json'));
    });

    test('inscription : auto-signée, sans X-Key-Id, avec code d\'inscription',
        () async {
      final signed = <String>[];
      late http.Request seen;
      final client = build((req) async {
        seen = req;
        return http.Response(
          jsonEncode({
            'publicId': 'u1',
            'displayName': 'Alice',
            'publicKey': 'pfa:v1:a:b',
            'status': 'active',
          }),
          201,
        );
      }, signed);
      client.enrollCode = 'sesame-2026';
      // Aucune identité locale à l'inscription : le keyId ne doit pas être lu.
      client.configureAuth(
        keyId: () async => fail('X-Key-Id ne doit pas être demandé'),
        sign: (m) async {
          signed.add(m);
          return 'U0lH';
        },
      );

      await client.registerUser(displayName: 'Alice', publicKey: 'pfa:v1:a:b');

      expect(seen.headers.containsKey('X-Key-Id'), isFalse);
      expect(seen.headers['X-Enroll-Code'], 'sesame-2026');
      expect(seen.headers['X-Signature'], 'U0lH');
    });

    test('/health : non signé', () async {
      final signed = <String>[];
      late http.Request seen;
      final client = build((req) async {
        seen = req;
        return http.Response('{"status":"ok"}', 200);
      }, signed);

      expect(await client.ping(), isTrue);
      expect(seen.headers.containsKey('X-Signature'), isFalse);
      expect(signed, isEmpty);
    });

    test('horloge : le décalage appris de l\'en-tête Date corrige le timestamp',
        () async {
      final signed = <String>[];
      final stamps = <String>[];
      final client = build((req) async {
        if (req.url.path.endsWith('/health')) {
          // La passerelle a 2 h d'avance sur le téléphone.
          return http.Response(
            '{"status":"ok"}',
            200,
            headers: {'date': 'Thu, 05 Nov 2026 05:00:00 GMT'},
          );
        }
        stamps.add(req.headers['X-Timestamp']!);
        return http.Response('[]', 200);
      }, signed);

      await client.ping();
      await client.fetchInbox('alice');

      expect(stamps.single, '${phoneEpoch + 7200}');
    });

    test('401 « Horodatage » : un seul nouvel essai, avec un nouveau nonce',
        () async {
      final signed = <String>[];
      final stamps = <String>[];
      final nonces = <String>[];
      var calls = 0;
      final client = build((req) async {
        calls++;
        stamps.add(req.headers['X-Timestamp']!);
        nonces.add(req.headers['X-Nonce']!);
        if (calls == 1) {
          return http.Response(
            '{"message":"Horodatage hors fenêtre."}',
            401,
            headers: {
              'date': 'Thu, 05 Nov 2026 05:00:00 GMT',
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }
        return http.Response('[]', 200);
      }, signed);

      await client.fetchInbox('alice');

      expect(calls, 2);
      expect(stamps, ['$phoneEpoch', '${phoneEpoch + 7200}']);
      expect(nonces[0], isNot(nonces[1]));
    });

    test('401 autre que l\'horodatage : pas de nouvel essai', () async {
      final signed = <String>[];
      var calls = 0;
      final client = build((req) async {
        calls++;
        return http.Response('{"message":"Signature invalide."}', 401);
      }, signed);

      await expectLater(
        client.fetchInbox('alice'),
        throwsA(isA<GatewayException>()),
      );
      expect(calls, 1);
    });

    test('sans identité locale : requête non signable', () async {
      final signed = <String>[];
      final client = build((req) async => http.Response('[]', 200), signed);
      client.configureAuth(keyId: () async => null, sign: (m) async => 'x');

      await expectLater(client.fetchInbox('alice'), throwsA(isA<StateError>()));
    });
  });
}
