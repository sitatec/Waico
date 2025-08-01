import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/core/widgets/ai_voice_waveform.dart';
import 'package:waico/core/widgets/loading_widget.dart';
import 'package:wakelock_plus/wakelock_plus.dart' show WakelockPlus;

class VoiceChatView extends StatefulWidget {
  final VoiceChatPipeline voiceChatPipeline;
  final String voice;
  final double speechSpeed;

  const VoiceChatView({super.key, required this.voiceChatPipeline, this.voice = "af_heart", this.speechSpeed = 1.0});

  @override
  State<VoiceChatView> createState() => _VoiceChatViewState();
}

class _VoiceChatViewState extends State<VoiceChatView> {
  bool _chatStarted = false;
  final _imagePicker = ImagePicker();
  final _pageController = PageController(viewportFraction: 0.9);

  /// A history of what the AI has displayed to the user and what the user has sent to the AI.
  final _displayHistory = <Widget>[];

  @override
  void initState() {
    super.initState();
    widget.voiceChatPipeline.startChat(voice: widget.voice).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _chatStarted = true;
        });
        // Enable wakelock to keep the screen on during the voice chat session
        WakelockPlus.enable();
      });
    });
    _retrieveLostData();
  }

  Future<void> _retrieveLostData() async {
    final lostData = await _imagePicker.retrieveLostData();
    if (lostData.files != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (var image in lostData.files!) {
          displayImage(image);
        }
      });
    }
  }

  void displayImage(XFile image) {
    setState(() {
      _displayHistory.add(Image.file(File(image.path), fit: BoxFit.contain, width: double.infinity));
      _pageController.animateToPage(
        _displayHistory.length - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
            const SizedBox(height: 16), // Space for the top bar
            AspectRatio(
              aspectRatio: 1,
              child: PageView(
                controller: _pageController,
                children: [
                  ..._displayHistory,
                  Card(
                    clipBehavior: Clip.hardEdge,
                    color: Colors.white,
                    child: InkWell(
                      onTap: () async {
                        final image = await _pickImage();
                        if (image != null) {
                          displayImage(image);
                        }
                      },
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo, size: 40, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 16),
                          Text(
                            "Show an image to Waico",
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
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

  Future<XFile?> _pickImage() async {
    final source = await _showImageSourcePicker(context);
    if (source == null) return null;
    return await _imagePicker.pickImage(source: source);
  }

  Future<ImageSource?> _showImageSourcePicker(BuildContext context) {
    final theme = Theme.of(context);
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Card(
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop(ImageSource.camera);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.camera_alt_outlined, size: 47, color: theme.colorScheme.primary),
                          const SizedBox(height: 8),
                          Text('Camera'),
                        ],
                      ),
                    ),
                  ),
                ),
                Card(
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pop(ImageSource.gallery);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.image_outlined, size: 50, color: theme.colorScheme.primary),
                          const SizedBox(height: 8),
                          Text('Gallery'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
