import "package:desktop_updater/desktop_updater_platform_interface.dart";
import "package:desktop_updater/src/app_archive.dart";
import "package:desktop_updater/src/file_hash.dart";
import "package:desktop_updater/src/prepare.dart";
import "package:desktop_updater/src/update.dart";
import "package:desktop_updater/src/update_progress.dart";
import "package:desktop_updater/src/version_check.dart";

export "package:desktop_updater/src/app_archive.dart";
export "package:desktop_updater/src/localization.dart";
export "package:desktop_updater/src/update_progress.dart";
export "package:desktop_updater/widget/update_dialog.dart";
export "package:desktop_updater/widget/update_direct_card.dart";
export "package:desktop_updater/widget/update_direct_card_fluent.dart";
export "package:desktop_updater/widget/update_card_fluent.dart";
export "package:desktop_updater/widget/update_sliver.dart";

export "desktop_updater_inherited_widget.dart";

class DesktopUpdater {
  DesktopUpdater();
  Future<String?> getPlatformVersion() {
    return DesktopUpdaterPlatform.instance.getPlatformVersion();
  }

  Future<String?> sayHello() {
    return Future.value("Hello from DesktopUpdater!");
  }

  Future<void> restartApp({String? stagingPath}) {
    if (stagingPath != null) {
      return installUpdate(stagingPath: stagingPath);
    }

    return DesktopUpdaterPlatform.instance.restartApp();
  }

  Future<void> installUpdate({
    required String stagingPath,
    List<String> removedFiles = const [],
  }) {
    return DesktopUpdaterPlatform.instance.installUpdate(
      stagingPath: stagingPath,
      removedFiles: removedFiles,
    );
  }

  Future<String?> getExecutablePath() {
    return DesktopUpdaterPlatform.instance.getExecutablePath();
  }

  Future<List<FileHashModel?>> verifyFileHash(
    String oldHashFilePath,
    String newHashFilePath,
  ) {
    return verifyFileHashes(oldHashFilePath, newHashFilePath);
  }

  Future<String?> generateFileHashes({
    String? path,
    List<String>? skipHashes,
  }) async {
    final result = await genFileHashes(path: path, skipHashes: skipHashes);
    // Immediately clean up the temp directory — the caller only needs the path
    // value and cannot perform cleanup themselves.
    if (await result.tempDir.exists()) {
      await result.tempDir.delete(recursive: true);
    }
    return result.filePath;
  }

  Future<Stream<UpdateProgress>> updateApp({
    required String remoteUpdateFolder,
    required List<FileHashModel?> changedFiles,
    String manifestPath = "release-manifest.json",
  }) {
    return updateAppFunction(
      remoteUpdateFolder: remoteUpdateFolder,
      changes: changedFiles,
      manifestPath: manifestPath,
    );
  }

  Future<List<FileHashModel?>> prepareUpdateApp({
    required String remoteUpdateFolder,
    List<String>? skipHashes,
  }) {
    return prepareUpdateAppFunction(
      remoteUpdateFolder: remoteUpdateFolder,
      skipHashes: skipHashes,
    );
  }

  Future<String?> getCurrentVersion() {
    return DesktopUpdaterPlatform.instance.getCurrentVersion();
  }

  Future<ItemModel?> versionCheck({
    required String appArchiveUrl,
    List<String>? skipHashes,
  }) {
    return versionCheckFunction(
      appArchiveUrl: appArchiveUrl,
      skipHashes: skipHashes,
    );
  }
}
