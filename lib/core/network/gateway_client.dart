import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../../data/models/gateway_dtos.dart';
import 'request_signer.dart';

/// Erreur renvoyée par l'API passerelle.
class GatewayException implements Exception {
  GatewayException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'GatewayException($statusCode): $body';
}

/// Client HTTP vers l'API passerelle (admin-service).
///
/// C'est par ce canal que l'application mobile transmet à la passerelle
/// les données qu'elle doit récupérer : identités (utilisateurs), messages
/// et fichiers chiffrés. La passerelle les stocke puis les expose à
/// l'admin-frontend.
///
/// Authentification : sauf `/health`, chaque requête est signée en Ed25519
/// avec la clé privée de l'utilisateur (en-têtes `X-Key-Id`, `X-Timestamp`,
/// `X-Nonce`, `X-Signature`). Voir [buildSigningString]. La signature est
/// fournie par [configureAuth] (la clé privée ne sort jamais du KeyStore).
class GatewayClient {
  GatewayClient({
    http.Client? httpClient,
    String? host,
    int? port,
    DateTime Function()? clock,
    Random? random,
  })  : _http = httpClient ?? http.Client(),
        _now = clock ?? DateTime.now,
        _random = random,
        host = host ?? AppConstants.defaultGatewayHost,
        port = port ?? AppConstants.gatewayPort;

  final http.Client _http;
  final DateTime Function() _now;
  final Random? _random;

  /// Identifiant public de l'utilisateur (en-tête `X-Key-Id`).
  Future<String?> Function()? _keyId;

  /// Signe un texte avec la clé privée Ed25519 ; renvoie la signature en base64.
  Future<String> Function(String message)? _sign;

  /// Code d'inscription (en-tête `X-Enroll-Code`), seulement à l'inscription ;
  /// requis si `ENROLLMENT_CODE` est défini côté passerelle.
  String? enrollCode;

  /// Écart entre l'horloge de la passerelle et celle du téléphone (ms).
  /// Les Raspberry Pi n'ont pas d'horloge temps réel et la passerelle rejette
  /// toute requête à plus de 300 s de son horloge : on se cale donc sur
  /// l'en-tête `Date` de ses réponses.
  int _clockOffsetMs = 0;

  /// Branche la signature des requêtes (appelé une fois par [AppServices]).
  void configureAuth({
    required Future<String?> Function() keyId,
    required Future<String> Function(String message) sign,
  }) {
    _keyId = keyId;
    _sign = sign;
  }

  /// Port de la passerelle.
  int port;

  /// Hôte de la passerelle (mis à jour après découverte mDNS).
  String host;

