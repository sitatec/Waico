import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/core/widgets/loading_widget.dart';
import 'package:waico/core/widgets/voice_chat_view.dart';

class CounselorPage extends StatefulWidget {
  const CounselorPage({super.key});

  @override
  State<CounselorPage> createState() => _CounselorPageState();
}

class _CounselorPageState extends State<CounselorPage> {
  String _conversationMode = 'speech';
  ChatModel? _chatModel;
  VoiceChatPipeline? _voiceChat;
  bool _initialized = false;

  bool get _isSpeechMode => _conversationMode == 'speech';

  @override
  void initState() {
    super.initState();
    // We use context and setState in the init() method so we wait util build finish before running it
    WidgetsBinding.instance.addPostFrameCallback((_) => init());
  }

  Future<void> init() async {
    _chatModel = ChatModel(systemPrompt: _getSystemPrompt());
    await _chatModel!.initialize();
    // ignore: use_build_context_synchronously
    _voiceChat = VoiceChatPipeline(llm: _chatModel!);
    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _voiceChat?.dispose();
    _chatModel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            toolbarHeight: 50,
            titleSpacing: 8,
            title: Text("Counselor", style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white, fontSize: 20)),
            actions: [
              Text("Mode:"),
              const SizedBox(width: 8),
              DropdownButton(
                isDense: true,
                underline: const SizedBox.shrink(),
                iconEnabledColor: Colors.white,
                dropdownColor: theme.colorScheme.primary,
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                items: [
                  DropdownMenuItem(value: "speech", child: Text("Speech")),
                  DropdownMenuItem(value: "text", child: Text("Text")),
                ],
                value: _conversationMode,
                onChanged: (value) {
                  setState(() {
                    _conversationMode = value!;
                  });
                },
              ),
            ],
          ),
          body: _initialized
              ? _isSpeechMode
                    ? VoiceChatView(voiceChatPipeline: _voiceChat!)
                    : LlmChatView(provider: _chatModel!, enableVoiceNotes: false)
              : null,
        ),
        if (!_initialized) LoadingWidget(message: "Initializing Chat"),
      ],
    );
  }
}

String _getSystemPrompt() =>
    "You are Waico, a compassionate and trustworthy AI counselor. "
    "Your role is to provide emotional support, active listening, and thoughtful guidance rooted in evidence-based therapeutic principles (such as CBT, ACT, and mindfulness). "
    "Respond with empathy, clarity, and non-judgment. Encourage self-reflection, validate emotions, and offer practical coping strategies when appropriate. "
    "You are not a licensed therapist and do not diagnose or treat mental health conditions—always recommend speaking to a qualified professional when needed. "
    "Prioritize safety, confidentiality, and the well-being of the user in every interaction.";
