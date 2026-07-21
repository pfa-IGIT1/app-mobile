import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto_keys.dart';

/// Stockage sécurisé du matériel cryptographique de l'utilisateur.
///
/// La clé privée est le cœur de l'identité : elle est conservée dans le
/// stockage protégé du système (Android Keystore / iOS Keychain), jamais dans
/// les `SharedPreferences` ni sur le réseau.
class KeyStore {
  KeyStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  static const _keysEntry = 'pfa_key_material_v1';

  StoredKeys? _cache;

  /// Enregistre (et met en cache) le matériel cryptographique.
  Future<void> saveKeys(StoredKeys keys) async {
    _cache = keys;
    await _storage.write(key: _keysEntry, value: keys.toJsonString());
  }

  /// Charge le matériel cryptographique, ou `null` si aucune identité.
  Future<StoredKeys?> loadKeys() async {
    if (_cache != null) return _cache;
    final raw = await _storage.read(key: _keysEntry);
    if (raw == null) return null;
    try {
      _cache = StoredKeys.fromJsonString(raw);
      return _cache;
    } catch (_) {
      return null;
    }
  }

  /// Supprime définitivement les clés (déconnexion / réinitialisation).
  Future<void> deleteKeys() async {
    _cache = null;
    await _storage.delete(key: _keysEntry);
  }

  Future<bool> hasKeys() async => (await loadKeys()) != null;
}
