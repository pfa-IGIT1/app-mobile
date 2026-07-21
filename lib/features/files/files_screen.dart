import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/app/app_scope.dart';
import '../../core/crypto/crypto_keys.dart';
import '../../data/models/file_item.dart';
import '../../data/models/gateway_dtos.dart';

/// Onglet Fichiers : fichiers chiffrés échangés via la passerelle.
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key});

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  int _filter = 0; // 0 tous, 1 reçus, 2 envoyés
  List<FileItem> _files = [];
  List<GatewayUser> _directory = [];
  String? _myPublicId;
  bool _loading = true;
  bool _busy = false;
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
      final files = await services.fileRepository.listForUser(identity.publicId);
      if (!mounted) return;
      setState(() {
        _myPublicId = identity.publicId;
        _directory = directory;
        _files = files;
        _loading = false;
      });
    } catch (e) {
      final cached = await services.fileRepository.cached();
      if (!mounted) return;
      setState(() {
        _myPublicId = identity.publicId;
        _files = cached;
        _loading = false;
        _error = cached.isEmpty ? '$e' : null;
      });
    }
  }

  List<FileItem> get _visible => switch (_filter) {
        1 => _files.where((f) => !f.isMine).toList(),
        2 => _files.where((f) => f.isMine).toList(),
        _ => _files,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fichiers'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _sendFileFlow,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.upload_file),
        label: const Text('Envoyer'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                for (final (i, label) in ['Tous', 'Reçus', 'Envoyés'].indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == i,
                      onSelected: (_) => setState(() => _filter = i),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody(theme)),
        ],
      ),
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
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Réessayer')),
            ],
          ),
        ),
      );
    }
    final visible = _visible;
    if (visible.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Aucun fichier.\nEnvoyez un fichier chiffré via le bouton ci-dessous.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (_, i) {
        final f = visible[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: Icon(_iconFor(f), color: theme.colorScheme.onSurfaceVariant),
          ),
          title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${_formatSize(f.size)} · ${f.isMine ? 'envoyé' : 'reçu'} · ${_formatDate(f.receivedAt)}',
          ),
          trailing: const Icon(Icons.download),
          onTap: _busy ? null : () => _downloadFile(f),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Envoi
  // ---------------------------------------------------------------------------

  Future<void> _sendFileFlow() async {
    final recipient = await _pickRecipient();
    if (recipient == null || !mounted) return;

    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes ??
        (file.path != null ? await File(file.path!).readAsBytes() : null);
    if (bytes == null) {
      _snack('Impossible de lire le fichier sélectionné.');
      return;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    final services = AppScope.of(context);
    try {
      await services.fileRepository.send(
        bytes: bytes,
        filename: file.name,
        mimeType: _mimeFromName(file.name),
        senderPublicId: _myPublicId!,
        recipientPublicId: recipient.publicId,
        recipientPublicKey: recipient.publicKey,
      );
      _snack('« ${file.name} » chiffré et envoyé à ${recipient.displayName}.');
      await _load();
    } catch (e) {
      _snack('Envoi échoué : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<GatewayUser?> _pickRecipient() async {
    final candidates = _directory
        .where((u) =>
            u.publicId != _myPublicId &&
            u.status == 'active' &&
            PublicKeyBundle.isE2ECapable(u.publicKey))
        .toList();
    if (candidates.isEmpty) {
      _snack('Aucun destinataire compatible E2E enregistré.');
      return null;
    }
    return showModalBottomSheet<GatewayUser>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Envoyer à…',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            for (final u in candidates)
              ListTile(
                leading: const Icon(Icons.person),
                title: Text(u.displayName),
                onTap: () => Navigator.pop(ctx, u),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Téléchargement + déchiffrement
  // ---------------------------------------------------------------------------

  Future<void> _downloadFile(FileItem item) async {
    setState(() => _busy = true);
    final services = AppScope.of(context);
    try {
      final decrypted = await services.fileRepository
          .download(item, directory: _directory);
      final dir = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(dir.path, 'pfa_downloads'));
      await outDir.create(recursive: true);
      final outPath = p.join(outDir.path, decrypted.name);
      await File(outPath).writeAsBytes(decrypted.bytes);
      _snack('Déchiffré et enregistré : $outPath');
    } catch (e) {
      _snack('Téléchargement échoué : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------------

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  IconData _iconFor(FileItem f) {
    final ext = p.extension(f.name).toLowerCase();
    if (['.png', '.jpg', '.jpeg', '.gif', '.webp'].contains(ext)) {
      return Icons.image;
    }
    if (['.pdf', '.doc', '.docx', '.txt'].contains(ext)) return Icons.description;
    if (['.xls', '.xlsx', '.csv'].contains(ext)) return Icons.table_chart;
    if (['.bin', '.img'].contains(ext)) return Icons.memory;
    return Icons.insert_drive_file;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  String? _mimeFromName(String name) {
    final ext = p.extension(name).toLowerCase();
    return switch (ext) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.jpg' || '.jpeg' => 'image/jpeg',
      '.txt' => 'text/plain',
      '.csv' => 'text/csv',
      _ => null,
    };
  }
}
