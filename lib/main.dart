import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:waico/app.dart';
import 'package:waico/core/stt_model.dart';
import 'package:waico/core/user_speech_listener.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const _TestApp());
}

class _TestApp extends StatefulWidget {
  const _TestApp();

  @override
  State<_TestApp> createState() => __TestAppState();
}

class __TestAppState extends State<_TestApp> {
  late final UserSpeechToTextListener listener;
  final List<String> speechState = [];

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    listener.dispose();
    SttModel.dispose();
    super.dispose();
  }

  Future<void> init() async {
    sherpa_onnx.initBindings();
    print(Directory("/data/user/0/ai.buinitylabs.waico/app_flutter/ai_models/parakeet-tdt-0.6b-v2-int8").listSync());
    // return;
    await SttModel.initialize(
      modelPath: "/data/user/0/ai.buinitylabs.waico/app_flutter/ai_models/parakeet-tdt-0.6b-v2-int8",
    );
    listener = UserSpeechListener.withTranscription();
    if (!await listener.hasRecordingPermission) {
      throw Exception("Record Permission required");
    }
    await listener.initialize();
    print("UserSpeechListener initialized");
    listener.listen((text) {
      speechState.add(text);
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Material(
        child: SafeArea(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: speechState.map(Text.new).toList()),
        ),
      ),
    );
  }
}
