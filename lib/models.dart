import 'dart:math';
import 'dart:ui';

/// Paleta padrão usada para ramos e preenchimentos.
const kPalette = <String>[
  '#FF5252', // vermelho
  '#FFB300', // âmbar
  '#00C853', // verde
  '#2979FF', // azul
  '#7C4DFF', // roxo
  '#00B8D4', // ciano
  '#FF4081', // rosa
  '#8D6E63', // marrom
];

const kFillPalette = <String>[
  '', // automático
  '#1F2333',
  '#FFFFFF',
  ...kPalette,
];

const kShapes = <String, String>{
  'pill': 'Pílula',
  'rounded': 'Arredondado',
  'rect': 'Retângulo',
  'ellipse': 'Elipse',
  'underline': 'Sublinhado',
};

const kConnectorStyles = <String, String>{
  'curved': 'Curvo',
  'straight': 'Reto',
  'elbow': 'Cotovelo',
};

final _rand = Random();

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 30).toRadixString(36)}';

String autoColor(int i) => kPalette[i % kPalette.length];

Color? parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceAll('#', '').trim();
  if (h.isEmpty) return null;
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

class NodeAttachment {
  NodeAttachment({required this.name, required this.path});

  final String name;
  final String path;

  Map<String, dynamic> toJson() => {'name': name, 'path': path};

  static NodeAttachment fromJson(Map<String, dynamic> j) => NodeAttachment(
        name: (j['name'] as String?) ?? 'arquivo',
        path: (j['path'] as String?) ?? '',
      );
}

class MindMapNode {
  MindMapNode({
    required this.id,
    required this.text,
    this.note = '',
    this.parentId,
    List<String>? childrenIds,
    this.pos = Offset.zero,
    required this.color,
    this.fillColor,
    this.textColor,
    this.shape = 'pill',
    this.fontSize = 16,
    this.bold = false,
    this.italic = false,
    this.borderWidth = 1.5,
    this.dashed = false,
    this.collapsed = false,
    this.link,
    List<NodeAttachment>? attachments,
  })  : childrenIds = childrenIds ?? [],
        attachments = attachments ?? [];

  String id;
  String text;
  String note;
  String? parentId;
  List<String> childrenIds;

  /// Centro do nó em coordenadas da cena.
  Offset pos;

  /// Cor do ramo/borda.
  String color;
  String? fillColor;
  String? textColor;
  String shape;
  double fontSize;
  bool bold;
  bool italic;
  double borderWidth;
  bool dashed;
  bool collapsed;
  String? link;
  List<NodeAttachment> attachments;

