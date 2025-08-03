import 'dart:convert';
import 'dart:developer' show log;
import 'package:easy_localization/easy_localization.dart' show DateFormat;
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart' show ChatMessage;
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/ai_models/embedding_model.dart';
import 'package:waico/core/entities/conversation.dart';
import 'package:waico/core/entities/conversation_memory.dart';
import 'package:waico/core/repositories/conversation_memory_repository.dart';
import 'package:waico/core/repositories/conversation_repository.dart';
import 'package:waico/core/repositories/user_repository.dart';

/// Process a conversation to extract useful insights
///
/// Used to summarize conversations, extract user info (name, preferences,...) and long-term memories from them,
/// and generate observations about the conversation that can serve the assistant and a professional
/// (therapist, coach, doctor,...) to better assist the user.
class ConversationProcessor {
  static const _summaryPrompt = '''
You are an expert at creating concise, clear summaries of therapeutic or coaching conversations.

First, think through the conversation step by step:
1. What were the main topics discussed?
2. What key points did the user raise?
3. Were there any important decisions or commitments made?
4. What was the overall tone and emotional context?
5. Were there any significant developments or changes?

Then provide a summary that captures these elements. Keep it factual, objective, and focused on the most important elements. The summary should be 1-4 paragraphs and serve as a quick reference for understanding what happened in this conversation without missing any important details.
''';

  static const _userInfoPrompt = '''
You are an expert at extracting user information from conversations.
Given a conversation and the current user information (which can be empty), your goal is to extract new or updated user information.

First, analyze the conversation step by step:
1. What personal information did the user explicitly mention?
2. What preferences, interests, or goals did they express (present goals, not past)?
3. What demographic or circumstantial information is evident?
4. Did the user provide any information (contact details, location, name, etc.) about their healthcare/wellbeing professionals?

Only include information that is explicitly mentioned or can be reasonably inferred.

If the current user information is not empty, merge the new information from the conversation with the existing user information prioritizing the new information to keep it up-to-date.

Your final answer should be a *concise* text containing only:
- User information
- Contact information of their healthcare/wellbeing professionals. 
- NOTHING ELSE.

Example 1:
```text
The user's goals are to improve their mental health, manage anxiety, and build better relationships. They are interested in mindfulness practices and have a therapist named Alex that they see weekly. Their therapist Alex phone number is 123-456-7890.
```

Example 2:
```text
The user is a 35-year-old male named John Doe. He is married with two children and lives in New York City. He works as a marketing manager and enjoys hiking and cooking.
He has a Gym coach hose email is mason@gymwarriors.com, he sometimes struggles with work-life balance and is interested in improving his time management skills.
```

If there isn't much information, keep it short:
```text
The user is dealing stress, but is getting help from a therapist.
```

If there is not information to extract, output an empty text:
```text
```
''';

  static const _memoriesPrompt = '''
You are an expert at identifying significant moments that should be remembered long-term from conversations. Your role is to extract episodic memories from a given conversation.

First, analyze the conversation step by step:
1. What significant life events or milestones were mentioned?
2. What important decisions or commitments were made?
3. Were there any emotional moments or breakthroughs?
4. What key insights or realizations occurred?
5. Were any significant life goals set or achievements celebrated?
6. Anything that is important to remember about the user for future interactions?

Then extract important memories. Each memory should be:
- Clear and concise around a single significant moment
- Self-contained and meaningful for future reference
- Focused on significant moments, not small talk

IMPORTANT RULES:
- Every memory should be about a single significant moment. Don't combine multiple moments into one memory.
- A single event can not be mentioned in multiple memories to avoid redundancy.

Format your final answer as the following examples:

Example 1:
```json
[
  "When the user was 10 years old, they moved to a new city with their family, which was a significant change for them. They remember feeling excited but also nervous about making new friends.",
  "The user had an cousin named Sarah who was a significant influence in their life. They use to discuss personal growth and career goals with her, and she has helped them through difficult times. But one day, Sarah had a car accident and passed away, which was a very difficult time for the user.",
]
```

Example 2:
```json
[
  "The user's math professor, Dr. Smith, is an important figure in their academic journey. Dr. Smith has been a mentor, providing guidance and support throughout the user's studies. The user often seeks Dr. Smith's advice on academic and career decisions."
]
```

If no significant memories are found, return an empty array:
```json
[]
```
''';

