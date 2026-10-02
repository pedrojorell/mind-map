import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app_info.dart';

/// Versão nova publicada no GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    this.notes = '',
    this.downloadUrl,
  });

  final String version;

  /// Página do release.
  final String url;
  final String notes;

  /// Link direto do instalador (.exe), se o release tiver um.
  final String? downloadUrl;

  /// Lê a resposta de /releases/latest da API do GitHub.
  static UpdateInfo? fromJson(Object? json) {
    if (json is! Map || json['tag_name'] is! String) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;
    String? exe;
    for (final a in (json['assets'] as List?) ?? const []) {
      final name = a is Map ? '${a['name']}' : '';
      if (name.toLowerCase().endsWith('.exe')) {
        exe = '${a['browser_download_url']}';
        break;
      }
    }
    return UpdateInfo(
      version: (json['tag_name'] as String).replaceFirst(RegExp(r'^[vV]'), ''),
      url: (json['html_url'] as String?) ?? kReleasesUrl,
      notes: ((json['body'] as String?) ?? '').trim(),
      downloadUrl: exe,
    );
  }
}

/// Consulta o último release no GitHub. Retorna a versão nova, ou nulo se o
/// app já está atualizado, se não há releases ou se não há internet.
Future<UpdateInfo?> checkForUpdate({
  http.Client? client,
  String current = kAppVersion,
}) async {
  final c = client ?? http.Client();
  try {
    final r = await c
        .get(
          Uri.https(
            'api.github.com',
            '/repos/$kRepoOwner/$kRepoName/releases/latest',
          ),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 10));
    if (r.statusCode != 200) return null;
    final info = UpdateInfo.fromJson(jsonDecode(utf8.decode(r.bodyBytes)));
    if (info == null || compareVersions(info.version, current) <= 0) {
      return null;
    }
    return info;
  } catch (_) {
    return null; // Sem internet: tenta de novo na próxima abertura.
  } finally {
    if (client == null) c.close();
  }
}
