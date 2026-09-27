import 'file_io_stub.dart' if (dart.library.io) 'file_io_native.dart' as impl;

/// true quando é possível ler/gravar arquivos diretamente por caminho
/// (Windows, macOS, Linux). No navegador os arquivos são baixados/enviados.
bool get canUseFilePaths => impl.canUseFilePaths;

Future<void> writeBytes(String path, List<int> bytes) =>
    impl.writeBytes(path, bytes);

Future<List<int>> readBytes(String path) => impl.readBytes(path);

Future<bool> fileExists(String path) => impl.fileExists(path);
