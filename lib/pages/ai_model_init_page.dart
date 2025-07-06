import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:waico/core/gemma3n_model.dart';
import 'package:waico/core/kokoro_model.dart';
import 'package:waico/core/utils/model_download_utils.dart';
import 'package:waico/core/utils/navigation_utils.dart';

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
  final _modelsToDownload = <DownloadItem>[
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

  bool isDownloading = false;
  bool isInitializing = false;
  bool isInitializationComplete = false;
  double modelLoadingProgress = 0.0;
  int currentDownloadIndex = 0;
  late final StreamSubscription<TaskUpdate> _downloadUpdatesSubscription;
  Timer? _progressTimer;
  final _downloader = FileDownloader();

  @override
  void initState() {
    super.initState();
    init();
  }

  Future<void> init() async {
    await _setupDownloader();
    await _initDownloadTasks();

    // Check if all downloads are already complete if this is not the first time the app is opened
    final allComplete = _modelsToDownload.every((item) => item.isCompleted);
    if (allComplete) {
      await _startInitialization();
    } else {
      _downloadNextFile();
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
                  item.errorMessage = update.exception?.description ?? 'Download failed';

                  _continueWithNextDownload();
                  break;
                case TaskStatus.canceled:
                  item.isError = true;
                  item.errorMessage = 'Download canceled';
                  _continueWithNextDownload();
                  break;
                case TaskStatus.paused:
                  item.isPaused = true;
                default:
                  break;
              }
            case TaskProgressUpdate():
              _modelsToDownload[itemIndex].progress = update.progress;
              break;
          }
        });
      }
    });
    // Setup notifications
    _downloader.configureNotification(
      progressBar: true,
      running: TaskNotification("Downloading", "{displayName}"),
      complete: TaskNotification("Download Complete", "{displayName}"),
      error: TaskNotification("Download Failed", "{displayName}"),
      canceled: TaskNotification("Download Canceled", "{displayName}"),
      paused: TaskNotification("Download Paused", "{displayName}"),
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
              Text("We need permission to show download progress notification"),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () {
                      context.navBack(false);
                    },
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    child: Text("Deny"),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.navBack(true);
                    },
                    child: Text("Grant"),
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
      // Enqueue the task (don't wait for completion)
      final success = await _downloader.enqueue(item.task!);
      if (!success) {
        setState(() {
          item.isError = true;
          item.errorMessage = 'Failed to enqueue download';
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
      ).showSnackBar(SnackBar(content: Text("Wait until the ongoing download complete before retrying this one.")));
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
    await _downloader.resume(item.task!);
  }

  Future<void> _startInitialization() async {
    final downloadComplete = _modelsToDownload.every((item) => item.isCompleted);
    // It is possible that we reach here even if download is not complete in the case
    // where the user open the app and there some canceled/failed downloads in DB, they won't
    // automatically retry. Some error types may be retried but not user cancelled downloads
    if (isInitializing || isInitializationComplete || !downloadComplete) return;

    setState(() {
      isInitializing = true;
      modelLoadingProgress = 0.0;
    });

    // Start dummy progress simulation
    _startModelLoadingProgressSimulation();

    try {
      final gemmaModelPath = await _modelsToDownload[0].downloadedFilePath;
      await Gemma3nModel.loadBaseModel(gemmaModelPath);

      final kokoroModelPath = await _modelsToDownload[1].downloadedFilePath;
      final kokoroVoicesPath = await _modelsToDownload[2].downloadedFilePath;
      await KokoroModel.initialize(modelPath: kokoroModelPath, voicesPath: kokoroVoicesPath);

      // Model loaded successfully, set to 100%
      _progressTimer?.cancel();
      setState(() {
        modelLoadingProgress = 1.0;
        isInitializationComplete = true;
      });

      widget.onDone?.call(
        DownloadedModelPaths(
          kokoroPath: kokoroModelPath,
          kokoroVoicesPath: kokoroVoicesPath,
          gemma3nPath: gemmaModelPath,
        ),
      );
    } catch (e) {
      // Handle error
      _progressTimer?.cancel();
      setState(() {
        isInitializing = false;
        modelLoadingProgress = 0.0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Model initialization failed: $e')));
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
          // 50-90%: add 1% every 5 seconds
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
      appBar: AppBar(title: const Text('AI Models Initialization')),
      body: Center(
        child: ListView(
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
                Text("Downloading", style: theme.textTheme.titleMedium?.copyWith(fontSize: 17)),
                if (_modelsToDownload.every((item) => item.isCompleted)) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, color: Colors.green, size: 22),
                ],
              ],
            ),
            const SizedBox(height: 12),
            for (final item in _modelsToDownload)
              ConstrainedBox(
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
                                    if (item.isError) ...[
                                      const SizedBox(width: 16),
                                      Flexible(
                                        child: Text(
                                          item.errorMessage ?? 'Unknown error',
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
                              onPressed: () => _downloader.pause(item.task!),
                              tooltip: 'Pause',
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
                              onPressed: () => _downloader.resume(item.task!),
                              tooltip: 'Resume',
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
                              onPressed: () => _retryDownload(item),
                              tooltip: 'Retry',
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
              ),
            const SizedBox(height: 42),
            Text("Initializing", style: theme.textTheme.titleMedium?.copyWith(fontSize: 17)),
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
                                  'Loading Model Weights',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: isInitializationComplete ? null : Colors.black54,
                                  ),
                                ),
                                const Spacer(),
                                if (isInitializing)
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
        ),
      ),
    );
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

  Widget _buildInitializationIcon() {
    if (isInitializationComplete) {
      return const Icon(Icons.check, color: Colors.green, size: 18);
    } else {
      return CircularProgressIndicator.adaptive(
        constraints: const BoxConstraints.tightFor(width: 18, height: 18),
        strokeWidth: 3,
        valueColor: isInitializing ? null : AlwaysStoppedAnimation<Color>(Colors.grey.shade300),
      );
    }
  }
}
