import 'dart:convert';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'layout.dart';
import 'library.dart';
import 'models.dart';

/// Estado de edição de um documento aberto: seleção, histórico
/// (desfazer/refazer) e todas as operações sobre os nós.
class EditorController extends ChangeNotifier {
  EditorController({required this.library, required this.doc})
    : selectedId = doc.rootId {
    _lastFileJson = doc.filePath == null ? null : _fileJson();
  }

  final Library library;
  final MindMapDoc doc;

  String? selectedId;

  /// Nó em edição de texto no próprio canvas.
  String? editingId;

  /// Quando true, a edição começou com o texto selecionado (nó novo).
  bool editingSelectAll = false;

  /// Texto inicial ao começar a editar digitando direto (substitui o atual).
  String? editingInitialText;

  /// Origem de uma relação sendo criada (aguardando o clique no destino).
  String? linkingFrom;

  /// Outros tópicos selecionados além de [selectedId] (Ctrl/Shift + clique).
  final Set<String> multi = {};

  /// Modo foco: mostra apenas este tópico e seus descendentes.
  String? focusId;

  /// Estilo copiado pelo pincel de formato.
  Map<String, dynamic>? copiedStyle;

  /// Tamanhos medidos na tela (não são salvos).
  final Map<String, Size> sizes = {};

  final List<String> _undo = [];
  final List<String> _redo = [];
  static const _historyLimit = 100;

  String? _dragSnapshot;
  bool _layoutScheduled = false;
  bool _disposed = false;

  /// JSON salvo por último no arquivo .maplong (para saber se há alterações).
  String? _lastFileJson;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Teste grátis encerrado e sem licença: o mapa só pode ser visto.
  bool get readOnly => library.readOnly;

  /// Chamado quando uma alteração é bloqueada pelo modo leitura.
  VoidCallback? onReadOnly;

  /// True (e avisa a tela) quando a alteração não é permitida.
  bool _blocked() {
    if (!readOnly) return false;
    onReadOnly?.call();
    return true;
  }

  MindMapNode? get selected =>
      selectedId == null ? null : doc.nodes[selectedId!];

  /// Há alterações ainda não gravadas no arquivo .maplong?
  bool get hasUnsavedFileChanges =>
      doc.filePath != null && _lastFileJson != _fileJson();

  String _fileJson() {
    final j = doc.toJson()
      ..remove('updatedAt')
      ..remove('filePath');
    return jsonEncode(j);
  }

  void markSavedToFile(String? path) {
    doc.filePath = path ?? doc.filePath;
    _lastFileJson = _fileJson();
    library.saveNow(doc);
    notifyListeners();
  }

  // ---------------------------------------------------------------- histórico

  String _snapshot() => jsonEncode(doc.toJson());

