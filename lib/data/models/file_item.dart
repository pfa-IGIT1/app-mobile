class FileItem {
  const FileItem({
    required this.id,
    required this.name,
    required this.size,
    required this.receivedAt,
    this.mimeType,
    this.isMine = false,
    this.encrypted = true,
  });

  final String id;
  final String name;
  final int size;
  final DateTime receivedAt;
  final String? mimeType;

  /// `true` si le fichier a été envoyé par l'utilisateur local.
  final bool isMine;
  final bool encrypted;
}
