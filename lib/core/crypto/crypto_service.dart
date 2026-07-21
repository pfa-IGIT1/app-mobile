import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' as classic;

import 'crypto_keys.dart';
import 'key_store.dart';

/// Erreur cryptographique (clé illisible, MAC invalide, pair inconnu…).
class CryptoException implements Exception {
  CryptoException(this.message);
  final String message;
  @override
  String toString() => 'CryptoException: $message';
}

/// Charge utile chiffrée prête à être transmise à la passerelle.
///
/// [ciphertextBase64] est l'enveloppe binaire encodée en base64 ; [contentHash]
/// est le SHA-256 (hex minuscule) de ces MÊMES octets — la passerelle rejette
/// le message si le hash ne correspond pas (CONTENT_HASH_MISMATCH).
class EncryptedPayload {
  const EncryptedPayload({
    required this.ciphertextBase64,
    required this.contentHash,
  });
  final String ciphertextBase64;
  final String contentHash;
}

/// Résultat d'un déchiffrement où l'expéditeur a dû être identifié à l'aveugle.
class DecryptedFrom {
  const DecryptedFrom({required this.plaintext, required this.peerBundle});

  /// Contenu en clair (octets).
  final Uint8List plaintext;

  /// Clé publique combinée du pair dont le secret a permis le déchiffrement.
  final String peerBundle;

  String get text => utf8.decode(plaintext);
}

/// Cryptographie de bout en bout de l'application (§5, §11).
///
/// - **Signature** : Ed25519.
/// - **Chiffrement** : secret partagé X25519 (ECDH) → dérivation HKDF-SHA256 →
///   AES-256-GCM (confidentialité + intégrité).
///
/// L'enveloppe binaire est : `[version:1][nonce:12][mac:16][ciphertext:n]`.
class CryptoService {
  CryptoService(this._keyStore);

  final KeyStore _keyStore;

  static final _ed = Ed25519();
  static final _x = X25519();
  static final _aead = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static const int _version = 1;
  static const int _nonceLen = 12;
  static const int _macLen = 16;

  /// Sel de dérivation de clé (constant, non secret) — sépare les usages.
  static final List<int> _hkdfSalt = utf8.encode('pfa-mesh-e2e-v1');

  // ---------------------------------------------------------------------------
  // Génération / identité
  // ---------------------------------------------------------------------------

  /// Génère une nouvelle identité cryptographique (Ed25519 + X25519).
  Future<StoredKeys> generateKeys() async {
    final edPair = await _ed.newKeyPair();
    final edPub = await edPair.extractPublicKey();
    final edSeed = await edPair.extractPrivateKeyBytes();

    final xPair = await _x.newKeyPair();
    final xPub = await xPair.extractPublicKey();
    final xSeed = await xPair.extractPrivateKeyBytes();

    return StoredKeys(
      edPrivateSeed: Uint8List.fromList(edSeed),
      edPublic: Uint8List.fromList(edPub.bytes),
      xPrivateSeed: Uint8List.fromList(xSeed),
      xPublic: Uint8List.fromList(xPub.bytes),
    );
  }

  /// Récupère (et met en cache via le KeyStore) mes clés, ou lève une erreur.
  Future<StoredKeys> _myKeys() async {
    final keys = await _keyStore.loadKeys();
    if (keys == null) {
      throw CryptoException('Identité cryptographique absente du KeyStore.');
    }
    return keys;
  }

  // ---------------------------------------------------------------------------
  // Signature (Ed25519)
  // ---------------------------------------------------------------------------

  /// Signe un texte avec la clé privée Ed25519 locale ; renvoie la signature b64.
  Future<String> sign(String payload) async {
    final keys = await _myKeys();
    final keyPair = await _ed.newKeyPairFromSeed(keys.edPrivateSeed);
    final signature = await _ed.sign(utf8.encode(payload), keyPair: keyPair);
    return base64.encode(signature.bytes);
  }

  /// Vérifie une signature Ed25519 avec la clé publique d'un pair (bundle).
  Future<bool> verify(String payload, String signatureBase64, String peerBundle) async {
    final bundle = _requireBundle(peerBundle);
    final signature = Signature(
      base64.decode(signatureBase64),
      publicKey: SimplePublicKey(bundle.edPublic, type: KeyPairType.ed25519),
    );
    return _ed.verify(utf8.encode(payload), signature: signature);
  }

  // ---------------------------------------------------------------------------
  // Chiffrement (X25519 + AES-GCM)
  // ---------------------------------------------------------------------------

  /// Chiffre un texte à destination d'un pair. Voir [encryptBytesFor].
  Future<EncryptedPayload> encryptFor(String plaintext, String peerBundle) =>
      encryptBytesFor(utf8.encode(plaintext), peerBundle);

  /// Chiffre des octets à destination d'un pair identifié par son bundle.
  Future<EncryptedPayload> encryptBytesFor(
    List<int> plaintext,
    String peerBundle,
  ) async {
    final aesKey = await _sharedKey(await _myKeys(), _requireBundle(peerBundle));
    final box = await _aead.encrypt(
      plaintext,
      secretKey: aesKey,
      nonce: _aead.newNonce(),
    );
    final envelope = _pack(box);
    return EncryptedPayload(
      ciphertextBase64: base64.encode(envelope),
      contentHash: sha256Hex(envelope),
    );
  }

