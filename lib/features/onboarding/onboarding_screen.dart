import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/app/app_scope.dart';
import '../../core/network/gateway_client.dart';

/// 1er lancement : créer son identité et l'enregistrer sur la passerelle.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _loading = false;

  Future<void> _createIdentity() async {
    final services = AppScope.of(context);
    final form = await _askRegistration(services.gateway.enrollCode);
    if (form == null || form.name.trim().isEmpty || !mounted) return;

    setState(() => _loading = true);

    try {
      await services.setEnrollCode(form.enrollCode);
      await services.pingGateway(); // WiFi + redécouverte auto de l'adresse
      await services.identity.createAndRegister(form.name.trim());
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, App.routeHome);
    } on GatewayException catch (e) {
      if (!mounted) return;
      _showError(_describeGatewayError(e));
    } catch (e) {
      if (!mounted) return;
      _showError(
        'Passerelle injoignable. Le téléphone est-il connecté au WiFi du '
        'dongle (et l\'adresse de la passerelle correcte dans Réglages) ? '
        '($e)',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Adresse de la passerelle : nécessaire AVANT l'inscription (les Réglages ne
  /// sont accessibles qu'une fois l'identité créée).
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
    final host = hostCtrl.text.trim();
    if (host.isEmpty) return;
    final port = int.tryParse(portCtrl.text.trim()) ?? services.gateway.port;
    await services.setGatewayEndpoint(host, port);
    if (!mounted) return;
    setState(() {});
    final online = await services.pingGateway();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          online
              ? 'Passerelle joignable : $host:$port'
              : 'Passerelle injoignable : $host:$port (WiFi du dongle ?)',
        ),
      ),
    );
  }

  Future<void> _discover() async {
    setState(() => _loading = true);
    final services = AppScope.of(context);
    try {
      await services.pingGateway(); // rebranche le trafic sur le WiFi
      final found = await services.discoverGateway();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            found != null
                ? 'Passerelle trouvée : $found'
                : 'Aucune passerelle détectée par mDNS : saisissez son adresse.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Traduit un refus HTTP de la passerelle (elle EST joignable).
  String _describeGatewayError(GatewayException e) {
    final body = e.body;
    if (e.statusCode == 401 && body.contains('Code d')) {
      return 'Code d\'inscription manquant ou invalide.';
    }
    if (e.statusCode == 401 && body.contains('Horodatage')) {
      return 'Horloge déréglée : la passerelle refuse l\'horodatage de la '
          'requête (tolérance 300 s).';
    }
    if (e.statusCode == 401 || e.statusCode == 403) {
      return 'Inscription refusée par la passerelle (${e.statusCode}) : $body';
    }
    return 'Erreur de la passerelle (${e.statusCode}) : $body';
  }

  Future<({String name, String enrollCode})?> _askRegistration(
    String? currentCode,
  ) async {
    final nameController = TextEditingController();
    final codeController = TextEditingController(text: currentCode ?? '');
    return showDialog<({String name, String enrollCode})>(
      context: context,
      builder: (ctx) {
        void submit() => Navigator.pop(
              ctx,
              (name: nameController.text, enrollCode: codeController.text),
            );
        return AlertDialog(
          title: const Text('Votre nom affiché'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Ex. Moussa Sissao',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(
                  labelText: 'Code d\'inscription (si demandé)',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => submit(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(onPressed: submit, child: const Text('Continuer')),
          ],
        );
      },
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Icon(Icons.hub_outlined, size: 72, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              Text(
                'Réseau mesh sécurisé',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Communiquez en local, sans Internet. '
                'Votre identité est enregistrée sur la passerelle (admin-service).',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _loading ? null : _createIdentity,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.key),
                label: Text(_loading ? 'Enregistrement…' : 'Créer mon identité'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loading
                    ? null
                    : () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Import de clé : bientôt disponible'),
                          ),
                        ),
                icon: const Icon(Icons.download),
                label: const Text('Importer une identité'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _loading ? null : _editEndpoint,
                icon: const Icon(Icons.dns),
                label: Text(
                  'Passerelle : ${AppScope.of(context).gateway.host}:'
                  '${AppScope.of(context).gateway.port}',
                ),
              ),
              TextButton.icon(
                onPressed: _loading ? null : _discover,
                icon: const Icon(Icons.wifi_find),
                label: const Text('Rechercher la passerelle (mDNS)'),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
