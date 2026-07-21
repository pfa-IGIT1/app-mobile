import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../crypto/crypto_service.dart';
import '../crypto/key_store.dart';
import '../network/gateway_client.dart';
import 'local_identity.dart';

/// Crée, persiste et enregistre l'identité mobile auprès de la passerelle.
///
/// L'identité EST la paire de clés (§11) : la clé privée reste dans le
/// [KeyStore] sécurisé, seule la clé publique combinée (bundle) est transmise
/// à la passerelle comme `publicKey`.
class IdentityService {
  IdentityService(this._gateway, this._crypto, this._keyStore);

  static const _prefsKey = 'local_identity';

  final GatewayClient _gateway;
  final CryptoService _crypto;
  final KeyStore _keyStore;
  LocalIdentity? _cached;

  LocalIdentity? get current => _cached;

  Future<LocalIdentity?> load() async {
    if (_cached != null) return _cached;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return null;
    _cached = LocalIdentity.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    return _cached;
  }

  Future<void> save(LocalIdentity identity) async {
    _cached = identity;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(identity.toJson()));
  }

  Future<void> clear() async {
    _cached = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
    await _keyStore.deleteKeys();
  }

  /// Une identité complète existe-t-elle (profil + clé privée) ?
  Future<bool> isInitialised() async {
    final identity = await load();
    if (identity == null) return false;
    return _keyStore.hasKeys();
  }

  /// Génère une VRAIE paire de clés Ed25519/X25519, la stocke de façon
  /// sécurisée, puis enregistre la clé publique sur la passerelle.
  Future<LocalIdentity> createAndRegister(String displayName) async {
    final keys = await _crypto.generateKeys();
    await _keyStore.saveKeys(keys);
    final publicKey = keys.bundle.encode();
    final createdAt = DateTime.now();

    try {
      final remote = await _gateway.registerUser(
        displayName: displayName.trim(),
        publicKey: publicKey,
      );
      final identity = LocalIdentity(
        publicId: remote.publicId,
        displayName: remote.displayName,
        publicKey: remote.publicKey,
        createdAt: createdAt,
      );
      await save(identity);
      return identity;
    } on GatewayException {
      // La passerelle a peut-être déjà cette clé : on tente de la retrouver.
      try {
        final users = await _gateway.fetchUsers();
        final match = users.where((u) => u.publicKey == publicKey).toList();
        if (match.isNotEmpty) {
          final remote = match.first;
          final identity = LocalIdentity(
            publicId: remote.publicId,
            displayName: remote.displayName,
            publicKey: remote.publicKey,
            createdAt: createdAt,
          );
          await save(identity);
          return identity;
        }
      } catch (_) {
        // ignore : on bascule sur une identité locale ci-dessous.
      }
      return _saveLocalOnly(displayName.trim(), publicKey, createdAt);
    } catch (_) {
      // Passerelle injoignable (réseau) : identité locale hors-ligne.
      return _saveLocalOnly(displayName.trim(), publicKey, createdAt);
    }
  }

  /// Identité de repli enregistrée uniquement sur l'appareil (sans passerelle).
  /// Permet d'utiliser/parcourir l'app quand la passerelle n'est pas joignable.
  Future<LocalIdentity> _saveLocalOnly(
    String displayName,
    String publicKey,
    DateTime createdAt,
  ) async {
    final localPublicId = 'local-${_crypto.sha256Hex(publicKey.codeUnits).substring(0, 16)}';
    final identity = LocalIdentity(
      publicId: localPublicId,
      displayName: displayName,
      publicKey: publicKey,
      createdAt: createdAt,
      registeredOnGateway: false,
    );
    await save(identity);
    return identity;
  }
}
