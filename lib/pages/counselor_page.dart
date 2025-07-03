import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/gemma3n_model.dart';

class CounselorPage extends StatefulWidget {
  const CounselorPage({super.key});

  @override
  State<CounselorPage> createState() => _CounselorPageState();
}

class _CounselorPageState extends State<CounselorPage> {
  String _conversationMode = 'speech';
  final _llm = Gemma3nModel();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    // TODO: Uncomment when ready
    // _llm.initialize().then((_) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     setState(() {
    //       _initialized = true;
    //     });
    //   });
    // });
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
          body: LlmChatView(provider: _llm),
        ),
        if (!_initialized)
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black.withValues(alpha: 0.7),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator.adaptive(),
                  const SizedBox(height: 16),
                  Text("Initializing Chat", style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
