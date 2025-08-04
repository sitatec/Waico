import 'dart:async';
import 'dart:io';
import 'dart:developer' show log;
import 'package:path_provider/path_provider.dart';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/ai_models/tts_model.dart';
import 'package:waico/core/utils/list_utils.dart';
import 'package:waico/features/meditation/models/meditation_guide.dart';
import 'package:waico/features/meditation/background_sound_manager.dart';
import 'package:waico/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';

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
    log(LocaleKeys.meditation_generator_log_messages_generating_prompt.tr(namedArgs: {'prompt': prompt}));
    String generatedContent = '';
    await for (final chunk in chatModel.sendMessageStream(prompt)) {
      generatedContent += chunk;
    }
    log(LocaleKeys.meditation_generator_log_messages_generated_content.tr(namedArgs: {'content': generatedContent}));
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
    return LocaleKeys.meditation_generator_system_prompt.tr();
  }

  static String _buildPrompt(MeditationType type, int durationMinutes, String? customTitle) {
    final titleInstruction = customTitle != null
        ? LocaleKeys.meditation_generator_prompts_title_instruction.tr(namedArgs: {'title': customTitle})
        : '';

    final basePrompt =
        titleInstruction +
        LocaleKeys.meditation_generator_prompts_base_prompt.tr(namedArgs: {'duration': durationMinutes.toString()});

    switch (type) {
      case MeditationType.mindfulness:
        return basePrompt + LocaleKeys.meditation_generator_prompts_mindfulness.tr();

      case MeditationType.bodyScanning:
        return basePrompt + LocaleKeys.meditation_generator_prompts_body_scanning.tr();

      case MeditationType.lovingKindness:
        return basePrompt + LocaleKeys.meditation_generator_prompts_loving_kindness.tr();

      case MeditationType.breathwork:
        return basePrompt + LocaleKeys.meditation_generator_prompts_breathwork.tr();

      case MeditationType.visualization:
        return basePrompt + LocaleKeys.meditation_generator_prompts_visualization.tr();

      case MeditationType.walking:
        return basePrompt + LocaleKeys.meditation_generator_prompts_walking.tr();

      case MeditationType.mantra:
        return basePrompt + LocaleKeys.meditation_generator_prompts_mantra.tr();

      case MeditationType.beginner:
        return basePrompt + LocaleKeys.meditation_generator_prompts_beginner.tr();
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
    final titleRegex = RegExp(
      '${LocaleKeys.meditation_generator_parsing_title_prefix.tr()}\\s*(.+)',
      caseSensitive: false,
    );
    final titleMatch = titleRegex.firstMatch(generatedContent);
    if (titleMatch != null && customTitle == null) {
      title = titleMatch.group(1)?.trim() ?? title;
    }

    // Extract description from the response
    String description = _generateDescriptionForType(type);
    final descriptionRegex = RegExp(
      '${LocaleKeys.meditation_generator_parsing_description_prefix.tr()}\\s*(.+)',
      caseSensitive: false,
    );
    final descriptionMatch = descriptionRegex.firstMatch(generatedContent);
    if (descriptionMatch != null) {
      description = descriptionMatch.group(1)?.trim() ?? description;
    }

    // Extract script from the response after "Meditation Script:" line
    String script = '';
    final scriptRegex = RegExp(
      '${LocaleKeys.meditation_generator_parsing_script_prefix.tr()}\\s*\\n([\\s\\S]*)',
      multiLine: true,
    );
    final scriptMatch = scriptRegex.firstMatch(generatedContent);
    if (scriptMatch != null) {
      script = scriptMatch.group(1)?.trim() ?? '';
    } else {
      // Fallback: look for content after any title/description headers
      final lines = generatedContent.split('\n');
      bool foundScriptSection = false;
      final scriptLines = <String>[];

      for (final line in lines) {
        final lowerLine = line.toLowerCase();
        final scriptPrefix = LocaleKeys.meditation_generator_parsing_script_prefix.tr().toLowerCase();
        if (lowerLine.contains(scriptPrefix) || lowerLine.contains('script:')) {
          foundScriptSection = true;
          continue;
        }

        if (foundScriptSection &&
            !lowerLine.startsWith(LocaleKeys.meditation_generator_parsing_title_prefix.tr().toLowerCase()) &&
            !lowerLine.startsWith(LocaleKeys.meditation_generator_parsing_description_prefix.tr().toLowerCase())) {
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

        log(
          LocaleKeys.meditation_generator_log_messages_saved_audio_chunk.tr(
            namedArgs: {'index': i.toString(), 'path': audioFile.path},
          ),
        );

        // Add chunk index to processed script
        processedChunks.add('CHUNK_$i');

        // Add pause after chunk if there's a corresponding pause duration
        if (i < pauseDurations.length) {
          processedChunks.add('[pause ${pauseDurations[i]}s]');
        }
      } catch (e, s) {
        log(
          LocaleKeys.meditation_generator_log_messages_synthesis_error.tr(
            namedArgs: {'index': i.toString(), 'error': e.toString()},
          ),
          error: e,
          stackTrace: s,
        );
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
        return LocaleKeys.meditation_generator_titles_mindfulness.tr();
      case MeditationType.bodyScanning:
        return LocaleKeys.meditation_generator_titles_body_scanning.tr();
      case MeditationType.lovingKindness:
        return LocaleKeys.meditation_generator_titles_loving_kindness.tr();
      case MeditationType.breathwork:
        return LocaleKeys.meditation_generator_titles_breathwork.tr();
      case MeditationType.visualization:
        return LocaleKeys.meditation_generator_titles_visualization.tr();
      case MeditationType.walking:
        return LocaleKeys.meditation_generator_titles_walking.tr();
      case MeditationType.mantra:
        return LocaleKeys.meditation_generator_titles_mantra.tr();
      case MeditationType.beginner:
        return LocaleKeys.meditation_generator_titles_beginner.tr();
    }
  }

  static String _generateDescriptionForType(MeditationType type) {
    switch (type) {
      case MeditationType.mindfulness:
        return LocaleKeys.meditation_generator_descriptions_mindfulness.tr();
      case MeditationType.bodyScanning:
        return LocaleKeys.meditation_generator_descriptions_body_scanning.tr();
      case MeditationType.lovingKindness:
        return LocaleKeys.meditation_generator_descriptions_loving_kindness.tr();
      case MeditationType.breathwork:
        return LocaleKeys.meditation_generator_descriptions_breathwork.tr();
      case MeditationType.visualization:
        return LocaleKeys.meditation_generator_descriptions_visualization.tr();
      case MeditationType.walking:
        return LocaleKeys.meditation_generator_descriptions_walking.tr();
      case MeditationType.mantra:
        return LocaleKeys.meditation_generator_descriptions_mantra.tr();
      case MeditationType.beginner:
        return LocaleKeys.meditation_generator_descriptions_beginner.tr();
    }
  }
}
