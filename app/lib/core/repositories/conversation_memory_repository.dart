import 'dart:math';

import 'package:waico/core/entities/conversation_memory.dart';
import 'package:waico/core/services/database/db.dart';
import 'package:waico/core/services/database/repository.dart';
import 'package:waico/generated/objectbox.g.dart';

class ConversationMemoryRepository extends ObjectBoxBaseRepository<ConversationMemory> {
  ConversationMemoryRepository() : super(DB.provider.getBox<ConversationMemory>());

  Future<List<ConversationMemory>> searchMemories({required List<double> queryVector, int maxResultCount = 5}) async {
    // TODO: output both the conversation and the score and fine-tuned the LLM to ajust it's confidence
    // of the remembered memory based on the score and respond to the user accordingly (uncertain for low scores,...)

    // Passing higher maxResultCount to the vector search but limit the result to the requested maxResultCount
    // Can improve quality according to docs.
    final maxVectorSearchCount = min(maxResultCount * 10, 100);
    final query = box
        .query(ConversationMemory_.embeddings.nearestNeighborsF32(queryVector, maxVectorSearchCount))
        .build();
    query.limit = maxResultCount;

    final results = await query.findWithScoresAsync();

    final eligibleConversations = results
        .where((result) => result.score > ConversationMemory.embeddingsScoreThreshold)
        .toList();
    eligibleConversations.sort((a, b) => b.score.compareTo(a.score));

    return eligibleConversations.map((result) => result.object).toList();
  }
}
