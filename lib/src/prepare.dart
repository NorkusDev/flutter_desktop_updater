import "dart:io";

import "package:desktop_updater/src/app_archive.dart";
import "package:desktop_updater/src/file_hash.dart";
import "package:desktop_updater/src/macos_update.dart";
import "package:desktop_updater/src/remote_file.dart";
import "package:path/path.dart" as path;

Future<List<FileHashModel?>> prepareUpdateAppFunction({
  required String remoteUpdateFolder,
  List<String>? skipHashes,
}) async {
  final tempDir = await Directory.systemTemp.createTemp("desktop_updater_");
  Directory? oldHashTempDir;

  try {
    if (Platform.isMacOS) {
      final manifest = await downloadMacOSReleaseManifest(
        remoteUpdateFolder: remoteUpdateFolder,
        tempDirectory: tempDir,
      );
      final diff = await diffInstalledMacOSApp(targetManifest: manifest);
      return fileHashModelsForManifestDiff(diff);
    }

    final newHashFile = File(path.join(tempDir.path, "hashes.json"));
    await downloadRemoteFileTo(
      base: remoteUpdateFolder,
      relativePath: "hashes.json",
      destination: newHashFile,
    );

    final oldHashResult = await genFileHashes(skipHashes: skipHashes);
    oldHashTempDir = oldHashResult.tempDir;
    return await verifyFileHashes(oldHashResult.filePath, newHashFile.path);
  } finally {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    if (oldHashTempDir != null && await oldHashTempDir.exists()) {
      await oldHashTempDir.delete(recursive: true);
    }
  }
}
