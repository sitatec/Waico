import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
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
  final listener = UserSpeechListener();
  final List<String> speechState = [];

  @override
  void initState() {
    super.initState();
    init();
  }

  @override
  void dispose() {
    listener.dispose();
    super.dispose();
  }

  Future<void> init() async {
    sherpa_onnx.initBindings();
    if (!await listener.hasRecordingPermission) {
      throw Exception("Record Permission required");
    }
    listener.initialize(await copyModelToAppDir());
    print("UserSpeechListener initialized");
    listener.listen((_) {
      speechState.add("Speech received");
      setState(() {});
    });
  }

  Future<String> copyModelToAppDir() async {
    // Load the model from assets
    final byteData = await rootBundle.load('assets/silero_vad_v5.onnx');

    // Get the app's document directory
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/silero_vad_v5.onnx');

    // Write the bytes to a file
    await file.writeAsBytes(byteData.buffer.asUint8List(), flush: true);

    return file.path;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: ColoredBox(
        color: Colors.white,
        child: Column(children: speechState.map(Text.new).toList()),
      ),
    );
  }
}
