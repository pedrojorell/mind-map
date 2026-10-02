import 'file_io_stub.dart' if (dart.library.io) 'file_io_native.dart' as impl;

/// true quando é possível ler/gravar arquivos diretamente por caminho
/// (Windows, macOS, Linux). No navegador os arquivos são baixados/enviados.
bool get canUseFilePaths => impl.canUseFilePaths;

Future<void> writeBytes(String path, List<int> bytes) =>
    impl.writeBytes(path, bytes);

Future<List<int>> readBytes(String path) => impl.readBytes(path);

Future<bool> fileExists(String path) => impl.fileExists(path);

/// Copia os dados salvos pelo app com o nome antigo (PinealMap) para a
/// pasta do MapLong, na primeira vez que o MapLong é aberto.
Future<void> migrateLegacyStorage() => impl.migrateLegacyStorage();

/// Pasta onde o MapLong guarda os dados no computador (nulo no navegador).
String? appDataDir() => impl.appDataDir();

/// Acrescenta uma linha a um arquivo de texto (cria a pasta se preciso).
/// Se o arquivo passar de [maxBytes], guarda o antigo com ".1" e recomeça.
Future<void> appendLine(String path, String line, {int maxBytes = 1 << 20}) =>
    impl.appendLine(path, line, maxBytes: maxBytes);
