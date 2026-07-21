import 'dart:convert';

import '../app_database.dart';

/// File d'attente locale des transactions à pousser vers la passerelle.
///
/// Quand la passerelle est hors de portée, les envois sont mis ici et rejoués
/// dès qu'elle revient (voir [SyncService]).
class SyncDao {
  SyncDao(this._db);

  final AppDatabase _db;

  Future<List<Map<String, dynamic>>> getPendingTransactions() async {
    final db = await _db.database;
    final rows = await db.query('sync_queue', orderBy: 'created_at ASC');
    return rows.map((row) {
      final payload = jsonDecode(row['payload'] as String) as Map<String, dynamic>;
      return {...payload, 'id': row['id']};
    }).toList();
  }

  Future<void> enqueue(String id, Map<String, dynamic> payload) async {
    final db = await _db.database;
    await db.insert('sync_queue', {
      'id': id,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> markSynced(String txId) async {
    final db = await _db.database;
    await db.delete('sync_queue', where: 'id = ?', whereArgs: [txId]);
  }
}
