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
    final name = await _askDisplayName();
    if (name == null || name.trim().isEmpty || !mounted) return;

    setState(() => _loading = true);
    final services = AppScope.of(context);

    try {
      await services.identity.createAndRegister(name.trim());
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, App.routeHome);
    } on GatewayException catch (e) {
      if (!mounted) return;
      _showError(
        'Passerelle injoignable (${e.statusCode}). '
        'Vérifiez que admin-service tourne sur le port 3001.',
      );
    } catch (e) {
      if (!mounted) return;
      _showError('Impossible de créer l\'identité : $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askDisplayName() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Votre nom affiché'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Ex. Moussa Sissao',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Continuer'),
          ),
        ],
      ),
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
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
