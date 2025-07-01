import 'dart:async';

import 'package:flutter/material.dart';
import 'package:background_downloader/background_downloader.dart';
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
  int currentDownloadIndex = 0;
  late final StreamSubscription<TaskUpdate> _downloadUpdatesSubscription;

  @override
  void initState() {
    super.initState();
    _setupDownloader();
    _checkExistingFiles().then((_) => _downloadNextFile());
  }

  @override
  void dispose() {
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
              print("Progress update for ${widget.downloadItems[itemIndex].displayName}: ${update.progress}");
              widget.downloadItems[itemIndex].progress = update.progress;
              break;
          }
        });
      }
    });
  }

  Future<void> _checkExistingFiles() async {
    for (int i = 0; i < widget.downloadItems.length; i++) {
      final item = widget.downloadItems[i];
      final task = DownloadTask(
        url: item.url,
        filename: item.fileName,
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
        _downloadFile(currentDownloadIndex);
        return;
      }
      currentDownloadIndex++;
    }

    // All downloads are complete
    setState(() {
      isDownloading = false;
    });
  }

  void _continueWithNextDownload() {
    currentDownloadIndex++;
    _downloadNextFile();
  }

  Future<void> _downloadFile(int index) async {
    final item = widget.downloadItems[index];

    try {
      final task = DownloadTask(
        url: item.url,
        filename: item.fileName,
        updates: Updates.statusAndProgress,
        directory: 'ai_models',
      );

      setState(() {
        widget.downloadItems[index].task = task;
      });

      // Enqueue the task (don't wait for completion)
      final success = await FileDownloader().enqueue(task);
      if (!success) {
        setState(() {
          widget.downloadItems[index].isError = true;
          widget.downloadItems[index].errorMessage = 'Failed to enqueue download';
        });
        _continueWithNextDownload();
      }
    } catch (e) {
      setState(() {
        widget.downloadItems[index].isError = true;
        widget.downloadItems[index].errorMessage = e.toString();
      });
      _continueWithNextDownload();
    }
  }

  Future<void> _retryDownload(int index) async {
    setState(() {
      widget.downloadItems[index].isError = false;
      widget.downloadItems[index].errorMessage = null;
      widget.downloadItems[index].progress = 0.0;
    });

    if (!isDownloading) {
      setState(() {
        isDownloading = true;
        currentDownloadIndex = index;
      });
      _downloadFile(index);
    }
  }

  void _cancelDownload(int index) {
    final task = widget.downloadItems[index].task;
    if (task != null) {
      FileDownloader().cancelTaskWithId(task.taskId);
      setState(() {
        widget.downloadItems[index].isError = true;
        widget.downloadItems[index].errorMessage = 'Canceled by user';
      });
    }
  }

  void _pauseDownload(int index) {
    final task = widget.downloadItems[index].task;
    if (task != null) {
      FileDownloader().pause(task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('AI Models Initialization')),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.downloadItems.length,
            padding: EdgeInsets.only(bottom: MediaQuery.sizeOf(context).height * 0.1),
            itemBuilder: (context, index) {
              final item = widget.downloadItems[index];
              return Padding(
                padding: const EdgeInsets.all(16),
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
                                      color: item.isCompleted ? Colors.green : Colors.black54,
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
                            onPressed: () => _pauseDownload(index),
                            tooltip: 'Pause',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => _cancelDownload(index),
                            tooltip: 'Cancel',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ],
                        if (item.isError)
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 20),
                            onPressed: () => _retryDownload(index),
                            tooltip: 'Retry',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIcon(DownloadItem item) {
    if (item.isCompleted) {
      return const Icon(Icons.check, color: Colors.green, size: 20);
    } else if (item.isError) {
      return const Icon(Icons.error_outline, color: Colors.red, size: 20);
    } else {
      return CircularProgressIndicator.adaptive(
        constraints: const BoxConstraints.tightFor(width: 18, height: 18),
        strokeWidth: 3,
        valueColor: item.progress > 0 ? null : AlwaysStoppedAnimation<Color>(Colors.grey.shade300),
      );
    }
  }
}
