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

/// Pastas de dados (shared_preferences) antes e depois da mudança de nome.
/// No Windows a pasta é `%APPDATA%/CompanyName/ProductName` (do Runner.rc);
/// no Linux, `~/.local/share/<id do aplicativo>`.
List<(String, String)> _legacyDataDirs() {
  final env = Platform.environment;
  String join(List<String> parts) => parts.join(Platform.pathSeparator);
  if (Platform.isWindows) {
    final appData = env['APPDATA'];
    if (appData == null) return const [];
    return [
      (
        join([appData, 'com.pinealmap', 'pinealmap']),
        join([appData, 'MapLong', 'MapLong']),
      ),
    ];
  }
  if (Platform.isLinux) {
    final home = env['HOME'];
    final data =
        env['XDG_DATA_HOME'] ?? (home == null ? null : '$home/.local/share');
    if (data == null) return const [];
    return [('$data/com.pinealmap.pinealmap', '$data/com.maplong.maplong')];
  }
  return const [];
}

Future<void> migrateLegacyStorage() async {
  for (final (oldDir, newDir) in _legacyDataDirs()) {
    try {
      final sep = Platform.pathSeparator;
      final oldFile = File('$oldDir${sep}shared_preferences.json');
      final newFile = File('$newDir${sep}shared_preferences.json');
      if (await oldFile.exists() && !await newFile.exists()) {
        await newFile.parent.create(recursive: true);
        await oldFile.copy(newFile.path);
      }
    } catch (_) {
      // Sem permissão ou pasta inválida: o app continua com dados novos.
    }
  }
}

/// Mesma pasta usada pelo shared_preferences de cada sistema.
String? appDataDir() {
  final env = Platform.environment;
  final sep = Platform.pathSeparator;
  if (Platform.isWindows) {
    final appData = env['APPDATA'];
    return appData == null ? null : '$appData${sep}MapLong${sep}MapLong';
  }
  final home = env['HOME'];
  if (Platform.isMacOS) {
    return home == null
        ? null
        : '$home/Library/Application Support/com.maplong.maplong';
  }
  if (Platform.isLinux) {
    final data =
        env['XDG_DATA_HOME'] ?? (home == null ? null : '$home/.local/share');
    return data == null ? null : '$data/com.maplong.maplong';
  }
  return null;
}

Future<void> appendLine(
  String path,
  String line, {
  int maxBytes = 1 << 20,
}) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  if (await file.exists() && await file.length() > maxBytes) {
    final old = File('$path.1');
    if (await old.exists()) await old.delete();
    await file.rename(old.path);
  }
  await File(path).writeAsString('$line\n', mode: FileMode.append, flush: true);
}
