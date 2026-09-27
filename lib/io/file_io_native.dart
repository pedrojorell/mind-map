import 'dart:io';

bool get canUseFilePaths =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

Future<void> writeBytes(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  // Grava em arquivo temporário e renomeia, para não corromper o original.
  final tmp = File('$path.tmp');
  await tmp.writeAsBytes(bytes, flush: true);
  if (await file.exists()) await file.delete();
  await tmp.rename(path);
}

Future<List<int>> readBytes(String path) => File(path).readAsBytes();

Future<bool> fileExists(String path) => File(path).exists();
