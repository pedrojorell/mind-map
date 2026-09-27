import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinealmap/editor_controller.dart';
import 'package:pinealmap/file_actions.dart';
import 'package:pinealmap/import_export.dart';
import 'package:pinealmap/layout.dart';
import 'package:pinealmap/library.dart';
import 'package:pinealmap/main.dart';
import 'package:pinealmap/models.dart';
import 'package:pinealmap/templates.dart';
import 'package:pinealmap/widgets/node_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Library> newLibrary([Map<String, Object> values = const {}]) async {
  SharedPreferences.setMockInitialValues(values);
  final lib = Library(prefs: await SharedPreferences.getInstance());
  await lib.load();
  return lib;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('modelo', () {
    test('JSON ida e volta preserva o mapa', () {
      final doc = docFromTemplate(
        'Teste',
        kTemplates.firstWhere((t) => t.title == 'Projeto'),
      );
      doc.nodes.values.first.note = 'nota';
      final back = MindMapDoc.fromJson(
        jsonDecode(utf8.decode(encodeDoc(doc))) as Map<String, dynamic>,
      );
      expect(back.nodes.length, doc.nodes.length);
      expect(back.root.text, 'Projeto');
      expect(back.nodes.values.first.note, 'nota');
      expect(jsonEncode(back.toJson()), jsonEncode(doc.toJson()));
    });

    test('lê o formato antigo (v1)', () {
      final legacy = {
        'id': '1',
        'name': 'Antigo',
        'createdAt': 1,
        'updatedAt': 2,
        'rootId': 'root_1',
        'nodes': {
          'root_1': {
            'id': 'root_1',
            'text': 'Raiz',
            'parentId': null,
            'childrenIds': ['a'],
            'pos': {'dx': 0, 'dy': 0},
            'branchColor': '#FF5252',
            'shape': 'label',
            'borderStyle': 'dashed',
          },
          'a': {
            'id': 'a',
            'text': 'Filho',
            'parentId': 'root_1',
            'childrenIds': ['sumiu'],
            'pos': {'dx': 320, 'dy': 0},
          },
        },
      };
      final d = MindMapDoc.fromJson(legacy);
      expect(d.root.color, '#FF5252');
      expect(d.root.shape, 'underline');
      expect(d.root.dashed, isTrue);
      expect(d.nodes['a']!.childrenIds, isEmpty);
      expect(d.autoLayout, isFalse);
    });

    test('texto com marcadores de lista vira mapa', () {
      final doc = docFromOutline(
        'x',
        '# Férias\n- Destino\n  - Praia\n- Orçamento',
      );
      expect(doc.root.text, 'Férias');
      expect(doc.root.childrenIds.length, 2);
      final destino = doc.nodes[doc.root.childrenIds.first]!;
      expect(destino.text, 'Destino');
      expect(doc.nodes[destino.childrenIds.single]!.text, 'Praia');
    });

    test('links: tipo e endereço resolvido', () {
      expect(
        NodeLink(url: 'www.site.com.br').resolved,
        'https://www.site.com.br',
      );
      expect(NodeLink(url: 'ana@ex.com').kind, 'email');
      expect(NodeLink(url: 'ana@ex.com').resolved, 'mailto:ana@ex.com');
      expect(
        NodeLink(url: '+55 (11) 91234-5678').resolved,
        'tel:+5511912345678',
      );
      expect(NodeLink(url: 'https://a.b/c').resolved, 'https://a.b/c');
    });

    test('link, imagem, etiquetas e numeração sobrevivem ao JSON', () {
      final doc = docFromOutline('x', 'Raiz\n  A\n    A1\n  B')
        ..numbering = true;
      final a = doc.nodes[doc.root.childrenIds.first]!;
      a.links.add(NodeLink(url: 'site.com', title: 'Site'));
      a.image = NodeImage(data: 'AAAA', name: 'foto.png', width: 120);
      a.tags.add('urgente');
      a.attachments.add(NodeAttachment(name: 'r.pdf', data: 'QQ==', size: 1));
      final back = MindMapDoc.fromJson(doc.toJson());
      final b = back.nodes[a.id]!;
      expect(b.links.single.title, 'Site');
      expect(b.image!.width, 120);
      expect(b.tags, ['urgente']);
      expect(b.attachments.single.embedded, isTrue);
      expect(back.numbering, isTrue);
      expect(back.numberOf(a.childrenIds.single), '1.1');
      expect(back.numberOf(back.root.childrenIds[1]), '2');
    });

    test('link antigo (texto) vira lista de links', () {
      final n = MindMapNode.fromJson({
        'id': 'a',
        'text': 't',
        'link': 'exemplo.com',
        'pos': {'dx': 0, 'dy': 0},
      });
      expect(n.links.single.url, 'exemplo.com');
    });

    test('importa Markdown, OPML e FreeMind', () {
      final md = docFromOutline(
        'x',
        markdownToOutline('# Viagem\n## Destino\n- Praia\n## Custos'),
      );
      expect(md.root.text, 'Viagem');
      final destino = md.nodes[md.root.childrenIds.first]!;
      expect(destino.text, 'Destino');
      expect(md.nodes[destino.childrenIds.single]!.text, 'Praia');

      final src = docFromOutline('y', 'Raiz\n  A\n    A1\n  B');
      final opml = opmlToDoc('y', toOpml(src));
      expect(opml.root.text, 'Raiz');
      expect(opml.nodes.length, 4);
      final mm = freeMindToDoc('y', toFreeMind(src));
      expect(mm.root.text, 'Raiz');
      expect(mm.nodes.length, 4);
      expect(toCsv(src), contains('A1'));
      expect(toHtml(src), contains('<strong>A1</strong>'));
    });

    test('markdown exporta a hierarquia', () {
      final doc = docFromOutline('x', 'Raiz\n  A\n    A1\n  B');
      expect(toMarkdown(doc), '# Raiz\n\n- A\n  - A1\n- B\n');
    });
  });

  group('editor', () {
    late Library lib;
    late EditorController ed;

    setUp(() async {
      lib = await newLibrary();
      final doc = docFromOutline('Mapa', 'Raiz\n  A\n  B');
      lib.add(doc);
      ed = EditorController(library: lib, doc: doc);
    });

    test('adicionar, desfazer e refazer', () {
      final before = ed.doc.nodes.length;
      final id = ed.addChild(ed.doc.rootId)!;
      expect(ed.doc.nodes.length, before + 1);
      expect(ed.editingId, id);
      ed.commitEditing('Novo');
      expect(ed.doc.nodes[id]!.text, 'Novo');
      ed.undo();
      expect(ed.doc.nodes[id]!.text, isNot('Novo'));
      ed.undo();
      expect(ed.doc.nodes.length, before);
      ed.redo();
      ed.redo();
      expect(ed.doc.nodes[id]!.text, 'Novo');
    });

    test('excluir remove a subárvore inteira', () {
      final a = ed.doc.root.childrenIds.first;
      ed.select(a);
      ed.addChild();
      ed.commitEditing('neto');
      final count = ed.doc.nodes.length;
      ed.deleteNode(a);
      expect(ed.doc.nodes.length, count - 2);
      expect(ed.doc.root.childrenIds, isNot(contains(a)));
    });

    test('mover para outro pai não cria ciclos', () {
      final a = ed.doc.root.childrenIds[0];
      final b = ed.doc.root.childrenIds[1];
      expect(ed.reparent(a, b), isTrue);
      expect(ed.doc.nodes[a]!.parentId, b);
      expect(ed.reparent(b, a), isFalse); // a está dentro de b
      expect(ed.reparent(ed.doc.rootId, a), isFalse);
    });

    test('copiar e colar duplica com novos ids', () {
      ed.select(ed.doc.root.childrenIds.first);
      ed.copy();
      ed.select(ed.doc.rootId);
      final n = ed.doc.nodes.length;
      expect(ed.paste(), isTrue);
      expect(ed.doc.nodes.length, n + 1);
      expect(ed.doc.root.childrenIds.length, 3);
    });

    test('colar texto com recuo cria tópicos', () {
      ed.select(ed.doc.rootId);
      ed.pasteOutline('- Um\n  - Um.1\n  - Um.2\n- Dois');
      final texts = ed.doc.nodes.values.map((n) => n.text).toSet();
      expect(texts, containsAll(['Um', 'Um.1', 'Um.2', 'Dois']));
      final um = ed.doc.nodes.values.firstWhere((n) => n.text == 'Um');
      expect(um.childrenIds.length, 2);
      expect(um.parentId, ed.doc.rootId);
    });

    test('marcadores: um por grupo, alterna e sobrevive ao JSON', () {
      final a = ed.doc.root.childrenIds.first;
      ed.select(a);
      ed.toggleMarker('priority', '1');
      ed.toggleMarker('flag', '#F44336');
      ed.toggleMarker('priority', '2');
      final n = ed.doc.nodes[a]!;
      expect(n.markers, ['priority:2', 'flag:#F44336']);
      ed.toggleMarker('priority', '2');
      expect(n.marker('priority'), isNull);
      ed.setSticker('🚀');
      final back = MindMapDoc.fromJson(ed.doc.toJson());
      expect(back.nodes[a]!.markers, ['flag:#F44336']);
      expect(back.nodes[a]!.sticker, '🚀');
    });

    test('relações: cria, evita duplicata e some ao excluir o tópico', () {
      final a = ed.doc.root.childrenIds[0];
      final b = ed.doc.root.childrenIds[1];
      ed.select(a);
      ed.startRelation();
      expect(ed.completeRelation(b), isTrue);
      ed.startRelation(b);
      expect(ed.completeRelation(a), isFalse); // já existe
      expect(ed.doc.relations.length, 1);
      final back = MindMapDoc.fromJson(ed.doc.toJson());
      expect(back.relations.single.to, b);
      ed.deleteNode(b);
      expect(ed.doc.relations, isEmpty);
      ed.undo();
      expect(ed.doc.relations.length, 1);
    });

    test('tópico antes e ramo principal', () {
      final a = ed.doc.root.childrenIds[0];
      ed.select(a);
      final before = ed.addSiblingBefore()!;
      expect(ed.doc.root.childrenIds.first, before);
      final main = ed.addMainTopic()!;
      expect(ed.doc.nodes[main]!.parentId, ed.doc.rootId);
    });

    test('estrutura à direita coloca todos os ramos do mesmo lado', () {
      ed.addMainTopic();
      ed.addMainTopic();
      ed.setLayout('right');
      final rootX = ed.doc.root.pos.dx;
      for (final c in ed.doc.root.childrenIds) {
        expect(ed.doc.nodes[c]!.pos.dx, greaterThan(rootX));
      }
      ed.setLayout('left');
      for (final c in ed.doc.root.childrenIds) {
        expect(ed.doc.nodes[c]!.pos.dx, lessThan(rootX));
      }
    });

    test('tema recolore os ramos e o fundo', () {
      ed.applyTheme('floresta');
      final t = themeById('floresta');
      expect(ed.doc.root.fillColor, t.rootFill);
      expect(ed.doc.nodes[ed.doc.root.childrenIds[1]]!.color, t.palette[1]);
      expect(ed.doc.background, t.background);
      expect(ed.doc.branchColor(0), t.palette[0]);
    });

    test('estruturas: organograma, linha do tempo e espinha de peixe', () {
      ed.addMainTopic();
      final root = ed.doc.root.pos;
      ed.setLayout('org');
      for (final c in ed.doc.root.childrenIds) {
        expect(ed.doc.nodes[c]!.pos.dy, greaterThan(root.dy));
      }
      ed.setLayout('timeline');
      for (final c in ed.doc.root.childrenIds) {
        expect(ed.doc.nodes[c]!.pos.dx, greaterThan(root.dx));
      }
      ed.setLayout('fishbone');
      for (final c in ed.doc.root.childrenIds) {
        expect(ed.doc.nodes[c]!.pos.dx, lessThan(root.dx));
      }
      ed.setLayout('tree');
      final first = ed.doc.nodes[ed.doc.root.childrenIds.first]!;
      expect(first.pos.dy, greaterThan(root.dy));
    });

    test('seleção múltipla aplica estilo e exclui juntos', () {
      final a = ed.doc.root.childrenIds[0];
      final b = ed.doc.root.childrenIds[1];
      ed.select(a);
      ed.toggleMultiSelect(b);
      expect(ed.selection, [a, b]);
      ed.updateNode(a, (n) => n.bold = true);
      expect(ed.doc.nodes[b]!.bold, isTrue);
      ed.deleteSelection();
      expect(ed.doc.nodes.containsKey(a), isFalse);
      expect(ed.doc.nodes.containsKey(b), isFalse);
      ed.undo();
      expect(ed.doc.nodes.containsKey(b), isTrue);
    });

    test('pincel de formato e substituir', () {
      final a = ed.doc.root.childrenIds[0];
      final b = ed.doc.root.childrenIds[1];
      ed.updateNode(
        a,
        (n) => n
          ..shape = 'hexagon'
          ..italic = true,
      );
      ed.copyStyle(a);
      ed.select(b);
      ed.pasteStyle();
      expect(ed.doc.nodes[b]!.shape, 'hexagon');
      expect(ed.doc.nodes[b]!.italic, isTrue);
      expect(ed.replaceAll('A', 'Z', caseSensitive: true), 1);
      expect(ed.doc.nodes[a]!.text, 'Z');
    });

    test('foco mostra só o ramo', () {
      final a = ed.doc.root.childrenIds[0];
      ed.select(a);
      ed.addChild();
      ed.commitEditing('filho');
      ed.setFocus(a);
      final ids = ed.visibleNodes().map((n) => n.id).toSet();
      expect(ids.contains(ed.doc.rootId), isFalse);
      expect(ids.length, 2);
    });

    test('elementos sobrevivem ao JSON', () {
      final a = ed.doc.root.childrenIds[0];
      ed.updateNode(a, (n) {
        n
          ..callouts.add('obs')
          ..boundary = true
          ..boundaryLabel = 'Grupo'
          ..summary = 'Conclusão'
          ..table = [
            ['a', 'b'],
          ]
          ..formula = 'x^2'
          ..task = NodeTask(
            start: 0,
            end: 86400000,
            progress: 50,
            assignee: 'Ana',
          )
          ..comments.add(NodeComment(id: 'c', text: 'oi', at: 1))
          ..underline = true
          ..align = 'left';
      });
      final back = MindMapDoc.fromJson(ed.doc.toJson()).nodes[a]!;
      expect(back.callouts, ['obs']);
      expect(back.boundaryLabel, 'Grupo');
      expect(back.summary, 'Conclusão');
      expect(back.table, [
        ['a', 'b'],
      ]);
      expect(back.formula, 'x^2');
      expect(back.task!.assignee, 'Ana');
      expect(back.comments.single.text, 'oi');
      expect(back.underline, isTrue);
      expect(back.align, 'left');
    });

    test('tópicos nunca ficam um em cima do outro', () {
      Rect rectOf(String id) {
        final n = ed.doc.nodes[id]!;
        final s = estimateNodeSize(n);
        return Rect.fromCenter(center: n.pos, width: s.width, height: s.height);
      }

      // Posição livre: um tópico cresce (texto longo) e invade os vizinhos.
      ed.doc.autoLayout = false;
      final a = ed.doc.root.childrenIds[0];
      final b = ed.doc.root.childrenIds[1];
      ed.doc.nodes[b]!.pos = ed.doc.nodes[a]!.pos + const Offset(20, 10);
      ed.doc.nodes[a]!.text = 'Um texto bem comprido digitado agora';
      expect(rectOf(a).overlaps(rectOf(b)), isTrue);
      expect(resolveOverlaps(ed.doc, const {}, anchorId: a), isTrue);
      expect(rectOf(a).overlaps(rectOf(b)), isFalse);

      // Tópicos flutuantes em cima da árvore são afastados.
      final f = ed.addFloating(ed.doc.root.pos, edit: false);
      resolveOverlaps(ed.doc, const {}, onlyFloating: true);
      expect(rectOf(f).overlaps(rectOf(ed.doc.rootId)), isFalse);
    });

    test('recolher esconde descendentes', () {
      final a = ed.doc.root.childrenIds.first;
      ed.select(a);
      ed.addChild();
      ed.commitEditing('x');
      ed.toggleCollapse(a);
      expect(ed.doc.visibleNodes().any((n) => n.text == 'x'), isFalse);
    });
  });

  group('biblioteca', () {
    test('salva e recarrega os mapas', () async {
      final lib = await newLibrary();
      final d = lib.create(name: 'Persistido');
      d.root.text = 'Alterado';
      await lib.saveNow(d);

      final prefs = await SharedPreferences.getInstance();
      final lib2 = Library(prefs: prefs);
      await lib2.load();
      expect(lib2.doc(d.id)!.name, 'Persistido');
      expect(lib2.doc(d.id)!.root.text, 'Alterado');

      await lib2.delete(d.id);
      final lib3 = Library(prefs: prefs);
      await lib3.load();
      expect(lib3.doc(d.id), isNull);
    });

    test('lixeira, favoritos e versões', () async {
      final lib = await newLibrary();
      final d = lib.create(name: 'Lixo');
      lib.toggleStar(d.id);
      expect(lib.doc(d.id)!.starred, isTrue);
      await lib.moveToTrash(d.id);
      expect(lib.doc(d.id), isNull);
      expect(lib.trash.single.id, d.id);
      await lib.restore(d.id);
      expect(lib.doc(d.id), isNotNull);

      expect(await lib.saveVersion(d, force: true), isFalse); // já salvo igual
      d.root.text = 'Mudou';
      expect(await lib.saveVersion(d, force: true), isTrue);
      expect(lib.versions(d.id).length, greaterThanOrEqualTo(2));
    });

    test('migra dados da versão antiga', () async {
      final old = MindMapDoc.blank(name: 'Velho');
      final lib = await newLibrary({
        'pinealmap.docs.v1': jsonEncode([old.toJson()]),
      });
      expect(lib.doc(old.id)!.name, 'Velho');
    });
  });

  testWidgets('fluxo: criar mapa, adicionar tópico pelo teclado e voltar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lib = await newLibrary();
    await tester.pumpWidget(PinealMapApp(library: lib));
    await tester.pumpAndSettle();

    expect(find.text('Começar com um modelo'), findsOneWidget);
    await tester.tap(find.text('Clássico'));
    await tester.pumpAndSettle();

    expect(find.text('Ideia Principal'), findsWidgets);
    expect(find.text('Tópico 1'), findsOneWidget);
    final doc = lib.docsByRecent.single;
    final before = doc.nodes.length;

    // Seleciona a ideia principal e cria um subtópico com Tab.
    await tester.tap(find.text('Ideia Principal').first);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(doc.nodes.length, before + 1);

    // Digita o texto do novo tópico e confirma com Enter.
    final inline = find.descendant(
      of: find.byType(NodeView),
      matching: find.byType(TextField),
    );
    expect(inline, findsOneWidget);
    await tester.enterText(inline, 'Minha ideia');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Minha ideia'), findsWidgets);

    // Dois cliques: edita o nome; três cliques: cria um tópico conectado.
    final target = find.descendant(
      of: find.byType(NodeView),
      matching: find.text('Tópico 2'),
    );
    final pos = tester.getCenter(target);
    await tester.tapAt(pos);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(pos);
    await tester.pump(const Duration(milliseconds: 60));
    final t2 = doc.nodes.values.firstWhere((n) => n.text == 'Tópico 2');
    expect(
      find.descendant(
        of: find.byType(NodeView),
        matching: find.byType(TextField),
      ),
      findsOneWidget,
    );
    final kids = t2.childrenIds.length;
    await tester.tapAt(pos);
    await tester.pumpAndSettle();
    expect(t2.childrenIds.length, kids + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Voltar à tela inicial'));
    await tester.pumpAndSettle();
    expect(find.text('Mapas recentes (1)'), findsOneWidget);

    // Abas: o mapa continua aberto; "+" abre outro mapa numa nova aba.
    await tester.tap(find.byTooltip('Novo mapa em nova aba (Ctrl+T)'));
    await tester.pumpAndSettle();
    expect(lib.docsByRecent.length, 2);
    expect(find.text('Novo mapa 2'), findsWidgets);
    expect(find.byTooltip('Fechar aba (Ctrl+W)'), findsNWidgets(2));

    // Volta para a primeira aba: o tópico criado continua lá.
    await tester.tap(find.text('Novo mapa').first);
    await tester.pumpAndSettle();
    expect(find.text('Minha ideia'), findsWidgets);

    await tester.tap(find.byTooltip('Fechar aba (Ctrl+W)').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Fechar aba (Ctrl+W)'), findsOneWidget);
    await lib.flush();
  });
}
