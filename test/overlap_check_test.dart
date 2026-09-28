import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:maplong/layout.dart';
import 'package:maplong/models.dart';
import 'package:maplong/templates.dart';

void main() {
  test('nenhuma estrutura sobrepõe tópicos', () {
    const outline = '''
Planejamento anual
  Marketing e comunicação
    Redes sociais
      Instagram
      LinkedIn
    E-mail
  Produto
    Pesquisa com clientes
    Protótipo
    Lançamento da versão 2
  Finanças
    Orçamento
    Investimentos
      Curto prazo
      Longo prazo
  Pessoas
  Operações
    Fornecedores
    Logística''';
    for (final layout in kLayouts.keys) {
      final doc = docFromOutline('x', outline, layout: layout);
      autoLayout(doc, const {});
      final bad = <String>[];
      final nodes = doc.nodes.values.toList();
      Rect r(MindMapNode n) {
        final s = estimateNodeSize(n);
        return Rect.fromCenter(center: n.pos, width: s.width, height: s.height);
      }

      for (var i = 0; i < nodes.length; i++) {
        for (var j = i + 1; j < nodes.length; j++) {
          if (r(nodes[i]).deflate(1).overlaps(r(nodes[j]).deflate(1))) {
            bad.add('${nodes[i].text} x ${nodes[j].text}');
          }
        }
      }
      expect(bad, isEmpty, reason: 'estrutura $layout');
    }
  });
}
