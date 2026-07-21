
import 'constants.dart';

/// Hôte par défaut de la passerelle selon la plateforme.
///
/// Sur un appareil physique connecté au point d'accès WiFi de la passerelle
/// (réseau EPO-MESH), l'adresse réelle du Raspberry Pi doit être utilisée.
/// `10.0.2.2` reste disponible pour un émulateur Android testant contre un
/// admin-service lancé sur la machine hôte (developpement local uniquement).
String resolveDefaultGatewayHost() {
  return AppConstants.defaultGatewayHost;
}
