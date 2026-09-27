import 'layout.dart';
import 'models.dart';

class MapTemplate {
  const MapTemplate(this.title, this.description, this.outline);
  final String title;
  final String description;

  /// Primeira linha = ideia principal; demais linhas recuadas = tópicos.
  final String outline;
}

const kTemplates = <MapTemplate>[
  MapTemplate('Em branco', 'Só a ideia principal', 'Ideia Principal'),
  MapTemplate('Clássico', 'Ideia principal + 4 tópicos', '''
Ideia Principal
  Tópico 1
  Tópico 2
  Tópico 3
  Tópico 4'''),
  MapTemplate('Brainstorm', 'Gerar e avaliar ideias', '''
Brainstorm
  Problema
    O que queremos resolver?
    Para quem?
  Ideias
    Ideia A
    Ideia B
    Ideia C
  Prós e contras
  Próximos passos'''),
  MapTemplate('Projeto', 'Planejamento de projeto', '''
Projeto
  Objetivos
    Meta principal
    Indicadores de sucesso
  Escopo
    Entregas
    Fora do escopo
  Cronograma
    Fase 1
    Fase 2
    Fase 3
  Equipe
  Riscos'''),
  MapTemplate('Estudo', 'Resumo de matéria', '''
Matéria
  Conceitos-chave
    Definição
    Exemplos
  Fórmulas
  Dúvidas
  Revisão
    Exercícios
    Resumo'''),
  MapTemplate('SWOT', 'Análise estratégica', '''
Análise SWOT
  Forças
  Fraquezas
  Oportunidades
  Ameaças'''),
];

/// Cria um documento a partir de um roteiro com recuo.
MindMapDoc docFromOutline(String name, String outline) {
  final lines =
      outline.split('\n').where((l) => l.trim().isNotEmpty).toList();
  final doc = MindMapDoc.blank(name: name, withTopics: false);
  doc.root.text = lines.first.trim();
  final stack = <(int, MindMapNode)>[(-1, doc.root)];
  for (final raw in lines.skip(1)) {
    final indent = raw.length - raw.trimLeft().length;
    while (stack.length > 1 && stack.last.$1 >= indent) {
      stack.removeLast();
    }
    final parent = stack.last.$2;
    final isRootChild = parent.id == doc.rootId;
    final n = MindMapNode(
      id: newId(),
      text: raw.trim(),
      parentId: parent.id,
      color: isRootChild ? autoColor(parent.childrenIds.length) : parent.color,
      fontSize: isRootChild ? 17 : 15,
      shape: isRootChild ? 'pill' : 'underline',
    );
    doc.nodes[n.id] = n;
    parent.childrenIds.add(n.id);
    stack.add((indent, n));
  }
  autoLayout(doc, const {});
  return doc;
}
