import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Enregistre les fichiers dans un dossier visible depuis l'explorateur Android.
///
/// Cible : `Téléchargements/TraNaSi/envoyes/` et `.../recus/`.
class UserFileStorage {
  UserFileStorage._();

  static const folderName = 'TraNaSi';

  /// Chemin affiché à l'utilisateur (ex. « Téléchargements/TraNaSi/recus »).
  static Future<String> displayPath(String subfolder) async {
    final dir = await _resolveDir(subfolder);
    if (dir.path.contains('Download')) {
      return 'Téléchargements/$folderName/$subfolder';
    }
    return dir.path;
  }

  /// Écrit le fichier et renvoie le chemin absolu.
  static Future<String> saveBytes({
    required List<int> bytes,
    required String filename,
    required String subfolder,
  }) async {
    final dir = await _resolveDir(subfolder);
    final safeName = _safeFilename(filename);
    var outPath = p.join(dir.path, safeName);
    if (await File(outPath).exists()) {
      final stem = p.basenameWithoutExtension(safeName);
      final ext = p.extension(safeName);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      outPath = p.join(dir.path, '${stem}_$stamp$ext');
    }
    await File(outPath).writeAsBytes(bytes, flush: true);
    return outPath;
  }

  /// Copie temporaire pour l'aperçu (ouverture sans enregistrer dans Téléchargements).
  static Future<String> saveToCache({
    required List<int> bytes,
    required String filename,
  }) async {
    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, folderName, 'cache'));
    await dir.create(recursive: true);
    final safeName = _safeFilename(filename);
    final outPath = p.join(dir.path, safeName);
    await File(outPath).writeAsBytes(bytes, flush: true);
    return outPath;
  }

  /// Cherche une copie locale déjà enregistrée (nom exact ou variante horodatée).
  static Future<String?> findLatest({
    required String filename,
    required String subfolder,
  }) async {
    final dir = await _resolveDir(subfolder);
    final safeName = _safeFilename(filename);
    final exact = File(p.join(dir.path, safeName));
    if (await exact.exists()) return exact.path;

    final stem = p.basenameWithoutExtension(safeName);
    final ext = p.extension(safeName);
    String? bestPath;
    DateTime? bestTime;

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final base = p.basename(entity.path);
      final matches = base == safeName ||
          (base.startsWith('${stem}_') && base.endsWith(ext));
      if (!matches) continue;
      final mod = await entity.lastModified();
      if (bestTime == null || mod.isAfter(bestTime)) {
        bestTime = mod;
        bestPath = entity.path;
      }
    }
    return bestPath;
  }

  /// Retourne le chemin d'une copie locale si elle existe (envoyes puis recus).
  static Future<String?> findAnywhere(String filename, {bool preferSent = false}) async {
    final order = preferSent ? ['envoyes', 'recus'] : ['recus', 'envoyes'];
    for (final sub in order) {
      final path = await findLatest(filename: filename, subfolder: sub);
      if (path != null) return path;
    }
    return null;
  }

  static Future<Directory> _resolveDir(String subfolder) async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    base ??= await getExternalStorageDirectory();
    base ??= await getApplicationDocumentsDirectory();

    final dir = Directory(p.join(base.path, folderName, subfolder));
    await dir.create(recursive: true);
    return dir;
  }

  static String _safeFilename(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return cleaned.isEmpty ? 'fichier' : cleaned;
  }
}
