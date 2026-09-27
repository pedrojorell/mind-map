import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinealmap/editor_controller.dart';
import 'package:pinealmap/file_actions.dart';
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
      final doc = docFromOutline('Teste', kTemplates[3].outline);
      doc.nodes.values.first.note = 'nota';
      final back = MindMapDoc.fromJson(
          jsonDecode(utf8.decode(encodeDoc(doc))) as Map<String, dynamic>);
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

    test('migra dados da versão antiga', () async {
      final old = MindMapDoc.blank(name: 'Velho');
      final lib = await newLibrary({
        'pinealmap.docs.v1': jsonEncode([old.toJson()]),
      });
      expect(lib.doc(old.id)!.name, 'Velho');
    });
  });

  testWidgets('fluxo: criar mapa, adicionar tópico pelo teclado e voltar',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final lib = await newLibrary();
    await tester.pumpWidget(PinealMapApp(library: lib));
    await tester.pumpAndSettle();

    expect(find.text('Criar novo mapa'), findsOneWidget);
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
        of: find.byType(NodeView), matching: find.byType(TextField));
    expect(inline, findsOneWidget);
    await tester.enterText(inline, 'Minha ideia');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Minha ideia'), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Meus mapas (1)'), findsOneWidget);
    await lib.flush();
  });
}
