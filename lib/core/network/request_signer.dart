import 'dart:math';

import 'package:crypto/crypto.dart' as classic;

/// Signature des requêtes envoyées à la passerelle (admin-service).
///
/// Spécification côté serveur : `docs/MOBILE_AUTH.md` de l'admin-service.
/// Message signé (UTF-8) :
///
/// ```
/// METHODE \n cheminEtRequête \n timestamp \n nonce \n sha256hex(corps)
/// ```
///
/// - `cheminEtRequête` : chemin tel que reçu par le serveur, préfixe `/api` et
///   chaîne de requête compris (`/api/messages/inbox/abc`) ;
/// - `timestamp` : secondes Unix ;
/// - `nonce` : 16 octets aléatoires en hexadécimal (32 caractères) ;
/// - corps vide (requête GET) : SHA-256 de la chaîne vide.
String buildSigningString({
  required String method,
  required String pathAndQuery,
  required int timestamp,
  required String nonce,
  required List<int> body,
}) {
  final bodyHash = classic.sha256.convert(body).toString(); // hex minuscule
  return '${method.toUpperCase()}\n$pathAndQuery\n$timestamp\n$nonce\n$bodyHash';
}

/// Nonce de 16 octets aléatoires, en hexadécimal minuscule (32 caractères).
String newNonce([Random? random]) {
  final rng = random ?? Random.secure();
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
