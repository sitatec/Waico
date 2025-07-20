import 'package:waico/core/entities/user.dart';
import 'package:waico/core/services/database/db.dart';
import 'package:waico/core/services/database/repository.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/models/workout_status.dart';

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

  /// Save workout setup data for the current user
  Future<User> saveWorkoutSetupData(WorkoutSetupData workoutSetupData) async {
    final existingUser = await getUser();

    if (existingUser != null) {
      existingUser.workoutSetupData = workoutSetupData;
      existingUser.touch();
      save(existingUser);
      return existingUser;
    } else {
      // Create a new user with default name if none exists (less likely scenario)
      final newUser = User(preferredName: 'User', workoutSetupData: workoutSetupData);
      save(newUser);
      return newUser;
    }
  }

  /// Get workout setup data for the current user
  Future<WorkoutSetupData?> getWorkoutSetupData() async {
    final user = await getUser();
    return user?.workoutSetupData;
  }

  /// Clear workout setup data for the current user
  Future<void> clearWorkoutSetupData() async {
    final user = await getUser();
    if (user != null) {
      user.workoutSetupData = null;
      user.touch();
      save(user);
    }
  }

  /// Save workout plan for the current user
  Future<User> saveWorkoutPlan(WorkoutPlan workoutPlan) async {
    final existingUser = await getUser();

    if (existingUser != null) {
      existingUser.workoutPlan = workoutPlan;
      existingUser.touch();
      save(existingUser);
      return existingUser;
    } else {
      // Create a new user with default name if none exists (less likely scenario)
      final newUser = User(preferredName: 'User', workoutPlan: workoutPlan);
      save(newUser);
      return newUser;
    }
  }

  /// Get workout plan for the current user
  Future<WorkoutPlan?> getWorkoutPlan() async {
    final user = await getUser();
    return user?.workoutPlan;
  }

  /// Clear workout plan for the current user
  Future<void> clearWorkoutPlan() async {
    final user = await getUser();
    if (user != null) {
      user.workoutPlan = null;
      user.touch();
      save(user);
    }
  }

  /// Check if user has completed workout setup and has a workout plan
  Future<WorkoutStatus> getWorkoutStatus() async {
    final user = await getUser();

    if (user?.workoutSetupData == null) {
      return WorkoutStatus.noSetup;
    }

    if (user?.workoutPlan == null) {
      return WorkoutStatus.setupCompleteNoPlan;
    }

    return WorkoutStatus.planReady;
  }
}
