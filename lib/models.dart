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
  'hexagon': 'Hexágono',
  'underline': 'Sublinhado',
  'plain': 'Só texto',
};

const kConnectorStyles = <String, String>{
  'curved': 'Curvo',
  'straight': 'Reto',
  'elbow': 'Cotovelo',
};

const kLayouts = <String, String>{
  'balanced': 'Mapa balanceado',
  'right': 'Mapa à direita',
  'left': 'Mapa à esquerda',
  'logic': 'Mapa lógico',
  'org': 'Organograma',
  'tree': 'Árvore',
  'timeline': 'Linha do tempo',
  'fishbone': 'Espinha de peixe',
};

/// Alinhamento do texto dentro do tópico.
const kAligns = <String, String>{
  'left': 'Esquerda',
  'center': 'Centro',
  'right': 'Direita',
};

/// Comentário deixado num tópico.
class NodeComment {
  NodeComment({
    required this.id,
    required this.text,
    this.author = '',
    required this.at,
  });

  final String id;
  String text;
  String author;
  int at;

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'author': author,
    'at': at,
  };

  static NodeComment fromJson(Map<String, dynamic> j) => NodeComment(
    id: (j['id'] as String?) ?? newId(),
    text: (j['text'] as String?) ?? '',
    author: (j['author'] as String?) ?? '',
    at: ((j['at'] as num?) ?? 0).toInt(),
  );
}

/// Informações de tarefa (usadas na visão Gantt).
class NodeTask {
  NodeTask({
    this.start,
    this.end,
    this.progress = 0,
    this.assignee = '',
    this.duration,
  });

  /// Datas em milissegundos desde a época (dia inteiro).
  int? start;
  int? end;

  /// 0 a 100.
  int progress;
  String assignee;

  /// Esforço estimado em horas (opcional).
  double? duration;

  bool get done => progress >= 100;

  Map<String, dynamic> toJson() => {
    if (start != null) 'start': start,
    if (end != null) 'end': end,
    'progress': progress,
    if (assignee.isNotEmpty) 'assignee': assignee,
    if (duration != null) 'duration': duration,
  };

  static NodeTask? fromJson(Object? j) {
    if (j is! Map) return null;
    return NodeTask(
      start: (j['start'] as num?)?.toInt(),
      end: (j['end'] as num?)?.toInt(),
      progress: ((j['progress'] as num?) ?? 0).toInt().clamp(0, 100),
      assignee: (j['assignee'] as String?) ?? '',
      duration: (j['duration'] as num?)?.toDouble(),
    );
  }
}

/// Tema de cores de um mapa: paleta dos ramos e estilo da ideia principal.
class MapTheme {
  const MapTheme(
    this.id,
    this.name,
    this.palette, {
    required this.rootFill,
    this.rootText = '#FFFFFF',
    this.background,
  });

  final String id;
  final String name;
  final List<String> palette;
  final String rootFill;
  final String rootText;

  /// Cor de fundo sugerida (nulo = segue o tema claro/escuro do app).
  final String? background;
}

const kThemes = <MapTheme>[
  MapTheme('pineal', 'MapLong', kPalette, rootFill: '#3B4CF5'),
  MapTheme('grafite', 'Grafite', [
    '#5B8DEF',
    '#7AC7A8',
    '#F2A65A',
    '#E86A92',
    '#9C88FF',
    '#4FC1E9',
  ], rootFill: '#1F2333'),
  MapTheme(
    'oceano',
    'Oceano',
    ['#0077B6', '#00B4D8', '#0096C7', '#48CAE4', '#023E8A', '#5FA8D3'],
    rootFill: '#03045E',
    background: '#F1FAFD',
  ),
  MapTheme(
    'floresta',
    'Floresta',
    ['#2D6A4F', '#40916C', '#52B788', '#74A57F', '#1B4332', '#6A994E'],
    rootFill: '#1B4332',
    background: '#F3F8F2',
  ),
  MapTheme(
    'por-do-sol',
    'Pôr do sol',
    ['#F94144', '#F3722C', '#F8961E', '#E9C46A', '#F9844A', '#E76F51'],
    rootFill: '#9D0208',
    background: '#FFF8F0',
  ),
  MapTheme(
    'pastel',
    'Pastel',
    ['#9B87F5', '#F28DA2', '#5FBFA6', '#F2B05E', '#6FA3EF', '#B38CC9'],
    rootFill: '#5E548E',
    background: '#FCFAFF',
  ),
  MapTheme(
    'mono',
    'Monocromático',
    ['#343A40', '#495057', '#6C757D', '#868E96', '#212529', '#5C636A'],
    rootFill: '#212529',
    background: '#FFFFFF',
  ),
  MapTheme(
    'neon',
    'Neon',
    ['#FF2E88', '#00F5D4', '#FEE440', '#9B5DE5', '#00BBF9', '#F15BB5'],
    rootFill: '#9B5DE5',
    background: '#14111F',
  ),
];

