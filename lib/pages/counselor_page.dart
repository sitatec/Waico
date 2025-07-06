import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/gemma3n_model.dart';
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
  final _llm = Gemma3nModel();
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
    await _llm.initialize();
    // ignore: use_build_context_synchronously
    _voiceChat = VoiceChatPipeline(llm: _llm);
    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _voiceChat?.dispose();
    _llm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
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
                    : LlmChatView(provider: _llm, enableVoiceNotes: false)
              : null,
        ),
        if (!_initialized) LoadingWidget(message: "Initializing Chat"),
      ],
    );
  }
}