  static const _observationPrompt = '''
You are a professional clinical observer writing notes for healthcare providers, therapists, or coaches.

First, analyze the conversation systematically and check if any of the following questions can be answered based on the content of the conversation:
1. What is the user's current emotional state and mood patterns?
3. What key concerns or issues did they present?
4. Are there any signs of progress or changes from previous interactions?
5. What strengths and positive indicators do you observe?
6. What did the user and the assistant agree on to talk about in the next conversation?

Then provide a professional observation that would be valuable for someone providing care or guidance to the user. Focus on observable behaviors and stated concerns rather than making diagnoses.
Keep the observation concise and focus on important insights.

Your final answer should formatted as the following examples:
Example 1:
```text
The user mentioned experiencing a high level of anxiety related to their work performance. They expressed feelings of being overwhelmed and mentioned difficulty sleeping due to racing thoughts about deadlines.
The user also indicated a desire to improve their time management skills and is considering seeking professional help to address these issues. 
```

Example 2:
```text
The user is showing signs of improvement in their emotional well-being. They reported feeling more optimistic about their future and have been actively engaging in self-care activities.
```

If the conversation doesn't contain enough information for a meaningful observation, return an empty string:
```text
```
''';

  final UserRepository _userRepository;
  final ConversationRepository _conversationRepository;
  final ConversationMemoryRepository _conversationMemoryRepository;

  ConversationProcessor({
    UserRepository? userRepository,
    ConversationRepository? conversationRepository,
    ConversationMemoryRepository? conversationMemoryRepository,
  }) : _userRepository = userRepository ?? UserRepository(),
       _conversationRepository = conversationRepository ?? ConversationRepository(),
       _conversationMemoryRepository = conversationMemoryRepository ?? ConversationMemoryRepository();

  /// Processes a conversation to extract useful information with comprehensive error handling.
  ///
  /// This method analyzes the conversation extract key insights such as (summary, user info, memories, and observations).
  /// and stores them in the database. Handles failures gracefully and logs detailed error information.
  Future<void> processConversation(
    List<ChatMessage> conversation, {
    void Function(Map<String, bool>)? updateProgress,
  }) async {
    final currentProgress = {
      // True == Complete | False == Incomplete
      'Memory Generation': false,
      'Observations Generation': false,
      'Summary Generation': false,
      'User Info Extraction': false,
    };
    updateProgress?.call(currentProgress);

    if (conversation.isEmpty) {
      log('ConversationProcessor: Empty conversation provided, skipping processing');
      return;
    }

    try {
      final conversationText = formatConversationToText(conversation);
      // _returnDefaultOnError ensures that if one extraction fails, the others can still proceed
      final memories = await _returnDefaultOnError(() => extractMemories(conversationText), []);
      _markCompleted(currentProgress, 'Memory Generation', updateProgress);
      final observation = await _returnDefaultOnError(() => extractObservation(conversationText), '');
      _markCompleted(currentProgress, 'Observations Generation', updateProgress);
      final summary = await _returnDefaultOnError(() => summarizeConversation(conversationText), '');
      _markCompleted(currentProgress, 'Summary Generation', updateProgress);
      final userInfo = await _returnDefaultOnError(() => extractUserInfo(conversationText), '');
      _markCompleted(currentProgress, 'User Info Extraction', updateProgress);

      if (userInfo.isEmpty && memories.isEmpty && observation.isEmpty && summary.isEmpty) {
        throw Exception('All extractions returned empty contents');
      }

      // Store the extracted information in the databases
      await Future.wait([_storeUserInfo(userInfo), _storeConversationAndMemories(summary, observation, memories)]);
    } catch (e, stackTrace) {
      log(
        'ConversationProcessor.processConversation: Failed to process conversation',
        error: e,
        stackTrace: stackTrace,
      );
      throw ConversationProcessingException(
        'Failed to process conversation',
        e is Exception ? e : Exception(e.toString()),
      );
    }
  }

  void _markCompleted(Map<String, bool> currentProgress, String key, void Function(Map<String, bool>)? updateProgress) {
    log('Processing "$key" Completed ✅');
    currentProgress[key] = true;
    updateProgress?.call(currentProgress);
  }

