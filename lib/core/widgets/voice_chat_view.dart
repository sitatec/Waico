import 'package:flutter/material.dart';
import 'package:siri_wave/siri_wave.dart' show IOS9SiriWaveformController, IOS9SiriWaveformOptions, SiriWaveform;
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/core/widgets/loading_widget.dart';

class VoiceChatView extends StatefulWidget {
  final VoiceChatPipeline voiceChatPipeline;

  const VoiceChatView({super.key, required this.voiceChatPipeline});

  @override
  State<VoiceChatView> createState() => _VoiceChatViewState();
}

class _VoiceChatViewState extends State<VoiceChatView> {
  final aiVoiceWaveController = IOS9SiriWaveformController(
    amplitude: 0.5,
    color1: Colors.green,
    color2: Colors.tealAccent,
    color3: Colors.blue,
    speed: 0.15,
  );
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

      widget.voiceChatPipeline.aiSpeechLoudnessStream.listen((loudness) {
        aiVoiceWaveController
          ..amplitude = loudness
          ..speed = loudness * 0.5;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Column(
          children: [
            const Spacer(),
            SiriWaveform.ios9(
              controller: aiVoiceWaveController,
              options: const IOS9SiriWaveformOptions(height: 200, width: 400),
            ),
          ],
        ),
        if (!_chatStarted) LoadingWidget(message: "Starting chat session"),
      ],
    );
  }
}
