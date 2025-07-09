import 'dart:io';

import 'package:archive/archive_io.dart' show extractFileToDisk;

class DownloadedModelPaths {
  final String ttsModelPath;
  final String? kokoroVoicesPath;
  final String gemma3nPath;

  DownloadedModelPaths({required this.ttsModelPath, this.kokoroVoicesPath, required this.gemma3nPath});
}

Future<String> extractModelData(String modelArchivePath) async {
  final modelDirPath = modelArchivePath.replaceAll(".tar.gz", "");
  final modelDir = Directory(modelDirPath);

  if (!await modelDir.exists()) {
    // Before extraction modelBaseDir doesn't exist when we extract in it's parent, it will
    await extractFileToDisk(modelArchivePath, modelDir.parent.path);

    if (await modelDir.exists()) {
      // Extracted successfully, delete archive
      await File(modelArchivePath).delete(recursive: true);
    }
  }
  return modelDirPath;
}
