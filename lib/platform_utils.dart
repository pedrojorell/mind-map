import 'platform_utils_stub.dart'
    if (dart.library.html) 'platform_utils_web.dart'
    if (dart.library.io) 'platform_utils_io.dart';

String? getDownloadsPath() => getDownloadsPathImpl();

Future<void> openFile(String path) => openFileImpl(path);

Future<void> openExternalUrl(String url) => openExternalUrlImpl(url);
