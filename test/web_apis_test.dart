import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:maplong/editor_controller.dart';
import 'package:maplong/library.dart';
import 'package:maplong/models.dart';
import 'package:maplong/services/web_apis.dart';
import 'package:maplong/templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Respostas reais (resumidas) de cada API.
final _responses = <String, Object>{
  '/w/rest.php/v1/search/title': {
    'pages': [
      {
        'title': 'Fotossíntese',
        'description': 'processo de obtenção de glicose',
        'thumbnail': {'url': '//upload.wikimedia.org/a.jpg'},
      },
    ],
  },
  '/api/rest_v1/page/summary/Fotoss%C3%ADntese': {
    'title': 'Fotossíntese',
    'extract': 'Fotossíntese é o processo pelo qual plantas captam energia.',
    'content_urls': {
      'desktop': {'page': 'https://pt.wikipedia.org/wiki/Fotoss%C3%ADntese'},
    },
    'thumbnail': {'source': 'https://upload.wikimedia.org/b.jpg'},
  },
  '/w/api.php': {
    'parse': {
      'sections': [
        {'toclevel': 1, 'line': 'Visão geral'},
        {'toclevel': 2, 'line': 'Escopo'},
        {'toclevel': 1, 'line': '<i>Etapas</i>'},
        {'toclevel': 1, 'line': 'Referências'},
      ],
    },
  },
  '/v1/images/': {
    'results': [
      {
        'title': 'forest',
        'thumbnail': 'https://api.openverse.org/v1/images/x/thumb/',
        'url': 'https://example.org/forest.jpg',
        'creator': 'barnyz',
        'license': 'by',
        'license_version': '2.0',
        'foreign_landing_url': 'https://example.org/forest',
      },
    ],
  },
  '/api/feriados/v1/2026': [
    {'date': '2026-01-01', 'name': 'Confraternização mundial'},
    {'date': '2026-04-21', 'name': 'Tiradentes'},
  ],
  '/scheme': {
    'colors': [
      {
        'hex': {'value': '#3345F0'},
      },
      {
        'hex': {'value': '#6D38F2'},
      },
    ],
  },
};

WebApis _fakeApis({int status = 200}) => WebApis(
  client: MockClient((req) async {
    final body = _responses[req.url.path];
    if (status != 200) return http.Response('erro', status);
    if (body == null) return http.Response('não encontrado', 404);
    return http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

void main() {
  group('APIs públicas', () {
    final apis = _fakeApis();

    test('Wikipédia: busca, resumo e seções', () async {
      final results = await apis.wikiSearch('fotossíntese');
      expect(results.single.title, 'Fotossíntese');
      expect(results.single.thumbnail, 'https://upload.wikimedia.org/a.jpg');

      final summary = await apis.wikiSummary('Fotossíntese');
      expect(summary!.extract, startsWith('Fotossíntese é'));
      expect(summary.url, contains('wikipedia.org/wiki/'));
      expect(summary.image, isNotNull);

      // Só seções de primeiro nível, sem HTML e sem "Referências".
      expect(await apis.wikiSections('Fotossíntese'), [
        'Visão geral',
        'Etapas',
      ]);
    });

    test('Openverse: imagens com crédito e licença', () async {
      final images = await apis.searchImages('forest');
      expect(images.single.license, 'CC BY 2.0');
      expect(images.single.credit, 'forest — barnyz (CC BY 2.0)');
    });

    test('BrasilAPI: feriados do ano', () async {
      final list = await apis.brazilHolidays(2026);
      expect(list.map((h) => h.name), contains('Tiradentes'));
      expect(list.first.date, DateTime(2026, 1, 1));
    });

    test('The Color API: paleta', () async {
      expect(await apis.colorScheme('#3B4CF5'), ['#3345F0', '#6D38F2']);
    });

    test('erro do serviço vira mensagem amigável', () async {
      final broken = _fakeApis(status: 500);
      expect(() => broken.wikiSearch('x'), throwsA(isA<WebApiException>()));
    });

    test('tema personalizado com a paleta gerada', () async {
      SharedPreferences.setMockInitialValues({});
      final lib = Library(prefs: await SharedPreferences.getInstance());
      await lib.load();
      final doc = docFromOutline('x', 'Raiz\n  A\n  B');
      lib.add(doc);
      final ed = EditorController(library: lib, doc: doc);
      ed.applyCustomPalette(['#111111', '#222222', '#333333']);
      expect(doc.themeId, 'custom');
      expect(doc.root.fillColor, '#111111');
      expect(doc.nodes[doc.root.childrenIds.first]!.color, '#222222');
      final back = MindMapDoc.fromJson(doc.toJson());
      expect(back.themeId, 'custom');
      expect(back.customPalette, ['#111111', '#222222', '#333333']);
      expect(back.theme.palette, ['#222222', '#333333']);
    });
  });
}
