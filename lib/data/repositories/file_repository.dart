import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/crypto/crypto_keys.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/database/daos/files_dao.dart';
import '../../core/network/gateway_client.dart';
import '../models/file_item.dart';
import '../models/gateway_dtos.dart';

/// Contenu déchiffré d'un fichier téléchargé.
class DecryptedFile {
  const DecryptedFile({required this.name, required this.bytes, this.mimeType});
  final String name;
  final Uint8List bytes;
  final String? mimeType;
}

/// Orchestre les fichiers : cache local <-> crypto E2E <-> passerelle.
class FileRepository {
  FileRepository({
    required this.filesDao,
    required this.crypto,
    required this.gateway,
  });

  final FilesDao filesDao;
  final CryptoService crypto;
  final GatewayClient gateway;

  static const _sentIdsKey = 'sent_file_ids';

  Future<List<FileItem>> cached() => filesDao.getAll();

  /// Liste les fichiers de l'utilisateur depuis la passerelle (métadonnées).
  ///
  /// La direction (envoyé/reçu) n'est pas exposée par l'API : on la déduit d'un
  /// registre local des identifiants de fichiers que l'on a soi-même envoyés.
  Future<List<FileItem>> listForUser(String userPublicId) async {
    final remote = await gateway.fetchFiles(userPublicId);
    final sentIds = await _sentIds();
    final items = remote
        .map((f) => FileItem(
              id: f.publicId,
              name: f.filename ?? f.publicId,
              size: f.sizeBytes ?? 0,
              receivedAt: f.createdAt ?? DateTime.now(),
              mimeType: f.mimeType,
              encrypted: f.encrypted,
              isMine: sentIds.contains(f.publicId),
            ))
        .toList()
      ..sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    for (final item in items) {
      await filesDao.insert(item);
    }
    return items;
  }

  /// Chiffre le fichier pour le destinataire et le transmet à la passerelle.
  Future<GatewayFile> send({
    required List<int> bytes,
    required String filename,
    String? mimeType,
    required String senderPublicId,
    required String recipientPublicId,
    required String recipientPublicKey,
  }) async {
    final payload = await crypto.encryptBytesFor(bytes, recipientPublicKey);
    final remote = await gateway.sendFile(
      senderPublicId: senderPublicId,
      recipientPublicId: recipientPublicId,
      filename: filename,
      mimeType: mimeType,
      ciphertextBase64: payload.ciphertextBase64,
      contentHash: payload.contentHash,
    );
    await _rememberSent(remote.publicId);
    await filesDao.insert(
      FileItem(
        id: remote.publicId,
        name: filename,
        size: remote.sizeBytes ?? bytes.length,
        receivedAt: remote.createdAt ?? DateTime.now(),
        mimeType: mimeType,
        isMine: true,
      ),
    );
    return remote;
  }

  /// Télécharge et déchiffre un fichier. `directory` fournit les clés publiques
  /// candidates pour identifier l'expéditeur (déchiffrement à l'aveugle).
  Future<DecryptedFile> download(
    FileItem item, {
    required List<GatewayUser> directory,
  }) async {
    final envelope = await gateway.downloadFileContent(item.id);
    final candidates = directory
        .where((u) => PublicKeyBundle.isE2ECapable(u.publicKey))
        .map((u) => u.publicKey);
    final decrypted = await crypto.decryptTryingBytes(envelope, candidates);
    if (decrypted == null) {
      throw CryptoException(
        'Impossible de déchiffrer ce fichier : clé de l\'expéditeur inconnue.',
      );
    }
    return DecryptedFile(
      name: item.name,
      bytes: decrypted.plaintext,
      mimeType: item.mimeType,
    );
  }

  Future<Set<String>> _sentIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_sentIdsKey) ?? const []).toSet();
  }

  Future<void> _rememberSent(String publicId) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_sentIdsKey) ?? const []).toSet()
      ..add(publicId);
    await prefs.setStringList(_sentIdsKey, ids.toList());
  }
}
