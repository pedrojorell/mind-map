import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// APIs públicas e gratuitas (sem chave) usadas pelo MapLong. Todas vêm do
/// catálogo public-apis (https://github.com/public-apis/public-apis):
///
/// - Wikipedia (MediaWiki): resumo, link, imagem e seções de um assunto.
/// - Creative Commons Catalog (Openverse): imagens de uso livre.
/// - Brazil (BrasilAPI): feriados nacionais para o Gantt.
/// - The Color API: paletas de cores para os temas.

/// Erro amigável ao consultar uma API (sem internet, fora do ar etc.).
class WebApiException implements Exception {
  WebApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Cliente HTTP com tempo limite e cabeçalho de identificação.
class WebApis {
  WebApis({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);

  /// A Wikimedia pede que apps se identifiquem. No navegador o cabeçalho
  /// User-Agent é bloqueado, então usa-se o equivalente Api-User-Agent.
  static final Map<String, String> _headers = {
    kIsWeb ? 'Api-User-Agent' : 'User-Agent':
        'MapLong/2.0 (https://github.com/pedrojorell/mind-map)',
  };

  Future<dynamic> _getJson(Uri uri, {bool identify = false}) async {
    final http.Response r;
    try {
      r = await _client
          .get(uri, headers: identify ? _headers : null)
          .timeout(_timeout);
    } on TimeoutException {
      throw WebApiException('O serviço demorou demais para responder.');
    } catch (_) {
      throw WebApiException(
        'Sem conexão com a internet (ou serviço fora do ar).',
      );
    }
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) {
      throw WebApiException('O serviço respondeu com erro ${r.statusCode}.');
    }
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Baixa uma imagem (bytes).
  Future<Uint8List> getBytes(String url) async {
    try {
      final r = await _client
          .get(Uri.parse(url), headers: kIsWeb ? null : _headers)
          .timeout(_timeout);
      if (r.statusCode != 200) {
        throw WebApiException(
          'Não foi possível baixar a imagem (${r.statusCode}).',
        );
      }
      return r.bodyBytes;
    } on WebApiException {
      rethrow;
    } catch (_) {
      throw WebApiException('Não foi possível baixar a imagem.');
    }
  }

  // ------------------------------------------------------------ Wikipédia

  static String _wikiHost(String lang) => '$lang.wikipedia.org';

  /// Busca artigos pelo título.
  Future<List<WikiSearchResult>> wikiSearch(
    String query, {
    String lang = 'pt',
    int limit = 10,
  }) async {
    if (query.trim().isEmpty) return const [];
    final data = await _getJson(
      Uri.https(_wikiHost(lang), '/w/rest.php/v1/search/title', {
        'q': query.trim(),
        'limit': '$limit',
      }),
      identify: true,
    );
    return WikiSearchResult.listFromJson(data);
  }

  /// Resumo do artigo (primeiro parágrafo, link e imagem).
  Future<WikiSummary?> wikiSummary(String title, {String lang = 'pt'}) async {
    // pathSegments codifica o título uma única vez (inclusive "/" e acentos).
    final data = await _getJson(
      Uri(
        scheme: 'https',
        host: _wikiHost(lang),
        pathSegments: [
          'api',
          'rest_v1',
          'page',
          'summary',
          title.replaceAll(' ', '_'),
        ],
      ),
      identify: true,
    );
    return data is Map<String, dynamic> ? WikiSummary.fromJson(data) : null;
  }

  /// Títulos das seções principais do artigo (para virar subtópicos).
  Future<List<String>> wikiSections(String title, {String lang = 'pt'}) async {
    final data = await _getJson(
      Uri.https(_wikiHost(lang), '/w/api.php', {
        'action': 'parse',
        'page': title,
        'prop': 'sections',
        'format': 'json',
        'origin': '*',
        'redirects': '1',
      }),
      identify: true,
    );
    return parseWikiSections(data);
  }

  // ------------------------------------------------------------- Openverse

  /// Imagens de uso livre (licenças Creative Commons e domínio público).
  Future<List<OpenImage>> searchImages(
    String query, {
    int pageSize = 24,
  }) async {
    if (query.trim().isEmpty) return const [];
    final data = await _getJson(
      Uri.https('api.openverse.org', '/v1/images/', {
        'q': query.trim(),
        'page_size': '$pageSize',
      }),
    );
    return OpenImage.listFromJson(data);
  }

  // ------------------------------------------------------------- BrasilAPI

  final Map<int, List<Holiday>> _holidayCache = {};

  /// Feriados nacionais do Brasil no ano [year].
  Future<List<Holiday>> brazilHolidays(int year) async {
    final cached = _holidayCache[year];
    if (cached != null) return cached;
    final data = await _getJson(
      Uri.https('brasilapi.com.br', '/api/feriados/v1/$year'),
    );
    return _holidayCache[year] = Holiday.listFromJson(data);
  }

  // --------------------------------------------------------- The Color API

  /// Modos de paleta aceitos pela The Color API.
  static const colorModes = <String, String>{
    'analogic': 'Análoga',
    'monochrome': 'Monocromática',
    'complement': 'Complementar',
    'triad': 'Tríade',
    'quad': 'Quádrupla',
    'analogic-complement': 'Análoga + complementar',
  };

  /// Gera [count] cores harmônicas a partir de [hex] (ex.: "#3B4CF5").
  Future<List<String>> colorScheme(
    String hex, {
    String mode = 'analogic',
    int count = 6,
  }) async {
    final data = await _getJson(
      Uri.https('www.thecolorapi.com', '/scheme', {
        'hex': hex.replaceAll('#', ''),
        'mode': mode,
        'count': '$count',
        'format': 'json',
      }),
    );
    return parseColorScheme(data);
  }

  void close() => _client.close();
}

/// Instância compartilhada pelo app.
final webApis = WebApis();

// =====================================================================
// Modelos
// =====================================================================

class WikiSearchResult {
  const WikiSearchResult({
    required this.title,
    this.description = '',
    this.thumbnail,
  });