  /// Déchiffre une enveloppe reçue d'un pair connu (bundle donné).
  Future<Uint8List> decryptBytesFrom(
    String ciphertextBase64,
    String peerBundle,
  ) async {
    final aesKey = await _sharedKey(await _myKeys(), _requireBundle(peerBundle));
    final box = _unpack(base64.decode(ciphertextBase64));
    final clear = await _aead.decrypt(box, secretKey: aesKey);
    return Uint8List.fromList(clear);
  }

  /// Déchiffre un texte reçu d'un pair connu.
  Future<String> decryptFrom(String ciphertextBase64, String peerBundle) async =>
      utf8.decode(await decryptBytesFrom(ciphertextBase64, peerBundle));

  /// Déchiffre « à l'aveugle » : la passerelle n'expose que l'UUID interne de
  /// l'expéditeur, pas son identifiant public. On essaie donc chaque pair connu
  /// jusqu'à ce que le MAC AES-GCM valide — ce qui identifie l'expéditeur.
  ///
  /// Renvoie `null` si aucun secret partagé ne déchiffre l'enveloppe.
  Future<DecryptedFrom?> decryptTrying(
    String ciphertextBase64,
    Iterable<String> candidatePeerBundles,
  ) async {
    try {
      return decryptTryingBytes(
        base64.decode(ciphertextBase64),
        candidatePeerBundles,
      );
    } catch (_) {
      return null;
    }
  }

  /// Variante « à l'aveugle » travaillant directement sur les octets de
  /// l'enveloppe (utile pour le contenu binaire des fichiers via `/content`).
  Future<DecryptedFrom?> decryptTryingBytes(
    List<int> envelope,
    Iterable<String> candidatePeerBundles,
  ) async {
    final SecretBox box;
    try {
      box = _unpack(envelope);
    } catch (_) {
      return null;
    }
    final myKeys = await _myKeys();
    for (final bundle in candidatePeerBundles) {
      final parsed = PublicKeyBundle.tryParse(bundle);
      if (parsed == null) continue;
      try {
        final aesKey = await _sharedKey(myKeys, parsed);
        final clear = await _aead.decrypt(box, secretKey: aesKey);
        return DecryptedFrom(
          plaintext: Uint8List.fromList(clear),
          peerBundle: bundle,
        );
      } catch (_) {
        // MAC invalide pour ce pair : on continue avec le suivant.
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Empreintes / encodages (utilitaires)
  // ---------------------------------------------------------------------------

  /// SHA-256 (hex minuscule) d'octets — format attendu par la passerelle.
  String sha256Hex(List<int> bytes) => classic.sha256.convert(bytes).toString();

  /// SHA-256 (hex) d'un texte.
  String hash(String data) => sha256Hex(utf8.encode(data));

  String toBase64(String data) => base64.encode(utf8.encode(data));

  String fromBase64(String data) {
    try {
      return utf8.decode(base64.decode(data));
    } catch (_) {
      return data;
    }
  }

  // ---------------------------------------------------------------------------
  // Interne
  // ---------------------------------------------------------------------------

  /// Dérive la clé AES-256-GCM à partir du secret partagé X25519 (ECDH).
  Future<SecretKey> _sharedKey(StoredKeys mine, PublicKeyBundle peer) async {
    final myXPair = await _x.newKeyPairFromSeed(mine.xPrivateSeed);
    final shared = await _x.sharedSecretKey(
      keyPair: myXPair,
      remotePublicKey: SimplePublicKey(peer.xPublic, type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: _hkdfSalt,
      info: utf8.encode('pfa-message'),
    );
  }

  Uint8List _pack(SecretBox box) {
    final out = BytesBuilder();
    out.addByte(_version);
    out.add(box.nonce);
    out.add(box.mac.bytes);
    out.add(box.cipherText);
    return out.toBytes();
  }

  SecretBox _unpack(List<int> envelope) {
    if (envelope.isEmpty || envelope[0] != _version) {
      throw CryptoException('Version d\'enveloppe inconnue.');
    }
    const headerEnd = 1 + _nonceLen + _macLen;
    if (envelope.length < headerEnd) {
      throw CryptoException('Enveloppe tronquée.');
    }
    final nonce = envelope.sublist(1, 1 + _nonceLen);
    final mac = envelope.sublist(1 + _nonceLen, headerEnd);
    final cipher = envelope.sublist(headerEnd);
    return SecretBox(cipher, nonce: nonce, mac: Mac(mac));
  }

  PublicKeyBundle _requireBundle(String value) {
    final bundle = PublicKeyBundle.tryParse(value);
    if (bundle == null) {
      throw CryptoException(
        'Clé publique non compatible E2E (attendu pfa:v1:…). '
        'Ce contact doit s\'enregistrer via l\'application.',
      );
    }
    return bundle;
  }
}
