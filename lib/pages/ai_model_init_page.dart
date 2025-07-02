import 'dart:async';

import 'package:flutter/material.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:waico/core/gemma3n_model.dart';
import 'dart:io';

class DownloadItem {
  final String url;
  final String? displayName;
  final String fileName;
  double progress;
  bool isCompleted;
  bool isError;
  String? errorMessage;
  DownloadTask? task;

  DownloadItem({
    required this.url,
    required this.fileName,
    this.displayName,
    this.progress = 0.0,
    this.isCompleted = false,
    this.isError = false,
    this.errorMessage,
    this.task,
  });
}

class AiModelsInitializationPage extends StatefulWidget {
  final List<DownloadItem> downloadItems;

  const AiModelsInitializationPage({super.key, required this.downloadItems});

  @override
  State<AiModelsInitializationPage> createState() => _AiModelsInitializationPageState();
}

class _AiModelsInitializationPageState extends State<AiModelsInitializationPage> {
  bool isDownloading = false;
  bool isInitializing = false;
  bool isInitializationComplete = false;
  double initializationProgress = 0.0;
  int currentDownloadIndex = 0;
  late final StreamSubscription<TaskUpdate> _downloadUpdatesSubscription;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _setupDownloader();
    _checkExistingFiles().then((_) {
      // Check if all downloads are already complete
      final allComplete = widget.downloadItems.every((item) => item.isCompleted);
      if (allComplete) {
        _startInitialization();
      } else {
        _downloadNextFile();
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _downloadUpdatesSubscription.cancel();
    FileDownloader().destroy();
    super.dispose();
  }

  void _setupDownloader() {
    // Set up progress listener
    _downloadUpdatesSubscription = FileDownloader().updates.listen((update) {
      final itemIndex = widget.downloadItems.indexWhere((item) => item.task?.taskId == update.task.taskId);

      if (itemIndex != -1) {
        setState(() {
          switch (update) {
            case TaskStatusUpdate():
              switch (update.status) {
                case TaskStatus.complete:
                  widget.downloadItems[itemIndex].progress = 1.0;
                  widget.downloadItems[itemIndex].isCompleted = true;
                  _continueWithNextDownload();
                  break;
                case TaskStatus.failed:
                  widget.downloadItems[itemIndex].isError = true;
                  widget.downloadItems[itemIndex].errorMessage = update.exception?.description ?? 'Download failed';
                  _continueWithNextDownload();
                  break;
                case TaskStatus.canceled:
                  widget.downloadItems[itemIndex].isError = true;
                  widget.downloadItems[itemIndex].errorMessage = 'Download canceled';
                  _continueWithNextDownload();
                  break;
                default:
                  break;
              }
            case TaskProgressUpdate():
              widget.downloadItems[itemIndex].progress = update.progress;
              break;
          }
        });
      }
    });
    // Setup notifications
    FileDownloader().configureNotification(
      progressBar: true,
      running: TaskNotification("Downloading", "{displayName}"),
      complete: TaskNotification("Download Complete", "{displayName}"),
      error: TaskNotification("Download Failed", "{displayName}"),
      canceled: TaskNotification("Download Canceled", "{displayName}"),
      paused: TaskNotification("Download Paused", "{displayName}"),
    );
  }

  Future<void> _checkExistingFiles() async {
    for (int i = 0; i < widget.downloadItems.length; i++) {
      final item = widget.downloadItems[i];
      final task = DownloadTask(
        url: item.url,
        filename: item.fileName,
        displayName: item.displayName ?? item.fileName,
        updates: Updates.status,
        directory: 'ai_models',
      );

      // Get the full file path
      final filePath = await task.filePath();
      final file = File(filePath);

      if (await file.exists()) {
        setState(() {
          widget.downloadItems[i].isCompleted = true;
          widget.downloadItems[i].progress = 1.0;
        });
      }
    }
  }

  void _downloadNextFile() {
    // Find next file that isn't completed and isn't in error
    while (currentDownloadIndex < widget.downloadItems.length) {
      final item = widget.downloadItems[currentDownloadIndex];
      if (!item.isCompleted && !item.isError) {
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
      final task = DownloadTask(
        url: item.url,
        filename: item.fileName,
        displayName: item.displayName ?? item.fileName,
        updates: Updates.statusAndProgress,
        directory: 'ai_models',
      );

      setState(() {
        item.task = task;
      });

      // Enqueue the task (don't wait for completion)
      final success = await FileDownloader().enqueue(task);
      if (!success) {
        setState(() {
          item.isError = true;
          item.errorMessage = 'Failed to enqueue download';
        });
        _continueWithNextDownload();
      }
    } catch (e) {
      setState(() {
        item.isError = true;
        item.errorMessage = e.toString();
      });
      _continueWithNextDownload();
    }
  }

  Future<void> _retryDownload(DownloadItem item) async {
    setState(() {
      item.isError = false;
      item.errorMessage = null;
      item.progress = 0.0;
    });

    if (!isDownloading) {
      setState(() {
        isDownloading = true;
        currentDownloadIndex = widget.downloadItems.indexOf(item);
      });
      _downloadItem(item);
    }
  }

  void _cancelDownload(DownloadItem item) {
    final task = item.task;
    if (task != null) {
      FileDownloader().cancelTaskWithId(task.taskId);
      setState(() {
        item.isError = true;
        item.errorMessage = 'Canceled by user';
      });
    }
  }

  void _pauseDownload(DownloadItem item) {
    final task = item.task;
    if (task != null) {
      FileDownloader().pause(task);
    }
  }

  Future<void> _startInitialization() async {
    if (isInitializing || isInitializationComplete) return;

    setState(() {
      isInitializing = true;
      initializationProgress = 0.0;
    });

    // Start dummy progress simulation
    _startProgressSimulation();

    try {
      // Load the base model
      await Gemma3nModel.loadBaseModel();

      // Model loaded successfully, set to 100%
      _progressTimer?.cancel();
      setState(() {
        initializationProgress = 1.0;
        isInitializationComplete = true;
      });
    } catch (e) {
      // Handle error
      _progressTimer?.cancel();
      setState(() {
        isInitializing = false;
        initializationProgress = 0.0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Model initialization failed: $e')));
      }
    }
  }

  void _startProgressSimulation() {
    int secondsElapsed = 0;

    _progressTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      secondsElapsed++;

      setState(() {
        if (initializationProgress < 0.25) {
          // 0-25%: add 2% every second
          initializationProgress += 0.02;
        } else if (initializationProgress < 0.50) {
          // 25-50%: add 2% every 5 seconds
          if (secondsElapsed % 5 == 0) {
            initializationProgress += 0.02;
          }
        } else if (initializationProgress < 0.90) {
          // 50-90%: add 1% every 10 seconds
          if (secondsElapsed % 10 == 0) {
            initializationProgress += 0.01;
          }
        }
        // After 90%, wait for actual model loading to complete

        // Ensure we don't exceed 90% in simulation
        if (initializationProgress > 0.90) {
          initializationProgress = 0.90;
        }
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
                if (widget.downloadItems.every((item) => item.isCompleted)) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check, color: Colors.green),
                ],
              ],
            ),
            const SizedBox(height: 16),
            for (final item in widget.downloadItems)
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
                                    const SizedBox(width: 16),
                                    if (item.isError)
                                      Flexible(
                                        child: Text(
                                          item.errorMessage ?? 'Unknown error',
                                          style: const TextStyle(color: Colors.red, fontSize: 12),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                LinearProgressIndicator(
                                  value: item.progress,
                                  backgroundColor: Colors.grey.shade300,
                                  valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                                ),
                              ],
                            ),
                          ),

                          if (item.progress > 0 && !item.isCompleted && item.task != null) ...[
                            IconButton(
                              icon: const Icon(Icons.pause, size: 20),
                              onPressed: () => _pauseDownload(item),
                              tooltip: 'Pause',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => _cancelDownload(item),
                              tooltip: 'Cancel',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                          ],
                          if (item.isError)
                            IconButton(
                              icon: const Icon(Icons.refresh, size: 20),
                              onPressed: () => _retryDownload(item),
                              tooltip: 'Retry',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 42),
            Text("Initializing", style: theme.textTheme.titleMedium?.copyWith(fontSize: 17)),
            const SizedBox(height: 22),
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
                                    '${(initializationProgress * 100).toStringAsFixed(0)}%',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            LinearProgressIndicator(
                              value: isInitializationComplete ? 1.0 : initializationProgress,
                              backgroundColor: Colors.grey.shade300,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                isInitializationComplete ? Colors.green : Theme.of(context).primaryColor,
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
      return const Icon(Icons.check, color: Colors.green, size: 20);
    } else {
      return CircularProgressIndicator.adaptive(
        constraints: const BoxConstraints.tightFor(width: 18, height: 18),
        strokeWidth: 3,
        valueColor: isInitializing ? null : AlwaysStoppedAnimation<Color>(Colors.grey.shade300),
      );
    }
  }
}
