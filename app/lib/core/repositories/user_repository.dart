import 'package:waico/core/entities/user.dart';
import 'package:waico/core/services/database/db.dart';
import 'package:waico/core/services/database/repository.dart';

class UserRepository extends ObjectBoxBaseRepository<User> {
  UserRepository() : super(DB.provider.getBox<User>());

  /// Get the current user (assuming single user app)
  /// Returns the first user if exists, null otherwise
  Future<User?> getUser() async {
    final users = findAll();
    return users.isNotEmpty ? users.first : null;
  }

  /// Create or update the current user
  /// In a single-user app, this will update the existing user or create a new one
  Future<User> saveUser(String name, {Map<String, String>? preferences}) async {
    final existingUser = await getUser();

    if (existingUser != null) {
      existingUser.preferredName = name;
      if (preferences != null) {
        existingUser.preferences = preferences;
      }
      existingUser.touch();
      save(existingUser);
      return existingUser;
    } else {
      final newUser = User(preferredName: name, preferences: preferences);
      save(newUser);
      return newUser;
    }
  }

  /// Update user preferences
  Future<void> updatePreferences(Map<String, String> preferences) async {
    final user = await getUser();
    if (user != null) {
      user.preferences = preferences;
      user.touch();
      save(user);
    }
  }
}
