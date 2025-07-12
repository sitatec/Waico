import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:waico/core/chat_model.dart';
import 'package:waico/core/constants.dart';
import 'package:waico/core/stt_model.dart';
import 'package:waico/core/tts_model.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/examples/calendar_example.dart';
import 'package:waico/pages/ai_model_init_page.dart';
import 'package:waico/pages/home_page.dart';
import 'package:provider/provider.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    sherpa_onnx.initBindings();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log("#######\n   AppState : $state\n#######");
    if (state == AppLifecycleState.detached) {
      log("App closing detected, disposing Models");
      ChatModel.unloadBaseModel();
      TtsModel.dispose();
      SttModel.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultTheme = Theme.of(context);

    return MaterialApp(
      title: 'Waico',
      theme: defaultTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor).copyWith(primary: primaryColor),
        appBarTheme: defaultTheme.appBarTheme.copyWith(backgroundColor: primaryColor, foregroundColor: Colors.white),
      ),
      home: Builder(
        builder: (context) {
          return CalendarServiceWidget();
          // return AiModelsInitializationPage(
          //   onDone: (downloadedModelPaths) {
          //     context.navigateTo(
          //       Provider.value(value: downloadedModelPaths, updateShouldNotify: (_, _) => false, child: HomePage()),
          //       replaceCurrent: true,
          //     );
          //   },
          // );
        },
      ),
    );
  }
}
