import 'package:objectbox/objectbox.dart';
import 'package:waico/core/entities/conversation_memory.dart';

@Entity()
class Conversation {
  @Id()
  int id;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  /// Key observations or notes about the conversation
  /// Usually much shorter than the summary, as it focuses on the noticed pain points, progresses, urgencies
  /// or anything that can give a glance of what need to be worked on to help the user. It can also include
  /// what the user and the assistant agreed on to talk about next time.
  /// When sending reports to a healthcare professional, this is the field that will be used for the selected conversations.
  String observations;

  /// Summary of the conversation
  /// When needed, can be included in reports sent to healthcare professionals.
  String summary;

  /// Memories associated with this conversation
  @Backlink('conversation')
  final memories = ToMany<ConversationMemory>();

  Conversation({
    this.id = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    required this.summary,
    required this.observations,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  void touch() {
    updatedAt = DateTime.now();
  }

  @override
  String toString() {
    return 'Conversation('
        'id: $id, '
        'createdAt: $createdAt, '
        'updatedAt: $updatedAt, '
        'observations: $observations, '
        'summary: $summary)';
  }
}
