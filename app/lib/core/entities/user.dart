import 'dart:developer';

import 'package:objectbox/objectbox.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/models/workout_progress.dart';

@Entity()
class User {
  @Id()
  int id;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  /// The preferred name of the user
  ///
  /// This is the name that will be used in conversations and interactions
  String preferredName;

  /// User preferences and additional info stored as key-value pairs
  ///
  /// This can include environment/settings that calms the user, their wellbeing professional (therapist, coach,..)
  /// contact info, things that stresses them...
  String? userInfo;

  // The WorkoutSetupData type is not supported by ObjectBox.
  // So ignore this field...
  @Transient()
  WorkoutSetupData? workoutSetupData;

  // ...and define a field with a supported type,
  // that is backed by the workoutSetupData field.
  String? get dbWorkoutSetupData {
    return workoutSetupData?.toJsonString();
  }

  set dbWorkoutSetupData(String? value) {
    if (value == null || value.isEmpty) {
      workoutSetupData = null;
    } else {
      try {
        workoutSetupData = WorkoutSetupData.fromJsonString(value);
      } catch (e, s) {
        log('Error parsing WorkoutSetupData from JSON', error: e, stackTrace: s);
        // Handle parsing errors gracefully
        workoutSetupData = null;
      }
    }
  }

  // The WorkoutPlan type is not supported by ObjectBox.
  // So ignore this field...
  @Transient()
  WorkoutPlan? workoutPlan;

  // ...and define a field with a supported type,
  // that is backed by the workoutPlan field.
  String? get dbWorkoutPlan {
    return workoutPlan?.toJsonString();
  }

  set dbWorkoutPlan(String? value) {
    if (value == null || value.isEmpty) {
      workoutPlan = null;
    } else {
      try {
        workoutPlan = WorkoutPlan.fromJsonString(value);
      } catch (e, s) {
        log('Error parsing WorkoutPlan from JSON', error: e, stackTrace: s);
        workoutPlan = null;
      }
    }
  }

  // The WorkoutProgress type is not supported by ObjectBox.
  // So ignore this field...
  @Transient()
  WorkoutProgress? workoutProgress;

  // ...and define a field with a supported type,
  // that is backed by the workoutProgress field.
  String? get dbWorkoutProgress {
    return workoutProgress?.toJsonString();
  }

  set dbWorkoutProgress(String? value) {
    if (value == null || value.isEmpty) {
      workoutProgress = null;
    } else {
      try {
        workoutProgress = WorkoutProgress.fromJsonString(value);
      } catch (e, s) {
        log('Error parsing WorkoutProgress from JSON', error: e, stackTrace: s);
        // Handle parsing errors gracefully
        workoutProgress = null;
      }
    }
  }

  User({
    this.id = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.preferredName,
    this.userInfo,
    this.workoutSetupData,
    this.workoutPlan,
    this.workoutProgress,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  void touch() {
    updatedAt = DateTime.now();
  }

  @override
  String toString() {
    return 'User('
        'id: $id, '
        'createdAt: $createdAt, '
        'updatedAt: $updatedAt, '
        'name: $preferredName, '
        'workoutSetupData: $workoutSetupData, '
        'workoutPlan: $workoutPlan, '
        'workoutProgress: $workoutProgress, '
        'userInfo: $userInfo)';
  }
}
