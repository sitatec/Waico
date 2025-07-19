import 'package:flutter/material.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/core/widgets/ai_voice_waveform.dart';
import 'package:waico/core/widgets/loading_widget.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show WakelockPlus;

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
        // Enable wakelock to keep the screen on during the voice chat session
        WakelockPlus.enable();
      });
    });
  }

  @override
  void dispose() {
    widget.voiceChatPipeline.endChat();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(width: double.infinity),
            Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 125, maxWidth: 350),
                child: AIVoiceWaveform(loudnessStream: widget.voiceChatPipeline.aiSpeechLoudnessStream),
              ),
            ),
          ],
        ),
        if (!_chatStarted) LoadingWidget(message: "Starting chat session"),
      ],
    );
  }
}
