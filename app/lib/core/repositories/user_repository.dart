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
  Future<User> saveUser(String name, {String? info}) async {
    final existingUser = await getUser();

    if (existingUser != null) {
      existingUser.preferredName = name;
      if (info != null) {
        existingUser.userInfo = info;
      }
      existingUser.touch();
      save(existingUser);
      return existingUser;
    } else {
      final newUser = User(preferredName: name, userInfo: info);
      save(newUser);
      return newUser;
    }
  }

  /// Update user info
  Future<void> updateUserInfo(String info) async {
    final user = await getUser();
    if (user != null) {
      user.userInfo = info;
      user.touch();
      save(user);
    }
  }
}
