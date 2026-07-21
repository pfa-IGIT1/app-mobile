import '../../core/config/constants.dart';
import '../../core/crypto/crypto_keys.dart';
import '../../core/crypto/crypto_service.dart';
import '../../core/database/daos/messages_dao.dart';
import '../../core/database/daos/sync_dao.dart';
import '../../core/network/gateway_client.dart';
import '../models/gateway_dtos.dart';
import '../models/message.dart';

/// Orchestre : cache local (clair) <-> crypto E2E <-> passerelle (admin-service).
///
/// La passerelle n'expose que des UUID internes pour `senderId`/`recipientId`,
/// jamais l'identifiant public. On identifie donc l'interlocuteur « à l'aveugle »
/// en essayant chaque clé publique connue jusqu'à ce que le MAC AES-GCM valide.
class MessageRepository {
  MessageRepository({
    required this.messagesDao,
    required this.syncDao,
    required this.crypto,
    required this.gateway,
  });

  final MessagesDao messagesDao;
  final SyncDao syncDao;
  final CryptoService crypto;
  final GatewayClient gateway;

  /// Messages en cache local pour une conversation (disponible hors-ligne).
  Future<List<Message>> cachedConversation(String contactPublicId) =>
      messagesDao.getByContactId(contactPublicId);

  /// Chiffre le message, le met en cache en clair, puis le transmet.
  Future<void> send(
    Message message, {
    required String senderPublicId,
    required String recipientPublicId,
    required String recipientPublicKey,
  }) async {
    final payload = await crypto.encryptFor(message.content, recipientPublicKey);

    // Cache local : on stocke le CLAIR (bout-en-bout).
    await messagesDao.insert(
      Message(
        id: message.id,
        contactId: recipientPublicId,
        content: message.content,
        sentAt: message.sentAt,
        isMine: true,
      ),
    );

    try {
      await gateway.sendMessage(
        senderPublicId: senderPublicId,
        recipientPublicId: recipientPublicId,
        ciphertextBase64: payload.ciphertextBase64,
        contentHash: payload.contentHash,
      );
    } on GatewayException {
      // Erreur applicative (4xx) : on remonte l'échec.
      rethrow;
    } catch (_) {
      // Passerelle hors de portée : on met en file d'attente pour rejouer.
      await syncDao.enqueue(message.id, {
        'type': AppConstants.txTypeMessage,
        'senderPublicId': senderPublicId,
        'recipientPublicId': recipientPublicId,
        'ciphertext': payload.ciphertextBase64,
        'contentHash': payload.contentHash,
      });
    }
  }

  /// Récupère la conversation depuis la passerelle, déchiffre, met en cache et
  /// renvoie la liste triée. `directory` = utilisateurs connus (pour les clés).
  Future<List<Message>> syncConversation({
    required String myPublicId,
    required String contactPublicId,
    required List<GatewayUser> directory,
  }) async {
    final candidates = directory
        .where((u) => PublicKeyBundle.isE2ECapable(u.publicKey))
        .toList();
    final bundleToUser = <String, GatewayUser>{
      for (final u in candidates) u.publicKey: u,
    };
    final candidateKeys = candidates.map((u) => u.publicKey).toList();

    final inbox = await gateway.fetchInbox(myPublicId);
    final outbox = await gateway.fetchOutbox(myPublicId);

    final result = <Message>[];

    Future<void> ingest(
      List<GatewayMessage> messages, {
      required bool isMine,
    }) async {
      for (final m in messages) {
        final decrypted =
            await crypto.decryptTrying(m.ciphertext, candidateKeys);
        if (decrypted == null) continue;
        final peer = bundleToUser[decrypted.peerBundle];
        if (peer == null || peer.publicId != contactPublicId) continue;
        result.add(
          Message(
            id: m.publicId,
            contactId: contactPublicId,
            content: decrypted.text,
            sentAt: m.createdAt ?? DateTime.now(),
            isMine: isMine,
          ),
        );
      }
    }

    await ingest(inbox, isMine: false);
    await ingest(outbox, isMine: true);

    result.sort((a, b) => a.sentAt.compareTo(b.sentAt));

    // Rafraîchit le cache local avec le clair déchiffré.
    for (final m in result) {
      await messagesDao.insert(m);
    }
    return result;
  }
}
