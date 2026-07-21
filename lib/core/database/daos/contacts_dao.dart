import 'package:sqflite/sqflite.dart';

import '../../../data/models/contact.dart';
import '../app_database.dart';

class ContactsDao {
  ContactsDao(this._db);

  final AppDatabase _db;

  Future<List<Contact>> getAll() async {
    final db = await _db.database;
    final rows = await db.query('contacts', orderBy: 'display_name ASC');
    return rows.map(_fromRow).toList();
  }

  Future<void> insert(Contact contact) async {
    final db = await _db.database;
    await db.insert(
      'contacts',
      {
        'public_id': contact.id,
        'display_name': contact.name,
        'public_key': contact.publicKey,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final db = await _db.database;
    await db.delete('contacts', where: 'public_id = ?', whereArgs: [id]);
  }

  Contact _fromRow(Map<String, Object?> row) => Contact(
        id: row['public_id'] as String,
        name: row['display_name'] as String,
        publicKey: row['public_key'] as String,
      );
}
