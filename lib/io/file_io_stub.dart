const bool canUseFilePaths = false;

Future<void> writeBytes(String path, List<int> bytes) =>
    throw UnsupportedError('Arquivos locais não disponíveis nesta plataforma.');

Future<List<int>> readBytes(String path) =>
    throw UnsupportedError('Arquivos locais não disponíveis nesta plataforma.');

Future<bool> fileExists(String path) async => false;

/// No navegador os dados continuam no mesmo lugar: nada a migrar.
Future<void> migrateLegacyStorage() async {}
