import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplong/editor_controller.dart';
import 'package:maplong/layout.dart';
import 'package:maplong/library.dart';
import 'package:maplong/models.dart';
import 'package:maplong/templates.dart';
import 'package:maplong/widgets/markers.dart';
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

  test('ramo colorido: uma cor, por nível e arco-íris', () async {
    final ed = await _editor();
    final pal = ed.doc.theme.palette;
    final mains = [for (final i in ed.doc.root.childrenIds) ed.doc.nodes[i]!];
    final sub = ed.doc.nodes[mains.first.childrenIds.first]!;

    ed.setColorMode('single');
    expect(mains.every((n) => n.color == pal.first), isTrue);

    ed.setColorMode('level');
    expect(mains.every((n) => n.color == pal[0]), isTrue);
    expect(sub.color, pal[1]);

    ed.setColorMode('rainbow');
    expect(mains[1].fillColor, mains[1].color);
    expect(mains[1].textColor, '#FFFFFF');

    ed.setColorMode('branch');
    expect(mains[1].color, pal[1]);
    expect(mains[1].fillColor, isNull);
    ed.dispose();
  });

  test('alinhar tópicos do mesmo nível forma colunas', () async {
    final ed = await _editor();
    final doc = ed.doc..layout = 'right';
    ed.setAlignLevels(true);
    final level2 = [
      for (final m in doc.root.childrenIds)
        for (final c in doc.nodes[m]!.childrenIds) doc.nodes[c]!,
    ];
    double left(MindMapNode n) => n.pos.dx - estimateNodeSize(n).width / 2;
    final lefts = level2.map(left).toSet();
    expect(lefts.length, 1, reason: 'todos começam na mesma coluna');
    ed.dispose();
  });

  test('sobreposição permitida não afasta tópicos', () async {
    final ed = await _editor();
    ed.setAllowOverlap(true);
    final a = ed.doc.nodes[ed.doc.root.childrenIds.first]!;
    final p = a.pos;
    final f = ed.addFloating(p, edit: false);
    ed.arrangeNow();
    expect(ed.doc.nodes[f]!.pos, p, reason: 'o flutuante não foi afastado');
    ed.dispose();
  });

  test('tema personalizado é salvo e aplicado', () async {
    final ed = await _editor();
    ed
      ..setMapFont('Georgia')
      ..setHandDrawn(true)
      ..setBackground('#FFF8F0');
    await ed.library.saveTheme(ed.themeSnapshot('Meu estilo'));
    expect(ed.library.savedThemes.single.name, 'Meu estilo');

    final again = Library(prefs: await SharedPreferences.getInstance());
    await again.load();
    final saved = again.savedThemes.single;
    expect(saved.font, 'Georgia');
    expect(saved.handDrawn, isTrue);

    ed
      ..setMapFont(null)
      ..setHandDrawn(false)
      ..applySavedTheme(saved);
    expect(ed.doc.fontFamily, 'Georgia');
    expect(ed.doc.handDrawn, isTrue);
    expect(ed.doc.background, '#FFF8F0');
    expect(ed.doc.themeId, 'custom');
    await again.deleteTheme('Meu estilo');
    expect(again.savedThemes, isEmpty);
    ed.dispose();
  });

  test('relação em linha reta e opções da relação', () async {
    final ed = await _editor();
    final ids = ed.doc.root.childrenIds;
    ed.startRelation(ids[0], 'straight');
    expect(ed.completeRelation(ids[1]), isTrue);
    final r = ed.doc.relations.single;
    expect(r.straight, isTrue);
    ed.updateRelation(r.id, (r) {
      r
        ..dashed = false
        ..arrowStart = true;
    });
    final back = NodeRelation.fromJson(
      jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>,
    );
    expect(back.straight, isTrue);
    expect(back.dashed, isFalse);
    expect(back.arrowStart, isTrue);
    expect(back.arrowEnd, isTrue);
    ed.dispose();
  });

  test('linha de conexão liga um tópico flutuante a outro tópico', () async {
    final ed = await _editor();
    final target = ed.doc.root.childrenIds.first;
    final f = ed.addFloating(const Offset(900, 900), edit: false);
    ed.startConnection(f);
    expect(ed.linkingMode, 'connect');
    expect(ed.completeRelation(target), isTrue);
    expect(ed.doc.nodes[f]!.parentId, target);
    expect(ed.doc.nodes[target]!.childrenIds, contains(f));
    expect(ed.doc.relations, isEmpty);
    expect(ed.linkingMode, 'relation');
    ed.dispose();
  });

  test('marcadores usados recentemente são lembrados', () async {
    final ed = await _editor();
    final id = ed.doc.root.childrenIds.first;
    ed
      ..toggleMarker('priority', '12', id)
      ..toggleMarker('arrow', 'up', id)
      ..toggleMarker('face', 'party', id);
    expect(ed.library.recentMarkers.take(3), [
      'face:party',
      'arrow:up',
      'priority:12',
    ]);
    final again = Library(prefs: await SharedPreferences.getInstance());
    await again.load();
    expect(again.recentMarkers.first, 'face:party');
    ed.dispose();
  });

  testWidgets('todos os marcadores são desenhados', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Wrap(
              children: [
                for (final g in kMarkerGroups)
                  for (final v in g.values) MarkerIcon(g.id, v, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      find.byType(MarkerIcon),
      findsNWidgets(kMarkerGroups.fold(0, (s, g) => s + g.values.length)),
    );
    for (final g in kMarkerGroups) {
      for (final v in g.values) {
        expect(markerLabel(g.id, v), isNotEmpty);
      }
    }
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
