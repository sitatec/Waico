import 'dart:io';

import 'package:archive/archive_io.dart' show extractFileToDisk;

class DownloadedModelPaths {
  final String ttsModelPath;
  final String? kokoroVoicesPath;
  final String gemma3nPath;

  DownloadedModelPaths({required this.ttsModelPath, this.kokoroVoicesPath, required this.gemma3nPath});
}

Future<String> extractModelData(String modelArchivePath) async {
  final modelDirPath = modelArchivePath.replaceAll(RegExp(r"\.tar\.(gz|bz2|xz)$"), "");
  final modelDir = Directory(modelDirPath);

  if (!await modelDir.exists()) {
    if (!await File(modelArchivePath).exists()) {
      throw Exception("Model path not found: $modelArchivePath");
    }
    // Before extraction modelBaseDir doesn't exist when we extract in it's parent, it will
    await extractFileToDisk(modelArchivePath, modelDir.parent.path);

    if (await modelDir.exists()) {
      // Extracted successfully, delete archive
      await File(modelArchivePath).delete(recursive: true);
    }
  }
  return modelDirPath;
}
