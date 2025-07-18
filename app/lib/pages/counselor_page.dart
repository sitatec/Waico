import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/ai_agent/counselor_agent.dart';
import 'package:waico/core/services/health_service.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/core/widgets/chart_widget.dart' show ChartDataPoint;
import 'package:waico/core/widgets/loading_widget.dart';
import 'package:waico/core/widgets/voice_chat_view.dart';

class CounselorPage extends StatefulWidget {
  const CounselorPage({super.key});

  @override
  State<CounselorPage> createState() => _CounselorPageState();
}

class _CounselorPageState extends State<CounselorPage> {
  String _conversationMode = 'speech';
  CounselorAgent? _agent;
  VoiceChatPipeline? _voiceChat;
  bool _initialized = false;
  bool finalizationModalShown = false;

  bool get _isSpeechMode => _conversationMode == 'speech';

  @override
  void initState() {
    super.initState();
    // We use context and setState in the init() method so we wait util build finish before running it
    WidgetsBinding.instance.addPostFrameCallback((_) => init());
  }

  Future<void> init() async {
    final healthService = HealthService();
    await healthService.initialize();
    _agent = CounselorAgent(healthService: healthService, displayHealthData: _displayHealthData);
    await _agent!.initialize();
    // ignore: use_build_context_synchronously
    _voiceChat = VoiceChatPipeline(agent: _agent!);
    setState(() {
      _initialized = true;
    });
  }

  @override
  void dispose() {
    _voiceChat?.dispose();
    _agent?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || finalizationModalShown) return;
        finalizationModalShown = true;
        _showChatFinalizationProgressModal();
      },
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              toolbarHeight: 50,
              titleSpacing: 8,
              leading: BackButton(
                onPressed: () {
                  if (_initialized) {
                    _showChatFinalizationProgressModal();
                  } else {
                    context.navBack();
                  }
                },
              ),
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
            body: _initialized
                ? _isSpeechMode
                      ? VoiceChatView(voiceChatPipeline: _voiceChat!)
                      : LlmChatView(
                          enableVoiceNotes: false,
                          provider: _agent!.chatModel,
                          messageSender: _agent!.sendMessage,
                        )
                : null,
          ),
          if (!_initialized) LoadingWidget(message: "Initializing Chat"),
        ],
      ),
    );
  }

  void _displayHealthData(List<ChartDataPoint> healthData) {
    throw UnimplementedError("Display health data is not implemented yet.");
  }

  Future<void> _showChatFinalizationProgressModal() {
    Map<String, bool> progress = {};
    bool finalizationStarted = false;
    return showModalBottomSheet(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (!finalizationStarted) {
              _agent!.finalize(
                updateProgress: (newProgress) {
                  setState(() => progress = newProgress);
                  if (newProgress.isNotEmpty && newProgress.values.every((value) => value)) {
                    // All tasks completed, close the modal
                    Future.delayed(const Duration(milliseconds: 700), () {
                      // Close the finalization modal and the counselor page
                      if (context.mounted) {
                        context.navBack();
                        context.navBack();
                      }
                    });
                  }
                },
              );
              finalizationStarted = true;
            }
            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Processing conversation", style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 16),
                  if (progress.isEmpty)
                    const Text("please wait...") // Initial state before any progress is made
                  else
                    ...progress.entries.map((entry) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(entry.key, style: Theme.of(context).textTheme.bodyMedium),
                          SizedBox(width: 8),
                          Visibility(
                            visible: entry.value,
                            maintainSize: true,
                            maintainAnimation: true,
                            maintainState: true,
                            child: Icon(Icons.check, color: Colors.green, size: 18),
                          ),
                        ],
                      );
                    }),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [ElevatedButton(onPressed: _confirmFinalizationCancel, child: const Text("Cancel"))],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmFinalizationCancel() {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Cancel Finalization"),
          content: const Text(
            "Are you sure you want to cancel the finalization?\nThis process helps improve your experience by extracting useful information from the conversation for future reference.",
          ),
          actions: [
            TextButton(onPressed: context.navBack, child: const Text("No")),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: () {
                context.navBack(); // Close the confirmation dialog
                context.navBack(); // Close the counselor page
              },
              child: const Text("Yes"),
            ),
          ],
        );
      },
    );
  }
}
