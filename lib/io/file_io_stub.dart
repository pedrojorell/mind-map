const bool canUseFilePaths = false;

Future<void> writeBytes(String path, List<int> bytes) =>
    throw UnsupportedError('Arquivos locais não disponíveis nesta plataforma.');

Future<List<int>> readBytes(String path) =>
    throw UnsupportedError('Arquivos locais não disponíveis nesta plataforma.');

Future<bool> fileExists(String path) async => false;
