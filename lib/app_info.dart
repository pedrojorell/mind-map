/// Informações do aplicativo exibidas em "Sobre" e usadas na verificação de
/// atualizações. Mantenha [kAppVersion] igual à versão do pubspec.yaml (um
/// teste confere isso).
library;

const kAppVersion = '2.1.0';

const kRepoOwner = 'pedrojorell';
const kRepoName = 'mind-map';
const kRepoUrl = 'https://github.com/$kRepoOwner/$kRepoName';
const kReleasesUrl = '$kRepoUrl/releases';
const kTutorialUrl = '$kRepoUrl/blob/main/docs/TUTORIAL.md';
const kIssuesUrl = '$kRepoUrl/issues';

/// Compara versões "maior.menor.correção" (ignora um "v" no início e
/// sufixos como "-beta"). Retorna negativo, zero ou positivo.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .trim()
      .replaceFirst(RegExp(r'^[vV]'), '')
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