  void _pushUndo(String snap) {
    _undo.add(snap);
    if (_undo.length > _historyLimit) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(String snap) {
    final r = MindMapDoc.fromJson(jsonDecode(snap) as Map<String, dynamic>);
    doc
      ..name = r.name
      ..rootId = r.rootId
      ..nodes = r.nodes
      ..connectorStyle = r.connectorStyle
      ..connectorWidth = r.connectorWidth
      ..autoLayout = r.autoLayout
      ..layout = r.layout
      ..hGap = r.hGap
      ..vGap = r.vGap
      ..themeId = r.themeId
      ..background = r.background
      ..relations = r.relations
      ..numbering = r.numbering
      ..customPalette = r.customPalette
      ..fontFamily = r.fontFamily
      ..handDrawn = r.handDrawn
      ..texture = r.texture
      ..backgroundImage = r.backgroundImage
      ..watermark = r.watermark
      ..colorMode = r.colorMode
      ..alignLevels = r.alignLevels
      ..allowOverlap = r.allowOverlap
      ..relationsOnTop = r.relationsOnTop
      ..touch();
    if (selectedId != null && !doc.nodes.containsKey(selectedId)) {
      selectedId = doc.rootId;
    }
    multi.removeWhere((m) => !doc.nodes.containsKey(m));
    if (focusId != null && !doc.nodes.containsKey(focusId)) focusId = null;
    editingId = null;
    linkingFrom = null;
    _changed();
  }

  /// Volta o mapa para uma versão salva (pode ser desfeito com Ctrl+Z).
  void restoreVersion(String json) {
    if (_blocked()) return;
    _pushUndo(_snapshot());
    final r = MindMapDoc.fromJson(jsonDecode(json) as Map<String, dynamic>);
    r.filePath = doc.filePath;
    r.id = doc.id;
    _restore(jsonEncode(r.toJson()));
  }

  void undo() {
    if (_undo.isEmpty || _blocked()) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty || _blocked()) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  /// Executa uma alteração registrando-a no histórico. Com [viewOnly], a
  /// alteração só muda a visualização (ex.: recolher um ramo) e vale também
  /// no modo leitura.
  void mutate(VoidCallback fn, {bool relayout = false, bool viewOnly = false}) {
    if (!viewOnly && _blocked()) return;
    _pushUndo(_snapshot());
    fn();
    doc.touch();
    if (relayout) requestLayout();
    _changed();
  }

  void _changed() {
    library.scheduleSave(doc);
    notifyListeners();
  }

  // -------------------------------------------------------------- organização

  /// Reorganiza depois do próximo quadro (quando os tamanhos já foram medidos).
  void requestLayout({bool force = false}) {
    if (!doc.autoLayout && !force) {
      _requestUnstack();
      return;
    }
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (_disposed) return;
      _arrange();
      _changed();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  /// Organiza a árvore e afasta tópicos flutuantes que ficaram por cima.
  void _arrange() {
    autoLayout(doc, sizes);
    if (!doc.allowOverlap) {
      resolveOverlaps(doc, sizes, onlyFloating: true, anchorId: editingId);
    }
  }

  bool _unstackScheduled = false;

  /// Com a posição livre, afasta tópicos que ficaram um sobre o outro
  /// (por exemplo, quando um tópico cresce enquanto o texto é digitado).
  void _requestUnstack() {
    if (_unstackScheduled || doc.allowOverlap) return;
    _unstackScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _unstackScheduled = false;
      if (_disposed || _dragSnapshot != null) return;
      if (resolveOverlaps(doc, sizes, anchorId: editingId ?? selectedId)) {
        _changed();
      }
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void arrangeNow() {
    mutate(_arrange);
  }

  void setAutoLayout(bool on) {
    mutate(() => doc.autoLayout = on);
    if (on) requestLayout();
  }

  void reportSize(String id, Size size) {
    final old = sizes[id];
    if (old != null &&
        (old.width - size.width).abs() < 0.5 &&
        (old.height - size.height).abs() < 0.5) {
      return;
    }
    sizes[id] = size;
    if (doc.autoLayout) {
      requestLayout();
    } else {
      _requestUnstack();
      if (old == null) notifyListeners();
    }
  }

  // ---------------------------------------------------------------- seleção

  bool isSelected(String id) => selectedId == id || multi.contains(id);

  /// Todos os tópicos selecionados (o principal primeiro).
  List<String> get selection => [
    ?selectedId,
    ...multi.where((m) => m != selectedId),
  ];

  void toggleMultiSelect(String id) {
    if (selectedId == null) {
      select(id);
      return;
    }
    if (id == selectedId) {
      if (multi.isEmpty) return;
      selectedId = multi.first;
      multi.remove(selectedId);
    } else if (!multi.remove(id)) {
      multi.add(id);
    }
    editingId = null;
    notifyListeners();
  }

  void selectAll() {
    selectedId ??= doc.rootId;
    multi
      ..clear()
      ..addAll(visibleNodes().map((n) => n.id).where((i) => i != selectedId));
    notifyListeners();
  }

  /// Nós visíveis, respeitando os ramos recolhidos e o modo foco.
  Iterable<MindMapNode> visibleNodes() {
    final f = focusId;
    if (f == null || !doc.nodes.containsKey(f)) return doc.visibleNodes();
    final keep = doc.subtreeIds(f).toSet();
    return doc.visibleNodes().where((n) => keep.contains(n.id));
  }

  void setFocus(String? id) {
    focusId = id;
    if (id != null) select(id);
    notifyListeners();
  }

  void select(String? id) {
    if (multi.isNotEmpty) {
      multi.clear();
      if (selectedId == id) {
        notifyListeners();
        return;
      }
    }
    if (selectedId == id) return;
    if (editingId != null && editingId != id) editingId = null;
    selectedId = id;
    notifyListeners();
  }

  void startEditing([String? id, bool selectAll = false, String? initialText]) {
    final target = id ?? selectedId;
    if (target == null || _blocked()) return;
    selectedId = target;
    editingId = target;
    editingSelectAll = selectAll;
    editingInitialText = initialText;
    notifyListeners();
  }

  /// Grava o texto editado. Com [forId], só grava se esse ainda for o tópico
  /// em edição (evita gravar no tópico errado quando o foco muda).
  void commitEditing(String text, [String? forId]) {
    final id = editingId;
    if (forId != null && id != forId) return;
    editingId = null;
    if (id == null) return;
    final n = doc.nodes[id];
    if (n == null || n.text == text) {
      notifyListeners();
      return;
    }
    mutate(() => n.text = text, relayout: true);
  }

  void cancelEditing() {
    if (editingId == null) return;
    editingId = null;
    notifyListeners();
  }

  /// Navega entre nós com as setas do teclado.
  void navigate(AxisDirection dir) {
    final cur = selected;
    if (cur == null) {
      select(doc.rootId);
      return;
    }
    final visible = doc.visibleNodes().where((n) => n.id != cur.id).toList();
    MindMapNode? best;
    var bestScore = double.infinity;
    for (final n in visible) {
      final d = n.pos - cur.pos;
      double primary, secondary;
      switch (dir) {
        case AxisDirection.right:
          primary = d.dx;
          secondary = d.dy.abs();
        case AxisDirection.left:
          primary = -d.dx;
          secondary = d.dy.abs();
        case AxisDirection.down:
          primary = d.dy;
          secondary = d.dx.abs();
        case AxisDirection.up:
          primary = -d.dy;
          secondary = d.dx.abs();
      }
      if (primary <= 1) continue;
      final score = primary + secondary * 2.5;
      if (score < bestScore) {
        bestScore = score;
        best = n;
      }
    }
    if (best != null) select(best.id);
  }

  // ------------------------------------------------------------------- nós

  MindMapNode _newChildOf(MindMapNode parent, {String? text}) {
    final isRootChild = parent.id == doc.rootId;
    final idx = parent.childrenIds.length;
    final palette = doc.theme.palette;
    final color = switch (doc.colorMode) {
      'single' => palette.first,
      'level' => palette[doc.depthOf(parent.id) % palette.length],
      _ => isRootChild ? doc.branchColor(idx) : parent.color,
    };
    final side = parent.id == doc.rootId
        ? switch (doc.layout) {
            'right' => 1,
            'left' => -1,
            _ => idx.isEven ? 1 : -1,
          }
        : sideOf(doc, parent);
    final pSize = sizes[parent.id] ?? estimateNodeSize(parent);
    var y = parent.pos.dy;
    if (parent.childrenIds.isNotEmpty) {
      final sameSide = parent.childrenIds
          .map((c) => doc.nodes[c]!)
          .where((c) => sideOf(doc, c) == side);
      if (sameSide.isNotEmpty) {
        y = sameSide.map((c) => c.pos.dy).reduce((a, b) => a > b ? a : b) + 56;
      }
    }
    final n = MindMapNode(
      id: newId(),
      text: text ?? (isRootChild ? 'Novo tópico' : 'Subtópico'),
      parentId: parent.id,
      color: color,
      fontSize: isRootChild ? 17 : 15,
      shape: isRootChild ? 'pill' : 'underline',
      fillColor: isRootChild && doc.colorMode == 'rainbow' ? color : null,
      textColor: isRootChild && doc.colorMode == 'rainbow' ? '#FFFFFF' : null,
    );
    final size = estimateNodeSize(n);
    n.pos = Offset(
      parent.pos.dx + side * (pSize.width / 2 + doc.hGap + size.width / 2),
      y,
    );
    return n;
  }

  String? addChild([String? parentId]) => addChildWith(parentId);

  /// Novo subtópico; com [edit] falso não entra em modo de edição.
  String? addChildWith(String? parentId, {String? text, bool edit = true}) {
    final parent = doc.nodes[parentId ?? selectedId ?? doc.rootId];
    if (parent == null || _blocked()) return null;
    final n = _newChildOf(parent, text: text);
    mutate(() {
      parent.collapsed = false;
      doc.nodes[n.id] = n;
      parent.childrenIds.add(n.id);
    }, relayout: true);
    if (edit) {
      startEditing(n.id, true);
    } else {
      select(n.id);
    }
    return n.id;
  }

  String? addSibling() {
    final cur = selected;
    if (cur == null || cur.parentId == null) return addChild(cur?.id);
    if (_blocked()) return null;
    final parent = doc.nodes[cur.parentId]!;
    final n = _newChildOf(parent);
    n.color = cur.color;
    n.shape = cur.shape;
    n.fontSize = cur.fontSize;
    n.pos = Offset(cur.pos.dx, cur.pos.dy + 56);
    mutate(() {
      doc.nodes[n.id] = n;
      final i = parent.childrenIds.indexOf(cur.id);
      parent.childrenIds.insert(i + 1, n.id);
    }, relayout: true);
    startEditing(n.id, true);
    return n.id;
  }

  /// Novo tópico irmão logo antes do selecionado.
  String? addSiblingBefore() {
    final cur = selected;
    if (cur == null || cur.parentId == null) return addChild(cur?.id);
    if (_blocked()) return null;
    final parent = doc.nodes[cur.parentId]!;
    final n = _newChildOf(parent);
    n.color = cur.color;
    n.shape = cur.shape;
    n.fontSize = cur.fontSize;
    n.pos = Offset(cur.pos.dx, cur.pos.dy - 56);
    mutate(() {
      doc.nodes[n.id] = n;
      final i = parent.childrenIds.indexOf(cur.id);
      parent.childrenIds.insert(i, n.id);
    }, relayout: true);
    startEditing(n.id, true);
    return n.id;
  }

  /// Novo ramo principal (filho direto da ideia principal).
  String? addMainTopic() => addChild(doc.rootId);

  /// Cria vários tópicos de uma vez sob [parentId] (uma linha por tópico,
  /// recuo cria subtópicos).
  bool addMultiple(String text, [String? parentId]) {
    if (_blocked()) return false;
    if (parentId != null) select(parentId);
    return pasteOutline(text);
  }

  /// Novo tópico flutuante. No modo leitura não cria nada e devolve um id
  /// vazio (que não corresponde a nenhum tópico).
  String addFloating(
    Offset scenePos, {
    String text = 'Tópico flutuante',
    bool edit = true,
    void Function(MindMapNode n)? configure,
  }) {
    if (_blocked()) return '';
    final n = MindMapNode(
      id: newId(),
      text: text,
      pos: scenePos,
      color: '#00B8D4',
      shape: 'rounded',
    );
    configure?.call(n);
    mutate(() => doc.nodes[n.id] = n);
    if (edit) {
      startEditing(n.id, true);
    } else {
      select(n.id);
    }
    return n.id;
  }

  /// Caixa de texto solta no mapa (sem borda nem fundo).
  String addTextBox(Offset scenePos) => addFloating(
    scenePos,
    text: 'Caixa de texto',
    configure: (n) => n
      ..shape = 'plain'
      ..color = '#78909C'
      ..align = 'left'
      ..maxWidth = 260,
  );

  /// Nota adesiva amarela solta no mapa.
  String addStickyNote(Offset scenePos) => addFloating(
    scenePos,
    text: 'Nota',
    configure: (n) => n
      ..shape = 'sticky'
      ..color = '#F9A825'
      ..textColor = '#3E2723'
      ..borderStyle = 'none'
      ..align = 'left'
      ..maxWidth = 180
      ..fontSize = 15,
  );

  /// Exclui todos os tópicos selecionados.
  void deleteSelection() {
    final ids = selection.where((i) => i != doc.rootId).toList();
    if (ids.length <= 1) {
      deleteNode();
      return;
    }
    mutate(() {
      for (final id in ids) {
        final n = doc.nodes[id];
        if (n == null) continue;
        doc.nodes[n.parentId]?.childrenIds.remove(id);
        final removed = doc.subtreeIds(id).toSet();
        for (final r in removed) {
          doc.nodes.remove(r);
          sizes.remove(r);
        }
        doc.relations.removeWhere(
          (r) => removed.contains(r.from) || removed.contains(r.to),
        );
      }
      multi.clear();
      selectedId = doc.rootId;
      editingId = null;
    }, relayout: true);
  }

  void deleteNode([String? id]) {
    final target = id ?? selectedId;
    if (target == null || target == doc.rootId) return;
    final n = doc.nodes[target];
    if (n == null) return;
    final parent = n.parentId == null ? null : doc.nodes[n.parentId];
    String next = doc.rootId;
    if (parent != null) {
      final i = parent.childrenIds.indexOf(target);
      if (parent.childrenIds.length > 1) {
        next = parent.childrenIds[i > 0 ? i - 1 : 1];
      } else {
        next = parent.id;
      }
    }
    mutate(() {
      parent?.childrenIds.remove(target);
      final removed = doc.subtreeIds(target).toSet();
      for (final id in removed) {
        doc.nodes.remove(id);
        sizes.remove(id);
      }
      doc.relations.removeWhere(
        (r) => removed.contains(r.from) || removed.contains(r.to),
      );
      selectedId = next;
      editingId = null;
    }, relayout: true);
  }

  /// Altera um tópico. Se ele for o principal de uma seleção múltipla, a
  /// alteração vale para todos os tópicos selecionados.
  void updateNode(
    String id,
    void Function(MindMapNode n) fn, {
    bool relayout = false,
  }) {
    final n = doc.nodes[id];
    if (n == null) return;
    final targets = id == selectedId && multi.isNotEmpty
        ? selection.map((i) => doc.nodes[i]).whereType<MindMapNode>().toList()
        : [n];
    mutate(() {
      for (final t in targets) {
        fn(t);
      }
    }, relayout: relayout);
  }

  // ------------------------------------------------------ pincel de formato

  void copyStyle([String? id]) {
    final n = doc.nodes[id ?? selectedId ?? ''];
    if (n == null) return;
    copiedStyle = n.styleJson();
    notifyListeners();
  }

  /// Aplica o estilo copiado ao tópico (ou à seleção inteira).
  void pasteStyle([String? id]) {
    final st = copiedStyle;
    final target = id ?? selectedId;
    if (st == null || target == null) return;
    updateNode(target, (n) => n.applyStyleJson(st), relayout: true);
  }

  /// Copia o estilo do tópico para todos os tópicos do mesmo nível
  /// (cada um mantém a cor do próprio ramo).
  int applyStyleToLevel([String? id]) {
    final src = doc.nodes[id ?? selectedId ?? ''];
    if (src == null) return 0;
    final depth = doc.depthOf(src.id);
    final style = src.styleJson();
    final targets = doc.nodes.values
        .where((n) => n.id != src.id && doc.depthOf(n.id) == depth)
        .toList();
    if (targets.isEmpty) return 0;
    mutate(() {
      for (final n in targets) {
        n.applyStyleJson(style, includeColor: false);
      }
    }, relayout: true);
    return targets.length;
  }

  /// Volta o tópico (ou a seleção) ao estilo padrão do seu nível.
  void resetStyle([String? id]) {
    final target = id ?? selectedId;
    if (target == null) return;
    final t = doc.theme;
    updateNode(target, (n) {
      final isRoot = n.id == doc.rootId;
      final depth = doc.depthOf(n.id);
      n
        ..fillColor = isRoot ? t.rootFill : null
        ..textColor = isRoot ? t.rootText : null
        ..shape = isRoot || n.parentId == null
            ? 'rounded'
            : depth == 1
            ? 'pill'
            : 'underline'
        ..fontSize = isRoot
            ? 22
            : depth == 1
            ? 17
            : 15
        ..bold = isRoot
        ..italic = false
        ..underline = false
        ..strike = false
        ..align = 'center'
        ..maxWidth = 300
        ..borderWidth = isRoot ? 2 : 1.5
        ..borderStyle = 'solid'
        ..borderColor = null
        ..corner = null
        ..fontFamily = null
        ..highlight = null
        ..lineStyle = null
        ..lineWidth = null;
      if (isRoot) n.color = t.rootFill;
    }, relayout: true);
  }

  // --------------------------------------------------- localizar e substituir

  /// Substitui [find] por [replacement] no texto (e nas anotações, se
  /// [notes]). Retorna quantos tópicos mudaram.
  int replaceAll(
    String find,
    String replacement, {
    bool notes = false,
    bool caseSensitive = false,
  }) {
    if (find.isEmpty) return 0;
    final re = RegExp(RegExp.escape(find), caseSensitive: caseSensitive);
    final hits = doc.nodes.values
        .where((n) => re.hasMatch(n.text) || (notes && re.hasMatch(n.note)))
        .toList();
    if (hits.isEmpty || _blocked()) return 0;
    mutate(() {
      for (final n in hits) {
        n.text = n.text.replaceAll(re, replacement);
        if (notes) n.note = n.note.replaceAll(re, replacement);
      }
    }, relayout: true);
    return hits.length;
  }

  /// Aplica o mesmo estilo a um nó e (opcionalmente) a toda a sua subárvore.
  void updateBranch(String id, void Function(MindMapNode n) fn) {
    mutate(() {
      for (final i in doc.subtreeIds(id)) {
        fn(doc.nodes[i]!);
      }
    }, relayout: true);
  }

  void toggleCollapse([String? id]) {
    final n = doc.nodes[id ?? selectedId ?? ''];
    if (n == null || n.childrenIds.isEmpty) return;
    mutate(() => n.collapsed = !n.collapsed, relayout: true, viewOnly: true);
  }

  void setAllCollapsed(bool collapsed) {
    mutate(viewOnly: true, () {
      for (final n in doc.nodes.values) {
        if (n.id != doc.rootId && n.childrenIds.isNotEmpty) {
          n.collapsed = collapsed;
        }
      }
      if (!collapsed) doc.root.collapsed = false;
      if (selectedId != null &&
          doc.visibleNodes().every((n) => n.id != selectedId)) {
        selectedId = doc.rootId;
      }
    }, relayout: true);
  }

  /// Move um nó para ser filho de [newParentId] (arrastar e soltar).
  bool reparent(String id, String newParentId) {
    if (id == doc.rootId || doc.isInSubtree(newParentId, id)) return false;
    final n = doc.nodes[id];
    final np = doc.nodes[newParentId];
    if (n == null || np == null || n.parentId == newParentId) return false;
    if (_blocked()) return false;
    mutate(() {
      if (n.parentId != null) doc.nodes[n.parentId]?.childrenIds.remove(id);
      n.parentId = newParentId;
      np.childrenIds.add(id);
      np.collapsed = false;
      if (newParentId == doc.rootId) {
        n.color = doc.branchColor(np.childrenIds.length - 1);
      }
      final side = newParentId == doc.rootId ? 1 : sideOf(doc, np);
      final ps = sizes[np.id] ?? estimateNodeSize(np);
      final ns = sizes[id] ?? estimateNodeSize(n);
      final delta =
          Offset(
            np.pos.dx + side * (ps.width / 2 + doc.hGap + ns.width / 2),
            np.pos.dy + 40,
          ) -
          n.pos;
      for (final c in doc.subtreeIds(id)) {
        doc.nodes[c]!.pos += delta;
      }
    }, relayout: true);
    return true;
  }

  /// Transforma um nó em tópico flutuante (desliga do pai).
  void detach([String? id]) {
    final n = doc.nodes[id ?? selectedId ?? ''];
    if (n == null || n.parentId == null) return;
    mutate(() {
      doc.nodes[n.parentId]?.childrenIds.remove(n.id);
      n.parentId = null;
    }, relayout: true);
  }

  void moveSibling(int delta) {
    final n = selected;
    if (n == null || n.parentId == null) return;
    final p = doc.nodes[n.parentId]!;
    final i = p.childrenIds.indexOf(n.id);
    final j = i + delta;
    if (j < 0 || j >= p.childrenIds.length) return;
    mutate(() {
      p.childrenIds
        ..removeAt(i)
        ..insert(j, n.id);
    }, relayout: true);
  }

  // ---------------------------------------------------------------- arrastar

  void beginDrag(String id) {
    select(id);
    if (readOnly) return;
    _dragSnapshot = _snapshot();
  }

  void dragBy(String id, Offset delta) {
    if (readOnly) return;
    for (final c in doc.subtreeIds(id)) {
      final n = doc.nodes[c];
      if (n != null) n.pos += delta;
    }
    notifyListeners();
  }

  /// Retorna o nó sobre o qual [id] foi solto (candidato a novo pai).
  String? dropTargetFor(String id) {
    final n = doc.nodes[id];
    if (n == null) return null;
    for (final other in doc.visibleNodes()) {
      if (other.id == id || other.id == n.parentId) continue;
      if (doc.isInSubtree(other.id, id)) continue;
      final s = sizes[other.id] ?? estimateNodeSize(other);
      final rect = Rect.fromCenter(
        center: other.pos,
        width: s.width,
        height: s.height,
      );
      if (rect.contains(n.pos)) return other.id;
    }
    return null;
  }

  /// Termina o arraste. Retorna true se a organização automática foi desligada.
  bool endDrag(String id) {
    final snap = _dragSnapshot;
    _dragSnapshot = null;
    if (snap == null && _blocked()) return false;
    final target = dropTargetFor(id);
    if (target != null && snap != null) {
      // Restaura a posição original e registra a mudança de pai.
      final r = MindMapDoc.fromJson(jsonDecode(snap) as Map<String, dynamic>);
      for (final c in doc.subtreeIds(id)) {
        doc.nodes[c]!.pos = r.nodes[c]?.pos ?? doc.nodes[c]!.pos;
      }
      if (reparent(id, target)) return false;
    }
    if (snap != null) _pushUndo(snap);
    var turnedOff = false;
    if (doc.autoLayout && id != doc.rootId) {
      doc.autoLayout = false;
      turnedOff = true;
    }
    // O tópico solto fica onde o usuário deixou; os vizinhos abrem espaço.
    if (!doc.allowOverlap) resolveOverlaps(doc, sizes, anchorId: id);
    doc.touch();
    _changed();
    return turnedOff;
  }

  // -------------------------------------------------- copiar / colar

  Map<String, dynamic> _subtreeJson(String id) {
    final n = doc.nodes[id]!;
    return {
      'node': n.toJson(),
      'children': n.childrenIds.map(_subtreeJson).toList(),
    };
  }

  void copy() {
    final id = selectedId;
    if (id == null) return;
    library.clipboard = _subtreeJson(id);
  }

  void cut() {
    final id = selectedId;
    if (id == null || id == doc.rootId) return;
    copy();
    deleteNode(id);
  }

  /// Texto em tópicos (recuado) da subárvore — para a área de transferência.
  String outlineText(String id, [int depth = 0]) {
    final n = doc.nodes[id]!;
    final b = StringBuffer('${'  ' * depth}${n.text.replaceAll('\n', ' ')}\n');
    for (final c in n.childrenIds) {
      b.write(outlineText(c, depth + 1));
    }
    return b.toString();
  }

  bool paste() {
    final snap = library.clipboard;
    final parent = doc.nodes[selectedId ?? doc.rootId] ?? doc.root;
    if (snap == null || _blocked()) return false;
    String? newRoot;
    mutate(() {
      newRoot = _build(snap, parent, null);
      parent.collapsed = false;
    }, relayout: true);
    select(newRoot);
    return true;
  }

  String _build(Map<String, dynamic> tree, MindMapNode parent, Offset? delta) {
    final src = MindMapNode.fromJson(
      Map<String, dynamic>.from(tree['node'] as Map),
    );
    final oldPos = src.pos;
    src
      ..id = newId()
      ..parentId = parent.id
      ..childrenIds = [];
    if (delta == null) {
      final placed = _newChildOf(parent);
      delta = placed.pos - oldPos;
    }
    src.pos = oldPos + delta;
    doc.nodes[src.id] = src;
    parent.childrenIds.add(src.id);
    for (final c in (tree['children'] as List<dynamic>)) {
      _build(Map<String, dynamic>.from(c as Map), src, delta);
    }
    return src.id;
  }

  /// Cria tópicos a partir de texto com recuo (uma linha por tópico).
  bool pasteOutline(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (lines.isEmpty || _blocked()) return false;
    final base = doc.nodes[selectedId ?? doc.rootId] ?? doc.root;
    String? first;
    mutate(() {
      // Pilha de (nível de recuo, nó).
      final stack = <(int, MindMapNode)>[(-1, base)];
      for (final raw in lines) {
        final expanded = raw.replaceAll('\t', '    ');
        final indent = expanded.length - expanded.trimLeft().length;
        final text = expanded
            .trim()
            .replaceFirst(RegExp(r'^([-*+•]|\d+[.)])\s+'), '')
            .replaceFirst(RegExp(r'^#+\s*'), '');
        while (stack.length > 1 && stack.last.$1 >= indent) {
          stack.removeLast();
        }
        final parent = stack.last.$2;
        final n = _newChildOf(parent, text: text);
        doc.nodes[n.id] = n;
        parent.childrenIds.add(n.id);
        parent.collapsed = false;
        first ??= n.id;
        stack.add((indent, n));
      }
    }, relayout: true);
    select(first);
    return true;
  }

  // ---------------------------------------------------- marcadores e adesivos

  /// Coloca o marcador no tópico; se ele já estiver lá, remove.
  void toggleMarker(String group, String value, [String? id]) {
    final n = doc.nodes[id ?? selectedId ?? ''];
    if (n == null) return;
    final current = n.marker(group);
    mutate(
      () => n.setMarker(group, current == value ? null : value),
      relayout: true,
    );
  }

  void clearMarkers([String? id]) {
    final n = doc.nodes[id ?? selectedId ?? ''];
    if (n == null || n.markers.isEmpty) return;
    mutate(() => n.markers.clear(), relayout: true);
  }

  void setSticker(String? emoji, [String? id]) {
    final n = doc.nodes[id ?? selectedId ?? ''];
    if (n == null || n.sticker == emoji) return;
    mutate(() => n.sticker = emoji, relayout: true);
  }

  // --------------------------------------------------------------- relações

  /// Começa a criar uma relação a partir do tópico selecionado.
  void startRelation([String? from]) {
    final id = from ?? selectedId;
    if (id == null || _blocked()) return;
    linkingFrom = id;
    editingId = null;
    notifyListeners();
  }

  void cancelRelation() {
    if (linkingFrom == null) return;
    linkingFrom = null;
    notifyListeners();
  }

  /// Termina a relação iniciada em [startRelation] no tópico [to].
  bool completeRelation(String to) {
    final from = linkingFrom;
    linkingFrom = null;
    if (from == null || from == to || !doc.nodes.containsKey(to)) {
      notifyListeners();
      return false;
    }
    final exists = doc.relations.any(
      (r) => (r.from == from && r.to == to) || (r.from == to && r.to == from),
    );
    if (exists) {
      notifyListeners();
      return false;
    }
    mutate(
      () => doc.relations.add(NodeRelation(id: newId(), from: from, to: to)),
    );
    return true;
  }

  List<NodeRelation> relationsOf(String id) =>
      doc.relations.where((r) => r.from == id || r.to == id).toList();

  void updateRelation(String relId, void Function(NodeRelation r) fn) {
    final r = doc.relations.where((r) => r.id == relId).firstOrNull;
    if (r == null) return;
    mutate(() => fn(r));
  }

  void removeRelation(String relId) {
    mutate(() => doc.relations.removeWhere((r) => r.id == relId));
  }

  // ------------------------------------------------------------ aparência

  void setLayout(String layout) {
    mutate(() {
      doc.layout = layout;
      doc.autoLayout = true;
      _arrange();
    });
  }

  void setSpacing({double? h, double? v}) {
    mutate(() {
      if (h != null) doc.hGap = h;
      if (v != null) doc.vGap = v;
      if (doc.autoLayout) _arrange();
    });
  }

  /// Aplica uma paleta gerada (ex.: pela The Color API) como tema
  /// "Personalizado". A primeira cor vai para a ideia principal.
  void applyCustomPalette(List<String> colors) {
    if (colors.isEmpty || _blocked()) return;
    doc.customPalette = List.of(colors);
    applyTheme('custom');
  }

  /// Aplica um tema: recolore a ideia principal e os ramos com a paleta.
  void applyTheme(String themeId) {
    final previous = doc.themeId;
    doc.themeId = themeId;
    final t = doc.theme;
    doc.themeId = previous;
    final mode = doc.colorMode;
    mutate(() {
      doc.themeId = t.id;
      doc.background = t.background;
      final root = doc.root;
      root
        ..color = t.rootFill
        ..fillColor = t.rootFill
        ..textColor = t.rootText;
      for (var i = 0; i < root.childrenIds.length; i++) {
        final branchColor = t.palette[i % t.palette.length];
        for (final id in doc.subtreeIds(root.childrenIds[i])) {
          final n = doc.nodes[id]!;
          final depth = doc.depthOf(id);
          final color = switch (mode) {
            'single' => t.palette.first,
            'level' => t.palette[(depth - 1) % t.palette.length],
            _ => branchColor,
          };
          n.color = color;
          if (mode == 'rainbow' && depth == 1) {
            n
              ..fillColor = color
              ..textColor = '#FFFFFF';
          } else if (n.textColor == '#FFFFFF' && n.fillColor != null) {
            // Desfaz o preenchimento do modo arco-íris.
            n
              ..fillColor = null
              ..textColor = null;
          } else if (n.fillColor != null &&
              n.fillColor != kNoFill &&
              n.fillColor != '#FFFFFF' &&
              n.fillColor != '#1F2333') {
            // Preenchimentos com a cor antiga do ramo acompanham o novo tema.
            n.fillColor = color;
          }
        }
      }
    });
  }

  void setNumbering(bool on) {
    mutate(() => doc.numbering = on, relayout: true);
  }

  // ---------------------------------------------------------- estilo de página

  /// Fonte de todos os tópicos (os que têm fonte própria não mudam).
  void setMapFont(String? font) =>
      mutate(() => doc.fontFamily = font, relayout: true);

  void setHandDrawn(bool on) => mutate(() => doc.handDrawn = on);

  void setTexture(String? texture) => mutate(() => doc.texture = texture);

  void setBackgroundImage(String? data) =>
      mutate(() => doc.backgroundImage = data);

  void setWatermark(String? text) => mutate(
    () => doc.watermark = text == null || text.trim().isEmpty
        ? null
        : text.trim(),
  );

  void setRelationsOnTop(bool on) => mutate(() => doc.relationsOnTop = on);

  void setAlignLevels(bool on) {
    mutate(() {
      doc.alignLevels = on;
      if (doc.autoLayout) _arrange();
    });
  }

  /// Permite tópicos sobrepostos (sem afastar automaticamente).
  void setAllowOverlap(bool on) {
    mutate(() {
      doc.allowOverlap = on;
      if (!on && doc.autoLayout) _arrange();
    });
    if (!on && !doc.autoLayout) _requestUnstack();
  }

  /// Volta o espaçamento entre tópicos ao padrão.
  void resetSpacing() => setSpacing(h: 64, v: 18);

  /// O visual atual do mapa, para salvar como tema personalizado.
  SavedTheme themeSnapshot(String name) {
    final root = doc.root;
    final colors = <String>[root.fillColor ?? doc.theme.rootFill];
    for (final c in root.childrenIds) {
      final color = doc.nodes[c]?.color;
      if (color != null && !colors.contains(color)) colors.add(color);
    }
    for (final c in doc.theme.palette) {
      if (colors.length >= 7) break;
      if (!colors.contains(c)) colors.add(c);
    }
    return SavedTheme(
      name: name,
      colors: colors,
      background: doc.background,
      font: doc.fontFamily,
      handDrawn: doc.handDrawn,
      connectorStyle: doc.connectorStyle,
      connectorWidth: doc.connectorWidth,
    );
  }

  /// Aplica um tema salvo pelo usuário.
  void applySavedTheme(SavedTheme s) {
    if (_blocked()) return;
    applyCustomPalette(s.colors);
    mutate(() {
      doc
        ..background = s.background
        ..fontFamily = s.font
        ..handDrawn = s.handDrawn
        ..connectorStyle = s.connectorStyle
        ..connectorWidth = s.connectorWidth;
    }, relayout: true);
  }

  /// Muda a forma de colorir os ramos e recolore o mapa.
  void setColorMode(String mode) {
    if (!kColorModes.containsKey(mode)) return;
    doc.colorMode = mode;
    applyTheme(doc.themeId);
  }

  void setBackground(String? hex) {
    mutate(() => doc.background = hex);
  }

  // ---------------------------------------------------------- documento

  void setConnector({String? style, double? width}) {
    mutate(() {
      if (style != null) doc.connectorStyle = style;
      if (width != null) doc.connectorWidth = width;
    });
  }

  void rename(String name) {
    if (name.trim().isEmpty || _blocked()) return;
    mutate(() => doc.name = name.trim());
    library.rename(doc.id, name);
  }

  List<MindMapNode> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return doc.nodes.values
        .where(
          (n) =>
              n.text.toLowerCase().contains(q) ||
              n.note.toLowerCase().contains(q) ||
              n.tags.any((t) => t.toLowerCase().contains(q)) ||
              n.links.any((l) => l.label.toLowerCase().contains(q)) ||
              n.comments.any((c) => c.text.toLowerCase().contains(q)) ||
              n.callouts.any((c) => c.toLowerCase().contains(q)) ||
              (n.task?.assignee.toLowerCase().contains(q) ?? false),
        )
        .toList();
  }

  /// Ordem de leitura do mapa (raiz, depois os ramos em profundidade).
  List<String> readingOrder({bool visibleOnly = true}) {
    final out = <String>[];
    void walk(String id) {
      final n = doc.nodes[id];
      if (n == null) return;
      out.add(id);
      if (visibleOnly && n.collapsed) return;
      for (final c in n.childrenIds) {
        walk(c);
      }
    }

    walk(doc.rootId);
    for (final n in doc.nodes.values) {
      if (n.parentId == null && n.id != doc.rootId) walk(n.id);
    }
    return out;
  }

  /// Garante que o nó esteja visível (expande os ancestrais recolhidos).
  void reveal(String id) {
    var changed = false;
    var cur = doc.nodes[id]?.parentId;
    while (cur != null) {
      final p = doc.nodes[cur]!;
      if (p.collapsed) {
        p.collapsed = false;
        changed = true;
      }
      cur = p.parentId;
    }
    if (changed) {
      requestLayout();
      _changed();
    }
    select(id);
  }

  @override
  void dispose() {
    _disposed = true;
    library.saveNow(doc);
    super.dispose();
  }
}
