import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Android : force le trafic de l'application sur le WiFi.
///
/// Le WiFi du dongle n'a pas d'accès Internet. Android le détecte et, tant que
/// les données mobiles sont actives, route par défaut le trafic (même vers une
/// adresse privée comme 10.x.x.x) par le réseau mobile : la passerelle devient
/// alors injoignable alors que le téléphone « est connecté ». `bindToWifi`
/// attache le processus au réseau WiFi (`ConnectivityManager.bindProcessToNetwork`).
///
/// Sans effet (renvoie `false`) hors Android, sans WiFi, ou si le canal natif
/// est absent (tests).
abstract final class WifiBinding {
  static const MethodChannel _channel = MethodChannel('tranasi/network');

  static Future<bool> bindToWifi() async {
    try {
      if (!Platform.isAndroid) return false;
      return await _channel.invokeMethod<bool>('bindToWifi') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Android : adresse IPv4 de la passerelle du WiFi courant (celle du dongle,
  /// fournie par son DHCP), ou `null` si indisponible.
  static Future<String?> gatewayAddress() async {
    try {
      if (!Platform.isAndroid) return null;
      return await _channel.invokeMethod<String>('wifiGateway');
    } catch (_) {
      return null;
    }
  }
}
