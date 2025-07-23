import 'package:flutter/material.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/pose_detection/workout_camera_widget.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';
import 'package:waico/features/workout/pose_detection/exercise_classifiers.dart';

/// Page that displays the camera for a specific exercise
class ExerciseCameraPage extends StatefulWidget {
  final Exercise exercise;
  final int exerciseIndex;
  final int sessionIndex;
  final int weekIndex;

  const ExerciseCameraPage({
    super.key,
    required this.exercise,
    required this.exerciseIndex,
    required this.sessionIndex,
    required this.weekIndex,
  });

  @override
  State<ExerciseCameraPage> createState() => _ExerciseCameraPageState();
}

class _ExerciseCameraPageState extends State<ExerciseCameraPage> {
  RepsCounter? _repsCounter;

  @override
  void initState() {
    super.initState();
    _initializeRepsCounter();
  }

  void _initializeRepsCounter() {
    // Create appropriate rep counter based on exercise name. Since the workout plans are AI generated,
    // It's safer to use this parsing method than relying on exact values to determine exercise type.
    final exerciseName = widget.exercise.name.toLowerCase();

    if (exerciseName.contains('push') && exerciseName.contains('up')) {
      _repsCounter = RepsCounter(PushUpClassifier());
    } else if (exerciseName.contains('squat')) {
      if (exerciseName.contains('sumo')) {
        _repsCounter = RepsCounter(SumoSquatClassifier());
      } else if (exerciseName.contains('split')) {
        _repsCounter = RepsCounter(SplitSquatClassifier(frontLeg: SplitSquatSide.left));
      } else {
        _repsCounter = RepsCounter(SquatClassifier());
      }
    } else if (exerciseName.contains('crunch')) {
      if (exerciseName.contains('reverse')) {
        _repsCounter = RepsCounter(ReverseCrunchClassifier());
      } else if (exerciseName.contains('double')) {
        _repsCounter = RepsCounter(DoubleCrunchClassifier());
      } else {
        _repsCounter = RepsCounter(CrunchClassifier());
      }
    } else if (exerciseName.contains('superman')) {
      _repsCounter = RepsCounter(SupermanClassifier());
    }
    // If no specific classifier found, don't show rep counter
  }

  @override
  void dispose() {
    _repsCounter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: WorkoutCameraWidget(
        repsCounter: _repsCounter,
        showRepCounter: _repsCounter != null,
        onPermissionDenied: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Camera permission is required for exercise tracking'),
              backgroundColor: Colors.red,
            ),
          );
        },
      ),
    );
  }
}
