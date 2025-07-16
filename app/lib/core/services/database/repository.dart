import 'package:objectbox/objectbox.dart';

/// Generic repository interface for CRUD operations
abstract class Repository<T> {
  /// Save an entity (insert or update)
  int save(T entity);

  /// Save multiple entities
  List<int> saveAll(List<T> entities);

  /// Find entity by ID
  T? findById(int id);

  /// Find all entities
  List<T> findAll();

  /// Delete entity by ID
  bool deleteById(int id);

  /// Delete entity
  bool delete(T entity);

  /// Delete all entities
  int deleteAll();

  /// Count all entities
  int count();

  /// Check if entity exists by ID
  bool existsById(int id);

  /// Get the ObjectBox box for custom queries
  Box<T> get box;
}

/// Base repository implementation
class ObjectBoxBaseRepository<T> implements Repository<T> {
  final Box<T> _box;

  ObjectBoxBaseRepository(this._box);

  @override
  int save(T entity) {
    return _box.put(entity);
  }

  @override
  List<int> saveAll(List<T> entities) {
    return _box.putMany(entities);
  }

  @override
  T? findById(int id) {
    return _box.get(id);
  }

  @override
  List<T> findAll() {
    return _box.getAll();
  }

  @override
  bool deleteById(int id) {
    return _box.remove(id);
  }

  @override
  bool delete(T entity) {
    // Assuming entity has an 'id' property
    try {
      final id = (entity as dynamic).id as int;
      return _box.remove(id);
    } catch (e) {
      return false;
    }
  }

  @override
  int deleteAll() {
    return _box.removeAll();
  }

  @override
  int count() {
    return _box.count();
  }

  @override
  bool existsById(int id) {
    return _box.get(id) != null;
  }

  @override
  Box<T> get box => _box;
}
