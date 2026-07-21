/// Objets de transfert échangés avec l'API passerelle (admin-service).
/// Les champs reflètent les réponses des mappers HTTP côté NestJS.
library;

DateTime? _parseDate(dynamic value) =>
    value is String ? DateTime.tryParse(value) : null;

/// Utilisateur enregistré sur la passerelle (identité mobile).
class GatewayUser {
  const GatewayUser({
    required this.publicId,
    required this.displayName,
    required this.publicKey,
    required this.status,
    this.createdAt,
  });

  final String publicId;
  final String displayName;
  final String publicKey;
  final String status;
  final DateTime? createdAt;

  factory GatewayUser.fromJson(Map<String, dynamic> json) => GatewayUser(
        publicId: json['publicId'] as String,
        displayName: json['displayName'] as String,
        publicKey: json['publicKey'] as String,
        status: json['status'] as String? ?? 'active',
        createdAt: _parseDate(json['createdAt']),
      );
}

/// Message chiffré stocké/relayé par la passerelle.
class GatewayMessage {
  const GatewayMessage({
    required this.publicId,
    required this.senderId,
    this.recipientId,
    this.groupId,
    required this.ciphertext,
    required this.contentHash,
    required this.status,
    this.blockchainTxId,
    this.createdAt,
    this.deliveredAt,
  });

  final String publicId;
  final String senderId;
  final String? recipientId;
  final String? groupId;
  final String ciphertext;
  final String contentHash;
  final String status;
  final String? blockchainTxId;
  final DateTime? createdAt;
  final DateTime? deliveredAt;

  factory GatewayMessage.fromJson(Map<String, dynamic> json) => GatewayMessage(
        publicId: json['publicId'] as String,
        senderId: json['senderId'] as String,
        recipientId: json['recipientId'] as String?,
        groupId: json['groupId'] as String?,
        ciphertext: json['ciphertext'] as String? ?? '',
        contentHash: json['contentHash'] as String? ?? '',
        status: json['status'] as String? ?? 'sent',
        blockchainTxId: json['blockchainTxId'] as String?,
        createdAt: _parseDate(json['createdAt']),
        deliveredAt: _parseDate(json['deliveredAt']),
      );
}

/// Fichier chiffré référencé par la passerelle.
class GatewayFile {
  const GatewayFile({
    required this.publicId,
    required this.senderId,
    this.recipientId,
    this.groupId,
    this.filename,
    this.mimeType,
    this.sizeBytes,
    required this.contentHash,
    required this.encrypted,
    this.blockchainTxId,
    this.createdAt,
  });

  final String publicId;
  final String senderId;
  final String? recipientId;
  final String? groupId;
  final String? filename;
  final String? mimeType;
  final int? sizeBytes;
  final String contentHash;
  final bool encrypted;
  final String? blockchainTxId;
  final DateTime? createdAt;

  factory GatewayFile.fromJson(Map<String, dynamic> json) => GatewayFile(
        publicId: json['publicId'] as String,
        senderId: json['senderId'] as String,
        recipientId: json['recipientId'] as String?,
        groupId: json['groupId'] as String?,
        filename: json['filename'] as String?,
        mimeType: json['mimeType'] as String?,
        sizeBytes: json['sizeBytes'] as int?,
        contentHash: json['contentHash'] as String? ?? '',
        encrypted: json['encrypted'] as bool? ?? true,
        blockchainTxId: json['blockchainTxId'] as String?,
        createdAt: _parseDate(json['createdAt']),
      );
}
