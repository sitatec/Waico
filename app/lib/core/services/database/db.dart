import 'package:synchronized/synchronized.dart';
import 'package:waico/generated/objectbox.g.dart';
import 'repository.dart';

/// ObjectBox database service singleton
/// Provides easy access to ObjectBox functionality with a simple API
///
/// You should only use this inside repositories or db related classes.
/// Repositories should be only way to access db in business logic.
class ObjectBoxProvider {
  static ObjectBoxProvider? _instance;
  static final _lock = Lock();

  Store? _store;
  final Map<Type, Repository> _repositories = {};

  ObjectBoxProvider._();

  /// Get the singleton instance
  static Future<ObjectBoxProvider> get instance async {
    if (_instance == null) {
      await _lock.synchronized(() async {
        _instance ??= ObjectBoxProvider._();
        await _instance!._initialize();
      });
    }
    return _instance!;
  }

  /// Initialize the database
  Future<void> _initialize() async {
    if (_store != null) return;

    try {
      _store = await openStore();
    } catch (e) {
      throw Exception('Failed to initialize ObjectBox: $e');
    }
  }

  /// Get the ObjectBox store
  Store get store {
    if (_store == null) {
      throw StateError('Database not initialized. Call DatabaseService.instance first.');
    }
    return _store!;
  }

  /// Get a repository for a specific entity type
  Repository<T> getRepository<T>() {
    final type = T;
    if (!_repositories.containsKey(type)) {
      final box = store.box<T>();
      _repositories[type] = ObjectBoxBaseRepository<T>(box);
    }
    return _repositories[type] as Repository<T>;
  }

  /// Get a box directly for custom queries
  Box<T> getBox<T>() {
    return store.box<T>();
  }

  /// Close the database
  Future<void> close() async {
    _repositories.clear();
    _store?.close();
    _store = null;
    _instance = null;
  }

  /// Check if database is initialized
  bool get isInitialized => _store != null;

  /// Database statistics
  Map<String, dynamic> get stats {
    if (_store == null) return {};

    return {'isOpen': _store!.isClosed() == false, 'entities': _repositories.length};
  }

  /// Execute a transaction
  R runInTransaction<R>(R Function() fn) {
    return store.runInTransaction(TxMode.write, fn);
  }

  /// Execute a read transaction
  R runInReadTransaction<R>(R Function() fn) {
    return store.runInTransaction(TxMode.read, fn);
  }
}

/// Convenience class for database operations
class DB {
  static ObjectBoxProvider? _service;

  /// Initialize the database service
  static Future<void> init() async {
    _service = await ObjectBoxProvider.instance;
  }

  /// Get the database service instance
  ///
  /// You should only use this inside repositories or db related classes.
  /// Repositories should be only way to access db in business logic.
  static ObjectBoxProvider get provider {
    if (_service == null) {
      throw StateError('Database not initialized. Call DB.init() first.');
    }
    return _service!;
  }

  /// Get a repository for entity type T
  static Repository<T> repo<T>() => provider.getRepository<T>();

  /// Execute a transaction
  static R transaction<R>(R Function() fn) => provider.runInTransaction(fn);

  /// Execute a read transaction
  static R readTransaction<R>(R Function() fn) => provider.runInReadTransaction(fn);

  /// Close the database
  static Future<void> close() async {
    await _service?.close();
    _service = null;
  }
}
