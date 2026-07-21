/// Identité locale de l'utilisateur (clés + enregistrement passerelle).
class LocalIdentity {
  const LocalIdentity({
    required this.publicId,
    required this.displayName,
    required this.publicKey,
    required this.createdAt,
    this.registeredOnGateway = true,
  });

  final String publicId;
  final String displayName;
  final String publicKey;
  final DateTime createdAt;
  final bool registeredOnGateway;

  Map<String, dynamic> toJson() => {
        'publicId': publicId,
        'displayName': displayName,
        'publicKey': publicKey,
        'createdAt': createdAt.toIso8601String(),
        'registeredOnGateway': registeredOnGateway,
      };

  factory LocalIdentity.fromJson(Map<String, dynamic> json) => LocalIdentity(
        publicId: json['publicId'] as String,
        displayName: json['displayName'] as String,
        publicKey: json['publicKey'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        registeredOnGateway: json['registeredOnGateway'] as bool? ?? true,
      );
}