MapTheme themeById(String? id) =>
    kThemes.firstWhere((t) => t.id == id, orElse: () => kThemes.first);

/// Grupo de marcadores (ícones). Cada tópico tem no máximo um por grupo.
class MarkerGroup {
  const MarkerGroup(this.id, this.name, this.values);
  final String id;
  final String name;
  final List<String> values;
}

const kMarkerColors = <String>[
  '#F44336',
  '#FF9800',
  '#FFC107',
  '#4CAF50',
  '#2196F3',
  '#673AB7',
  '#9E9E9E',
];

const kMarkerGroups = <MarkerGroup>[
  MarkerGroup('priority', 'Prioridade', [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  ]),
  MarkerGroup('progress', 'Progresso', [
    '0',
    '12',
    '25',
    '37',
    '50',
    '62',
    '75',
    '87',
    '100',
  ]),
  MarkerGroup('flag', 'Bandeira', kMarkerColors),
  MarkerGroup('star', 'Estrela', kMarkerColors),
  MarkerGroup('face', 'Humor', [
    'happy',
    'calm',
    'neutral',
    'sad',
    'angry',
    'love',
  ]),
  MarkerGroup('symbol', 'Símbolo', [
    'check',
    'cross',
    'question',
    'warning',
    'idea',
    'info',
    'time',
    'money',
  ]),
  MarkerGroup('day', 'Dia da semana', [
    'seg',
    'ter',
    'qua',
    'qui',
    'sex',
    'sáb',
    'dom',
  ]),
];