  T _returnDefaultOnError<T>(T Function() action, defaultValue) {
    try {
      return action();
    } catch (e, stackTrace) {
      log('ConversationProcessor: Error during processing', error: e, stackTrace: stackTrace);
      return defaultValue;
    }
  }

  /// Formats a list of ChatMessage objects into a well-structured string
  String formatConversationToText(List<ChatMessage> conversation) {
    final buffer = StringBuffer();

    for (int i = 0; i < conversation.length; i++) {
      final message = conversation[i];
      final isLastMessage = i == conversation.length - 1;

      if (message.origin.isUser) {
        if (message.text?.contains('```tool_output') == true) {
          buffer.write('Tool Result: ${message.text ?? ""}');
        } else {
          buffer.write('User: ${message.text ?? ""}');
          if (message.attachments.isNotEmpty) {
            buffer.write('\nUser Uploaded Files: ${message.attachments.map((a) => a.name).join(', ')}');
          }
        }
      } else if (message.origin.isLlm) {
        buffer.write('Assistant: ${message.text ?? ""}');
      }

      if (!isLastMessage) {
        buffer.write('\n\n');
      }
    }

    return buffer.toString();
  }

  /// Extracts a concise summary of the conversation using chain-of-thought reasoning
  Future<String> summarizeConversation(String conversation) async {
    ChatModel? chatModel;
    try {
      chatModel = ChatModel(systemPrompt: _summaryPrompt);
      await chatModel.initialize();

      final response = StringBuffer();
      await for (final chunk in chatModel.sendMessageStream(
        'Analyze and summarize the following conversation, Output only the summary, do not include any titles or additional text.'
        'Conversation:\n\n$conversation\n\nConversation Summary:',
      )) {
        response.write(chunk);
      }

      return response.toString().trim();
    } catch (e, stackTrace) {
      log('ConversationProcessor: Error extracting summary', error: e, stackTrace: stackTrace);
      throw ExtractionException('summary', e.toString(), e is Exception ? e : Exception(e.toString()));
    } finally {
      await chatModel?.dispose();
    }
  }

  /// Extracts user information with chain-of-thought reasoning and text parsing
  Future<String> extractUserInfo(String conversation) async {
    ChatModel? chatModel;
    try {
      chatModel = ChatModel(systemPrompt: _userInfoPrompt);
      await chatModel.initialize();

      final response = StringBuffer();
      await for (final chunk in chatModel.sendMessageStream(
        'Analyze this conversation and extract user information:\n\n$conversation',
      )) {
        response.write(chunk);
      }

      final responseText = response.toString();
      // Extract text from markdown code block if present
      final textMatch = RegExp(r'```text\s*([\s\S]*?)\s*```').firstMatch(responseText);
      return textMatch?.group(1) ?? responseText.trim();
    } catch (e, stackTrace) {
      log('ConversationProcessor: Error extracting user info', error: e, stackTrace: stackTrace);
      throw ExtractionException('user info', e.toString(), e is Exception ? e : Exception(e.toString()));
    } finally {
      await chatModel?.dispose();
    }
  }

  /// Extracts memorable moments with chain-of-thought reasoning and JSON parsing
  Future<List<String>> extractMemories(String conversation) async {
    ChatModel? chatModel;
    try {
      chatModel = ChatModel(systemPrompt: _memoriesPrompt);
      await chatModel.initialize();

      final response = StringBuffer();
      await for (final chunk in chatModel.sendMessageStream(
        'Extract important memories from this conversation:\n\n$conversation',
      )) {
        response.write(chunk);
      }

      final responseText = response.toString();
      // Extract JSON from markdown code block if present
      final jsonMatch = RegExp(r'```json\s*([\s\S]*?)\s*```').firstMatch(responseText);
      final jsonText = jsonMatch?.group(1) ?? responseText.trim();

      final decoded = json.decode(jsonText);
      if (decoded is List) {
        final memories = decoded.cast<String>();
        // Format: Wednesday, 01 January 2023
        final formattedDate = DateFormat('EEEE, dd MMMM yyyy').format(DateTime.now());
        return memories.map((memory) => '$memory\n\nDate: $formattedDate').toList();
      }
      return <String>[];
    } catch (e, stackTrace) {
      log('ConversationProcessor: Error extracting memories', error: e, stackTrace: stackTrace);
      throw ExtractionException('memories', e.toString(), e is Exception ? e : Exception(e.toString()));
    } finally {
      await chatModel?.dispose();
    }
  }

