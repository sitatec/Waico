import 'package:objectbox/objectbox.dart';

@Entity()
class Conversation {
  /// Currently multilingual-e5-small is used, so the embeddings dimension is 384.
  static const embeddingsDimension = 384;

  /// multilingual-e5-small's scores range from 0.7 to 1.0, so we set the threshold to 0.8 for now
  static const embeddingsScoreThreshold = 0.8;

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
  /// Can serve as a memory for the assistant. When needed, can be included in reports sent to healthcare professionals.
  String summary;

  /// Embeddings of the conversation (summary and observations combined)
  @HnswIndex(dimensions: embeddingsDimension, distanceType: VectorDistanceType.dotProduct, indexingSearchCount: 200)
  @Property(type: PropertyType.floatVector)
  List<double> embeddings;

  Conversation({
    this.id = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.embeddings = const [],
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
        'summary: $summary, '
        'embeddings: ${embeddings.length} elements)';
  }
}
