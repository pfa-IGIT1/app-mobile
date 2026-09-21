/// Constantes globales de l'application.
abstract final class AppConstants {
  /// Port de l'API passerelle (admin-service NestJS).
  static const int gatewayPort = 3001;

  /// Préfixe global des routes de l'API passerelle.
  static const String gatewayApiPrefix = '/api';

  /// Hôte par défaut de la passerelle sur le réseau mesh (RPi).
  /// Écrasé à l'exécution par la découverte mDNS.
  /// Pour l'émulateur Android en dev, utiliser 10.0.2.2.
  static const String defaultGatewayHost = '10.0.1.1';

  /// Service mDNS annoncé par la passerelle.
  static const String gatewayMdnsService = '_pfa-gateway._tcp';

  static const String txTypeMessage = 'message';
  static const String txTypeFile = 'file';

  /// Taille max d'un fichier brut avant chiffrement (base64 + JSON grossit ~40 %).
  static const int maxUploadBytes = 15 * 1024 * 1024;
}