  /// Generates professional observations with chain-of-thought reasoning and text parsing
  Future<String> extractObservation(String conversation) async {
    ChatModel? chatModel;
    try {
      chatModel = ChatModel(systemPrompt: _observationPrompt);
      await chatModel.initialize();

      final response = StringBuffer();
      await for (final chunk in chatModel.sendMessageStream(
        'Provide a professional observation of this conversation:\n\n$conversation',
      )) {
        response.write(chunk);
      }

      final responseText = response.toString();
      // Extract text from markdown code block if present
      final textMatch = RegExp(r'```text\s*([\s\S]*?)\s*```').firstMatch(responseText);
      final extractedText = textMatch?.group(1) ?? responseText.trim();

      return extractedText.trim();
    } catch (e, stackTrace) {
      log('ConversationProcessor: Error extracting observation', error: e, stackTrace: stackTrace);
      throw ExtractionException('observation', e.toString(), e is Exception ? e : Exception(e.toString()));
    } finally {
      await chatModel?.dispose();
    }
  }

  /// Stores extracted user information in the user repository
  Future<void> _storeUserInfo(String userInfo) async {
    if (userInfo.isNotEmpty) {
      try {
        // Store user information using the existing updateUserInfo method
        await _userRepository.updateUserInfo(userInfo);
        log('ConversationProcessor: Successfully stored user info with ${userInfo.length} fields');
      } catch (e, stackTrace) {
        log('ConversationProcessor: Error storing user info', error: e, stackTrace: stackTrace);
        throw StorageException('user info', e.toString(), e is Exception ? e : Exception(e.toString()));
      }
    }
  }

  /// Stores conversation, observations, and memories in a single transaction
  Future<void> _storeConversationAndMemories(String summary, String observation, List<String> memories) async {
    if (summary.isEmpty && observation.isEmpty && memories.isEmpty) {
      log('ConversationProcessor: No content to store, skipping storage');
      return;
    }

    try {
      // Create conversation record
      final conversation = Conversation(
        summary: summary.isNotEmpty ? summary : 'No summary',
        observations: observation.isNotEmpty ? observation : 'No observations',
      );

      // Save the conversation
      _conversationRepository.save(conversation);
      log(
        'ConversationProcessor: Stored conversation with summary: ${summary.length} chars, observation: ${observation.length} chars, memories: ${memories.length}',
      );

      // Generate embeddings and save memories if any exist
      if (memories.isNotEmpty) {
        final embeddingModel = EmbeddingModel();
        int successfulMemories = 0;

        for (final memory in memories) {
          try {
            // Generate embeddings for the memory
            final embeddings = await embeddingModel.getEmbeddings(memory);
            final conversationMemory = ConversationMemory(content: memory, embeddings: embeddings);
            // Link to the conversation
            conversationMemory.conversation.target = conversation;
            _conversationMemoryRepository.save(conversationMemory);
            successfulMemories++;
          } catch (e) {
            log('ConversationProcessor: Failed to save memory: $memory', error: e);
            // Continue processing other memories if one fails
            continue;
          }
        }

        log('ConversationProcessor: Successfully stored $successfulMemories out of ${memories.length} memories');
      }
    } catch (e, stackTrace) {
      log('ConversationProcessor: Error storing conversation and memories', error: e, stackTrace: stackTrace);
      throw StorageException('conversation and memories', e.toString(), e is Exception ? e : Exception(e.toString()));
    }
  }
}

// Exception classes for better error handling
class ConversationProcessingException implements Exception {
  final String message;
  final Exception? cause;

  const ConversationProcessingException(this.message, [this.cause]);

  @override
  String toString() => 'ConversationProcessingException: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

class ExtractionException extends ConversationProcessingException {
  final String extractionType;

  const ExtractionException(this.extractionType, String message, [Exception? cause])
    : super('Failed to extract $extractionType: $message', cause);
}

class StorageException extends ConversationProcessingException {
  final String storageType;

  const StorageException(this.storageType, String message, [Exception? cause])
    : super('Failed to store $storageType: $message', cause);
}
