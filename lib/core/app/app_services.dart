import '../config/constants.dart';
import '../config/gateway_host.dart';
import '../crypto/crypto_service.dart';
import '../crypto/key_store.dart';
import '../database/app_database.dart';
import '../database/daos/contacts_dao.dart';
import '../database/daos/files_dao.dart';
import '../database/daos/messages_dao.dart';
import '../database/daos/sync_dao.dart';
import '../identity/identity_service.dart';
import '../network/gateway_client.dart';
import '../network/gateway_discovery.dart';
import '../network/wifi_binding.dart';
import '../sync/sync_service.dart';
import '../../data/repositories/contact_repository.dart';
import '../../data/repositories/file_repository.dart';
import '../../data/repositories/message_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Point d'entrée des dépendances partagées de l'application.
class AppServices {
  AppServices._({
    required this.gateway,
    required this.identity,
    required this.crypto,
    required this.keyStore,
    required this.database,
    required this.discovery,
    required this.messagesDao,
    required this.contactsDao,
    required this.filesDao,
    required this.syncDao,
    required this.messageRepository,
    required this.contactRepository,
    required this.fileRepository,
    required this.syncService,
  });

  static const _hostPrefsKey = 'gateway_host';
  static const _portPrefsKey = 'gateway_port';
  static const _enrollPrefsKey = 'enroll_code';

  final GatewayClient gateway;
  final IdentityService identity;
  final CryptoService crypto;
  final KeyStore keyStore;
  final AppDatabase database;
  final GatewayDiscovery discovery;
  final MessagesDao messagesDao;
  final ContactsDao contactsDao;
  final FilesDao filesDao;
  final SyncDao syncDao;
  final MessageRepository messageRepository;
  final ContactRepository contactRepository;
  final FileRepository fileRepository;
  final SyncService syncService;

  static Future<AppServices> create() async {
    final prefs = await SharedPreferences.getInstance();
    final gateway = GatewayClient(
      host: prefs.getString(_hostPrefsKey) ?? resolveDefaultGatewayHost(),
      port: prefs.getInt(_portPrefsKey) ?? AppConstants.gatewayPort,
    );
    final keyStore = KeyStore();
    final crypto = CryptoService(keyStore);
    final database = AppDatabase();
    final messagesDao = MessagesDao(database);
    final contactsDao = ContactsDao(database);
    final filesDao = FilesDao(database);
    final syncDao = SyncDao(database);
    final identity = IdentityService(gateway, crypto, keyStore);

    // Chaque requête est signée avec la clé Ed25519 de l'utilisateur
    // (MOBILE_AUTH=enforce côté passerelle).
    gateway.enrollCode = prefs.getString(_enrollPrefsKey);
    gateway.configureAuth(
      keyId: () async => (await identity.load())?.publicId,
      sign: crypto.sign,
    );
    // Android : forcer le trafic sur le WiFi du dongle (voir wifi_binding.dart).
    await WifiBinding.bindToWifi();

    final messageRepository = MessageRepository(
      messagesDao: messagesDao,
      syncDao: syncDao,
      crypto: crypto,
      gateway: gateway,
    );
    final contactRepository = ContactRepository(contactsDao: contactsDao);
    final fileRepository = FileRepository(
      filesDao: filesDao,
      crypto: crypto,
      gateway: gateway,
    );
    final syncService = SyncService(
      syncDao: syncDao,
      gatewayClient: gateway,
    );

    return AppServices._(
      gateway: gateway,
      identity: identity,
      crypto: crypto,
      keyStore: keyStore,
      database: database,
      discovery: const GatewayDiscovery(),
      messagesDao: messagesDao,
      contactsDao: contactsDao,
      filesDao: filesDao,
      syncDao: syncDao,
      messageRepository: messageRepository,
      contactRepository: contactRepository,
      fileRepository: fileRepository,
      syncService: syncService,
    );
  }

  /// Ping de la passerelle. Rebranche d'abord le trafic sur le WiFi : le
  /// téléphone a pu changer de réseau depuis le dernier appel.
  Future<bool> pingGateway() async {
    await WifiBinding.bindToWifi();
    if (await gateway.ping()) return true;
    return _autoResolveGateway();
  }

  /// L'hôte courant ne répond pas (adresse du dongle changée ?) : on essaie
  /// 1) la passerelle DHCP du WiFi (= le dongle), 2) mDNS. Un candidat n'est
  /// retenu et mémorisé que s'il répond à `/health`.
  Future<bool> _autoResolveGateway() async {
    final candidates = <GatewayEndpoint>[];
    final dhcp = await WifiBinding.gatewayAddress();
    if (dhcp != null && dhcp.isNotEmpty) {
      candidates.add(GatewayEndpoint(host: dhcp, port: gateway.port));
    }
    final mdns = await discovery.discover(timeout: const Duration(seconds: 2));
    if (mdns != null) candidates.add(mdns);

    final prevHost = gateway.host;
    final prevPort = gateway.port;
    for (final c in candidates) {
      if (c.host == prevHost && c.port == prevPort) continue;
      gateway.host = c.host;
      gateway.port = c.port;
      if (await gateway.ping()) {
        await setGatewayEndpoint(c.host, c.port);
        return true;
      }
    }
    gateway.host = prevHost;
    gateway.port = prevPort;
    return false;
  }

  /// Code d'inscription demandé par la passerelle (vide = aucun).
  Future<void> setEnrollCode(String? code) async {
    final value = code?.trim();
    gateway.enrollCode = (value == null || value.isEmpty) ? null : value;
    final prefs = await SharedPreferences.getInstance();
    if (gateway.enrollCode == null) {
      await prefs.remove(_enrollPrefsKey);
    } else {
      await prefs.setString(_enrollPrefsKey, gateway.enrollCode!);
    }
  }

  /// Fixe manuellement l'hôte/port de la passerelle et le mémorise.
  Future<void> setGatewayEndpoint(String host, int port) async {
    gateway.host = host;
    gateway.port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostPrefsKey, host);
    await prefs.setInt(_portPrefsKey, port);
  }

  /// Cherche la passerelle par mDNS ; en cas de succès, l'applique et la garde.
  /// Renvoie l'endpoint trouvé, ou `null`.
  Future<GatewayEndpoint?> discoverGateway() async {
    final found = await discovery.discover();
    if (found != null) {
      await setGatewayEndpoint(found.host, found.port);
    }
    return found;
  }
}
