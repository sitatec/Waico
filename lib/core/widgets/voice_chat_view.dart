import 'package:flutter/material.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/core/widgets/ai_voice_waveform.dart';
import 'package:waico/core/widgets/loading_widget.dart';

class VoiceChatView extends StatefulWidget {
  final VoiceChatPipeline voiceChatPipeline;

  const VoiceChatView({super.key, required this.voiceChatPipeline});

  @override
  State<VoiceChatView> createState() => _VoiceChatViewState();
}

class _VoiceChatViewState extends State<VoiceChatView> {
  bool _chatStarted = false;

  @override
  void initState() {
    super.initState();
    widget.voiceChatPipeline.startChat(voice: "af_heart").then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _chatStarted = true;
        });
      });
    });
  }

  @override
  void dispose() {
    widget.voiceChatPipeline.endChat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 150,
              child: AIVoiceWaveform(loudnessStream: widget.voiceChatPipeline.aiSpeechLoudnessStream),
            ),
          ],
        ),
        if (!_chatStarted) LoadingWidget(message: "Starting chat session"),
      ],
    );
  }
}
