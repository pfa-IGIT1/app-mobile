import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../core/app/app_scope.dart';
import '../../core/config/constants.dart';
import '../../core/crypto/crypto_keys.dart';
import '../../core/network/gateway_client.dart';
import '../../core/storage/user_file_storage.dart';
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

    _myPublicId = identity.publicId;

    // Annuaire : toujours rafraîchi, même si la liste des fichiers échoue.
    List<GatewayUser> directory = _directory;
    try {
      directory = await services.gateway.fetchUsers();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Passerelle injoignable : $e';
      });
      return;
    }

    try {
      final files = await services.fileRepository.listForUser(identity.publicId);
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _files = files;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      final cached = await services.fileRepository.cached();
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _files = cached;
        _loading = false;
        _error = cached.isEmpty ? '$e' : null;
      });
    }
  }

  /// Recharge l'annuaire avant l'envoi (l'onglet peut être resté ouvert sans
  /// actualisation alors que Messages a déjà chargé les contacts).
  Future<List<GatewayUser>> _refreshDirectory() async {
    final services = AppScope.of(context);
    final identity = await services.identity.load();
    if (identity == null) return _directory;

    try {
      final directory = await services.gateway.fetchUsers();
      if (mounted) {
        setState(() {
          _myPublicId = identity.publicId;
          _directory = directory;
        });
      }
      return directory;
    } catch (_) {
      return _directory;
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
          trailing: IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Télécharger',
            onPressed: _busy ? null : () => _downloadFile(f),
          ),
          onTap: _busy ? null : () => _openFile(f),
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
    if (bytes.length > AppConstants.maxUploadBytes) {
      _snack(
        'Fichier trop volumineux (${_formatSize(bytes.length)}). '
        'Maximum : ${_formatSize(AppConstants.maxUploadBytes)}.',
      );
      return;
    }
    if (!mounted) return;

    setState(() => _busy = true);
    final services = AppScope.of(context);
    try {
      if (!await services.pingGateway()) {
        _snack(
          'Passerelle injoignable (${services.gateway.host}:${services.gateway.port}). '
          'Vérifiez le WiFi mesh puis réessayez.',
        );
        return;
      }

      await services.fileRepository.send(
        bytes: bytes,
        filename: file.name,
        mimeType: _mimeFromName(file.name),
        senderPublicId: _myPublicId!,
        recipientPublicId: recipient.publicId,
        recipientPublicKey: recipient.publicKey,
      );
      await UserFileStorage.saveBytes(
        bytes: bytes,
        filename: file.name,
        subfolder: 'envoyes',
      );
      final localHint = await UserFileStorage.displayPath('envoyes');
      _snack(
        '« ${file.name} » envoyé à ${recipient.displayName}.\n'
        'Copie locale : $localHint',
      );
      await _load();
    } on GatewayException catch (e) {
      _snack(_describeSendError(e));
      await _load();
    } on TimeoutException catch (e) {
      _snack(_describeSendError(e));
      await _load();
    } catch (e) {
      _snack(_describeSendError(e));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<GatewayUser?> _pickRecipient() async {
    final directory = await _refreshDirectory();
    final active = directory
        .where((u) => u.publicId != _myPublicId && u.status == 'active')
        .toList();

    if (active.isEmpty) {
      _snack(
        'Aucun contact actif sur la passerelle. '
        'Vérifiez que l\'autre téléphone est bien enregistré, puis actualisez.',
      );
      return null;
    }

    final e2eCapable = active
        .where((u) => PublicKeyBundle.isE2ECapable(u.publicKey))
        .toList();

    // Même annuaire que Messages : on affiche tous les contacts actifs.
    final candidates = active;

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
            if (e2eCapable.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Les contacts ci-dessous n\'ont pas encore de clé E2E '
                  'compatible (format pfa:v1). Réenregistrez-les via l\'app.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ),
            for (final u in candidates)
              ListTile(
                leading: Icon(
                  PublicKeyBundle.isE2ECapable(u.publicKey)
                      ? Icons.person
                      : Icons.person_off_outlined,
                ),
                title: Text(u.displayName),
                subtitle: PublicKeyBundle.isE2ECapable(u.publicKey)
                    ? null
                    : const Text('Clé non compatible E2E'),
                enabled: PublicKeyBundle.isE2ECapable(u.publicKey),
                onTap: PublicKeyBundle.isE2ECapable(u.publicKey)
                    ? () => Navigator.pop(ctx, u)
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Téléchargement (enregistre dans Téléchargements/TraNaSi, sans ouvrir)
  // ---------------------------------------------------------------------------

  Future<void> _downloadFile(FileItem item) async {
    setState(() => _busy = true);
    final services = AppScope.of(context);
    try {
      final decrypted = await services.fileRepository
          .download(item, directory: _directory);
      await UserFileStorage.saveBytes(
        bytes: decrypted.bytes,
        filename: decrypted.name,
        subfolder: item.isMine ? 'envoyes' : 'recus',
      );
      final localHint = await UserFileStorage.displayPath(
        item.isMine ? 'envoyes' : 'recus',
      );
      _snack('« ${item.name} » enregistré dans $localHint');
    } catch (e) {
      _snack('Téléchargement échoué : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Ouverture (appui sur la ligne — n'enregistre pas dans Téléchargements)
  // ---------------------------------------------------------------------------

  Future<void> _openFile(FileItem item) async {
    setState(() => _busy = true);
    final services = AppScope.of(context);
    try {
      var localPath = await UserFileStorage.findAnywhere(
        item.name,
        preferSent: item.isMine,
      );

      if (localPath == null) {
        final decrypted = await services.fileRepository
            .download(item, directory: _directory);
        localPath = await UserFileStorage.saveToCache(
          bytes: decrypted.bytes,
          filename: decrypted.name,
        );
      }

      if (!mounted) return;
      final result = await OpenFilex.open(localPath);
      if (!mounted) return;

      if (result.type != ResultType.done) {
        _snack(
          result.message.isNotEmpty
              ? result.message
              : 'Aucune application pour ouvrir « ${item.name} ».',
        );
      }
    } catch (e) {
      _snack('Impossible d\'ouvrir le fichier : $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Utilitaires
  // ---------------------------------------------------------------------------

  String _describeSendError(Object error) {
    final msg = error.toString();
    if (msg.contains('413') || msg.contains('entity too large')) {
      return 'Fichier trop volumineux pour la passerelle. '
          'Essayez un fichier de moins de ${_formatSize(AppConstants.maxUploadBytes)}.';
    }
    if (error is TimeoutException || msg.contains('TimeoutException')) {
      return 'Envoi interrompu (délai dépassé). '
          'Vérifiez le WiFi mesh ou essayez un fichier plus petit.';
    }
    if (msg.contains('Connection reset') ||
        msg.contains('SocketException') ||
        msg.contains('ClientException')) {
      return 'Connexion coupée avec la passerelle pendant l\'envoi. '
          'L\'app réessaie automatiquement ; si l\'erreur persiste, '
          'rapprochez-vous du routeur mesh et actualisez la liste.';
    }
    return 'Envoi échoué : $error';
  }

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
