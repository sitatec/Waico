import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/ai_models/embedding_model.dart';
import 'package:waico/core/ai_models/stt_model.dart';
import 'package:waico/core/ai_models/tts_model.dart';
import 'package:waico/core/utils/model_download_utils.dart';
import 'package:waico/core/services/app_preferences.dart';
import 'package:waico/core/widgets/voice_model_selection_modal.dart';
import 'package:waico/generated/locale_keys.g.dart';

class DownloadItem {
  static String get baseUrl {
    // During development we setup a local server to download the models and provide it's URL
    // in the MODELS_DOWNLOAD_BASE_URL env var. But you can still use the huggingface url in dev mode
    const url = String.fromEnvironment("MODELS_DOWNLOAD_BASE_URL");
    if (url.isNotEmpty) {
      if (Platform.isAndroid) {
        // Android emulators can't access the host using localhost, they use the special IP 10.0.2.2 instead
        return url.replaceAll("localhost", "10.0.2.2");
      }
      return url;
    }

    return "https://huggingface.co/sitatech/waico-models/resolve/main";
  }

  final String url;
  final String? displayName;
  final String fileName;
  double progress;
  String? fileSize;
  bool isCompleted;
  bool isError;
  bool isPaused;
  String? errorMessage;
  DownloadTask? task;

  /// Return the filepath of the downloaded file. Most be called when download completes
  Future<String> get downloadedFilePath => task!.filePath();

  DownloadItem({
    required this.url,
    required this.fileName,
    this.displayName,
    this.progress = 0.0,
    this.isCompleted = false,
    this.isError = false,
    this.isPaused = false,
    this.errorMessage,
    this.task,
  });
}

class AiModelsInitializationPage extends StatefulWidget {
  final Function(DownloadedModelPaths)? onDone;

  const AiModelsInitializationPage({super.key, this.onDone});

  @override
  State<AiModelsInitializationPage> createState() => _AiModelsInitializationPageState();
}

class _AiModelsInitializationPageState extends State<AiModelsInitializationPage> {
  List<DownloadItem> _modelsToDownload = [];
  bool isReady = false;
  bool isDownloading = false;
  bool isInitializingModels = false;
  bool isInitializationComplete = false;
  double modelLoadingProgress = 0.0;
  int currentDownloadIndex = 0;
  late final StreamSubscription<TaskUpdate> _downloadUpdatesSubscription;
  Timer? _progressTimer;
  final _downloader = FileDownloader();
  bool _hasShownDevicePerfSelection = false;
  late final currentLanguageCode = context.locale.languageCode;

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await _setupDownloader();

    // Check if we need to show voice model selection
    if (!AppPreferences.hasShownDevicePerfSelection()) {
      _showDevicePerfSelectionModal();
      return;
    }

