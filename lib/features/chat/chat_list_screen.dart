import 'package:flutter/material.dart';

import '../../core/app/app_scope.dart';
import '../../data/models/gateway_dtos.dart';
import '../../shared/widgets/avatar_widget.dart';
import 'conversation_screen.dart';

/// Liste des conversations : contacts issus de la passerelle (admin-service).
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<GatewayUser> _contacts = [];
  bool _loading = true;
  bool _gatewayOnline = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final services = AppScope.of(context);
    final identity = await services.identity.load();

    try {
      _gatewayOnline = await services.pingGateway();
      if (_gatewayOnline) {
        // Passerelle joignable : on rejoue les envois mis en attente hors-ligne.
        await services.syncService.syncPending();
      }
      final users = await services.gateway.fetchUsers();
      final me = identity?.publicId;
      if (!mounted) return;
      setState(() {
        _contacts = users.where((u) => u.publicId != me && u.status == 'active').toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
        _gatewayOnline = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: Icon(
                _gatewayOnline ? Icons.router : Icons.wifi_off,
                size: 16,
                color: _gatewayOnline ? Colors.green.shade700 : Colors.orange.shade800,
              ),
              label: Text(_gatewayOnline ? 'passerelle' : 'hors-ligne'),
              labelStyle: const TextStyle(fontSize: 12),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text('Passerelle injoignable', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    if (_contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aucun contact sur la passerelle.\n'
            'Les utilisateurs enregistrés via l\'app ou le seed admin-service apparaîtront ici.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _contacts.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, i) {
        final c = _contacts[i];
        return ListTile(
          leading: AvatarWidget(name: c.displayName),
          title: Text(c.displayName),
          subtitle: Row(
            children: [
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.lock, size: 13),
              ),
              Expanded(
                child: Text(
                  c.publicKey,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ConversationScreen(
                contactPublicId: c.publicId,
                contactName: c.displayName,
                contactPublicKey: c.publicKey,
              ),
            ),
          ),
        );
      },
    );
  }
}