  Uri _uri(String path) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: '${AppConstants.gatewayApiPrefix}$path',
      );

  static const Map<String, String> _jsonHeaders = {
    'Content-Type': 'application/json',
  };

  static const Duration _timeout = Duration(seconds: 10);
  static const Duration _fileTimeout = Duration(minutes: 2);

  // ---------------------------------------------------------------------------
  // Envoi des requêtes (signature, horloge)
  // ---------------------------------------------------------------------------

  /// Envoie une requête, signée par défaut.
  ///
  /// - [json] : corps JSON ; il est encodé UNE fois en octets, ces mêmes octets
  ///   sont signés puis envoyés (le serveur recalcule le SHA-256 du corps brut).
  /// - [selfSigned] : inscription, pas de `X-Key-Id` (la clé est dans le corps).
  /// - En cas de 401 « Horodatage hors fenêtre », l'écart d'horloge est appris
  ///   de la réponse puis la requête est renvoyée UNE fois, avec un nouveau nonce.
  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? json,
    bool signed = true,
    bool selfSigned = false,
    Duration? timeout,
  }) async {
    final uri = _uri(path);
    final body = json == null ? null : utf8.encode(jsonEncode(json));

    for (var attempt = 0;; attempt++) {
      final request = http.Request(method, uri);
      if (body != null) {
        request.headers.addAll(_jsonHeaders);
        request.bodyBytes = body;
      }
      if (signed) {
        request.headers.addAll(
          await _authHeaders(method, uri, body, selfSigned: selfSigned),
        );
      }

      final response = await Future<http.Response>(() async {
        return http.Response.fromStream(await _http.send(request));
      }).timeout(timeout ?? _timeout);
      _learnServerClock(response);

      final clockRejected = response.statusCode == 401 &&
          signed &&
          attempt == 0 &&
          response.body.contains('Horodatage');
      if (clockRejected) continue;
      return response;
    }
  }

  Future<Map<String, String>> _authHeaders(
    String method,
    Uri uri,
    List<int>? body, {
    required bool selfSigned,
  }) async {
    final sign = _sign;
    if (sign == null) {
      throw StateError('Signature des requêtes non configurée.');
    }
    String? keyId;
    if (!selfSigned) {
      keyId = await _keyId?.call();
      if (keyId == null || keyId.isEmpty) {
        throw StateError('Identité absente : requête non signable.');
      }
    }

    final timestamp = (_now().millisecondsSinceEpoch + _clockOffsetMs) ~/ 1000;
    final nonce = newNonce(_random);
    final message = buildSigningString(
      method: method,
      pathAndQuery: uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path,
      timestamp: timestamp,
      nonce: nonce,
      body: body ?? const <int>[],
    );

    final code = enrollCode;
    return {
      'X-Timestamp': '$timestamp',
      'X-Nonce': nonce,
      'X-Signature': await sign(message),
      if (keyId != null) 'X-Key-Id': keyId,
      if (selfSigned && code != null && code.isNotEmpty) 'X-Enroll-Code': code,
    };
  }

  /// Mémorise l'écart d'horloge d'après l'en-tête `Date` (résolution 1 s, très
  /// en deçà de la tolérance de 300 s de la passerelle).
  void _learnServerClock(http.Response response) {
    final header = response.headers['date'];
    if (header == null) return;
    try {
      final server = HttpDate.parse(header);
      _clockOffsetMs = server.millisecondsSinceEpoch - _now().millisecondsSinceEpoch;
    } catch (_) {
      // En-tête illisible : on garde l'écart précédent.
    }
  }

  // ---------------------------------------------------------------------------
  // Santé
  // ---------------------------------------------------------------------------

  /// Vérifie que la passerelle est joignable.
  Future<bool> ping() async {
    try {
      final res = await _send('GET', '/health', signed: false);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Utilisateurs (identités)
  // ---------------------------------------------------------------------------

  /// Enregistre l'identité locale auprès de la passerelle.
  Future<GatewayUser> registerUser({
    required String displayName,
    required String publicKey,
  }) async {
    final res = await _send(
      'POST',
      '/users',
      json: {
        'displayName': displayName,
        'publicKey': publicKey,
      },
      selfSigned: true,
    );
    _ensureSuccess(res);
    return GatewayUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Liste les utilisateurs connus de la passerelle (annuaire).
  ///
  /// `GET /users` est réservé au JWT administrateur : le mobile utilise
  /// `GET /users/directory` (signé, tout utilisateur actif).
  Future<List<GatewayUser>> fetchUsers() async {
    final res = await _send('GET', '/users/directory');
    _ensureSuccess(res);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => GatewayUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Récupère un utilisateur par son identifiant public.
  Future<GatewayUser> fetchUser(String publicId) async {
    final res = await _send('GET', '/users/$publicId');
    _ensureSuccess(res);
    return GatewayUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  // ---------------------------------------------------------------------------
  // Messages
  // ---------------------------------------------------------------------------

  /// Envoie un message chiffré à la passerelle.
  Future<GatewayMessage> sendMessage({
    required String senderPublicId,
    String? recipientPublicId,
    String? groupId,
    required String ciphertextBase64,
    required String contentHash,
  }) async {
    final res = await _send(
      'POST',
      '/messages',
      json: {
        'senderPublicId': senderPublicId,
        'recipientPublicId': ?recipientPublicId,
        'groupId': ?groupId,
        'ciphertext': ciphertextBase64,
        'contentHash': contentHash,
      },
    );
    _ensureSuccess(res);
    return GatewayMessage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Récupère les messages reçus par un utilisateur.
  Future<List<GatewayMessage>> fetchInbox(String userPublicId) async {
    final res = await _send('GET', '/messages/inbox/$userPublicId');
    _ensureSuccess(res);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => GatewayMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Récupère les messages envoyés par un utilisateur.
  Future<List<GatewayMessage>> fetchOutbox(String userPublicId) async {
    final res = await _send('GET', '/messages/outbox/$userPublicId');
    _ensureSuccess(res);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => GatewayMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Fichiers
  // ---------------------------------------------------------------------------

  /// Envoie un fichier chiffré (contenu en base64) à la passerelle.
  Future<GatewayFile> sendFile({
    required String senderPublicId,
    String? recipientPublicId,
    String? groupId,
    String? filename,
    String? mimeType,
    required String ciphertextBase64,
    required String contentHash,
  }) async {
    return _retryTransient(
      () async {
        final res = await _send(
          'POST',
          '/files',
          json: {
            'senderPublicId': senderPublicId,
            'recipientPublicId': ?recipientPublicId,
            'groupId': ?groupId,
            'filename': ?filename,
            'mimeType': ?mimeType,
            'ciphertext': ciphertextBase64,
            'contentHash': contentHash,
          },
          timeout: _fileTimeout,
        );
        _ensureSuccess(res);
        return GatewayFile.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>,
        );
      },
      label: 'envoi fichier',
    );
  }

  /// Liste les fichiers associés à un utilisateur.
  Future<List<GatewayFile>> fetchFiles(String userPublicId) async {
    final res = await _send('GET', '/files/user/$userPublicId');
    _ensureSuccess(res);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => GatewayFile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Télécharge le contenu binaire (chiffré) d'un fichier.
  Future<List<int>> downloadFileContent(String publicId) async {
    return _retryTransient(
      () async {
        final res = await _send(
          'GET',
          '/files/$publicId/content',
          timeout: _fileTimeout,
        );
        _ensureSuccess(res);
        return res.bodyBytes;
      },
      label: 'téléchargement fichier',
    );
  }

  // ---------------------------------------------------------------------------
  // Compatibilité mempool (SyncService)
  // ---------------------------------------------------------------------------

  /// Pousse une transaction locale en attente vers la passerelle.
  /// Route vers `/messages` ou `/files` selon le champ `type`.
  Future<void> sendTransaction(Map<String, dynamic> tx) async {
    final type = tx['type'] as String?;
    if (type == AppConstants.txTypeFile) {
      await sendFile(
        senderPublicId: tx['senderPublicId'] as String? ?? '',
        recipientPublicId: tx['recipientPublicId'] as String?,
        groupId: tx['groupId'] as String?,
        filename: tx['filename'] as String? ?? tx['name'] as String?,
        mimeType: tx['mimeType'] as String?,
        ciphertextBase64: tx['ciphertext'] as String? ?? tx['payload'] as String? ?? '',
        contentHash: tx['contentHash'] as String? ?? '',
      );
    } else {
      await sendMessage(
        senderPublicId: tx['senderPublicId'] as String? ?? '',
        recipientPublicId: tx['recipientPublicId'] as String?,
        groupId: tx['groupId'] as String?,
        ciphertextBase64: tx['ciphertext'] as String? ?? tx['payload'] as String? ?? '',
        contentHash: tx['contentHash'] as String? ?? '',
      );
    }
  }

  /// Récupère les messages en attente pour l'utilisateur donné.
  Future<List<Map<String, dynamic>>> fetchPending(String userPublicId) async {
    final messages = await fetchInbox(userPublicId);
    return messages
        .map((m) => {
              'publicId': m.publicId,
              'senderId': m.senderId,
              'ciphertext': m.ciphertext,
              'contentHash': m.contentHash,
              'status': m.status,
              'createdAt': m.createdAt?.toIso8601String(),
            })
        .toList();
  }

  void _ensureSuccess(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw GatewayException(res.statusCode, res.body);
    }
  }

  /// Réessaie les opérations fichiers en cas de coupure réseau passagère
  /// (fréquent sur le WiFi mesh).
  Future<T> _retryTransient<T>(
    Future<T> Function() action, {
    required String label,
    int attempts = 3,
  }) async {
    Object? lastError;
    for (var i = 0; i < attempts; i++) {
      try {
        return await action();
      } catch (e) {
        lastError = e;
        if (e is GatewayException || !_isTransientNetworkError(e) || i == attempts - 1) {
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 1 << i));
      }
    }
    throw lastError ?? StateError('$label: échec après $attempts tentatives');
  }

  bool _isTransientNetworkError(Object error) {
    final msg = error.toString();
    return error is TimeoutException ||
        msg.contains('Connection reset') ||
        msg.contains('Connection closed') ||
        msg.contains('SocketException') ||
        msg.contains('ClientException') ||
        msg.contains('Software caused connection abort');
  }

  void close() => _http.close();
}
