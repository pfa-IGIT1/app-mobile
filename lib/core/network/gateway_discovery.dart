import 'package:multicast_dns/multicast_dns.dart';

import '../config/constants.dart';

/// Point d'accès (hôte + port) d'une passerelle découverte sur le réseau local.
class GatewayEndpoint {
  const GatewayEndpoint({required this.host, required this.port});
  final String host;
  final int port;

  @override
  String toString() => '$host:$port';
}

/// Découverte de la passerelle sur le WiFi local via mDNS (§5).
///
/// La passerelle annonce le service `_pfa-gateway._tcp`. On évite ainsi toute
/// IP codée en dur : le téléphone trouve la passerelle dès qu'il rejoint le
/// point d'accès Raspberry Pi.
class GatewayDiscovery {
  const GatewayDiscovery();

  Future<GatewayEndpoint?> discover({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final service = '${AppConstants.gatewayMdnsService}.local';
    final client = MDnsClient();
    try {
      await client.start();
      final deadline = DateTime.now().add(timeout);

      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(service),
      )) {
        if (DateTime.now().isAfter(deadline)) break;
        await for (final srv in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
        )) {
          await for (final ip in client.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
          )) {
            return GatewayEndpoint(
              host: ip.address.address,
              port: srv.port,
            );
          }
        }
      }
    } catch (_) {
      // mDNS indisponible (émulateur, permissions…) : on renvoie null.
    } finally {
      client.stop();
    }
    return null;
  }
}