/// Adesivos (emojis grandes exibidos acima do texto), por categoria.
const kStickers = <String, List<String>>{
  'Escritório': [
    '💼',
    '📎',
    '📌',
    '📊',
    '📈',
    '🗂️',
    '🖊️',
    '📅',
    '💡',
    '🖥️',
    '📝',
    '📦',
    '🏢',
    '💰',
    '🔒',
    '📣',
  ],
  'Estudos': [
    '📚',
    '🎓',
    '✏️',
    '📐',
    '🔬',
    '🧪',
    '🧠',
    '🌍',
    '🧮',
    '📖',
    '🎒',
    '🏫',
    '📏',
    '🔭',
    '🗒️',
    '🧾',
  ],
  'Viagem': [
    '✈️',
    '🧳',
    '🗺️',
    '🏖️',
    '🏔️',
    '🚗',
    '🚆',
    '🏨',
    '📷',
    '🧭',
    '⛺',
    '🚢',
    '🎫',
    '🌅',
    '🗽',
    '🏝️',
  ],
  'Festas': [
    '🎉',
    '🎂',
    '🎁',
    '🎄',
    '🎃',
    '🎆',
    '🥂',
    '🎈',
    '🕯️',
    '❄️',
    '⛄',
    '🦃',
    '🐣',
    '💝',
    '🎊',
    '🔔',
  ],
  'Comida': [
    '🍎',
    '🍕',
    '🍔',
    '🥗',
    '☕',
    '🍰',
    '🍣',
    '🥑',
    '🍇',
    '🥖',
    '🍫',
    '🍓',
    '🧀',
    '🍜',
    '🥕',
    '🍉',
  ],
  'Natureza': [
    '🌱',
    '🌳',
    '🌸',
    '🌻',
    '🍀',
    '🌊',
    '☀️',
    '🌙',
    '⭐',
    '🌈',
    '🔥',
    '💧',
    '🍁',
    '⚡',
    '☁️',
    '🌵',
  ],
  'Tecnologia': [
    '💻',
    '📱',
    '⌨️',
    '🖱️',
    '🤖',
    '🛰️',
    '🔋',
    '💾',
    '🧩',
    '⚙️',
    '🔌',
    '📡',
    '🕹️',
    '🧬',
    '🔧',
    '🚀',
  ],
  'Esporte': [
    '⚽',
    '🏀',
    '🏐',
    '🎾',
    '🏊',
    '🚴',
    '🏃',
    '🏋️',
    '🥇',
    '🏆',
    '⛳',
    '🥊',
    '🛹',
    '🏓',
    '🎯',
    '🧗',
  ],
  'Pessoas': [
    '😀',
    '😎',
    '🤔',
    '😍',
    '😴',
    '🥳',
    '🙌',
    '👍',
    '👎',
    '👏',
    '🤝',
    '💪',
    '👀',
    '❤️',
    '🧑‍💻',
    '👪',
  ],
  'Negócios': [
    '🤝',
    '📑',
    '🧾',
    '💳',
    '🏦',
    '📉',
    '🗃️',
    '🖨️',
    '📧',
    '📞',
    '🧮',
    '🏷️',
    '🎯',
    '🪙',
    '📋',
    '🔑',
  ],
  'Saúde': [
    '💊',
    '🩺',
    '🏥',
    '🦷',
    '🧘',
    '🥦',
    '💤',
    '🚰',
    '🩹',
    '🧠',
    '🫀',
    '🧴',
    '😷',
    '🌡️',
    '🍏',
    '🚶',
  ],
  'Casa': [
    '🏠',
    '🛋️',
    '🛏️',
    '🍳',
    '🧹',
    '🧺',
    '🪴',
    '🚪',
    '🧸',
    '🛁',
    '🧯',
    '🔨',
    '🪑',
    '📺',
    '🧼',
    '🔌',
  ],
  'Música e arte': [
    '🎵',
    '🎸',
    '🎹',
    '🥁',
    '🎤',
    '🎧',
    '🎨',
    '🖌️',
    '🎬',
    '📸',
    '🎭',
    '🎻',
    '🎷',
    '📀',
    '🖼️',
    '✂️',
  ],
  'Transporte': [
    '🚕',
    '🚌',
    '🚲',
    '🛵',
    '🚁',
    '⛵',
    '🚉',
    '🛫',
    '🚦',
    '⛽',
    '🚚',
    '🛴',
    '🚜',
    '🚑',
    '🚒',
    '🚓',
  ],
  'Clima': [
    '🌤️',
    '⛅',
    '🌧️',
    '⛈️',
    '🌩️',
    '🌪️',
    '🌫️',
    '☔',
    '☄️',
    '🌬️',
    '🌥️',
    '🌦️',
    '🌨️',
    '🌡️',
    '🌞',
    '🌝',
  ],
  'Símbolos': [
    '✅',
    '❌',
    '⚠️',
    '❓',
    '❗',
    '💯',
    '🔔',
    '📍',
    '🔗',
    '♻️',
    '⏰',
    '⏳',
    '🆕',
    '🔝',
    '🆗',
    '➕',
  ],
  'Bandeiras': [
    '🇧🇷',
    '🇵🇹',
    '🇺🇸',
    '🇪🇸',
    '🇫🇷',
    '🇩🇪',
    '🇮🇹',
    '🇯🇵',
    '🇨🇳',
    '🇬🇧',
    '🇦🇷',
    '🇲🇽',
    '🇨🇦',
    '🏁',
    '🏳️',
    '🏴',
  ],
  'Animais': [
    '🐶',
    '🐱',
    '🦊',
    '🐼',
    '🦁',
    '🐸',
    '🐧',
    '🦉',
    '🐝',
    '🦋',
    '🐢',
    '🐬',
    '🐙',
    '🦄',
    '🐞',
    '🐘',
  ],
};

final _rand = Random();

String newId() =>
    '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${_rand.nextInt(1 << 30).toRadixString(36)}';

String autoColor(int i, [List<String> palette = kPalette]) =>
    palette[i % palette.length];

Color? parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.replaceAll('#', '').trim();
  if (h.isEmpty) return null;
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(v);
}

/// Documento anexado a um tópico. No desktop guarda o caminho do arquivo;
/// arquivos pequenos (ou no navegador) podem ser embutidos em [data].
class NodeAttachment {
  NodeAttachment({required this.name, this.path = '', this.data, this.size});

  final String name;
  final String path;

  /// Conteúdo em base64 quando o arquivo está embutido no mapa.
  final String? data;

  /// Tamanho em bytes (se conhecido).
  final int? size;

  bool get embedded => data != null && data!.isNotEmpty;

