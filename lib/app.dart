import 'package:flutter/material.dart';
import 'package:waico/core/gemma3n_model.dart';
import 'package:waico/core/utils/model_download_utils.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/pages/ai_model_init_page.dart';
import 'package:waico/pages/home_page.dart';
import 'package:provider/provider.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final defaultTheme = Theme.of(context);
    final primaryColor = Color(0xFF4B9B6E);
    return MaterialApp(
      title: 'Waico',
      theme: defaultTheme.copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: primaryColor).copyWith(primary: primaryColor),
        appBarTheme: defaultTheme.appBarTheme.copyWith(backgroundColor: primaryColor, foregroundColor: Colors.white),
      ),
      home: _Entrypoint(),
    );
  }
}

class _Entrypoint extends StatefulWidget {
  @override
  State<_Entrypoint> createState() => _EntrypointState();
}

class _EntrypointState extends State<_Entrypoint> {
  final modelsToDownload = <DownloadItem>[
    DownloadItem(
      url: "${DownloadItem.baseUrl}/gemma-3n-E2B-it.task",
      fileName: "gemma-3n-E2B-it.task",
      displayName: "Gemma 3n E2B",
    ),
    DownloadItem(url: "${DownloadItem.baseUrl}/kokoro-v1.0.onnx", fileName: "kokoro.onnx", displayName: "Kokoro TTS"),
    DownloadItem(
      url: "${DownloadItem.baseUrl}/kokoro-voices-v1.0.json",
      fileName: "kokoro-voices.json",
      displayName: "AI Voices",
    ),
  ];

  @override
  void dispose() {
    Gemma3nModel.unloadBaseModel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AiModelsInitializationPage(
      downloadItems: modelsToDownload,
      onDone: () async {
        final downloadedModelPaths = DownloadedModelPaths(
          gemma3nPath: await modelsToDownload[0].task!.filePath(),
          kokoroPath: await modelsToDownload[1].task!.filePath(),
          kokoroVoicesPath: await modelsToDownload[2].task!.filePath(),
        );

        // ignore: use_build_context_synchronously
        context.navigateTo(
          Provider.value(value: downloadedModelPaths, updateShouldNotify: (_, _) => false, child: HomePage()),
        );
      },
    );
  }
}
