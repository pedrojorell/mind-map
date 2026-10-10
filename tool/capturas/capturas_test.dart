// Gera as capturas de tela usadas no site de vendas (site/img/).
//
//   flutter test tool/capturas/capturas_test.dart --update-goldens
//
// As imagens saem nesta pasta e são copiadas para site/img/ pelo comando
// descrito em docs/SITE_DE_VENDAS.md. Usa as fontes que vêm com o Flutter.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplong/library.dart';
import 'package:maplong/main.dart';
import 'package:maplong/models.dart';
import 'package:maplong/templates.dart';
import 'package:shared_preferences/shared_preferences.dart';

String get _flutterRoot {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // .../flutter/bin/cache/artifacts/engine/<plataforma>/flutter_tester
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  return dir.path;
}

Future<void> _font(String family, List<String> files) async {
  final dir = '$_flutterRoot/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(family);
  for (final f in files) {
    loader.addFont(
      Future.value(ByteData.sublistView(File('$dir/$f').readAsBytesSync())),
    );
  }
  await loader.load();
}

Future<void> _fonts() async {
  await _font('Roboto', [
    'roboto-regular.ttf',
    'roboto-medium.ttf',
    'roboto-bold.ttf',
    'roboto-italic.ttf',
  ]);
  await _font('MaterialIcons', ['materialicons-regular.otf']);
}

MindMapDoc _doc(String name, String template, {String? theme}) {
  final t = kTemplates.firstWhere((t) => t.title == template);
  final d = docFromTemplate(name, t);
  if (theme != null) {
    final th = themeById(theme);
    d
      ..themeId = th.id
      ..background = th.background;
  }
  return d;
}

/// Mapa de demonstração com formas, marcadores, nota adesiva e relação.
MindMapDoc _showcase() {
  final d = docFromOutline('Lançamento do produto', '''
Lançamento do produto
  Pesquisa
    Público-alvo
    Concorrentes
  Produto
    Recursos principais
    Preço
  Divulgação
    Redes sociais
    E-mail marketing
  Vendas
    Página de vendas
    Checkout''', theme: 'aurora');
  final ids = d.root.childrenIds.map((i) => d.nodes[i]!).toList();
  d.root.shape = 'cloud';
  ids[0]
    ..setMarker('priority', '1')
    ..setMarker('progress', '100')
    ..shape = 'rounded';
  ids[1]
    ..setMarker('priority', '2')
    ..setMarker('progress', '62')
    ..shape = 'hexagon';
  ids[2]
    ..setMarker('flag', '#F44336')
    ..shape = 'tag';
  ids[3]
    ..setMarker('star', '#FFC107')
    ..setMarker('symbol', 'rocket')
    ..shape = 'arrowRight';
  final sub = d.nodes[ids[1].childrenIds.first]!;
  sub.setMarker('symbol', 'idea');
  d.nodes[ids[3].childrenIds.last]!.setMarker('symbol', 'money');
  ids[2].boundary = true;
  // Rótulos desenhados no canvas não usam as fontes carregadas no teste,
  // então a relação fica sem rótulo na captura.
  d.relations.add(NodeRelation(id: newId(), from: ids[0].id, to: ids[3].id));
  return d;
}

Future<Library> _library({bool dark = false}) async {
  SharedPreferences.setMockInitialValues({});
  final lib = Library(prefs: await SharedPreferences.getInstance());
  await lib.load();
  lib
    ..markWelcomeSeen()
    ..setCheckUpdates(false)
    ..setThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
  return lib;
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  // Espera a organização automática e o enquadramento do mapa.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(_fonts);

  void window(WidgetTester tester) {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('tela inicial', (tester) async {
    window(tester);
    final lib = await _library();
    for (final (name, tpl, theme) in const [
      ('Plano de estudos', 'Estudo', 'oceano'),
      ('Projeto do site', 'Projeto', 'aurora'),
      ('Reunião semanal', 'Ata de reunião', 'grafite'),
      ('Brainstorm de ideias', 'Brainstorm', 'por-do-sol'),
      ('Viagem de férias', 'Viagem', 'praia'),
      ('Metas do ano', 'Metas do ano', 'floresta'),
    ]) {
      lib.add(_doc(name, tpl, theme: theme));
    }
    await tester.pumpWidget(MapLongApp(library: lib));
    await _settle(tester);
    await expectLater(
      find.byType(MapLongApp),
      matchesGoldenFile('tela-inicial.png'),
    );
    await lib.flush();
  });

  Future<void> openEditor(
    WidgetTester tester,
    Library lib,
    MindMapDoc doc,
  ) async {
    lib.add(doc);
    await tester.pumpWidget(MapLongApp(library: lib));
    await _settle(tester);
    await tester.tap(find.text(doc.name).first);
    await _settle(tester);
    // Tira a seleção (a barra flutuante cobriria o mapa) e mostra o painel
    // "Mapa e tema".
    await tester.tapAt(const Offset(150, 790));
    await tester.tap(find.byTooltip('Mapa e tema'));
    await _settle(tester);
  }

  testWidgets('editor', (tester) async {
    window(tester);
    final lib = await _library();
    final doc = _showcase();
    await openEditor(tester, lib, doc);
    await expectLater(
      find.byType(MapLongApp),
      matchesGoldenFile('editor.png'),
    );
    await lib.flush();
  });

  testWidgets('editor escuro', (tester) async {
    window(tester);
    final lib = await _library(dark: true);
    final doc = _doc('Plano de projeto', 'Projeto', theme: 'noite')
      ..layout = 'logic'
      ..texture = 'dots'
      ..colorMode = 'rainbow';
    for (final id in doc.root.childrenIds) {
      final n = doc.nodes[id]!;
      n
        ..fillColor = n.color
        ..textColor = '#FFFFFF';
    }
    await openEditor(tester, lib, doc);
    await expectLater(
      find.byType(MapLongApp),
      matchesGoldenFile('editor-escuro.png'),
    );
    await lib.flush();
  });

  testWidgets('desenho à mão', (tester) async {
    window(tester);
    final lib = await _library();
    final doc = _doc('Ideias para o fim de semana', 'Brainstorm',
        theme: 'pastel')
      ..handDrawn = true
      ..texture = 'paper'
      ..layout = 'right';
    await openEditor(tester, lib, doc);
    await expectLater(
      find.byType(MapLongApp),
      matchesGoldenFile('desenho-a-mao.png'),
    );
    await lib.flush();
  });
}
