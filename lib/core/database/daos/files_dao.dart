import 'package:sqflite/sqflite.dart';

import '../../../data/models/file_item.dart';
import '../app_database.dart';

class FilesDao {
  FilesDao(this._db);

  final AppDatabase _db;

  Future<List<FileItem>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('files', orderBy: 'received_at DESC');
    return rows.map(_fromRow).toList();
  }

  Future<void> insert(FileItem file) async {
    final db = await _db.database;
    await db.insert(
      'files',
      {
        'id': file.id,
        'name': file.name,
        'size': file.size,
        'received_at': file.receivedAt.toIso8601String(),
        'mime_type': file.mimeType,
        'is_mine': file.isMine ? 1 : 0,
        'encrypted': file.encrypted ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('files', where: 'id = ?', whereArgs: [id]);
  }

  FileItem _fromRow(Map<String, Object?> row) => FileItem(
        id: row['id'] as String,
        name: row['name'] as String,
        size: (row['size'] as int? ?? 0),
        receivedAt: DateTime.parse(row['received_at'] as String),
        mimeType: row['mime_type'] as String?,
        isMine: (row['is_mine'] as int? ?? 0) == 1,
        encrypted: (row['encrypted'] as int? ?? 1) == 1,
      );
}
