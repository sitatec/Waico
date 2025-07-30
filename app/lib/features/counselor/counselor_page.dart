import 'package:flutter/material.dart';
import 'package:flutter_ai_toolkit/flutter_ai_toolkit.dart';
import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/features/counselor/counselor_agent.dart';
import 'package:waico/core/services/health_service.dart';
import 'package:waico/core/utils/navigation_utils.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/core/widgets/chart_widget.dart' show ChartDataPoint;
import 'package:waico/core/widgets/loading_widget.dart';
import 'package:waico/core/widgets/voice_chat_view.dart';
import 'package:waico/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';

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
  bool chatProcessingModalShown = false;

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
    final user = await UserRepository().getUser();
    _agent = CounselorAgent(
      healthService: healthService,
      displayHealthData: _displayHealthData,
      userInfo: user!.userInfo,
    );
    await _agent!.initialize();
    // ignore: use_build_context_synchronously
    _voiceChat = VoiceChatPipeline(agent: _agent!);
    if (mounted) {
      setState(() {
        _initialized = true;
      });
    } else {
      // If the user exits the page while the agent is initializing (which can take a while),
      _voiceChat?.dispose();
      _agent?.chatModel.dispose();
    }
  }

  @override
  void dispose() {
    _voiceChat?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_initialized,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || chatProcessingModalShown) return;
        if (_initialized) {
          _showChatEndConfirmationBottomSheet();
        } else {
          context.navBack();
        }
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
                    _showChatEndConfirmationBottomSheet();
                  } else {
                    context.navBack();
                  }
                },
              ),
              title: Text(
                LocaleKeys.counselor_title.tr(),
                style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white, fontSize: 20),
              ),
              actions: [
                Text("${LocaleKeys.counselor_mode_label.tr()}:"),
                const SizedBox(width: 8),
                DropdownButton(
                  isDense: true,
                  underline: const SizedBox.shrink(),
                  iconEnabledColor: Colors.white,
                  dropdownColor: theme.colorScheme.primary,
                  style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white),
                  items: [
                    DropdownMenuItem(value: "speech", child: Text(LocaleKeys.counselor_speech_mode.tr())),
                    DropdownMenuItem(value: "text", child: Text(LocaleKeys.counselor_text_mode.tr())),
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
          if (!_initialized) LoadingWidget(message: LocaleKeys.counselor_initializing_chat.tr()),
        ],
      ),
    );
  }

  void _displayHealthData(List<ChartDataPoint> healthData) {
    throw UnimplementedError("Display health data is not implemented yet.");
  }

  Future<void> _showChatEndConfirmationBottomSheet() {
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: !_initialized,
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(LocaleKeys.counselor_end_chat_question.tr(), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FilledButton(
                      onPressed: () {
                        context.navBack(); // Close the confirmation dialog
                        Future.microtask(_showChatProcessingProgressModal);
                        chatProcessingModalShown = true;
                      },
                      child: Text(LocaleKeys.counselor_end_chat_button.tr()),
                    ),
                    const SizedBox(width: 16),
                    TextButton(onPressed: context.navBack, child: Text(LocaleKeys.counselor_continue_chatting.tr())),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showChatProcessingProgressModal() {
    Map<String, bool> progress = {};
    bool processingStarted = false;
    // The element being processed (elements are processed sequentially, since its on-device llm inference)
    String currentElement = '';
    return showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: StatefulBuilder(
            builder: (context, setState) {
              if (!processingStarted) {
                _voiceChat!.endChat();
                _agent!.finalize(
                  updateProgress: (newProgress) {
                    setState(() {
                      progress = newProgress;
                      currentElement = newProgress.entries
                          // Get the first element that is not complete, if all are complete reset current element to ''
                          .firstWhere((entry) => entry.value == false, orElse: () => MapEntry('', false))
                          .key;
                    });
                    if (newProgress.isNotEmpty && newProgress.values.every((value) => value)) {
                      // All tasks completed, close the modal
                      Future.delayed(const Duration(milliseconds: 700), () {
                        // Close the processing modal and the counselor page
                        if (context.mounted) {
                          context.navBack();
                          Future.microtask(context.navBack);
                        }
                      });
                    }
                  },
                );
                processingStarted = true;
              }
              return Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      LocaleKeys.counselor_processing_conversation.tr(),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 10),
                    Text(LocaleKeys.counselor_processing_description.tr()),
                    const SizedBox(height: 20),
                    if (progress.isEmpty)
                      Text(LocaleKeys.counselor_please_wait.tr()) // Initial state before any progress is made
                    else
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: progress.entries
                              .map((entry) {
                                return Row(
                                  children: [
                                    if (entry.key == currentElement)
                                      // Show loading indicator for the element currently being precessed
                                      CircularProgressIndicator.adaptive(
                                        constraints: const BoxConstraints.tightFor(width: 15, height: 15),
                                        strokeWidth: 2,
                                      )
                                    else
                                      Visibility(
                                        visible: entry.value,
                                        maintainSize: true,
                                        maintainAnimation: true,
                                        maintainState: true,
                                        child: Icon(Icons.check, color: Colors.green, size: 17),
                                      ),
                                    SizedBox(width: 10),
                                    Text(entry.key, style: Theme.of(context).textTheme.bodyMedium),
                                    SizedBox(width: 8),
                                  ],
                                );
                              })
                              .toList(growable: false),
                        ),
                      ),
                    const SizedBox(height: 24),
                    // TODO: add cancelation logic to ConversationProcessor
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.end,
                    //   children: [TextButton(onPressed: _confirmProcessingCancel, child: const Text("Cancel"))],
                    // ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  // ignore: unused_element
  Future<void> _confirmProcessingCancel() {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(LocaleKeys.counselor_cancel_processing.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(LocaleKeys.counselor_cancel_processing_question.tr(), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              Text(LocaleKeys.counselor_processing_description.tr(), style: const TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                context.navBack(); // Close the confirmation dialog
                context.navBack(); // Close the Conversation Processing bottom sheet
                context.navBack(); // Close the counselor page
              },
              child: Text(LocaleKeys.counselor_cancel_button.tr()),
            ),
            const SizedBox(width: 16),
            FilledButton(onPressed: context.navBack, child: Text(LocaleKeys.counselor_continue_processing.tr())),
          ],
        );
      },
    );
  }
}
