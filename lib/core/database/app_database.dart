import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Base SQLite locale du téléphone (§6, §11).
///
/// Le cache stocke le CLAIR : c'est le principe du bout-en-bout. La passerelle
/// ne voit que du chiffré, la blockchain n'ancre que des empreintes ; le
/// contenu lisible ne réside que sur les appareils des utilisateurs.
class AppDatabase {
  Database? _db;

  static const _fileName = 'pfa_mobile.db';
  static const _version = 1;

  /// Ouvre (et crée au besoin) la base ; réutilise l'instance déjà ouverte.
  Future<Database> get database async {
    final existing = _db;
    if (existing != null) return existing;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _fileName);
    final db = await openDatabase(path, version: _version, onCreate: _onCreate);
    _db = db;
    return db;
  }

  Future<void> open() async {
    await database;
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE contacts (
        public_id    TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        public_key   TEXT NOT NULL,
        updated_at   TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE messages (
        id         TEXT PRIMARY KEY,
        contact_id TEXT NOT NULL,
        content    TEXT NOT NULL,
        sent_at    TEXT NOT NULL,
        is_mine    INTEGER NOT NULL DEFAULT 0,
        is_read    INTEGER NOT NULL DEFAULT 0
      );
    ''');
    await db.execute(
      'CREATE INDEX idx_messages_contact ON messages (contact_id, sent_at);',
    );

    await db.execute('''
      CREATE TABLE files (
        id          TEXT PRIMARY KEY,
        name        TEXT NOT NULL,
        size        INTEGER NOT NULL DEFAULT 0,
        received_at TEXT NOT NULL,
        mime_type   TEXT,
        is_mine     INTEGER NOT NULL DEFAULT 0,
        encrypted   INTEGER NOT NULL DEFAULT 1
      );
    ''');

    // File d'attente : messages/fichiers à (re)pousser quand la passerelle revient.
    await db.execute('''
      CREATE TABLE sync_queue (
        id         TEXT PRIMARY KEY,
        payload    TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
