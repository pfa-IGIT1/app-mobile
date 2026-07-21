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

  /// Identité enregistrée sur la passerelle (pas un profil local de repli).
  bool _isRegistered(LocalIdentity identity) {
    return identity.registeredOnGateway && !identity.publicId.startsWith('local-');
  }

  /// Une identité complète existe-t-elle (profil + clé privée + passerelle) ?
  ///
  /// Les identités locales créées hors-ligne (ancien mode démo) sont
  /// automatiquement supprimées pour renvoyer vers l'onboarding.
  Future<bool> isInitialised() async {
    final identity = await load();
    final hasKeys = await _keyStore.hasKeys();

    if (identity == null) {
      if (hasKeys) await _keyStore.deleteKeys();
      return false;
    }

    if (!_isRegistered(identity) || !hasKeys) {
      await clear();
      return false;
    }

    return true;
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
    } on GatewayException catch (e) {
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
        // Récupération impossible : on propage l'erreur d'enregistrement.
      }
      await _keyStore.deleteKeys();
      throw e;
    } catch (e) {
      await _keyStore.deleteKeys();
      rethrow;
    }
  }
}
