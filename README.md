# Application mobile — Flutter (§5)

Messagerie et partage de fichiers. L’appareil se connecte en **WiFi local** au hotspot de la passerelle Raspberry Pi — sans Internet, sans radio LoRa.

## Choix retenus (synthèse)

- Flutter (plutôt que React Native) — Dart unique, perf ARM native
- Hors-ligne : `sqflite` (cache local en clair)
- Réseau local : `http`, `multicast_dns` (mDNS)
- Chiffrement : `cryptography` (Ed25519, X25519, AES-256-GCM) + `flutter_secure_storage`
- Environnement validé : Flutter 3.44 + VS Code, téléphone USB

## État (implémenté)

- **Cryptographie E2E** : génération Ed25519 (signature) + X25519 (accord de clé),
  chiffrement X25519→HKDF→AES-256-GCM. Clé privée dans le stockage sécurisé du
  système (`KeyStore`). Voir `test/crypto_service_test.dart`.
- **Identité** : la clé publique combinée (`pfa:v1:<ed>:<x>`) est enregistrée sur
  la passerelle ; la clé privée ne quitte jamais l'appareil.
- **Messagerie** : envoi chiffré, réception + déchiffrement. La passerelle
  n'exposant que des UUID internes, l'expéditeur est identifié « à l'aveugle »
  (essai des clés connues jusqu'à validation du MAC).
- **Fichiers** : envoi chiffré (sélection via `file_picker`), téléchargement +
  déchiffrement + enregistrement local.
- **Hors-ligne** : cache SQLite (clair) + file d'attente rejouée au retour de la
  passerelle (`SyncService`).
- **Découverte** : mDNS (`_pfa-gateway._tcp`) + configuration manuelle de l'hôte
  dans Réglages. Quasi-temps réel par interrogation périodique (l'admin-service
  n'expose pas de WebSocket).

## Cache local (§6, §11)

Le téléphone stocke le **clair** (bout-en-bout). La passerelle ne voit que du chiffré ; la blockchain n’ancre que des empreintes.

## Lancer

```bash
flutter pub get
flutter run
```
