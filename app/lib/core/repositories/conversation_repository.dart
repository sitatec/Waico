import 'package:waico/core/entities/conversation.dart';
import 'package:waico/core/services/database/db.dart';
import 'package:waico/core/services/database/repository.dart';
import 'package:waico/generated/objectbox.g.dart';

class ConversationRepository extends ObjectBoxBaseRepository<Conversation> {
  ConversationRepository() : super(DB.provider.getBox<Conversation>());

  List<Conversation> semanticSearch({required List<double> queryVector, int maxResultCount = 10}) {
    // TODO: output both the conversation and the score and fine-tuned the LLM to ajust it's confidence
    // of the remembered memory based on the score and respond to the user accordingly (uncertain for low scores,...)
    final query = box.query(Conversation_.embeddings.nearestNeighborsF32(queryVector, maxResultCount)).build();
    final results = query.findWithScores();

    final eligibleConversations = results
        .where((result) => result.score > Conversation.embeddingsScoreThreshold)
        .toList();
    eligibleConversations.sort((a, b) => b.score.compareTo(a.score));

    return eligibleConversations.map((result) => result.object).toList();
  }

  List<Conversation> getLatestConversations({required int count}) {
    final query = box.query().order(Conversation_.updatedAt, flags: Order.descending).build();
    query.limit = count;
    return query.find();
  }
}