  final String title;
  final String description;
  final String? thumbnail;

  static List<WikiSearchResult> listFromJson(Object? json) {
    if (json is! Map || json['pages'] is! List) return const [];
    return [
      for (final p in json['pages'] as List)
        if (p is Map && p['title'] is String)
          WikiSearchResult(
            title: p['title'] as String,
            description: (p['description'] as String?) ?? '',
            thumbnail: _absolute((p['thumbnail'] as Map?)?['url'] as String?),
          ),
    ];
  }
}

class WikiSummary {
  const WikiSummary({
    required this.title,
    required this.extract,
    required this.url,
    this.image,
  });

  final String title;
  final String extract;
  final String url;

  /// Miniatura (até ~330 px), boa para o tópico.
  final String? image;

  factory WikiSummary.fromJson(Map<String, dynamic> j) {
    final urls = j['content_urls'];
    final desktop = urls is Map ? urls['desktop'] : null;
    return WikiSummary(
      title: (j['title'] as String?) ?? '',
      extract: ((j['extract'] as String?) ?? '').trim(),
      url: (desktop is Map ? desktop['page'] as String? : null) ?? '',
      image: _absolute((j['thumbnail'] as Map?)?['source'] as String?),
    );
  }
}

/// Seções que não fazem sentido como subtópicos.
const _skipSections = {
  'referências',
  'referencias',
  'ver também',
  'ligações externas',
  'links externos',
  'bibliografia',
  'notas',
  'notas e referências',
  'leitura adicional',
  'fontes',
  'galeria',
  'see also',
  'references',
  'external links',
  'further reading',
  'notes',
};

/// Títulos das seções de primeiro nível, sem HTML e sem seções de apoio.
List<String> parseWikiSections(Object? json) {
  final parse = json is Map ? json['parse'] : null;
  final sections = parse is Map ? parse['sections'] : null;
  if (sections is! List) return const [];
  final out = <String>[];
  for (final s in sections) {
    if (s is! Map || s['toclevel'] != 1) continue;
    final line = '${s['line'] ?? ''}'.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (line.isEmpty || _skipSections.contains(line.toLowerCase())) continue;
    out.add(line);
  }
  return out;
}

class OpenImage {
  const OpenImage({
    required this.title,
    required this.thumbnail,
    required this.url,
    required this.creator,
    required this.license,
    required this.landingUrl,
  });

  final String title;

  /// Miniatura servida pelo próprio Openverse (funciona também no navegador).
  final String thumbnail;
  final String url;
  final String creator;

  /// Ex.: "CC BY 2.0" ou "CC0".
  final String license;
  final String landingUrl;

  String get credit =>
      '${title.isEmpty ? 'Imagem' : title}'
      '${creator.isEmpty ? '' : ' — $creator'} ($license)';

  static List<OpenImage> listFromJson(Object? json) {
    if (json is! Map || json['results'] is! List) return const [];
    return [
      for (final r in json['results'] as List)
        if (r is Map && r['thumbnail'] is String)
          OpenImage(
            title: ((r['title'] as String?) ?? '').trim(),
            thumbnail: r['thumbnail'] as String,
            url: (r['url'] as String?) ?? '',
            creator: ((r['creator'] as String?) ?? '').trim(),
            license: _licenseLabel(
              r['license'] as String?,
              r['license_version'] as String?,
            ),
            landingUrl: (r['foreign_landing_url'] as String?) ?? '',
          ),
    ];
  }

  static String _licenseLabel(String? license, String? version) {
    final l = (license ?? '').toLowerCase();
    if (l.isEmpty) return 'licença livre';
    if (l == 'cc0') return 'CC0';
    if (l == 'pdm') return 'domínio público';
    return 'CC ${l.toUpperCase()}${version == null ? '' : ' $version'}';
  }
}

class Holiday {
  const Holiday({required this.date, required this.name});

  final DateTime date;
  final String name;

  static List<Holiday> listFromJson(Object? json) {
    if (json is! List) return const [];
    return [
      for (final h in json)
        if (h is Map && DateTime.tryParse('${h['date']}') != null)
          Holiday(
            date: DateTime.parse('${h['date']}'),
            name: '${h['name'] ?? 'Feriado'}',
          ),
    ];
  }
}

/// Cores (#RRGGBB) de uma resposta da The Color API.
List<String> parseColorScheme(Object? json) {
  final colors = json is Map ? json['colors'] : null;
  if (colors is! List) return const [];
  return [
    for (final c in colors)
      if (c is Map && c['hex'] is Map && c['hex']['value'] is String)
        (c['hex']['value'] as String).toUpperCase(),
  ];
}

/// URLs da Wikimedia às vezes vêm sem o protocolo ("//upload...").
String? _absolute(String? url) {
  if (url == null || url.isEmpty) return null;
  return url.startsWith('//') ? 'https:$url' : url;
}
