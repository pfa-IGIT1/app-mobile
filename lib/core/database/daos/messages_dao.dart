import 'package:sqflite/sqflite.dart';

import '../../../data/models/message.dart';
import '../app_database.dart';

class MessagesDao {
  MessagesDao(this._db);

  final AppDatabase _db;

  Future<List<Message>> getByContactId(String contactId) async {
    final db = await _db.database;
    final rows = await db.query(
      'messages',
      where: 'contact_id = ?',
      whereArgs: [contactId],
      orderBy: 'sent_at ASC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<void> insert(Message message) async {
    final db = await _db.database;
    await db.insert(
      'messages',
      _toRow(message),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markAsRead(String messageId) async {
    final db = await _db.database;
    await db.update(
      'messages',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Map<String, Object?> _toRow(Message m) => {
        'id': m.id,
        'contact_id': m.contactId,
        'content': m.content,
        'sent_at': m.sentAt.toIso8601String(),
        'is_mine': m.isMine ? 1 : 0,
        'is_read': m.isRead ? 1 : 0,
      };

  Message _fromRow(Map<String, Object?> row) => Message(
        id: row['id'] as String,
        contactId: row['contact_id'] as String,
        content: row['content'] as String,
        sentAt: DateTime.parse(row['sent_at'] as String),
        isMine: (row['is_mine'] as int? ?? 0) == 1,
        isRead: (row['is_read'] as int? ?? 0) == 1,
      );
}
