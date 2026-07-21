class Message {
  const Message({
    required this.id,
    required this.contactId,
    required this.content,
    required this.sentAt,
    this.isMine = false,
    this.isRead = false,
  });

  final String id;

  /// Identifiant public du pair (l'autre partie de la conversation).
  final String contactId;

  /// Contenu EN CLAIR (le téléphone met en cache le clair — principe E2E).
  final String content;
  final DateTime sentAt;

  /// `true` si le message a été envoyé par l'utilisateur local.
  final bool isMine;
  final bool isRead;

  Message copyWith({bool? isRead}) => Message(
        id: id,
        contactId: contactId,
        content: content,
        sentAt: sentAt,
        isMine: isMine,
        isRead: isRead ?? this.isRead,
      );
}
