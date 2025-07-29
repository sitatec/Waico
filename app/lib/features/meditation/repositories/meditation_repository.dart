import 'package:waico/core/services/database/db.dart';
import 'package:waico/core/services/database/repository.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';

class MeditationRepository extends ObjectBoxBaseRepository<MeditationGuide> {
  MeditationRepository() : super(DB.provider.getBox<MeditationGuide>());

  /// Get all meditation guides ordered by creation date (newest first)
  List<MeditationGuide> getAllMeditationGuides() {
    final guides = findAll();
    guides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return guides;
  }

  /// Get meditation guides by type
  List<MeditationGuide> getMeditationGuidesByType(String type) {
    final guides = findAll().where((guide) => guide.type == type).toList();
    guides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return guides;
  }

  /// Get completed meditation guides
  List<MeditationGuide> getCompletedMeditationGuides() {
    final guides = findAll().where((guide) => guide.isCompleted).toList();
    guides.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return guides;
  }

  /// Mark a meditation guide as completed
  Future<void> markAsCompleted(int meditationId) async {
    final meditation = findById(meditationId);
    if (meditation != null) {
      meditation.isCompleted = true;
      meditation.touch();
      save(meditation);
    }
  }

  /// Mark a meditation guide as incomplete
  Future<void> markAsIncomplete(int meditationId) async {
    final meditation = findById(meditationId);
    if (meditation != null) {
      meditation.isCompleted = false;
      meditation.touch();
      save(meditation);
    }
  }

  /// Delete a meditation guide
  Future<void> deleteMeditationGuide(int meditationId) async {
    deleteById(meditationId);
  }

  /// Get meditation count by completion status
  int getTotalMeditationCount() => findAll().length;
  int getCompletedMeditationCount() => findAll().where((guide) => guide.isCompleted).length;
  int getIncompleteMeditationCount() => findAll().where((guide) => !guide.isCompleted).length;
}