  bool get hasLink => link != null && link!.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'note': note,
        'parentId': parentId,
        'childrenIds': childrenIds,
        'pos': {'dx': pos.dx, 'dy': pos.dy},
        'color': color,
        'fillColor': fillColor,
        'textColor': textColor,
        'shape': shape,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'borderWidth': borderWidth,
        'dashed': dashed,
        'collapsed': collapsed,
        'link': link,
        'attachments': attachments.map((e) => e.toJson()).toList(),
      };

  static MindMapNode fromJson(Map<String, dynamic> j) {
    final p = j['pos'];
    var pos = Offset.zero;
    if (p is Map) {
      pos = Offset(
        ((p['dx'] as num?) ?? 0).toDouble(),
        ((p['dy'] as num?) ?? 0).toDouble(),
      );
    }
    String? nonEmpty(Object? v) =>
        (v is String && v.trim().isNotEmpty) ? v : null;
    var shape = (j['shape'] as String?) ?? 'pill';
    // Compatibilidade com o formato antigo.
    if (shape == 'label') shape = 'underline';
    if (shape == 'circle') shape = 'ellipse';
    if (!kShapes.containsKey(shape)) shape = 'pill';
    return MindMapNode(
      id: j['id'] as String,
      text: (j['text'] as String?) ?? '',
      note: (j['note'] as String?) ?? '',
      parentId: j['parentId'] as String?,
      childrenIds:
          ((j['childrenIds'] as List<dynamic>?) ?? []).cast<String>().toList(),
      pos: pos,
      color: nonEmpty(j['color']) ?? nonEmpty(j['branchColor']) ?? '#7C4DFF',
      fillColor: nonEmpty(j['fillColor']),
      textColor: nonEmpty(j['textColor']),
      shape: shape,
      fontSize: ((j['fontSize'] as num?) ?? 16).toDouble(),
      bold: (j['bold'] as bool?) ?? false,
      italic: (j['italic'] as bool?) ?? false,
      borderWidth: ((j['borderWidth'] as num?) ?? 1.5).toDouble(),
      dashed: (j['dashed'] as bool?) ?? (j['borderStyle'] == 'dashed'),
      collapsed: (j['collapsed'] as bool?) ?? false,
      link: nonEmpty(j['link']),
      attachments: ((j['attachments'] as List<dynamic>?) ?? [])
          .map((e) => NodeAttachment.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class MindMapDoc {
  MindMapDoc({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.rootId,
    required this.nodes,
    this.connectorStyle = 'curved',
    this.connectorWidth = 2.5,
    this.autoLayout = true,
    this.filePath,
  });

  static const formatVersion = 2;

  String id;
  String name;
  int createdAt;
  int updatedAt;
  String rootId;
  Map<String, MindMapNode> nodes;
  String connectorStyle;
  double connectorWidth;

  /// Reorganiza o mapa automaticamente após mudanças na estrutura.
  bool autoLayout;

  /// Caminho do arquivo .pmap no disco (apenas desktop), se foi salvo/aberto.
  String? filePath;

  MindMapNode get root => nodes[rootId]!;

  void touch() => updatedAt = DateTime.now().millisecondsSinceEpoch;

  /// Retorna true se [id] for [ancestorId] ou descendente dele.
  bool isInSubtree(String id, String ancestorId) {
    String? cur = id;
    while (cur != null) {
      if (cur == ancestorId) return true;
      cur = nodes[cur]?.parentId;
    }
    return false;
  }

  /// Nós visíveis (ignora descendentes de nós recolhidos).
  Iterable<MindMapNode> visibleNodes() sync* {
    final hidden = <String>{};
    void hide(String id) {
      for (final c in nodes[id]?.childrenIds ?? const <String>[]) {
        hidden.add(c);
        hide(c);
      }
    }

    for (final n in nodes.values) {
      if (n.collapsed) hide(n.id);
    }
    for (final n in nodes.values) {
      if (!hidden.contains(n.id)) yield n;
    }
  }

  List<String> subtreeIds(String id) {
    final out = <String>[];
    void walk(String i) {
      out.add(i);
      for (final c in nodes[i]?.childrenIds ?? const <String>[]) {
        walk(c);
      }
    }

    walk(id);
    return out;
  }

  int depthOf(String id) {
    var d = 0;
    var cur = nodes[id]?.parentId;
    while (cur != null) {
      d++;
      cur = nodes[cur]?.parentId;
    }
    return d;
  }

  static MindMapDoc blank({required String name, bool withTopics = true}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final root = MindMapNode(
      id: newId(),
      text: 'Ideia Principal',
      color: '#7C4DFF',
      fillColor: '#7C4DFF',
      textColor: '#FFFFFF',
      fontSize: 22,
      bold: true,
      shape: 'rounded',
      borderWidth: 2,
    );
    final doc = MindMapDoc(
      id: newId(),
      name: name,
      createdAt: now,
      updatedAt: now,
      rootId: root.id,
      nodes: {root.id: root},
    );
    if (withTopics) {
      for (var i = 0; i < 4; i++) {
        final c = MindMapNode(
          id: newId(),
          text: 'Tópico ${i + 1}',
          parentId: root.id,
          color: autoColor(i),
        );
        doc.nodes[c.id] = c;
        root.childrenIds.add(c.id);
      }
    }
    return doc;
  }

  Map<String, dynamic> toJson() => {
        'format': 'pinealmap',
        'version': formatVersion,
        'id': id,
        'name': name,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'rootId': rootId,
        'connectorStyle': connectorStyle,
        'connectorWidth': connectorWidth,
        'autoLayout': autoLayout,
        'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
        if (filePath != null) 'filePath': filePath,
      };

  static MindMapDoc fromJson(Map<String, dynamic> j) {
    final rawNodes = Map<String, dynamic>.from(j['nodes'] as Map);
    final nodes = <String, MindMapNode>{};
    rawNodes.forEach((k, v) {
      final n = MindMapNode.fromJson(Map<String, dynamic>.from(v as Map));
      nodes[n.id] = n;
    });
    final rootId = j['rootId'] as String;
    if (!nodes.containsKey(rootId)) {
      throw const FormatException('Arquivo sem nó raiz.');
    }
    // Saneia referências quebradas.
    for (final n in nodes.values) {
      n.childrenIds.removeWhere((c) => !nodes.containsKey(c));
      if (n.parentId != null && !nodes.containsKey(n.parentId)) {
        n.parentId = null;
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    var style = (j['connectorStyle'] as String?) ?? 'curved';
    if (!kConnectorStyles.containsKey(style)) style = 'curved';
    return MindMapDoc(
      id: (j['id'] as String?) ?? newId(),
      name: (j['name'] as String?) ?? 'Mapa sem nome',
      createdAt: ((j['createdAt'] as num?) ?? now).toInt(),
      updatedAt: ((j['updatedAt'] as num?) ?? now).toInt(),
      rootId: rootId,
      nodes: nodes,
      connectorStyle: style,
      connectorWidth: ((j['connectorWidth'] as num?) ?? 2.5).toDouble(),
      autoLayout: (j['autoLayout'] as bool?) ?? false,
      filePath: j['filePath'] as String?,
    );
  }

  MindMapDoc clone() => fromJson(toJson());
}
