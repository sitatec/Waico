import 'package:objectbox/objectbox.dart';
import 'package:waico/core/entities/conversation.dart';

@Entity()
class ConversationMemory {
  /// Currently Qwen3-Embedding-0.6B is used, so the embeddings dimension is 1024.
  static const embeddingsDimension = 1024;

  /// The threshold for similarity score when comparing embeddings.
  /// Embeddings with a score below this threshold should be discarded from search results.
  static const embeddingsScoreThreshold = 0.6;

  @Id()
  int id;

  /// The content of a memory from a conversation, this is not simple summary of the whole conversation, it represent a specific
  /// memorable event from the conversation. This could be when a user talk about a specific event, how they feel,
  /// an issue they are dealing with, their relationship with someone... This field shouldn't contain mixed events
  /// or small talks. A conversation typically has many memories.
  String content;

  /// Embeddings of the conversation (summary and observations combined)
  @HnswIndex(dimensions: embeddingsDimension, distanceType: VectorDistanceType.dotProduct, indexingSearchCount: 200)
  @Property(type: PropertyType.floatVector)
  List<double> embeddings;

  /// The conversation this memory belongs to
  final conversation = ToOne<Conversation>();

  ConversationMemory({this.id = 0, required this.content, required this.embeddings});

  @override
  String toString() {
    return 'ConversationMemory('
        'id: $id, '
        'memory: $content, '
        'embeddings: ${embeddings.length} dimensions)';
  }
}
