import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/constants.dart';
import 'package:waico/core/ai_models/stt_model.dart';
import 'package:waico/core/ai_models/tts_model.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/ai_models_init_page.dart';
import 'package:waico/home_page.dart';
import 'package:waico/generated/locale_keys.g.dart';
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
      // Only one of the TTS model need to be disposed, but we can call dispose unconditionally.
      // It will gracefully handle the case where the model is not initialized.
      PremiumTtsModel.dispose();
      LiteTtsModel.dispose();
      SttModel.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final defaultTheme = Theme.of(context);

    return MaterialApp(
      title: LocaleKeys.app_title.tr(),
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      theme: defaultTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor).copyWith(primary: primaryColor),
        appBarTheme: defaultTheme.appBarTheme.copyWith(backgroundColor: primaryColor, foregroundColor: Colors.white),
      ),
      home: true
          ? HomePage()
          : Builder(
              // Using a Builder to ensure we get the correct context from material app for navigation
              builder: (context) {
                return AiModelsInitializationPage(
                  onDone: (downloadedModelPaths) {
                    context.navigateTo(
                      Provider.value(
                        value: downloadedModelPaths,
                        updateShouldNotify: (_, _) => false,
                        child: HomePage(),
                      ),
                      replaceCurrent: true,
                    );
                  },
                );
              },
            ),
    );
  }
}
