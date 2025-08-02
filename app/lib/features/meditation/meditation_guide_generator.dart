import 'dart:async';
import 'dart:io';
import 'dart:developer' show log;
import 'package:path_provider/path_provider.dart';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/ai_models/tts_model.dart';
import 'package:waico/core/utils/list_utils.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';
import 'package:waico/features/meditation/background_sound_manager.dart';

class MeditationGuideGenerator {
  /// Generate a meditation guide using AI and synthesize audio chunks
  static Future<MeditationGuide> generateGuide(
    MeditationType type,
    int durationMinutes, {
    String? customTitle,
    String? backgroundSound,
  }) async {
    final chatModel = ChatModel(systemPrompt: _getSystemPrompt());

    await chatModel.initialize();

    final prompt = _buildPrompt(type, durationMinutes, customTitle);
    log('Generating meditation guide with prompt: $prompt');
    String generatedContent = '';
    await for (final chunk in chatModel.sendMessageStream(prompt)) {
      generatedContent += chunk;
    }
    log('Generated meditation guide content: $generatedContent');
    final disposeFuture = chatModel.dispose();
    final meditationGuide = _parseAndSynthesizeGuide(
      generatedContent,
      type,
      durationMinutes,
      customTitle,
      backgroundSound,
    );
    await disposeFuture;
    return meditationGuide;
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

Please format your response exactly as follows:
Title: [Your meditation title here]
Description: [Your 1-2 sentence description here]
Meditation Script:
[Your complete meditation script here with pause instructions throughout]

Do not include any additional text or explanations outside of this format.

Example format:
Title: Peaceful Evening Meditation
Description: A calming meditation to help you unwind and release the day's tensions.
Meditation Script:
Welcome to this evening meditation. [pause 5s]

Find a comfortable position and allow your body to settle. [pause 10s]

Close your eyes gently and take a deep breath in. [pause 7s]

And slowly exhale, releasing any tension from the day. [pause 10s]

Continue to breathe deeply and observe your thoughts without judgment. Allow them to come and go, like waves on the ocean. [pause 45]

Continue with the full meditation script here...''';
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

  static Future<MeditationGuide> _parseAndSynthesizeGuide(
    String generatedContent,
    MeditationType type,
    int durationMinutes,
    String? customTitle,
    String? backgroundSound,
  ) async {
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

    // Extract script from the response after "Meditation Script:" line
    String script = '';
    final scriptMatch = RegExp(r'Meditation Script:\s*\n([\s\S]*)', multiLine: true).firstMatch(generatedContent);
    if (scriptMatch != null) {
      script = scriptMatch.group(1)?.trim() ?? '';
    } else {
      // Fallback: look for content after any title/description headers
      final lines = generatedContent.split('\n');
      bool foundScriptSection = false;
      final scriptLines = <String>[];

      for (final line in lines) {
        if (line.toLowerCase().contains('meditation script:') || line.toLowerCase().contains('script:')) {
          foundScriptSection = true;
          continue;
        }

        if (foundScriptSection &&
            !line.toLowerCase().startsWith('title:') &&
            !line.toLowerCase().startsWith('description:')) {
          scriptLines.add(line);
        }
      }

      if (scriptLines.isNotEmpty) {
        script = scriptLines.join('\n').trim();
      } else {
        // Final fallback: use the entire content if no clear structure found
        script = generatedContent.trim();
      }
    }

    // Generate unique meditation ID for folder naming
    final meditationId = DateTime.now().millisecondsSinceEpoch.toString();

    // Select background sound (use provided one or pick randomly)
    final selectedBackgroundSound = backgroundSound ?? BackgroundSoundManager.getRandomSound();

    // Synthesize audio chunks and get processed script
    final processedScript = await _synthesizeAudioChunks(script, meditationId);

    return MeditationGuide(
      title: title,
      type: type.title,
      description: description,
      durationMinutes: durationMinutes,
      script: processedScript,
      audioId: meditationId,
      backgroundSound: selectedBackgroundSound,
    );
  }

  /// Synthesize audio chunks from meditation script and save them
  /// Returns processed script with chunk indices instead of text
  static Future<String> _synthesizeAudioChunks(String script, String meditationId) async {
    // Create unique folder for this meditation
    final appDocumentsDir = await getApplicationDocumentsDirectory();
    final meditationDir = Directory('${appDocumentsDir.path}/meditation_audio/$meditationId');
    await meditationDir.create(recursive: true);

    // Split script into chunks based on [pause xs] markers
    final chunks = <String>[];
    final pauseDurations = <String>[];

    // Use a more robust approach to parse pause markers
    // This regex handles both [pause 5s] and [pause 5 s] formats
    final pauseRegex = RegExp(r'\[pause\s+(\d+(?:\.\d+)?)\s*s?\s*\]', caseSensitive: false);

    // Find all pause matches first
    final pauseMatches = pauseRegex.allMatches(script).toList();

    int lastIndex = 0;

    for (int i = 0; i < pauseMatches.length; i++) {
      final match = pauseMatches[i];

      // Extract text before this pause
      final textBeforePause = script.substring(lastIndex, match.start).trim();
      if (textBeforePause.isNotEmpty) {
        chunks.add(textBeforePause);

        // Extract pause duration from the match
        final pauseDuration = match.group(1) ?? '3';
        pauseDurations.add(pauseDuration);
      }

      lastIndex = match.end;
    }

    // Add any remaining text after the last pause
    final remainingText = script.substring(lastIndex).trim();
    if (remainingText.isNotEmpty) {
      chunks.add(remainingText);
    }

    // Get TTS model instance
    final tts = TtsModelFactory.instance;

    // Synthesize each text chunk
    final processedChunks = <String>[];

    for (int i = 0; i < chunks.length; i++) {
      final chunkText = chunks[i];

      try {
        final ttsResults = <TtsResult>[];
        // Split chunks containing multiple sentences and generate audio
        // If we don't do this, sherpa-onnx will split by sentences, and for some reason
        // it seems to trim the end of sentence pauses, which make the meditation sound unnatural.
        for (final sentence in chunkText.split(RegExp(r'(?<=[.!?])\s+'))) {
          if (sentence.trim().isNotEmpty) {
            ttsResults.add(await tts.generateSpeech(text: sentence.trim(), voice: 'af_nicole', speed: 0.85));
          }
        }

        final ttsResult = ttsResults.length > 1
            ? TtsResult(
                samples: mergeFloat32Lists(ttsResults.map((e) => e.samples)),
                sampleRate: ttsResults.first.sampleRate,
              )
            : ttsResults.first;

        // Save audio chunk to file
        final audioFile = File('${meditationDir.path}/chunk_$i.wav');
        await audioFile.writeAsBytes(ttsResult.toWav());

        log('Saved audio chunk $i to ${audioFile.path}');

        // Add chunk index to processed script
        processedChunks.add('CHUNK_$i');

        // Add pause after chunk if there's a corresponding pause duration
        if (i < pauseDurations.length) {
          processedChunks.add('[pause ${pauseDurations[i]}s]');
        }
      } catch (e, s) {
        log('Error synthesizing chunk $i: $e', error: e, stackTrace: s);
        // Fallback: keep original text if synthesis fails
        processedChunks.add(chunkText);
        if (i < pauseDurations.length) {
          processedChunks.add('[pause ${pauseDurations[i]}s]');
        }
      }
    }

    return processedChunks.join(' ');
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
