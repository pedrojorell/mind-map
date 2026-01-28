import 'dart:html' as html;

String? getDownloadsPathImpl() => null;

Future<void> openFileImpl(String path) async {
  html.window.open(path, '_blank');
}

Future<void> openExternalUrlImpl(String url) async {
  var u = url.trim();
  if (u.isEmpty) return;
  if (!u.startsWith('http://') && !u.startsWith('https://')) {
    u = 'https://$u';
  }
  html.window.open(u, '_blank');
}
