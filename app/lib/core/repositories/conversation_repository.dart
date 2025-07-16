import 'package:waico/core/entities/conversation.dart';
import 'package:waico/core/services/database/db.dart';
import 'package:waico/core/services/database/repository.dart';
import 'package:waico/generated/objectbox.g.dart';

class ConversationRepository extends ObjectBoxBaseRepository<Conversation> {
  ConversationRepository() : super(DB.provider.getBox<Conversation>());

  List<Conversation> getLatestConversations({required int count}) {
    final query = box.query().order(Conversation_.updatedAt, flags: Order.descending).build();
    query.limit = count;
    return query.find();
  }
}
