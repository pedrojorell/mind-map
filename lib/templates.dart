import 'layout.dart';
import 'models.dart';

class MapTemplate {
  const MapTemplate(
    this.title,
    this.description,
    this.outline, {
    this.category = 'Básico',
    this.layout = 'balanced',
    this.theme = 'pineal',
  });
  final String title;
  final String description;
  final String category;
  final String layout;
  final String theme;

  /// Primeira linha = ideia principal; demais linhas recuadas = tópicos.
  final String outline;
}

const kTemplateCategories = <String>[
  'Básico',
  'Estudos',
  'Projetos',
  'Reuniões',
  'Pessoal',
];

const kTemplates = <MapTemplate>[
  MapTemplate('Em branco', 'Só a ideia principal', 'Ideia Principal'),
  MapTemplate('Clássico', 'Ideia principal + 4 tópicos', '''
Ideia Principal
  Tópico 1
  Tópico 2
  Tópico 3
  Tópico 4'''),
  MapTemplate(
    'Lista à direita',
    'Ramos em um só lado',
    '''
Tema
  Primeiro ponto
    Detalhe
  Segundo ponto
  Terceiro ponto''',
    layout: 'right',
    theme: 'grafite',
  ),
  MapTemplate(
    'Brainstorm',
    'Gerar e avaliar ideias',
    '''
Brainstorm
  Problema
    O que queremos resolver?
    Para quem?
  Ideias
    Ideia A
    Ideia B
    Ideia C
  Prós e contras
  Próximos passos''',
    category: 'Projetos',
    theme: 'por-do-sol',
  ),
  MapTemplate(
    'Projeto',
    'Planejamento de projeto',
    '''
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
  Riscos''',
    category: 'Projetos',
    theme: 'oceano',
  ),
  MapTemplate(
    'SWOT',
    'Análise estratégica',
    '''
Análise SWOT
  Forças
  Fraquezas
  Oportunidades
  Ameaças''',
    category: 'Projetos',
    theme: 'grafite',
  ),
  MapTemplate(
    'Estudo',
    'Resumo de matéria',
    '''
Matéria
  Conceitos-chave
    Definição
    Exemplos
  Fórmulas
  Dúvidas
  Revisão
    Exercícios
    Resumo''',
    category: 'Estudos',
    theme: 'pastel',
  ),
  MapTemplate(
    'Resumo de livro',
    'Fichamento de leitura',
    '''
Título do livro
  Autor e contexto
  Personagens / ideias
    Principal
    Secundárias
  Enredo / argumento
    Início
    Meio
    Fim
  Citações marcantes
  Minha opinião''',
    category: 'Estudos',
    theme: 'floresta',
  ),
  MapTemplate(
    'Revisão para prova',
    'Organize o que estudar',
    '''
Prova
  Conteúdos
    Capítulo 1
    Capítulo 2
  Exercícios
  Pontos fracos
  Cronograma de estudo''',
    category: 'Estudos',
    layout: 'right',
  ),
  MapTemplate(
    'Ata de reunião',
    'Pauta, decisões e tarefas',
    '''
Reunião
  Participantes
  Pauta
    Item 1
    Item 2
  Decisões
  Tarefas
    Responsável
    Prazo
  Próxima reunião''',
    category: 'Reuniões',
    theme: 'mono',
  ),
  MapTemplate(
    'Planejamento semanal',
    'Dias e prioridades',
    '''
Minha semana
  Segunda
  Terça
  Quarta
  Quinta
  Sexta
  Fim de semana''',
    category: 'Reuniões',
    theme: 'oceano',
  ),
  MapTemplate(
    'Metas do ano',
    'Objetivos pessoais',
    '''
Metas do ano
  Saúde
    Exercícios
    Alimentação
  Carreira
  Finanças
  Estudos
  Lazer''',
    category: 'Pessoal',
    theme: 'por-do-sol',
  ),
  MapTemplate(
    'Viagem',
    'Roteiro e checklist',
    '''
Viagem
  Destino
  Transporte
  Hospedagem
  Roteiro
    Dia 1
    Dia 2
  Mala
  Orçamento''',
    category: 'Pessoal',
    theme: 'neon',
  ),
];

final _bullet = RegExp(r'^([-*+•]|\d+[.)])\s+');
final _heading = RegExp(r'^#+\s*');

/// Limpa marcadores de lista/títulos Markdown de uma linha.
String cleanOutlineLine(String line) =>
    line.trim().replaceFirst(_bullet, '').replaceFirst(_heading, '').trim();

/// Cria um documento a partir de um roteiro com recuo. Linhas no início com
/// o mesmo recuo da primeira viram ramos principais.
MindMapDoc docFromOutline(
  String name,
  String outline, {
  String layout = 'balanced',
  String theme = 'pineal',
}) {
  final lines = outline
      .replaceAll('\t', '    ')
      .split(RegExp(r'\r?\n'))
      .where((l) => cleanOutlineLine(l).isNotEmpty)
      .toList();
  final doc = MindMapDoc.blank(name: name, withTopics: false)..layout = layout;
  final t = themeById(theme);
  doc
    ..themeId = t.id
    ..background = t.background;
  doc.root
    ..color = t.rootFill
    ..fillColor = t.rootFill
    ..textColor = t.rootText;
  if (lines.isEmpty) return doc;
  doc.root.text = cleanOutlineLine(lines.first);
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
      text: cleanOutlineLine(raw),
      parentId: parent.id,
      color: isRootChild
          ? doc.branchColor(parent.childrenIds.length)
          : parent.color,
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

MindMapDoc docFromTemplate(String name, MapTemplate t) =>
    docFromOutline(name, t.outline, layout: t.layout, theme: t.theme);
