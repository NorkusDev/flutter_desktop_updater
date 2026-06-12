import "dart:async";
import "dart:io";

import "package:desktop_updater/src/app_archive.dart";
import "package:desktop_updater/src/download.dart";
import "package:desktop_updater/src/macos_update.dart";
import "package:desktop_updater/src/update_progress.dart";

Future<Stream<UpdateProgress>> updateAppFunction({
  required String remoteUpdateFolder,
  required List<FileHashModel?> changes,
  String manifestPath = "release-manifest.json",
}) async {
  if (Platform.isMacOS) {
    return updateMacOSAppFunction(
      remoteUpdateFolder: remoteUpdateFolder,
      manifestPath: manifestPath,
    );
  }

  final files = changes.whereType<FileHashModel>().toList(growable: false);
  final stagingDirectory = await Directory.systemTemp.createTemp(
    "desktop_updater_stage_",
  );

  late StreamController<UpdateProgress> controller;

  controller = StreamController<UpdateProgress>(
    onListen: () {
      unawaited(
        _downloadChangedFiles(
          controller: controller,
          remoteUpdateFolder: remoteUpdateFolder,
          files: files,
          stagingDirectory: stagingDirectory,
        ),
      );
    },
  );

  return controller.stream;
}

Future<void> _downloadChangedFiles({
  required StreamController<UpdateProgress> controller,
  required String remoteUpdateFolder,
  required List<FileHashModel> files,
  required Directory stagingDirectory,
}) async {
  final totalBytes = files.fold<int>(
    0,
    (previousValue, element) => previousValue + element.length,
  );

  var completedFiles = 0;
  var completedBytes = 0;

  try {
    if (files.isEmpty) {
      controller.add(
        UpdateProgress(
          totalBytes: 0,
          receivedBytes: 0,
          currentFile: "",
          totalFiles: 0,
          completedFiles: 0,
          stagingDirectory: stagingDirectory.path,
        ),
      );
      return;
    }

    for (final fileHash in files) {
      var currentFileBytes = 0;

      await downloadFile(
        remoteUpdateFolder: remoteUpdateFolder,
        fileHash: fileHash,
        stagingDirectory: stagingDirectory,
        onProgress: (receivedBytes, _) {
          currentFileBytes = receivedBytes;

          // Cap reported bytes to (totalBytes - 1) so that fraction never
          // reaches 1.0 inside onProgress — fraction hits 1.0 only after
          // downloadFile() returns, meaning disk flush + hash verification
          // have completed successfully.
          final rawReceived = completedBytes + currentFileBytes;
          final cappedReceived =
              totalBytes > 0 ? rawReceived.clamp(0, totalBytes - 1) : rawReceived;

          controller.add(
            UpdateProgress(
              totalBytes: totalBytes.toDouble(),
              receivedBytes: cappedReceived.toDouble(),
              currentFile: fileHash.filePath,
              totalFiles: files.length,
              completedFiles: completedFiles,
              stagingDirectory: stagingDirectory.path,
            ),
          );
        },
      );

      // Increment counters BEFORE emitting the final progress event so that
      // completedFiles is always accurate when fraction first reaches 1.0.
      completedFiles += 1;
      completedBytes +=
          fileHash.length > 0 ? fileHash.length : currentFileBytes;

      controller.add(
        UpdateProgress(
          totalBytes: totalBytes.toDouble(),
          receivedBytes: completedBytes.toDouble(),
          currentFile: fileHash.filePath,
          totalFiles: files.length,
          completedFiles: completedFiles,
          stagingDirectory: stagingDirectory.path,
        ),
      );
    }
  } catch (error, stackTrace) {
    controller.addError(error, stackTrace);
  } finally {
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }
    await controller.close();
  }
}
