import 'package:flutter/material.dart';

import '../../core/app/app_scope.dart';
import '../../data/models/gateway_dtos.dart';
import '../../shared/widgets/avatar_widget.dart';

/// Contacts issus de la passerelle (admin-service).
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<GatewayUser> _users = [];
  String? _myPublicId;
  bool _loading = true;
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
      final users = await services.gateway.fetchUsers();
      if (!mounted) return;
      setState(() {
        _myPublicId = identity?.publicId;
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = _users.where((u) => u.publicId != _myPublicId).toList();
    final me = _users.where((u) => u.publicId == _myPublicId).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _buildBody(context, me, others),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<GatewayUser> me,
    List<GatewayUser> others,
  ) {
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (me.isNotEmpty) ...[
          _header(context, 'Mon identité'),
          _tile(context, me.first, isSelf: true),
        ],
        _header(context, 'Utilisateurs passerelle · ${others.length}'),
        if (others.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Aucun autre utilisateur enregistré sur la passerelle.',
              textAlign: TextAlign.center,
            ),
          )
        else
          ...others.map((u) => _tile(context, u)),
      ],
    );
  }

  Widget _header(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.4,
              ),
        ),
      );

  Widget _tile(BuildContext context, GatewayUser user, {bool isSelf = false}) {
    final verified = user.status == 'active';
    return ListTile(
      leading: AvatarWidget(name: user.displayName),
      title: Row(
        children: [
          Flexible(
            child: Text(user.displayName, overflow: TextOverflow.ellipsis),
          ),
          if (isSelf) ...[
            const SizedBox(width: 6),
            Chip(
              label: const Text('moi', style: TextStyle(fontSize: 10)),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          Icon(
            verified ? Icons.verified_user : Icons.gpp_bad,
            size: 14,
            color: verified ? Colors.green.shade700 : Colors.red.shade700,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              user.publicKey,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
