import 'dart:io';

String? getDownloadsPathImpl() {
  try {
    if (!Platform.isWindows) return null;
    final user = Platform.environment['USERPROFILE'];
    if (user == null) return null;
    final downloads = '$user\\Downloads';
    if (Directory(downloads).existsSync()) return downloads;
  } catch (_) {}
  return null;
}

Future<void> openFileImpl(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path], runInShell: true);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
      return;
    }
  } catch (_) {}
}

Future<void> openExternalUrlImpl(String url) async {
  String u = url.trim();
  if (u.isEmpty) return;
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    u = 'https://$u';
  }

  try {
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', u], runInShell: true);
      return;
    }
    if (Platform.isMacOS) {
      await Process.run('open', [u]);
      return;
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [u]);
      return;
    }
  } catch (_) {}
}
