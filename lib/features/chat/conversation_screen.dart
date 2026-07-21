import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../core/app/app_scope.dart';
import '../../core/network/gateway_client.dart';
import '../../core/network/gateway_socket.dart';
import '../../data/models/message.dart';
import '../../shared/widgets/message_bubble.dart';

/// Conversation avec un contact : envoi/réception via la passerelle.
class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.contactPublicId,
    required this.contactName,
    required this.contactPublicKey,
  });

  final String contactPublicId;
  final String contactName;
  final String contactPublicKey;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _composer = TextEditingController();
  final _uuid = const Uuid();
  final _live = GatewayLiveUpdates();

  List<Message> _lines = [];
  bool _loading = true;
  bool _sending = false;
  bool _gatewayOnline = false;
  bool _fromCache = false;
  String? _error;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadMessages();
      // Quasi-temps réel : rafraîchit discrètement la conversation.
      _live.start(() => _loadMessages(silent: true));
    }
  }

  @override
  void dispose() {
    _live.dispose();
    _composer.dispose();
    super.dispose();
  }

  Future<void> _loadMessages({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    final services = AppScope.of(context);
    final identity = await services.identity.load();
    if (identity == null) {
      if (!mounted) return;
      setState(() {
        _error = 'Identité locale introuvable';
        _loading = false;
      });
      return;
    }

    try {
      final directory = await services.gateway.fetchUsers();
      final messages = await services.messageRepository.syncConversation(
        myPublicId: identity.publicId,
        contactPublicId: widget.contactPublicId,
        directory: directory,
      );
      if (!mounted) return;
      setState(() {
        _lines = messages;
        _loading = false;
        _gatewayOnline = true;
        _fromCache = false;
      });
    } catch (e) {
      // Hors-ligne : on se rabat sur le cache local (clair).
      final cached = await services.messageRepository
          .cachedConversation(widget.contactPublicId);
      if (!mounted) return;
      setState(() {
        _lines = cached;
        _loading = false;
        _gatewayOnline = false;
        _fromCache = cached.isNotEmpty;
        _error = cached.isEmpty ? '$e' : null;
      });
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty || _sending) return;

    final services = AppScope.of(context);
    final identity = await services.identity.load();
    if (identity == null) return;

    setState(() => _sending = true);
    _composer.clear();

    final optimistic = Message(
      id: _uuid.v4(),
      contactId: widget.contactPublicId,
      content: text,
      sentAt: DateTime.now(),
      isMine: true,
    );
    setState(() => _lines = [..._lines, optimistic]);

    try {
      await services.messageRepository.send(
        optimistic,
        senderPublicId: identity.publicId,
        recipientPublicId: widget.contactPublicId,
        recipientPublicKey: widget.contactPublicKey,
      );
      if (!mounted) return;
      setState(() => _gatewayOnline = true);
      await _loadMessages();
    } on GatewayException catch (e) {
      if (!mounted) return;
      setState(() {
        _lines = _lines.where((l) => l.id != optimistic.id).toList();
        _gatewayOnline = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_describeGatewayError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _lines = _lines.where((l) => l.id != optimistic.id).toList());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _describeGatewayError(GatewayException e) {
    if (e.body.contains('CONTENT_HASH_MISMATCH')) {
      return 'Intégrité refusée par la passerelle (hash).';
    }
    if (e.body.contains('USER_REVOKED')) return 'Ce contact est révoqué.';
    if (e.body.contains('INVALID_DESTINATION')) return 'Destinataire invalide.';
    return 'Envoi échoué (${e.statusCode}).';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.contactName, style: theme.textTheme.titleMedium),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _gatewayOnline ? Icons.lock : Icons.wifi_off,
                  size: 12,
                  color: _gatewayOnline ? Colors.green.shade700 : Colors.orange.shade800,
                ),
                const SizedBox(width: 4),
                Text(
                  _gatewayOnline
                      ? 'chiffré · via passerelle'
                      : (_fromCache ? 'hors-ligne · cache' : 'hors-ligne'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _gatewayOnline ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadMessages,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessages(theme)),
          _Composer(
            theme: theme,
            controller: _composer,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, textAlign: TextAlign.center),
        ),
      );
    }
    if (_lines.isEmpty) {
      return Center(
        child: Text(
          'Aucun message.\nEnvoyez le premier via la passerelle.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _lines.length,
      itemBuilder: (_, i) {
        final line = _lines[i];
        return MessageBubble(text: line.content, isMine: line.isMine);
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.theme,
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final ThemeData theme;
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !sending,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: sending ? null : onSend,
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
