import 'dart:convert';
import 'dart:typed_data';

/// Matériel cryptographique complet de l'utilisateur (clés privées incluses).
///
/// Ne quitte JAMAIS le [KeyStore] sécurisé en clair : sérialisé ici uniquement
/// pour être écrit dans le stockage protégé du système (Keystore / Keychain).
///
/// - `ed*` : paire Ed25519 — signe (identité, preuve d'origine).
/// - `x*`  : paire X25519 — dérive un secret partagé (chiffrement E2E).
class StoredKeys {
  const StoredKeys({
    required this.edPrivateSeed,
    required this.edPublic,
    required this.xPrivateSeed,
    required this.xPublic,
  });

  /// Graine (32 octets) de la clé privée Ed25519.
  final Uint8List edPrivateSeed;

  /// Clé publique Ed25519 (32 octets).
  final Uint8List edPublic;

  /// Graine (32 octets) de la clé privée X25519.
  final Uint8List xPrivateSeed;

  /// Clé publique X25519 (32 octets).
  final Uint8List xPublic;

  /// Représentation publique partageable (enregistrée sur la passerelle).
  PublicKeyBundle get bundle =>
      PublicKeyBundle(edPublic: edPublic, xPublic: xPublic);

  Map<String, dynamic> toJson() => {
        'v': 1,
        'edPriv': base64Url.encode(edPrivateSeed),
        'edPub': base64Url.encode(edPublic),
        'xPriv': base64Url.encode(xPrivateSeed),
        'xPub': base64Url.encode(xPublic),
      };

  String toJsonString() => jsonEncode(toJson());

  factory StoredKeys.fromJson(Map<String, dynamic> json) => StoredKeys(
        edPrivateSeed: _b64(json['edPriv'] as String),
        edPublic: _b64(json['edPub'] as String),
        xPrivateSeed: _b64(json['xPriv'] as String),
        xPublic: _b64(json['xPub'] as String),
      );

  factory StoredKeys.fromJsonString(String raw) =>
      StoredKeys.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  static Uint8List _b64(String s) => Uint8List.fromList(base64Url.decode(s));
}

/// Clés PUBLIQUES d'un utilisateur, encodées dans une chaîne unique.
///
/// Format : `pfa:v1:<ed25519_b64url>:<x25519_b64url>`
/// C'est cette chaîne qui est stockée comme `publicKey` sur la passerelle et
/// échangée entre utilisateurs. Elle contient les deux clés publiques : la clé
/// de signature (Ed25519) et la clé d'accord (X25519).
class PublicKeyBundle {
  const PublicKeyBundle({required this.edPublic, required this.xPublic});

  final Uint8List edPublic;
  final Uint8List xPublic;

  static const String _prefix = 'pfa';
  static const String _version = 'v1';

  /// Encode le bundle dans sa forme textuelle partageable.
  String encode() {
    final ed = base64Url.encode(edPublic);
    final x = base64Url.encode(xPublic);
    return '$_prefix:$_version:$ed:$x';
  }

  @override
  String toString() => encode();

  /// Tente de décoder une clé publique combinée. Renvoie `null` si la chaîne
  /// n'est pas au format attendu (ex. anciennes clés `ed25519:...` du seed).
  static PublicKeyBundle? tryParse(String value) {
    final parts = value.split(':');
    if (parts.length != 4) return null;
    if (parts[0] != _prefix || parts[1] != _version) return null;
    try {
      final ed = Uint8List.fromList(base64Url.decode(_pad(parts[2])));
      final x = Uint8List.fromList(base64Url.decode(_pad(parts[3])));
      if (ed.length != 32 || x.length != 32) return null;
      return PublicKeyBundle(edPublic: ed, xPublic: x);
    } catch (_) {
      return null;
    }
  }

  /// Indique si une chaîne est une clé publique E2E exploitable.
  static bool isE2ECapable(String value) => tryParse(value) != null;

  static String _pad(String s) {
    final mod = s.length % 4;
    return mod == 0 ? s : s + ('=' * (4 - mod));
  }
}
