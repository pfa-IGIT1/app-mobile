import '../../core/database/daos/contacts_dao.dart';
import '../models/contact.dart';

class ContactRepository {
  ContactRepository({required this._contactsDao});

  final ContactsDao _contactsDao;

  Future<List<Contact>> getAll() => _contactsDao.getAll();

  Future<void> add(Contact contact) => _contactsDao.insert(contact);

  Future<void> remove(String id) => _contactsDao.delete(id);
}