  String get extension {
    final i = name.lastIndexOf('.');
    return i < 0 ? '' : name.substring(i + 1).toLowerCase();
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    if (data != null) 'data': data,
    if (size != null) 'size': size,
  };

  static NodeAttachment fromJson(Map<String, dynamic> j) => NodeAttachment(
    name: (j['name'] as String?) ?? 'arquivo',
    path: (j['path'] as String?) ?? '',
    data: j['data'] as String?,
    size: (j['size'] as num?)?.toInt(),
  );
}

/// Link de um tópico: site, e-mail, telefone ou caminho de arquivo.
class NodeLink {
  NodeLink({required this.url, this.title = ''});

  String url;
  String title;

  static final _scheme = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:');
  static final _drive = RegExp(r'^[a-zA-Z]:[\\/]');
  static final _email = RegExp(r'^[^\s@/]+@[^\s@/]+\.[^\s@/]+$');
  static final _phone = RegExp(r'^\+?[\d\s().-]{6,}$');

  /// Tipo deduzido do endereço: web, email, phone ou file.
  String get kind {
    final u = url.trim().toLowerCase();
    if (u.startsWith('mailto:') || _email.hasMatch(u)) return 'email';
    if (u.startsWith('tel:') || _phone.hasMatch(u)) return 'phone';
    if (u.startsWith('file:') || _drive.hasMatch(u) || u.startsWith('/')) {
      return 'file';
    }
    return 'web';
  }

  /// Endereço pronto para abrir (acrescenta https://, mailto: ou tel:).
  String get resolved {
    final u = url.trim();
    if (_scheme.hasMatch(u) && !_drive.hasMatch(u)) return u;
    switch (kind) {
      case 'email':
        return 'mailto:$u';
      case 'phone':
        return 'tel:${u.replaceAll(RegExp(r'[\s().-]'), '')}';
      case 'file':
        return Uri.file(u).toString();
      default:
        return 'https://$u';
    }
  }

  /// Texto curto para exibir.
  String get label {
    if (title.trim().isNotEmpty) return title.trim();
    return url
        .trim()
        .replaceFirst(RegExp(r'^(https?://|mailto:|tel:)'), '')
        .replaceFirst(RegExp(r'^www\.'), '');
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    if (title.isNotEmpty) 'title': title,
  };

  static NodeLink fromJson(Map<String, dynamic> j) => NodeLink(
    url: (j['url'] as String?) ?? '',
    title: (j['title'] as String?) ?? '',
  );
}

/// Imagem exibida num tópico (bytes em base64, já reduzida).
class NodeImage {
  NodeImage({required this.data, this.name = '', this.width = 180});

  final String data;
  final String name;

  /// Largura de exibição no mapa.
  double width;

  Map<String, dynamic> toJson() => {'data': data, 'name': name, 'width': width};

  static NodeImage? fromJson(Object? j) {
    if (j is! Map) return null;
    final data = j['data'];
    if (data is! String || data.isEmpty) return null;
    return NodeImage(
      data: data,
      name: (j['name'] as String?) ?? '',
      width: ((j['width'] as num?) ?? 180).toDouble(),
    );
  }
}

/// Relação (seta) entre dois tópicos quaisquer do mapa.
class NodeRelation {
  NodeRelation({
    required this.id,
    required this.from,
    required this.to,
    this.label = '',
    this.color = '#8E7CC3',
  });

