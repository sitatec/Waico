import 'package:objectbox/objectbox.dart';
import 'package:waico/core/entities/conversation.dart';

@Entity()
class ConversationMemory {
  /// Currently multilingual-e5-small is used, so the embeddings dimension is 384.
  static const embeddingsDimension = 384;

  /// multilingual-e5-small's scores range from 0.7 to 1.0, so we set the threshold to 0.8 for now
  static const embeddingsScoreThreshold = 0.8;

  @Id()
  int id;

  /// A memory from a conversation, this is not simple summary of the whole conversation, it represent a specific
  /// memorable event from the conversation. This could be when a user talk about a specific event, how they feel,
  /// an issue they are dealing with, their relationship with someone... This field shouldn't contain mixed events
  /// or small talks. A conversation typically has many memories.
  String memory;

  /// Embeddings of the conversation (summary and observations combined)
  @HnswIndex(dimensions: embeddingsDimension, distanceType: VectorDistanceType.dotProduct, indexingSearchCount: 200)
  @Property(type: PropertyType.floatVector)
  List<double> embeddings;

  /// The conversation this memory belongs to
  final conversation = ToOne<Conversation>();

  ConversationMemory({this.id = 0, required this.memory, required this.embeddings});

  @override
  String toString() {
    return 'ConversationMemory('
        'id: $id, '
        'memory: $memory, '
        'embeddings: ${embeddings.length} dimensions)';
  }
}