    await _continueAfterDevicePerfSelection();
  }

  void _showDevicePerfSelectionModal() {
    if (_hasShownDevicePerfSelection) return;

    _hasShownDevicePerfSelection = true;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: VoiceModelSelectionModal(
            onContinue: () {
              Navigator.of(context).pop();
              _continueAfterDevicePerfSelection();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _continueAfterDevicePerfSelection() async {
    await _setupModelsToDownload();
    await _initDownloadTasks();
    setState(() {
      isReady = true;
    });

    // Check if all downloads are already complete if this is not the first time the app is opened
    final allComplete = _modelsToDownload.every((item) => item.isCompleted);
    if (allComplete) {
      await _startInitialization();
    } else {
      _downloadNextFile();
    }
  }

  Future<void> _setupModelsToDownload() async {
    final voiceModelType = AppPreferences.getVoiceModelType();

    _modelsToDownload = [
      DownloadItem(
        url: "${DownloadItem.baseUrl}/canary-180m-flash.tar.gz",
        fileName: "canary-180m-flash.tar.gz",
        displayName: "Canary Flash",
      ),
      DownloadItem(
        url: "${DownloadItem.baseUrl}/gemma-3n-E2B-it-int4.task",
        fileName: "gemma-3n-E2B-it-int4.task",
        displayName: "Gemma 3n E2B",
      ),
      DownloadItem(
        url: "${DownloadItem.baseUrl}/Qwen3-Embedding-0.6B-Q8_0.gguf",
        fileName: "Qwen3-Embedding-0.6B-Q8_0.gguf",
        displayName: "Qwen3 Embedding",
      ),
    ];

    // Add the appropriate TTS model based on user choice
    if (voiceModelType == VoiceModelType.premium) {
      _modelsToDownload.add(
        DownloadItem(
          url: "${DownloadItem.baseUrl}/kokoro-v1_0.tar.gz",
          fileName: "kokoro-v1_0.tar.gz",
          displayName: "Kokoro TTS",
        ),
      );
    } else {
      // Add lite TTS model based on current language
      final liteModelData = _getLiteTtsModelForLanguage(currentLanguageCode);
      _modelsToDownload.add(
        DownloadItem(
          url: "${DownloadItem.baseUrl}/${liteModelData['fileName']!}",
          fileName: liteModelData['fileName']!,
          displayName: liteModelData['displayName']!,
        ),
      );
    }
  }

  Map<String, String> _getLiteTtsModelForLanguage(String languageCode) {
    switch (languageCode) {
      case 'de':
        return {'fileName': 'piper-de-mls.tar.gz', 'displayName': 'Piper TTS DE'};
      case 'es':
        return {'fileName': 'piper-es-mx_ald.tar.gz', 'displayName': 'Piper TTS ES'};
      case 'fr':
        return {'fileName': 'piper-fr-mls.tar.gz', 'displayName': 'Piper TTS FR'};
      default:
        return {'fileName': 'piper-en-hfc-female.tar.gz', 'displayName': 'Piper TTS EN'};
    }
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _downloadUpdatesSubscription.cancel();
    _downloader.destroy();
    super.dispose();
  }

  Future<void> _setupDownloader() async {
    await _downloader.configure(
      globalConfig: [
        (Config.resourceTimeout, Duration(hours: 1)), // For slow network conditions (IOS)
        (Config.checkAvailableSpace, 1024 * 4), // 4GB
        (Config.runInForeground, true), // For android, to prevent timeout at 9minute on slow network conditions
      ],
    );
    await _handlePermissions();
    await _downloader.start();
    // Set up progress listener
    _downloadUpdatesSubscription = _downloader.updates.listen((update) {
      final itemIndex = _modelsToDownload.indexWhere(
        (item) => item.url == update.task.url && item.fileName == update.task.filename,
      );

      if (itemIndex != -1) {
        final item = _modelsToDownload[itemIndex];
        setState(() {
          switch (update) {
            case TaskStatusUpdate():
              switch (update.status) {
                case TaskStatus.complete:
                  item.progress = 1.0;
                  item.isCompleted = true;
                  _continueWithNextDownload();
                  break;
                case TaskStatus.failed:
                  item.isError = true;
                  item.errorMessage = update.exception?.description ?? LocaleKeys.ai_models_download_failed.tr();

                  _continueWithNextDownload();
                  break;
                case TaskStatus.canceled:
                  item.isError = true;
                  item.errorMessage = LocaleKeys.ai_models_download_canceled.tr();
                  _continueWithNextDownload();
                  break;
                case TaskStatus.paused:
                  item.isPaused = true;
                default:
                  break;
              }
            case TaskProgressUpdate():
              _modelsToDownload[itemIndex].progress = update.progress;
              if (update.hasExpectedFileSize) {
                _modelsToDownload[itemIndex].fileSize = _formatBytes(update.expectedFileSize);
              }
              break;
          }
        });
      }
    });
    // Setup notifications
    _downloader.configureNotification(
      progressBar: true,
      running: TaskNotification(LocaleKeys.ai_models_downloading.tr(), "{displayName}"),
      complete: TaskNotification(LocaleKeys.ai_models_download_complete.tr(), "{displayName}"),
      error: TaskNotification(LocaleKeys.ai_models_download_failed.tr(), "{displayName}"),
      canceled: TaskNotification(LocaleKeys.ai_models_download_canceled.tr(), "{displayName}"),
      paused: TaskNotification(LocaleKeys.ai_models_download_paused.tr(), "{displayName}"),
    );
  }

  Future<void> _initDownloadTasks() async {
    final savedTaskRecords = (await _downloader.database.allRecords()).map(
      (record) => record.copyWith(task: record.task.copyWith(metaData: 'fromDB')),
    );

    for (int i = 0; i < _modelsToDownload.length; i++) {
      final item = _modelsToDownload[i];
      final taskRecord = savedTaskRecords.firstWhere(
        (record) => record.task.url == item.url && record.task.filename == item.fileName,
        orElse: () => TaskRecord(
          DownloadTask(
            url: item.url,
            filename: item.fileName,
            displayName: item.displayName ?? item.fileName,
            updates: Updates.statusAndProgress,
            directory: 'ai_models',
            allowPause: true,
          ),
          TaskStatus.enqueued,
          0,
          -1, // -1 means unknown size,
        ),
      );
      item.task = taskRecord.task as DownloadTask;
      item.progress = taskRecord.progress;
      item.isCompleted = taskRecord.status == TaskStatus.complete;
      item.isError = [TaskStatus.canceled, TaskStatus.failed, TaskStatus.notFound].contains(taskRecord.status);

      if (taskRecord.expectedFileSize >= 0) {
        item.fileSize = _formatBytes(taskRecord.expectedFileSize);
      } else {
        item.task!
            .expectedFileSize()
            // Not using await to avoid prolonging initialization time since this is not critical,
            // also gracefully handles of errors
            .then((fileSize) {
              if (fileSize > 0) {
                item.fileSize = _formatBytes(fileSize);
              }
            })
            .catchError((e, s) {
              log("Failed to get file size for ${item.fileName}", error: e, stackTrace: s);
            });
      }
    }
  }

  Future<void> _handlePermissions() async {
    final permissionType = PermissionType.notifications;
    var status = await _downloader.permissions.status(permissionType);
    if (status != PermissionStatus.granted) {
      if (await _downloader.permissions.shouldShowRationale(permissionType)) {
        final result = await _showPermissionRationale();
        if (result != true) {
          // result is false (explicitly denied) or null (modal closed)
          return;
        }
      }
      status = await _downloader.permissions.request(permissionType);
      log('Permission result for $permissionType was $status');
    }
  }

  Future<bool?> _showPermissionRationale() {
    return showModalBottomSheet<bool>(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LocaleKeys.ai_models_permission_notification_message.tr(),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(LocaleKeys.ai_models_deny.tr()),
                  ),
                  const SizedBox(width: 16),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(LocaleKeys.ai_models_grant.tr()),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _downloadNextFile() {
    while (currentDownloadIndex < _modelsToDownload.length) {
      final item = _modelsToDownload[currentDownloadIndex];

      // All task in coming from DB will be handled by the library when the _downloader.start method is called
      if (!item.isCompleted && !item.isError && item.task?.metaData != "fromDB") {
        _downloadItem(item);
        return;
      }
      currentDownloadIndex++;
    }

    // All downloads are complete, start initialization
    setState(() {
      isDownloading = false;
    });
    _startInitialization();
  }

  void _continueWithNextDownload() {
    currentDownloadIndex++;
    _downloadNextFile();
  }

  Future<void> _downloadItem(DownloadItem item) async {
    try {
      log("Downloading ${item.url}");
      setState(() {
        isDownloading = true;
      });
      // Enqueue the task (don't wait for completion)
      final success = await _downloader.enqueue(item.task!);
      if (!success) {
        setState(() {
          item.isError = true;
          item.errorMessage = LocaleKeys.ai_models_failed_enqueue.tr();
        });
        _continueWithNextDownload();
      }
    } catch (e, s) {
      log("Failed to download ${item.url}", error: e, stackTrace: s);
      setState(() {
        item.isError = true;
        item.errorMessage = e.toString();
      });
      _continueWithNextDownload();
    }
  }

  Future<void> _retryDownload(DownloadItem item) async {
    if (isDownloading) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(LocaleKeys.ai_models_wait_download_complete.tr())));
      return;
    }

    setState(() {
      item.isError = false;
      item.errorMessage = null;
      item.progress = 0.0;
    });

    setState(() {
      isDownloading = true;
      currentDownloadIndex = _modelsToDownload.indexOf(item);
    });
    await _downloader.enqueue(item.task!);
  }

  Future<void> _startInitialization() async {
    final downloadComplete = _modelsToDownload.every((item) => item.isCompleted);
    // It is possible that we reach here even if download is not complete in the case
    // where the user open the app and there some canceled/failed downloads in DB, they won't
    // automatically retry. Some error types may be retried but not user cancelled downloads
    if (isInitializingModels || isInitializationComplete || !downloadComplete) return;

    setState(() {
      isInitializingModels = true;
      modelLoadingProgress = 0.0;
    });

    // Start dummy progress simulation
    _startModelLoadingProgressSimulation();

    try {
      // Loading all the model is not memory efficient but if we don't load them here,
      // every time the user opens a chat screen they will wait for a long time.
      // Even with the current approach (pre-loading), creating a new chat session takes 5-15 seconds
      // On a Samsung S21 Ultra. TODO: do lazy loading
      final gemmaModelPath = await _modelsToDownload[1].downloadedFilePath;
      await ChatModel.loadBaseModel(gemmaModelPath);

      // Load TTS model based on user choice
      final voiceModelType = AppPreferences.getVoiceModelType();
      String ttsModelPath;

      ttsModelPath = await _modelsToDownload[3].downloadedFilePath; // Premium TTS model

      await TtsModelFactory.initialize(type: voiceModelType, modelPath: ttsModelPath);

      final sttModelPath = await _modelsToDownload[0].downloadedFilePath;
      await SttModel.initialize(modelPath: sttModelPath, lang: currentLanguageCode);

      final embeddingModelPath = await _modelsToDownload[2].downloadedFilePath;
      await EmbeddingModel.initialize(modelPath: embeddingModelPath);

      // Model loaded successfully, set to 100%
      _progressTimer?.cancel();
      setState(() {
        modelLoadingProgress = 1.0;
        isInitializationComplete = true;
      });

      widget.onDone?.call(
        DownloadedModelPaths(
          ttsModelPath: ttsModelPath,
          gemma3nPath: gemmaModelPath,
          embeddingModelPath: embeddingModelPath,
        ),
      );
    } catch (e, s) {
      log("Model initialization failed:", error: e, stackTrace: s);
      // Handle error
      _progressTimer?.cancel();
      setState(() {
        isInitializingModels = false;
        modelLoadingProgress = 0.0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(LocaleKeys.ai_models_initialization_failed.tr(namedArgs: {'error': e.toString()}))),
        );
      }
    }
  }

  /// We can't track model loading progress, so we simulate it to give feedback to the user
  /// Otherwise it may seem like it is frozen since the gemma model is big and take minutes
  /// to load depending on the device
  void _startModelLoadingProgressSimulation() {
    int secondsElapsed = 0;

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      secondsElapsed++;

      setState(() {
        if (modelLoadingProgress < 0.25) {
          // 0-25%: add 3% every second
          modelLoadingProgress += 0.03;
        } else if (modelLoadingProgress < 0.75) {
          // 25-60%: add 1% every second
          modelLoadingProgress += 0.01;
        } else if (modelLoadingProgress < 0.75) {
          // 75-90%: add 1% every 5 seconds
          if (secondsElapsed % 5 == 0) {
            modelLoadingProgress += 0.01;
          }
        } else if (modelLoadingProgress < 0.90) {
          // 50-90%: add 1% every 7 seconds
          if (secondsElapsed % 7 == 0) {
            modelLoadingProgress += 0.01;
          }
        } else if (modelLoadingProgress < 0.95) {
          // 50-90%: add 1% every 10 seconds
          if (secondsElapsed % 10 == 0) {
            modelLoadingProgress += 0.01;
          }
        }
        // After 95%, wait for actual model loading to complete
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(LocaleKeys.ai_models_title.tr())),
      body: Center(
        child: isReady
            ? ListView(
                shrinkWrap: true,
                padding: EdgeInsets.only(
                  // Push centered content up a little
                  bottom: MediaQuery.sizeOf(context).height * 0.2,
                  left: 16,
                  right: 16,
                ),
                children: [
                  Row(
                    children: [
                      Text(
                        LocaleKeys.ai_models_downloading.tr(),
                        style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
                      ),
                      if (_modelsToDownload.every((item) => item.isCompleted)) ...[
                        const SizedBox(width: 8),
                        Icon(Icons.check, color: Colors.green, size: 22),
                      ],
                    ],
                  ),
                  Text(LocaleKeys.ai_models_download_description.tr(), style: theme.textTheme.bodySmall),
                  const SizedBox(height: 12),
                  for (final item in _modelsToDownload)
                    _DownloadItemWidget(
                      item: item,
                      onRetry: () => _retryDownload(item),
                      onPause: item.task != null ? () => _downloader.pause(item.task!) : null,
                      onResume: item.task != null ? () => _downloader.resume(item.task!) : null,
                    ),
                  const SizedBox(height: 42),
                  Text(
                    LocaleKeys.ai_models_initializing.tr(),
                    style: theme.textTheme.titleMedium?.copyWith(fontSize: 17),
                  ),
                  const SizedBox(height: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _buildInitializationIcon(),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        LocaleKeys.ai_models_loading_model_weights.tr(),
                                        style: theme.textTheme.labelLarge?.copyWith(
                                          color: isInitializationComplete ? null : Colors.black54,
                                        ),
                                      ),
                                      const Spacer(),
                                      if (isInitializingModels)
                                        Text(
                                          '${(modelLoadingProgress * 100).toStringAsFixed(0)}%',
                                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  LinearProgressIndicator(
                                    value: isInitializationComplete ? 1.0 : modelLoadingProgress,
                                    backgroundColor: Colors.grey.shade300,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      isInitializationComplete ? Colors.green : theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              )
            : CircularProgressIndicator.adaptive(),
      ),
    );
  }

  Widget _buildInitializationIcon() {
    if (isInitializationComplete) {
      return const Icon(Icons.check, color: Colors.green, size: 18);
    } else {
      return CircularProgressIndicator.adaptive(
        constraints: const BoxConstraints.tightFor(width: 18, height: 18),
        strokeWidth: 3,
        valueColor: isInitializingModels ? null : AlwaysStoppedAnimation<Color>(Colors.grey.shade300),
      );
    }
  }
}

class _DownloadItemWidget extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onRetry;
  final VoidCallback? onPause;
  final VoidCallback? onResume;

  const _DownloadItemWidget({required this.item, required this.onRetry, this.onPause, this.onResume});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                _buildStatusIcon(item),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(
                            item.displayName ?? item.fileName,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: item.isCompleted ? null : Colors.black54, // null = default color
                            ),
                          ),
                          if (item.fileSize?.isNotEmpty == true)
                            Text(" (${item.fileSize})", style: const TextStyle(color: Colors.black87, fontSize: 12)),
                          if (item.isError) ...[
                            const SizedBox(width: 16),
                            Flexible(
                              child: Text(
                                item.errorMessage ?? LocaleKeys.common_unknown_error.tr(),
                                style: const TextStyle(color: Colors.red, fontSize: 12),
                              ),
                            ),
                          ] else if (item.progress > 0) ...[
                            const Spacer(),
                            Text(
                              '${(item.progress * 100).toStringAsFixed(0)}%',
                              style: TextStyle(fontSize: 12, color: Colors.black87),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      LinearProgressIndicator(
                        value: item.progress,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),

                if (item.progress > 0 && !item.isCompleted && item.task != null && !item.isPaused) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.pause, size: 18),
                    onPressed: onPause,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                if (item.isPaused) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    onPressed: onResume,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
                if (item.isError) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: onRetry,
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatBytes(int bytes, [int decimals = 1]) {
  if (bytes < 1024) return '$bytes B';

  const suffixes = ['KB', 'MB', 'GB', 'TB', 'PB', 'EB'];
  var i = -1;
  double size = bytes.toDouble();

  do {
    size /= 1024;
    i++;
  } while (size >= 1024 && i < suffixes.length - 1);

  return '${size.toStringAsFixed(decimals)} ${suffixes[i]}';
}

Widget _buildStatusIcon(DownloadItem item) {
  if (item.isCompleted) {
    return const Icon(Icons.check, color: Colors.green, size: 18);
  } else if (item.isError) {
    return const Icon(Icons.error_outline, color: Colors.red, size: 18);
  } else {
    return CircularProgressIndicator.adaptive(
      constraints: const BoxConstraints.tightFor(width: 18, height: 18),
      strokeWidth: 3,
      valueColor: item.progress > 0 ? null : AlwaysStoppedAnimation<Color>(Colors.grey.shade300),
    );
  }
}
