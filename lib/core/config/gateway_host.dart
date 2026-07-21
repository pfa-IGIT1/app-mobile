import 'dart:io';

/// Hôte par défaut de la passerelle selon la plateforme.
String resolveDefaultGatewayHost() {
  if (Platform.isAndroid) return '10.0.2.2';
  return '127.0.0.1';
}