  final String id;
  String from;
  String to;
  String label;
  String color;

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'label': label,
    'color': color,
  };

  static NodeRelation fromJson(Map<String, dynamic> j) => NodeRelation(
    id: (j['id'] as String?) ?? newId(),
    from: j['from'] as String,
    to: j['to'] as String,
    label: (j['label'] as String?) ?? '',
    color: (j['color'] as String?) ?? '#8E7CC3',
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
    List<NodeLink>? links,
    List<NodeAttachment>? attachments,
    List<String>? markers,
    List<String>? tags,
    this.sticker,
    this.image,
    this.underline = false,
    this.strike = false,
    this.align = 'center',
    this.maxWidth = 300,
    List<String>? callouts,
    List<NodeComment>? comments,
    this.table,
    this.formula,
    this.task,
    this.boundary = false,
    this.boundaryLabel = '',
    this.summary,
  }) : childrenIds = childrenIds ?? [],
       links = links ?? [],
       attachments = attachments ?? [],
       markers = markers ?? [],
       tags = tags ?? [],
       callouts = callouts ?? [],
       comments = comments ?? [];

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
  List<NodeLink> links;
  List<NodeAttachment> attachments;

  /// Etiquetas curtas exibidas abaixo do texto.
  List<String> tags;

  /// Imagem exibida acima do texto.
  NodeImage? image;

  bool underline;
  bool strike;

  /// Alinhamento do texto (ver [kAligns]).
  String align;

  /// Largura máxima do texto antes de quebrar a linha.
  double maxWidth;

  /// Balões de texto presos ao tópico.
  List<String> callouts;

  List<NodeComment> comments;

  /// Tabela exibida no tópico (linhas x colunas).
  List<List<String>>? table;

  /// Fórmula em LaTeX exibida no tópico.
  String? formula;

  /// Dados de tarefa (datas, responsável e progresso).
  NodeTask? task;

  /// Contorno em volta do tópico e de todos os seus subtópicos.
  bool boundary;
  String boundaryLabel;

  /// Texto de resumo mostrado ao lado de todos os subtópicos (chave).
  String? summary;

  /// Marcadores no formato `grupo:valor` (ex.: `priority:1`, `flag:#F44336`).
  List<String> markers;

  /// Adesivo (emoji) exibido acima do texto.
  String? sticker;

  bool get hasLink => links.any((l) => l.url.trim().isNotEmpty);

  /// Valor do marcador do grupo [group], se houver.
  String? marker(String group) {
    for (final m in markers) {
      if (m.startsWith('$group:')) return m.substring(group.length + 1);
    }
    return null;
  }

  /// Define (ou remove, se [value] for nulo) o marcador de um grupo,
  /// mantendo a ordem dos grupos em [kMarkerGroups].
  void setMarker(String group, String? value) {
    markers.removeWhere((m) => m.startsWith('$group:'));
    if (value != null) markers.add('$group:$value');
    int order(String m) =>
        kMarkerGroups.indexWhere((g) => m.startsWith('${g.id}:'));
    markers.sort((a, b) => order(a).compareTo(order(b)));
  }

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
    if (links.isNotEmpty) 'links': links.map((e) => e.toJson()).toList(),
    'attachments': attachments.map((e) => e.toJson()).toList(),
    if (markers.isNotEmpty) 'markers': markers,
    if (tags.isNotEmpty) 'tags': tags,
    if (image != null) 'image': image!.toJson(),
    if (underline) 'underline': true,
    if (strike) 'strike': true,
    if (align != 'center') 'align': align,
    if (maxWidth != 300) 'maxWidth': maxWidth,
    if (callouts.isNotEmpty) 'callouts': callouts,
    if (comments.isNotEmpty)
      'comments': comments.map((c) => c.toJson()).toList(),
    if (table != null) 'table': table,
    if (formula != null) 'formula': formula,
    if (task != null) 'task': task!.toJson(),
    if (boundary) 'boundary': true,
    if (boundaryLabel.isNotEmpty) 'boundaryLabel': boundaryLabel,
    if (summary != null) 'summary': summary,
    if (sticker != null) 'sticker': sticker,
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
      childrenIds: ((j['childrenIds'] as List<dynamic>?) ?? [])
          .cast<String>()
          .toList(),
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
      links: [
        // Formato antigo: um único link em texto.
        if (nonEmpty(j['link']) != null) NodeLink(url: j['link'] as String),
        for (final l in (j['links'] as List<dynamic>?) ?? const [])
          if (l is Map) NodeLink.fromJson(Map<String, dynamic>.from(l)),
      ],
      attachments: ((j['attachments'] as List<dynamic>?) ?? [])
          .map((e) => NodeAttachment.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      markers: ((j['markers'] as List<dynamic>?) ?? []).cast<String>().toList(),
      tags: ((j['tags'] as List<dynamic>?) ?? []).cast<String>().toList(),
      sticker: nonEmpty(j['sticker']),
      image: NodeImage.fromJson(j['image']),
      underline: (j['underline'] as bool?) ?? false,
      strike: (j['strike'] as bool?) ?? false,
      align: kAligns.containsKey(j['align']) ? j['align'] as String : 'center',
      maxWidth: ((j['maxWidth'] as num?) ?? 300).toDouble(),
      callouts: ((j['callouts'] as List<dynamic>?) ?? [])
          .cast<String>()
          .toList(),
      comments: [
        for (final c in (j['comments'] as List<dynamic>?) ?? const [])
          if (c is Map) NodeComment.fromJson(Map<String, dynamic>.from(c)),
      ],
      table: (j['table'] as List<dynamic>?)
          ?.map((r) => (r as List<dynamic>).map((c) => '$c').toList())
          .toList(),
      formula: nonEmpty(j['formula']),
      task: NodeTask.fromJson(j['task']),
      boundary: (j['boundary'] as bool?) ?? false,
      boundaryLabel: (j['boundaryLabel'] as String?) ?? '',
      summary: j['summary'] as String?,
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
    this.layout = 'balanced',
    this.hGap = 64,
    this.vGap = 18,
    this.themeId = 'pineal',
    this.background,
    this.numbering = false,
    this.starred = false,
    this.deletedAt,
    List<NodeRelation>? relations,
  }) : relations = relations ?? [];

  static const formatVersion = 3;

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

  /// Caminho do arquivo .maplong no disco (apenas desktop), se foi salvo/aberto.
  String? filePath;

  /// Estrutura do mapa (ver [kLayouts]).
  String layout;

  /// Espaçamento horizontal e vertical entre tópicos.
  double hGap;
  double vGap;

  /// Tema de cores (ver [kThemes]).
  String themeId;

  /// Cor de fundo personalizada (nulo = automática).
  String? background;

  List<NodeRelation> relations;

  /// Mostra a numeração (1, 1.1, 1.2…) antes do texto dos tópicos.
  bool numbering;

  /// Marcado como favorito na tela inicial.
  bool starred;

  /// Quando foi para a lixeira (nulo = não está na lixeira).
  int? deletedAt;

  MindMapNode get root => nodes[rootId]!;

  MapTheme get theme => themeById(themeId);

  /// Cor automática para o i-ésimo ramo principal.
  String branchColor(int i) => autoColor(i, theme.palette);

  /// Número do tópico (1, 1.2, 1.2.3); vazio para a raiz e os flutuantes.
  String numberOf(String id) {
    final parts = <int>[];
    var cur = nodes[id];
    while (cur != null && cur.parentId != null) {
      final p = nodes[cur.parentId];
      if (p == null) return '';
      parts.insert(0, p.childrenIds.indexOf(cur.id) + 1);
      cur = p;
    }
    if (cur?.id != rootId) return '';
    return parts.join('.');
  }

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
      color: '#3B4CF5',
      fillColor: '#3B4CF5',
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
    'format': 'maplong',
    'version': formatVersion,
    'id': id,
    'name': name,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'rootId': rootId,
    'connectorStyle': connectorStyle,
    'connectorWidth': connectorWidth,
    'autoLayout': autoLayout,
    'layout': layout,
    'hGap': hGap,
    'vGap': vGap,
    'themeId': themeId,
    if (background != null) 'background': background,
    if (numbering) 'numbering': true,
    if (starred) 'starred': true,
    if (deletedAt != null) 'deletedAt': deletedAt,
    'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
    if (relations.isNotEmpty)
      'relations': relations.map((r) => r.toJson()).toList(),
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
    final relations = <NodeRelation>[];
    for (final r in (j['relations'] as List<dynamic>?) ?? const []) {
      if (r is! Map) continue;
      final rel = NodeRelation.fromJson(Map<String, dynamic>.from(r));
      if (nodes.containsKey(rel.from) && nodes.containsKey(rel.to)) {
        relations.add(rel);
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    var style = (j['connectorStyle'] as String?) ?? 'curved';
    if (!kConnectorStyles.containsKey(style)) style = 'curved';
    var layout = (j['layout'] as String?) ?? 'balanced';
    if (!kLayouts.containsKey(layout)) layout = 'balanced';
    final bg = j['background'];
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
      layout: layout,
      hGap: ((j['hGap'] as num?) ?? 64).toDouble(),
      vGap: ((j['vGap'] as num?) ?? 18).toDouble(),
      themeId: themeById(j['themeId'] as String?).id,
      background: bg is String && bg.trim().isNotEmpty ? bg : null,
      relations: relations,
      numbering: (j['numbering'] as bool?) ?? false,
      starred: (j['starred'] as bool?) ?? false,
      deletedAt: (j['deletedAt'] as num?)?.toInt(),
    );
  }

  MindMapDoc clone() => fromJson(toJson());
}
