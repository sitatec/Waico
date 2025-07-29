import 'dart:async';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';

class MeditationGuideGenerator {
  /// Generate a meditation guide using AI
  static Future<MeditationGuide> generateGuide(MeditationType type, int durationMinutes, {String? customTitle}) async {
    final chatModel = ChatModel(systemPrompt: _getSystemPrompt(), temperature: 0.7);

    await chatModel.initialize();

    final prompt = _buildPrompt(type, durationMinutes, customTitle);

    String generatedContent = '';
    await for (final chunk in chatModel.sendMessageStream(prompt)) {
      generatedContent += chunk;
    }

    return _parseGeneratedGuide(generatedContent, type, durationMinutes, customTitle);
  }

  static String _getSystemPrompt() {
    return '''You are an expert meditation instructor and guide creator. Your task is to create personalized, high-quality meditation scripts that help users achieve deep relaxation and mindfulness.

Key requirements for meditation scripts:
1. Include specific pause durations in brackets like [pause 3s], [pause 10s], etc.
2. Use a gentle, calming tone throughout
3. Provide clear, simple instructions
4. Include breathing guidance
5. Create a complete guided experience from beginning to end
6. End with a gentle return to awareness

Please format your response as follows:
1. First, provide a compelling title for the meditation
2. Then provide a brief description (1-2 sentences)
3. Finally, provide the meditation script wrapped in ```text blocks

Example format:
Title: Peaceful Evening Meditation
Description: A calming meditation to help you unwind and release the day's tensions.

```text
Welcome to this evening meditation. [pause 3s]

Find a comfortable position and allow your body to settle. [pause 5s]

Close your eyes gently and take a deep breath in... [pause 3s]

And slowly exhale, releasing any tension from the day. [pause 5s]

Continue with the full meditation script here...
```

Create only the meditation script within the text blocks, with appropriate pause instructions throughout.''';
  }

  static String _buildPrompt(MeditationType type, int durationMinutes, String? customTitle) {
    final titleInstruction = customTitle != null ? 'Use the title "$customTitle" for this meditation. ' : '';

    final basePrompt = '${titleInstruction}Create a $durationMinutes-minute meditation script for ';

    switch (type) {
      case MeditationType.mindfulness:
        return '${basePrompt}mindfulness meditation focused on present moment awareness and observing thoughts without judgment.';

      case MeditationType.bodyScanning:
        return '${basePrompt}body scanning meditation that guides the user through progressive relaxation of each body part from toes to head.';

      case MeditationType.lovingKindness:
        return '${basePrompt}loving kindness meditation that cultivates compassion and positive emotions toward self and others.';

      case MeditationType.breathwork:
        return '${basePrompt}breathwork meditation focused on specific breathing techniques like 4-7-8 breathing or box breathing.';

      case MeditationType.visualization:
        return '${basePrompt}visualization meditation with guided imagery of a peaceful, restorative place or experience.';

      case MeditationType.walking:
        return '${basePrompt}walking meditation that can be done slowly indoors or outdoors, focusing on mindful movement.';

      case MeditationType.mantra:
        return '${basePrompt}mantra meditation with a simple, repeated phrase or sound to focus the mind.';

      case MeditationType.beginner:
        return '${basePrompt}beginner-friendly meditation that introduces basic mindfulness concepts and simple breathing techniques. Make it welcoming and easy to follow for someone new to meditation.';
    }
  }

  static MeditationGuide _parseGeneratedGuide(
    String generatedContent,
    MeditationType type,
    int durationMinutes,
    String? customTitle,
  ) {
    // Extract title from the response
    String title = customTitle ?? _generateTitleForType(type);
    final titleMatch = RegExp(r'Title:\s*(.+)', caseSensitive: false).firstMatch(generatedContent);
    if (titleMatch != null && customTitle == null) {
      title = titleMatch.group(1)?.trim() ?? title;
    }

    // Extract description from the response
    String description = _generateDescriptionForType(type);
    final descriptionMatch = RegExp(r'Description:\s*(.+)', caseSensitive: false).firstMatch(generatedContent);
    if (descriptionMatch != null) {
      description = descriptionMatch.group(1)?.trim() ?? description;
    }

    // Extract script from text blocks
    String script = '';
    final textBlockMatch = RegExp(r'```text\s*\n([\s\S]*?)\n```', multiLine: true).firstMatch(generatedContent);
    if (textBlockMatch != null) {
      script = textBlockMatch.group(1)?.trim() ?? '';
    } else {
      // Fallback: use the entire content if no text block found
      script = generatedContent.trim();
    }

    return MeditationGuide(
      title: title,
      type: type.title,
      description: description,
      durationMinutes: durationMinutes,
      script: script,
    );
  }

  static String _generateTitleForType(MeditationType type) {
    switch (type) {
      case MeditationType.mindfulness:
        return 'Mindfulness Meditation';
      case MeditationType.bodyScanning:
        return 'Body Scan Meditation';
      case MeditationType.lovingKindness:
        return 'Loving Kindness Meditation';
      case MeditationType.breathwork:
        return 'Breathwork Meditation';
      case MeditationType.visualization:
        return 'Visualization Meditation';
      case MeditationType.walking:
        return 'Walking Meditation';
      case MeditationType.mantra:
        return 'Mantra Meditation';
      case MeditationType.beginner:
        return 'Beginner\'s Meditation';
    }
  }

  static String _generateDescriptionForType(MeditationType type) {
    switch (type) {
      case MeditationType.mindfulness:
        return 'Focus on present moment awareness and breathing.';
      case MeditationType.bodyScanning:
        return 'Progressive relaxation through body awareness.';
      case MeditationType.lovingKindness:
        return 'Cultivate compassion and positive emotions.';
      case MeditationType.breathwork:
        return 'Focus on specific breathing techniques.';
      case MeditationType.visualization:
        return 'Guided imagery and mental visualization.';
      case MeditationType.walking:
        return 'Mindful movement and awareness.';
      case MeditationType.mantra:
        return 'Repetition of sacred words or phrases.';
      case MeditationType.beginner:
        return 'Perfect introduction to meditation practice.';
    }
  }
}
