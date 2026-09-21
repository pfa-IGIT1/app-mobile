import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/constants.dart';
import '../../data/models/gateway_dtos.dart';

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
class GatewayClient {
  GatewayClient({
    http.Client? httpClient,
    String? host,
    int? port,
  })  : _http = httpClient ?? http.Client(),
        host = host ?? AppConstants.defaultGatewayHost,
        port = port ?? AppConstants.gatewayPort;

  final http.Client _http;

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
  // Santé
  // ---------------------------------------------------------------------------

  /// Vérifie que la passerelle est joignable.
  Future<bool> ping() async {
    try {
      final res = await _http.get(_uri('/health')).timeout(_timeout);
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
    final res = await _http
        .post(
          _uri('/users'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'displayName': displayName,
            'publicKey': publicKey,
          }),
        )
        .timeout(_timeout);
    _ensureSuccess(res);
    return GatewayUser.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Liste les utilisateurs connus de la passerelle (annuaire).
  Future<List<GatewayUser>> fetchUsers() async {
    final res = await _http.get(_uri('/users')).timeout(_timeout);
    _ensureSuccess(res);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => GatewayUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Récupère un utilisateur par son identifiant public.
  Future<GatewayUser> fetchUser(String publicId) async {
    final res = await _http.get(_uri('/users/$publicId')).timeout(_timeout);
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
    final res = await _http
        .post(
          _uri('/messages'),
          headers: _jsonHeaders,
          body: jsonEncode({
            'senderPublicId': senderPublicId,
            'recipientPublicId': ?recipientPublicId,
            'groupId': ?groupId,
            'ciphertext': ciphertextBase64,
            'contentHash': contentHash,
          }),
        )
        .timeout(_timeout);
    _ensureSuccess(res);
    return GatewayMessage.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Récupère les messages reçus par un utilisateur.
  Future<List<GatewayMessage>> fetchInbox(String userPublicId) async {
    final res =
        await _http.get(_uri('/messages/inbox/$userPublicId')).timeout(_timeout);
    _ensureSuccess(res);
    final data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => GatewayMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Récupère les messages envoyés par un utilisateur.
  Future<List<GatewayMessage>> fetchOutbox(String userPublicId) async {
    final res = await _http
        .get(_uri('/messages/outbox/$userPublicId'))
        .timeout(_timeout);
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
        final res = await _http
            .post(
              _uri('/files'),
              headers: _jsonHeaders,
              body: jsonEncode({
                'senderPublicId': senderPublicId,
                'recipientPublicId': ?recipientPublicId,
                'groupId': ?groupId,
                'filename': ?filename,
                'mimeType': ?mimeType,
                'ciphertext': ciphertextBase64,
                'contentHash': contentHash,
              }),
            )
            .timeout(_fileTimeout);
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
    final res =
        await _http.get(_uri('/files/user/$userPublicId')).timeout(_timeout);
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
        final res = await _http
            .get(_uri('/files/$publicId/content'))
            .timeout(_fileTimeout);
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
