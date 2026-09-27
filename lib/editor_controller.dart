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

  /// Tamanhos medidos na tela (não são salvos).
  final Map<String, Size> sizes = {};

  final List<String> _undo = [];
  final List<String> _redo = [];
  static const _historyLimit = 100;

  String? _dragSnapshot;
  bool _layoutScheduled = false;
  bool _disposed = false;

  /// JSON salvo por último no arquivo .pmap (para saber se há alterações).
  String? _lastFileJson;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  MindMapNode? get selected =>
      selectedId == null ? null : doc.nodes[selectedId!];

  /// Há alterações ainda não gravadas no arquivo .pmap?
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
      ..touch();
    if (selectedId != null && !doc.nodes.containsKey(selectedId)) {
      selectedId = doc.rootId;
    }
    editingId = null;
    _changed();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _redo.add(_snapshot());
    _restore(_undo.removeLast());
  }

  void redo() {
    if (_redo.isEmpty) return;
    _undo.add(_snapshot());
    _restore(_redo.removeLast());
  }

  /// Executa uma alteração registrando-a no histórico.
  void mutate(VoidCallback fn, {bool relayout = false}) {
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
    if (!doc.autoLayout && !force) return;
    if (_layoutScheduled) return;
    _layoutScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _layoutScheduled = false;
      if (_disposed) return;
      autoLayout(doc, sizes);
      _changed();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void arrangeNow() {
    mutate(() => autoLayout(doc, sizes));
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
    } else if (old == null) {
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------- seleção

  void select(String? id) {
    if (selectedId == id) return;
    if (editingId != null && editingId != id) editingId = null;
    selectedId = id;
    notifyListeners();
  }

  void startEditing([String? id, bool selectAll = false, String? initialText]) {
    final target = id ?? selectedId;
    if (target == null) return;
    selectedId = target;
    editingId = target;
    editingSelectAll = selectAll;
    editingInitialText = initialText;
    notifyListeners();
  }

  void commitEditing(String text) {
    final id = editingId;
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
    final color = isRootChild ? autoColor(idx) : parent.color;
    final side = parent.id == doc.rootId
        ? (idx.isEven ? 1 : -1)
        : sideOf(doc, parent);
    final pSize = sizes[parent.id] ?? estimateNodeSize(parent);
    var y = parent.pos.dy;
    if (parent.childrenIds.isNotEmpty) {
      final sameSide = parent.childrenIds
          .map((c) => doc.nodes[c]!)
          .where((c) => sideOf(doc, c) == side);
      if (sameSide.isNotEmpty) {
        y = sameSide.map((c) => c.pos.dy).reduce((a, b) => a > b ? a : b) +
            56;
      }
    }
    final n = MindMapNode(
      id: newId(),
      text: text ?? (isRootChild ? 'Novo tópico' : 'Subtópico'),
      parentId: parent.id,
      color: color,
      fontSize: isRootChild ? 17 : 15,
      shape: isRootChild ? 'pill' : 'underline',
    );
    final size = estimateNodeSize(n);
    n.pos = Offset(
        parent.pos.dx + side * (pSize.width / 2 + kHGap + size.width / 2), y);
    return n;
  }

  String? addChild([String? parentId]) {
    final parent = doc.nodes[parentId ?? selectedId ?? doc.rootId];
    if (parent == null) return null;
    final n = _newChildOf(parent);
    mutate(() {
      parent.collapsed = false;
      doc.nodes[n.id] = n;
      parent.childrenIds.add(n.id);
    }, relayout: true);
    startEditing(n.id, true);
    return n.id;
  }

  String? addSibling() {
    final cur = selected;
    if (cur == null || cur.parentId == null) return addChild(cur?.id);
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

  String addFloating(Offset scenePos) {
    final n = MindMapNode(
      id: newId(),
      text: 'Tópico flutuante',
      pos: scenePos,
      color: '#00B8D4',
      shape: 'rounded',
    );
    mutate(() => doc.nodes[n.id] = n);
    startEditing(n.id, true);
    return n.id;
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
      for (final id in doc.subtreeIds(target)) {
        doc.nodes.remove(id);
        sizes.remove(id);
      }
      selectedId = next;
      editingId = null;
    }, relayout: true);
  }

  void updateNode(String id, void Function(MindMapNode n) fn,
      {bool relayout = false}) {
    final n = doc.nodes[id];
    if (n == null) return;
    mutate(() => fn(n), relayout: relayout);
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
    mutate(() => n.collapsed = !n.collapsed, relayout: true);
  }

  void setAllCollapsed(bool collapsed) {
    mutate(() {
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
    mutate(() {
      if (n.parentId != null) doc.nodes[n.parentId]?.childrenIds.remove(id);
      n.parentId = newParentId;
      np.childrenIds.add(id);
      np.collapsed = false;
      if (newParentId == doc.rootId) {
        n.color = autoColor(np.childrenIds.length - 1);
      }
      final side = newParentId == doc.rootId ? 1 : sideOf(doc, np);
      final ps = sizes[np.id] ?? estimateNodeSize(np);
      final ns = sizes[id] ?? estimateNodeSize(n);
      final delta = Offset(
              np.pos.dx + side * (ps.width / 2 + kHGap + ns.width / 2),
              np.pos.dy + 40) -
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
    _dragSnapshot = _snapshot();
    select(id);
  }

  void dragBy(String id, Offset delta) {
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
          center: other.pos, width: s.width, height: s.height);
      if (rect.contains(n.pos)) return other.id;
    }
    return null;
  }

  /// Termina o arraste. Retorna true se a organização automática foi desligada.
  bool endDrag(String id) {
    final snap = _dragSnapshot;
    _dragSnapshot = null;
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
    if (snap == null) return false;
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
        Map<String, dynamic>.from(tree['node'] as Map));
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
    if (lines.isEmpty) return false;
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

  // ---------------------------------------------------------- documento

  void setConnector({String? style, double? width}) {
    mutate(() {
      if (style != null) doc.connectorStyle = style;
      if (width != null) doc.connectorWidth = width;
    });
  }

  void rename(String name) {
    if (name.trim().isEmpty) return;
    mutate(() => doc.name = name.trim());
    library.rename(doc.id, name);
  }

  List<MindMapNode> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return doc.nodes.values
        .where((n) =>
            n.text.toLowerCase().contains(q) ||
            n.note.toLowerCase().contains(q))
        .toList();
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
