import "dart:async";
import "dart:convert";
import "dart:io";

import "package:cryptography_plus/cryptography_plus.dart";
import "package:desktop_updater/src/app_paths.dart";
import "package:desktop_updater/src/app_archive.dart";
import "package:desktop_updater/src/remote_file.dart";
import "package:path/path.dart" as p;

class FileHashDiff {
  const FileHashDiff({required this.changedFiles, required this.removedFiles});

  final List<FileHashModel> changedFiles;
  final List<String> removedFiles;
}

List<String> _dynamicSkipList = [];

Future<void> loadUpdaterConfig(File configFile) async {
  try {
    if (await configFile.exists()) {
      final yamlString = await configFile.readAsString();
      final yamlDoc = loadYaml(yamlString);
      
      if (yamlDoc != null && yamlDoc['desktop_updater'] != null) {
        final config = yamlDoc['desktop_updater'];

        if (config['skip_hashes'] != null) {
          final YamlList skipList = config['skip_hashes'];
          _dynamicSkipList = skipList.map((e) => e.toString()).toList();
          return;
        }
      }
    }
    _setDefaultSkips();
  } catch (e) {
    print("Error loading config dari ${configFile.path}: $e. Menggunakan default.");
    _setDefaultSkips();
  }
}

void _setDefaultSkips() {
  _dynamicSkipList = [
    "hashes.json",
    ".DS_Store",
    ".desktop_updater_manifest.json",
    ".desktop_updater_release_manifest.json",
    "release-manifest.json",
    "update/"
  ];
}

Future<String> getFileHash(File file) async {
  try {
    final List<int> fileBytes = await file.readAsBytes();
    final hash = await Blake2b().hash(fileBytes);
    return base64.encode(hash.bytes);
  } catch (e) {
    print("Error reading file ${file.path}: $e");
    return "";
  }
}

Future<List<FileHashModel?>> verifyFileHashes(
  String oldHashFilePath,
  String newHashFilePath,
) async {
  return (await diffFileHashes(oldHashFilePath, newHashFilePath)).changedFiles;
}

Future<FileHashDiff> diffFileHashes(
  String oldHashFilePath,
  String newHashFilePath,
) async {
  if (oldHashFilePath == newHashFilePath) {
    return const FileHashDiff(changedFiles: [], removedFiles: []);
  }

  final oldFile = File(oldHashFilePath);
  final newFile = File(newHashFilePath);

  if (!oldFile.existsSync() || !newFile.existsSync()) {
    throw Exception("Desktop Updater: Hash files do not exist");
  }

  final oldString = await oldFile.readAsString();
  final newString = await newFile.readAsString();

  final oldHashes = _decodeHashes(oldString);
  final newHashes = _decodeHashes(newString);
  final oldByPath = {
    for (final hash in oldHashes) normalizeArchivePath(hash.filePath): hash,
  };
  final newByPath = {
    for (final hash in newHashes) normalizeArchivePath(hash.filePath): hash,
  };

  final changedFiles = <FileHashModel>[];
  for (final entry in newByPath.entries) {
    final oldHash = oldByPath[entry.key];
    final newHash = entry.value;

    if (oldHash == null || oldHash.calculatedHash != newHash.calculatedHash) {
      changedFiles.add(
        FileHashModel(
          filePath: entry.key,
          calculatedHash: newHash.calculatedHash,
          length: newHash.length,
        ),
      );
    }
  }

  final removedFiles = oldByPath.keys
      .where((filePath) => !newByPath.containsKey(filePath))
      .toList(growable: false);

  changedFiles.sort((a, b) => a.filePath.compareTo(b.filePath));
  removedFiles.sort();

  return FileHashDiff(changedFiles: changedFiles, removedFiles: removedFiles);
}

Future<String> genFileHashes({String? path, String? configPath}) async {

  final String finalConfigPath = configPath ?? p.join(Directory.current.path, "pubspec.yaml");
  final configFile = File(finalConfigPath);

  await loadUpdaterConfig(configFile);
  
  final dir = hashRootDirectory(pathValue: path);

  if (await dir.exists()) {
    final tempDir = await Directory.systemTemp.createTemp("desktop_updater");
    final outputFile = File(p.join(tempDir.path, "hashes.json"));
    final sink = outputFile.openWrite();
    final hashList = <FileHashModel>[];

    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        final relativePath = normalizeArchivePath(
          p.relative(entity.path, from: dir.path),
        );

        if (_shouldSkipHash(relativePath)) {
          continue;
        }

        final hash = await getFileHash(entity);
        if (hash.isNotEmpty) {
          hashList.add(
            FileHashModel(
              filePath: relativePath,
              calculatedHash: hash,
              length: entity.lengthSync(),
            ),
          );
        }
      }
    }

    hashList.sort((a, b) => a.filePath.compareTo(b.filePath));
    sink.write(const JsonEncoder.withIndent("  ").convert(hashList));
    await sink.close();
    return outputFile.path;
  } else {
    throw Exception("Desktop Updater: Directory does not exist");
  }
}

List<FileHashModel> _decodeHashes(String source) {
  return (jsonDecode(source) as List<dynamic>)
      .map((e) => FileHashModel.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

bool _shouldSkipHash(String relativePath) {
  for (final rule in _dynamicSkipList) {
    if (rule.endsWith('/')) {
      if (relativePath.startsWith(rule)) {
        return true;
      }
    } else {
      if (relativePath == rule) {
        return true;
      }
    }
  }
  return false;
}
