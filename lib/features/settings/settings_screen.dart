import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/app/app_scope.dart';
import '../../core/identity/local_identity.dart';
import '../../shared/widgets/avatar_widget.dart';

/// Réglages : identité locale synchronisée avec la passerelle.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  LocalIdentity? _identity;
  bool _gatewayOnline = false;
  bool _started = false;
  bool _discovering = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final identity = await services.identity.load();
    final online = await services.pingGateway();
    if (!mounted) return;
    setState(() {
      _identity = identity;
      _gatewayOnline = online;
    });
  }

  String _formatDate(DateTime date) {
    const months = [
      'jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _truncateKey(String key) {
    if (key.length <= 20) return key;
    return '${key.substring(0, 12)}…${key.substring(key.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identity = _identity;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Réglages'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: identity == null
          ? Center(
              child: Text(
                'Aucune identité locale.\nRelancez l\'onboarding.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            )
          : ListView(
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Column(
                    children: [
                      AvatarWidget(name: identity.displayName, radius: 36),
                      const SizedBox(height: 12),
                      Text(identity.displayName, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _gatewayOnline ? Icons.router : Icons.wifi_off,
                            size: 14,
                            color: _gatewayOnline
                                ? Colors.green.shade700
                                : Colors.orange.shade800,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _gatewayOnline ? 'passerelle connectée' : 'passerelle hors-ligne',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _gatewayOnline
                                  ? Colors.green.shade700
                                  : Colors.orange.shade800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const _Section('Profil'),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Nom affiché'),
                  subtitle: Text(identity.displayName),
                ),
                ListTile(
                  leading: const Icon(Icons.badge),
                  title: const Text('ID passerelle'),
                  subtitle: Text(
                    identity.publicId,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.key),
                  title: const Text('Clé publique'),
                  subtitle: Text(
                    _truncateKey(identity.publicKey),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                  trailing: const Icon(Icons.qr_code_2, size: 22),
                  onTap: () => _showQrCode(identity),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_today),
                  title: const Text('Identité créée'),
                  subtitle: Text(_formatDate(identity.createdAt)),
                ),
                const _Section('Passerelle'),
                ListTile(
                  leading: const Icon(Icons.dns),
                  title: const Text('Hôte'),
                  subtitle: Text(
                    '${AppScope.of(context).gateway.host}:${AppScope.of(context).gateway.port}',
                  ),
                  trailing: const Icon(Icons.edit, size: 18),
                  onTap: _editEndpoint,
                ),
                ListTile(
                  leading: _discovering
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_find),
                  title: const Text('Rechercher la passerelle (mDNS)'),
                  subtitle: const Text('Détection automatique sur le WiFi local'),
                  onTap: _discovering ? null : _discover,
                ),
                const _Section('Identité'),
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Afficher mon QR code'),
                  subtitle: const Text('À faire scanner par un autre appareil'),
                  onTap: () => _showQrCode(identity),
                ),
                ListTile(
                  leading: const Icon(Icons.ios_share),
                  title: const Text('Partager ma clé publique'),
                  subtitle: const Text('Envoyer via WhatsApp, e-mail…'),
                  onTap: () => _sharePublicKey(identity),
                ),
                ListTile(
                  leading: Icon(Icons.logout, color: theme.colorScheme.error),
                  title: Text(
                    'Réinitialiser l\'identité',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  subtitle: const Text(
                    'Supprime la clé privée de cet appareil (irréversible)',
                  ),
                  onTap: _resetIdentity,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }

  Future<void> _editEndpoint() async {
    final services = AppScope.of(context);
    final hostCtrl = TextEditingController(text: services.gateway.host);
    final portCtrl =
        TextEditingController(text: services.gateway.port.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adresse de la passerelle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: hostCtrl,
              decoration: const InputDecoration(labelText: 'Hôte / IP'),
            ),
            TextField(
              controller: portCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Port'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final port = int.tryParse(portCtrl.text.trim()) ?? services.gateway.port;
    await services.setGatewayEndpoint(hostCtrl.text.trim(), port);
    await _load();
    _snack('Passerelle : ${hostCtrl.text.trim()}:$port');
  }

  Future<void> _discover() async {
    setState(() => _discovering = true);
    final services = AppScope.of(context);
    try {
      final found = await services.discoverGateway();
      if (!mounted) return;
      if (found != null) {
        await _load();
        _snack('Passerelle trouvée : $found');
      } else {
        _snack('Aucune passerelle détectée sur le réseau local.');
      }
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _resetIdentity() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Réinitialiser l\'identité ?'),
        content: const Text(
          'La clé privée sera supprimée de cet appareil. Sans sauvegarde, '
          'l\'identité de validateur est définitivement perdue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await AppScope.of(context).identity.clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
  }

  Future<void> _showQrCode(LocalIdentity identity) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: const Text('Ma clé publique'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                identity.displayName,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SizedBox(
                  width: 240,
                  height: 240,
                  child: PrettyQrView.data(
                    data: identity.publicKey,
                    errorCorrectLevel: QrErrorCorrectLevel.M,
                    decoration: const PrettyQrDecoration(
                      shape: PrettyQrSmoothSymbol(color: Color(0xFF122019)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Faites scanner ce code par un autre appareil pour partager '
                'votre identité chiffrée.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _sharePublicKey(identity);
              },
              icon: const Icon(Icons.ios_share, size: 18),
              label: const Text('Partager'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _sharePublicKey(LocalIdentity identity) async {
    await Share.share(
      identity.publicKey,
      subject: 'Clé publique TraNaSi — ${identity.displayName}',
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
        ),
      );
}
