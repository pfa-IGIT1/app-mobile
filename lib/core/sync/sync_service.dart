// Libellés d'arguments publics conservés (syncDao/gatewayClient) : on garde
// donc l'affectation explicite plutôt que des formels d'initialisation privés.
// ignore_for_file: prefer_initializing_formals
import '../database/daos/sync_dao.dart';
import '../network/gateway_client.dart';

/// Rejoue le mempool local quand la passerelle redevient joignable.
class SyncService {
  SyncService({
    required SyncDao syncDao,
    required GatewayClient gatewayClient,
  })  : _syncDao = syncDao,
        _gatewayClient = gatewayClient;

  final SyncDao _syncDao;
  final GatewayClient _gatewayClient;

  bool _running = false;

  /// Pousse les transactions en attente. Renvoie le nombre effectivement envoyé.
  Future<int> syncPending() async {
    if (_running) return 0;
    _running = true;
    var sent = 0;
    try {
      final pending = await _syncDao.getPendingTransactions();
      for (final tx in pending) {
        try {
          await _gatewayClient.sendTransaction(tx);
          await _syncDao.markSynced(tx['id'] as String);
          sent++;
        } catch (_) {
          // Toujours hors ligne / erreur : on garde la transaction pour plus tard.
          break;
        }
      }
    } finally {
      _running = false;
    }
    return sent;
  }
}
