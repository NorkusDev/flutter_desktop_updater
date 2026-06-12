import "package:desktop_updater/desktop_updater.dart";
import "package:flutter/material.dart";

class DesktopUpdaterController extends ChangeNotifier {
  DesktopUpdaterController({
    required Uri? appArchiveUrl,
    this.localization,
    this.skipHashes,
  }) {
    if (appArchiveUrl != null) {
      init(appArchiveUrl);
    }
  }

  DesktopUpdateLocalization? localization;
  DesktopUpdateLocalization? get getLocalization => localization;

  List<String>? skipHashes;

  String? _appName;
  String? get appName => _appName;

  String? _appVersion;
  String? get appVersion => _appVersion;

  Uri? _appArchiveUrl;
  Uri? get appArchiveUrl => _appArchiveUrl;

  bool _needUpdate = false;
  bool get needUpdate => _needUpdate;

  bool _isMandatory = false;
  bool get isMandatory => _isMandatory;

  String? _folderUrl;

  UpdateProgress? _updateProgress;
  UpdateProgress? get updateProgress => _updateProgress;

  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  bool _isDownloaded = false;
  bool get isDownloaded => _isDownloaded;

  double _downloadProgress = 0;
  double get downloadProgress => _downloadProgress;

  double _downloadSize = 0;
  double? get downloadSize => _downloadSize;

  double _downloadedSize = 0;
  double get downloadedSize => _downloadedSize;

  List<FileHashModel?>? _changedFiles;
  List<String> _removedFiles = const [];
  String? _stagingPath;
  String _manifestPath = "release-manifest.json";

  List<ChangeModel?>? _releaseNotes;
  List<ChangeModel?>? get releaseNotes => _releaseNotes;

  bool _skipUpdate = false;
  bool get skipUpdate => _skipUpdate;

  final _plugin = DesktopUpdater();

  void init(Uri url) {
    _appArchiveUrl = url;
    checkVersion();
    notifyListeners();
  }

  void makeSkipUpdate() {
    _skipUpdate = true;
    debugPrint("Skip update: $_skipUpdate");
    notifyListeners();
  }

  Future<void> checkVersion() async {
    if (_appArchiveUrl == null) {
      throw Exception("App archive URL is not set");
    }

    final versionResponse = await _plugin.versionCheck(
      appArchiveUrl: appArchiveUrl.toString(),
      skipHashes: skipHashes,
    );

    if (versionResponse?.url != null) {
      debugPrint("Found folder url: ${versionResponse?.url}");

      _needUpdate = true;
      _folderUrl = versionResponse?.url;
      _isMandatory = versionResponse?.mandatory ?? false;

      // Calculate total length in bytes.
      _downloadSize = (versionResponse?.changedFiles?.fold<double>(
            0,
            (previousValue, element) => previousValue + (element?.length ?? 0),
          )) ??
          0.0;

      _changedFiles = versionResponse?.changedFiles;
      _removedFiles = versionResponse?.removedFiles ?? const [];
      _manifestPath = versionResponse?.manifestPath ?? "release-manifest.json";
      _releaseNotes = versionResponse?.changes;
      _appName = versionResponse?.appName;
      _appVersion = versionResponse?.version;

      debugPrint("Need update: $_needUpdate");

      notifyListeners();
    }
  }

  Future<void> downloadUpdate() async {
    if (_folderUrl == null) {
      throw Exception("Folder URL is not set");
    }

    if (_changedFiles == null) {
      throw Exception("Changed files are not set");
    }

    _isDownloading = true;
    _isDownloaded = false;
    _downloadProgress = 0;
    _downloadedSize = 0;
    _stagingPath = null;
    notifyListeners();

    final stream = await _plugin.updateApp(
      remoteUpdateFolder: _folderUrl!,
      changedFiles: _changedFiles ?? [],
      manifestPath: _manifestPath,
    );

    // Explicit flag — only set true when the stream completes without error.
    // This prevents `_isDownloaded` from becoming true if the stream closes
    // unexpectedly (e.g. the controller is closed before all files are done).
    var downloadSucceeded = false;

    try {
      await for (final event in stream) {
        _updateProgress = event;
        _stagingPath = event.stagingDirectory ?? _stagingPath;
        _isDownloading = true;
        _isDownloaded = false;
        _downloadProgress = event.fraction;
        _downloadedSize = event.receivedBytes;
        notifyListeners();
      }

      downloadSucceeded = true;
    } catch (_) {
      _isDownloading = false;
      _isDownloaded = false;
      notifyListeners();
      rethrow;
    } finally {
      if (downloadSucceeded) {
        _isDownloading = false;
        _downloadProgress = 1.0;
        _downloadedSize = _downloadSize;
        _isDownloaded = true;
        notifyListeners();
      }
    }
  }

  Future<void> restartApp() async {
    final stagingPath = _stagingPath;
    if (stagingPath == null || stagingPath.isEmpty) {
      throw StateError("No downloaded update is ready to install");
    }

    await _plugin.installUpdate(
      stagingPath: stagingPath,
      removedFiles: _removedFiles,
    );
  }
}
