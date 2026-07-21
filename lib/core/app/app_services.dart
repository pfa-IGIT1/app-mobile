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

  Future<bool> pingGateway() => gateway.ping();

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
