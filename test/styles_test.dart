import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplong/editor_controller.dart';
import 'package:maplong/library.dart';
import 'package:maplong/models.dart';
import 'package:maplong/templates.dart';
import 'package:maplong/widgets/node_view.dart';
import 'package:maplong/widgets/shapes.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<EditorController> _editor() async {
  SharedPreferences.setMockInitialValues({});
  final lib = Library(prefs: await SharedPreferences.getInstance());
  await lib.load();
  final doc = docFromTemplate(
    'Teste',
    kTemplates.firstWhere((t) => t.title == 'Projeto'),
  );
  lib.add(doc);
  return EditorController(library: lib, doc: doc);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('novos estilos do tópico e do mapa sobrevivem ao salvar', () {
    final doc = MindMapDoc.blank(name: 'x')
      ..fontFamily = 'Georgia'
      ..handDrawn = true
      ..texture = 'grid'
      ..watermark = 'Rascunho'
      ..colorMode = 'level'
      ..alignLevels = true
      ..allowOverlap = true
      ..relationsOnTop = false;
    doc.root
      ..borderStyle = 'dotted'
      ..borderColor = '#FF0000'
      ..corner = 6
      ..fontFamily = 'Arial'
      ..highlight = '#FFF59D'
      ..align = 'justify'
      ..shape = 'cloud';
    final c = doc.nodes[doc.root.childrenIds.first]!
      ..lineStyle = 'tapered'
      ..lineWidth = 4;
    final back = MindMapDoc.fromJson(
      jsonDecode(jsonEncode(doc.toJson())) as Map<String, dynamic>,
    );
    final r = back.root;
    expect(r.borderStyle, 'dotted');
    expect(r.borderColor, '#FF0000');
    expect(r.corner, 6);
    expect(r.fontFamily, 'Arial');
    expect(r.highlight, '#FFF59D');
    expect(r.align, 'justify');
    expect(r.shape, 'cloud');
    expect(back.nodes[c.id]!.lineStyle, 'tapered');
    expect(back.nodes[c.id]!.lineWidth, 4);
    expect(back.fontFamily, 'Georgia');
    expect(back.handDrawn, isTrue);
    expect(back.texture, 'grid');
    expect(back.watermark, 'Rascunho');
    expect(back.colorMode, 'level');
    expect(back.alignLevels, isTrue);
    expect(back.allowOverlap, isTrue);
    expect(back.relationsOnTop, isFalse);
  });

  test('arquivos antigos com borda tracejada continuam abrindo', () {
    final n = MindMapNode.fromJson({
      'id': 'a',
      'text': 'A',
      'dashed': true,
      'color': '#FF0000',
    });
    expect(n.borderStyle, 'dashed');
    expect(n.dashed, isTrue);
    n.dashed = false;
    expect(n.borderStyle, 'solid');
  });

  test('pincel de formato copia todos os estilos novos', () async {
    final ed = await _editor();
    final ids = ed.doc.root.childrenIds;
    final a = ed.doc.nodes[ids[0]]!, b = ed.doc.nodes[ids[1]]!;
    ed.updateNode(a.id, (n) {
      n
        ..shape = 'star'
        ..borderStyle = 'dotted'
        ..fontFamily = 'Verdana'
        ..highlight = '#C5E1A5'
        ..lineStyle = 'straight';
    });
    ed.copyStyle(a.id);
    ed.pasteStyle(b.id);
    expect(b.shape, 'star');
    expect(b.borderStyle, 'dotted');
    expect(b.fontFamily, 'Verdana');
    expect(b.highlight, '#C5E1A5');
    expect(b.lineStyle, 'straight');
    ed.dispose();
  });

  test('aplicar ao mesmo nível mantém a cor de cada ramo', () async {
    final ed = await _editor();
    final ids = ed.doc.root.childrenIds;
    final first = ed.doc.nodes[ids.first]!;
    final colors = [for (final i in ids) ed.doc.nodes[i]!.color];
    ed.updateNode(first.id, (n) => n.shape = 'hexagon');
    expect(ed.applyStyleToLevel(first.id), ids.length - 1);
    for (var i = 0; i < ids.length; i++) {
      final n = ed.doc.nodes[ids[i]]!;
      expect(n.shape, 'hexagon');
      expect(n.color, colors[i]);
    }
    // Os subtópicos (outro nível) não mudam.
    final grandchild = ed.doc.nodes[first.childrenIds.first]!;
    expect(grandchild.shape, 'underline');
    ed.dispose();
  });

  test('redefinir estilo volta ao padrão do nível', () async {
    final ed = await _editor();
    final id = ed.doc.root.childrenIds.first;
    ed.updateNode(id, (n) {
      n
        ..shape = 'cloud'
        ..fontSize = 30
        ..borderStyle = 'none'
        ..fontFamily = 'Impact';
    });
    ed.resetStyle(id);
    final n = ed.doc.nodes[id]!;
    expect(n.shape, 'pill');
    expect(n.fontSize, 17);
    expect(n.borderStyle, 'solid');
    expect(n.fontFamily, isNull);
    ed.dispose();
  });

  test('caixa de texto e nota adesiva', () async {
    final ed = await _editor();
    final box = ed.doc.nodes[ed.addTextBox(const Offset(500, 500))]!;
    expect(box.shape, 'plain');
    expect(box.parentId, isNull);
    ed.cancelEditing();
    final note = ed.doc.nodes[ed.addStickyNote(const Offset(-500, 500))]!;
    expect(note.shape, 'sticky');
    expect(note.borderStyle, 'none');
    ed.dispose();
  });

  test('todas as formas geram contorno dentro do retângulo', () {
    const r = Rect.fromLTWH(10, 20, 160, 60);
    for (final s in kShapes.keys) {
      final b = shapePath(s, r, details: true).getBounds();
      expect(b.width, greaterThan(0), reason: s);
      expect(b.left, greaterThanOrEqualTo(r.left - 0.5), reason: s);
      expect(b.right, lessThanOrEqualTo(r.right + 0.5), reason: s);
      expect(b.top, greaterThanOrEqualTo(r.top - 0.5), reason: s);
      // A onda do documento passa um pouco da borda de baixo.
      expect(b.bottom, lessThanOrEqualTo(r.bottom + 8), reason: s);
      final pad = shapeInsets(s, const Size(80, 20));
      expect(pad.horizontal, greaterThan(0), reason: s);
      expect(pad.vertical, greaterThan(0), reason: s);
    }
  });

  testWidgets('cada forma e borda é desenhada sem erro', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final nodes = [
      for (final (i, s) in kShapes.keys.indexed)
        MindMapNode(
          id: 'n$i',
          text: 'Forma $s',
          color: '#7C4DFF',
          shape: s,
          borderStyle: ['solid', 'dashed', 'dotted', 'none'][i % 4],
          highlight: i.isEven ? '#FFF59D' : null,
          fontFamily: kFonts[i % kFonts.length],
        ),
    ];
    for (final hand in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final n in nodes)
                    NodeView(
                      node: n,
                      selected: n.id == 'n3',
                      editing: false,
                      selectAllOnEdit: false,
                      dropTarget: false,
                      isRoot: false,
                      handDrawn: hand,
                      fontFamily: n.fontFamily,
                      onCommit: (_) {},
                      onCancel: () {},
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // O texto cabe dentro do losango e do círculo (forma cresce com ele).
      final diamond = tester.getSize(
        find.ancestor(
          of: find.text('Forma diamond'),
          matching: find.byType(NodeView),
        ),
      );
      final text = tester.getSize(find.text('Forma diamond'));
      expect(diamond.width, greaterThanOrEqualTo(text.width * 2));
    }
  });
}
