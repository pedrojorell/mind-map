import 'dart:ui' show PointMode;

import 'dart:math' as math;

import 'package:cross_file/cross_file.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

import '../editor_controller.dart';
import '../layout.dart';
import '../models.dart';
import 'node_view.dart';
import 'render_helpers.dart';

/// Tamanho da área de desenho; a origem (0,0) da cena fica no centro.
const double kCanvasSize = 40000;
const Offset kOrigin = Offset(kCanvasSize / 2, kCanvasSize / 2);

class MindMapCanvas extends StatefulWidget {
  const MindMapCanvas({
    super.key,
    required this.editor,
    required this.focusNode,
    required this.onContextMenu,
    required this.onMessage,
    required this.scale,
    this.selectionToolbar,
    this.showGrid = true,
    this.onBadgeTap,
    this.onFilesDropped,
    this.onNodeDoubleClick,
    this.showMinimap = true,
    this.highlightId,
  });

  final EditorController editor;
  final FocusNode focusNode;

  /// Menu de contexto (clique direito) em [globalPos]; [nodeId] nulo = fundo.
  final void Function(Offset globalPos, String? nodeId, Offset scenePos)
  onContextMenu;
  final ValueChanged<String> onMessage;

  /// Nível de zoom atual (atualizado pelo canvas).
  final ValueNotifier<double> scale;

  /// Barra flutuante exibida acima do tópico selecionado.
  final WidgetBuilder? selectionToolbar;

  final bool showGrid;

  /// Clique num ícone de um tópico ('links', 'files', 'note').
  final void Function(String nodeId, String kind, Offset globalPos)? onBadgeTap;

  /// Arquivos soltos sobre o mapa ([nodeId] nulo = área vazia).
  final void Function(List<XFile> files, String? nodeId, Offset scenePos)?
  onFilesDropped;

  /// Dois cliques num tópico (depois de entrar em edição do nome).
  final ValueChanged<String>? onNodeDoubleClick;

  final bool showMinimap;

  /// Tópico destacado (modo apresentação).
  final String? highlightId;

  @override
  State<MindMapCanvas> createState() => MindMapCanvasState();
}

class MindMapCanvasState extends State<MindMapCanvas> {
  final _transform = TransformationController();
  final _boundaryKey = GlobalKey();
  ValueNotifier<double> get scale => widget.scale;

  String? _draggingId;
  String? _dropTarget;
  Offset? _lastDragGlobal;
  bool _capturing = false;

  /// Estrutura desenhada por último (para reenquadrar quando ela muda).
  String? _lastLayout;

  /// Arquivos sendo arrastados sobre o mapa; guarda o tópico sob o cursor.
  bool _fileDrag = false;
  String? _fileDragNode;

  /// Posição do mouse na cena (para a prévia de uma relação).
  final _hover = ValueNotifier<Offset?>(null);

  // Contagem de cliques seguidos num mesmo tópico (2 = editar, 3 = novo).
  String? _clickNode;
  int _clickCount = 0;
  DateTime _clickAt = DateTime(0);
  Offset _clickPos = Offset.zero;

  EditorController get editor => widget.editor;
  MindMapDoc get doc => editor.doc;

  @override
  void initState() {
    super.initState();
    _transform.addListener(
      () => scale.value = _transform.value.getMaxScaleOnAxis(),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => fitToScreen(maxScale: 1),
    );
  }

  @override
  void dispose() {
    _transform.dispose();
    _hover.dispose();
    super.dispose();
  }

  Size get _viewport =>
      (context.findRenderObject() as RenderBox?)?.size ?? const Size(800, 600);

  Offset toScene(Offset local) {
    final inv = Matrix4.inverted(_transform.value);
    final v = inv.transform3(vm.Vector3(local.dx, local.dy, 0));
    return Offset(v.x, v.y) - kOrigin;
  }

  Offset get viewportCenterScene => toScene(_viewport.center(Offset.zero));

  void _setView(Offset sceneCenter, double s) {
    final vp = _viewport;
    final p = sceneCenter + kOrigin;
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        vp.width / 2 - p.dx * s,
        vp.height / 2 - p.dy * s,
        0,
        1,
      )
      ..scaleByDouble(s, s, 1, 1);
  }

  Rect contentBounds({double margin = 0}) {
    Rect? r;
    for (final n in editor.visibleNodes()) {
      final s = editor.sizes[n.id] ?? estimateNodeSize(n);
      final nr = Rect.fromCenter(
        center: n.pos,
        width: s.width,
        height: s.height,
      );
      r = r == null ? nr : r.expandToInclude(nr);
    }
    return (r ?? Rect.fromCenter(center: Offset.zero, width: 200, height: 80))
        .inflate(margin);
  }

  void fitToScreen({double maxScale = 1.5}) {
    if (!mounted) return;
    final b = contentBounds(margin: 60);
    final vp = _viewport;
    final s = math
        .min(vp.width / b.width, vp.height / b.height)
        .clamp(0.1, maxScale)
        .toDouble();
    _setView(b.center, s);
  }

  /// Enquadra os tópicos [ids] (com seus tamanhos) na tela.
  void fitToIds(
    Iterable<String> ids, {
    double maxScale = 1.6,
    double margin = 70,
  }) {
    if (!mounted) return;
    Rect? r;
    for (final id in ids) {
      final n = doc.nodes[id];
      if (n == null) continue;
      final s = editor.sizes[n.id] ?? estimateNodeSize(n);
      final nr = Rect.fromCenter(
        center: n.pos,
        width: s.width,
        height: s.height,
      );
      r = r == null ? nr : r.expandToInclude(nr);
    }
    if (r == null) return;
    final b = r.inflate(margin);
    final vp = _viewport;
    final sc = math
        .min(vp.width / b.width, vp.height / b.height)
        .clamp(0.1, maxScale)
        .toDouble();
    _setView(b.center, sc);
  }

  void centerOn(String id) {
    final n = doc.nodes[id];
    if (n == null) return;
    _setView(n.pos, scale.value);
  }

  /// Rola a tela apenas se o nó estiver fora da área visível.
  void ensureVisible(String id) {
    final n = doc.nodes[id];
    if (n == null) return;
    final s = editor.sizes[n.id] ?? estimateNodeSize(n);
    final m = _transform.value;
    final p = MatrixUtils.transformPoint(m, n.pos + kOrigin);
    final half = Offset(s.width, s.height) * scale.value / 2;
    final vp = Offset.zero & _viewport;
    if (vp.deflate(20).contains(p - half) &&
        vp.deflate(20).contains(p + half)) {
      return;
    }
    centerOn(id);
  }

  void zoomBy(double factor) => setZoom(scale.value * factor);

  void setZoom(double s) =>
      _setView(viewportCenterScene, s.clamp(0.1, 3.0).toDouble());

  void resetZoom() => _setView(viewportCenterScene, 1);

  Future<Uint8List?> capturePng() async {
    // Pinta o fundo dentro da área capturada durante a exportação.
    setState(() => _capturing = true);
    await WidgetsBinding.instance.endOfFrame;
    try {
      final ro = _boundaryKey.currentContext?.findRenderObject();
      if (ro is! RenderCaptureBoundary) return null;
      final b = contentBounds(margin: 40).shift(kOrigin);
      final pixels = b.width * b.height;
      // Limita a resolução em mapas enormes.
      final ratio = math.min(2.0, math.sqrt(40e6 / pixels));
      return await ro.capturePng(b, pixelRatio: ratio);
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  /// Tópico visível sob o ponto [scene] (coordenadas da cena).
  String? nodeAt(Offset scene) {
    String? hit;
    for (final n in editor.visibleNodes()) {
      final s = editor.sizes[n.id] ?? estimateNodeSize(n);
      if (Rect.fromCenter(
        center: n.pos,
        width: s.width,
        height: s.height,
      ).inflate(6).contains(scene)) {
        hit = n.id;
      }
    }
    return hit;
  }

  // --------------------------------------------------------------- cliques

  void _onNodePointerDown(String id, PointerDownEvent e) {
    if (e.buttons != kPrimaryMouseButton) return;
    final now = DateTime.now();
    // Cliques rápidos no mesmo ponto contam para o tópico do primeiro clique,
    // mesmo que ele mude de tamanho ao entrar em edição.
    final quick =
        _clickNode != null &&
        now.difference(_clickAt) < const Duration(milliseconds: 450) &&
        (e.position - _clickPos).distance < 12;
    if (quick) {
      _clickCount++;
    } else {
      _clickCount = 1;
      _clickNode = id;
      _clickPos = e.position;
    }
    _clickAt = now;
    final target = _clickNode!;
    if (editor.linkingFrom != null || !doc.nodes.containsKey(target)) return;
    if (_clickCount == 2) {
      editor.select(target);
      editor.startEditing(target);
      widget.onNodeDoubleClick?.call(target);
    } else if (_clickCount == 3) {
      // Três cliques: cria um tópico conectado a este.
      editor.cancelEditing();
      editor.addChild(target);
      _clickNode = null;
      _clickCount = 0;
    }
  }

  // ------------------------------------------------------------- arrastar

  void _onDragStart(String id, Offset global) {
    if (editor.editingId == id || editor.linkingFrom != null) return;
    _draggingId = id;
    _lastDragGlobal = global;
    editor.beginDrag(id);
  }

  void _onDragUpdate(String id, Offset global) {
    if (_draggingId != id || _lastDragGlobal == null) return;
    final delta = (global - _lastDragGlobal!) / scale.value;
    _lastDragGlobal = global;
    editor.dragBy(id, delta);
    final t = editor.dropTargetFor(id);
    if (t != _dropTarget) setState(() => _dropTarget = t);
  }

  void _onDragEnd(String id) {
    if (_draggingId != id) return;
    _draggingId = null;
    _lastDragGlobal = null;
    final target = _dropTarget;
    setState(() => _dropTarget = null);
    final turnedOff = editor.endDrag(id);
    if (target != null) {
      widget.onMessage(
        'Tópico movido para “${doc.nodes[target]?.text ?? ''}”.',
      );
    } else if (turnedOff) {
      widget.onMessage(
        'Posição livre: organização automática desativada (reative em Design).',
      );
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = parseHex(doc.background) ?? theme.scaffoldBackgroundColor;
    final visible = editor.visibleNodes().toList();
    final visibleIds = visible.map((n) => n.id).toSet();
    final linking = editor.linkingFrom != null;
    if (_lastLayout != null && _lastLayout != doc.layout) {
      WidgetsBinding.instance.addPostFrameCallback((_) => fitToScreen());
    }
    _lastLayout = doc.layout;

    final nodeWidgets = <Widget>[];
    final toggles = <Widget>[];
    for (final n in visible) {
      final isRoot = n.id == doc.rootId;
      final p = n.pos + kOrigin;
      nodeWidgets.add(
        Positioned(
          key: ValueKey(n.id),
          left: p.dx,
          top: p.dy,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -0.5),
            child: MeasureSize(
              onChange: (s) => editor.reportSize(n.id, s),
              child: Listener(
                onPointerDown: (e) => _onNodePointerDown(n.id, e),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) {
                    widget.focusNode.requestFocus();
                    if (linking) {
                      if (!editor.completeRelation(n.id)) {
                        widget.onMessage('Relação não criada.');
                      }
                      return;
                    }
                    final hk = HardwareKeyboard.instance;
                    if (hk.isControlPressed ||
                        hk.isShiftPressed ||
                        hk.isMetaPressed) {
                      editor.toggleMultiSelect(n.id);
                    } else if (!editor.isSelected(n.id)) {
                      editor.select(n.id);
                    }
                  },
                  // Os cliques duplos/triplos são tratados no Listener acima; este
                  // callback só impede que o fundo crie um tópico flutuante.
                  onDoubleTap: () {},
                  onSecondaryTapDown: (d) {
                    editor.select(n.id);
                    widget.onContextMenu(d.globalPosition, n.id, n.pos);
                  },
                  onPanStart: (d) => _onDragStart(n.id, d.globalPosition),
                  onPanUpdate: (d) => _onDragUpdate(n.id, d.globalPosition),
                  onPanEnd: (_) => _onDragEnd(n.id),
                  onPanCancel: () => _onDragEnd(n.id),
                  child: NodeView(
                    node: n,
                    isRoot: isRoot,
                    selected:
                        editor.isSelected(n.id) ||
                        editor.linkingFrom == n.id ||
                        widget.highlightId == n.id,
                    editing: editor.editingId == n.id,
                    selectAllOnEdit: editor.editingSelectAll,
                    initialText: editor.editingId == n.id
                        ? editor.editingInitialText
                        : null,
                    dropTarget: _dropTarget == n.id || _fileDragNode == n.id,
                    number: doc.numbering ? doc.numberOf(n.id) : '',
                    onBadgeTap: widget.onBadgeTap == null
                        ? null
                        : (kind, pos) => widget.onBadgeTap!(n.id, kind, pos),
                    onCommit: (text) {
                      editor.commitEditing(text, n.id);
                      widget.focusNode.requestFocus();
                    },
                    onCancel: () {
                      editor.cancelEditing();
                      widget.focusNode.requestFocus();
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Botão de recolher/expandir ramos.
      final size = editor.sizes[n.id];
      if (n.childrenIds.isNotEmpty && size != null && !isRoot) {
        final c = p + collapseToggleOffset(doc, n, size);
        toggles.add(
          Positioned(
            key: ValueKey('t_${n.id}'),
            left: c.dx - 9,
            top: c.dy - 9,
            child: _CollapseToggle(
              collapsed: n.collapsed,
              count: doc.subtreeIds(n.id).length - 1,
              color: parseHex(n.color) ?? theme.colorScheme.primary,
              background: bg,
              onTap: () => editor.toggleCollapse(n.id),
            ),
          ),
        );
      }
    }

    final onBg = bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    // O contraste automático do texto considera o fundo do mapa.
    return Theme(
      data: theme.copyWith(scaffoldBackgroundColor: bg),
      child: DropTarget(
        enable: widget.onFilesDropped != null,
        onDragEntered: (_) => setState(() => _fileDrag = true),
        onDragUpdated: (d) {
          final id = nodeAt(toScene(d.localPosition));
          if (id != _fileDragNode) setState(() => _fileDragNode = id);
        },
        onDragExited: (_) => setState(() {
          _fileDrag = false;
          _fileDragNode = null;
        }),
        onDragDone: (d) {
          final scene = toScene(d.localPosition);
          final id = nodeAt(scene);
          setState(() {
            _fileDrag = false;
            _fileDragNode = null;
          });
          widget.onFilesDropped?.call(d.files, id, scene);
        },
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: bg)),
            if (widget.showGrid)
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(
                    transform: _transform,
                    color: onBg.withValues(alpha: 0.09),
                  ),
                ),
              ),
            Positioned.fill(
              child: MouseRegion(
                cursor: linking
                    ? SystemMouseCursors.precise
                    : MouseCursor.defer,
                onHover: (e) {
                  if (editor.linkingFrom != null) {
                    _hover.value = toScene(e.localPosition);
                  }
                },
                child: GestureDetector(
                  onTapDown: (_) {
                    widget.focusNode.requestFocus();
                    if (editor.editingId != null) {
                      FocusManager.instance.primaryFocus?.unfocus();
                    }
                  },
                  onTap: () {
                    if (editor.linkingFrom != null) {
                      editor.cancelRelation();
                    } else {
                      editor.select(null);
                    }
                  },
                  onDoubleTapDown: (d) {
                    final scene = toScene(d.localPosition);
                    editor.addFloating(scene);
                  },
                  onDoubleTap: () {},
                  onSecondaryTapDown: (d) => widget.onContextMenu(
                    d.globalPosition,
                    null,
                    toScene(d.localPosition),
                  ),
                  child: InteractiveViewer(
                    transformationController: _transform,
                    constrained: false,
                    minScale: 0.1,
                    maxScale: 3,
                    boundaryMargin: const EdgeInsets.all(2000),
                    child: CaptureBoundary(
                      key: _boundaryKey,
                      child: SizedBox(
                        width: kCanvasSize,
                        height: kCanvasSize,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (_capturing)
                              Positioned.fill(child: ColoredBox(color: bg)),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _EdgesPainter(
                                  doc: doc,
                                  sizes: editor.sizes,
                                  visibleIds: visibleIds,
                                  fallback: theme.colorScheme.primary,
                                  textColor: onBg,
                                ),
                              ),
                            ),
                            ...nodeWidgets,
                            ...toggles,
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _RelationsPainter(
                                    doc: doc,
                                    sizes: editor.sizes,
                                    visibleIds: visibleIds,
                                    labelBg: bg,
                                    linkingFrom: editor.linkingFrom,
                                    hover: _hover,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.selectionToolbar != null &&
                editor.selectedId != null &&
                _draggingId == null &&
                !linking)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _transform,
                  builder: (context, _) => _toolbarOverlay(context, visibleIds),
                ),
              ),
            if (widget.showMinimap && visible.length > 1)
              Positioned(
                right: 12,
                bottom: 12,
                child: _Minimap(
                  doc: doc,
                  editor: editor,
                  transform: _transform,
                  viewport: () => _viewport,
                  onJump: (scene) => _setView(scene, scale.value),
                ),
              ),
            if (_fileDrag)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.06),
                      border: Border.all(
                        color: theme.colorScheme.primary,
                        width: 3,
                      ),
                    ),
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Material(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          _fileDragNode == null
                              ? 'Solte para criar um tópico com os arquivos'
                              : 'Solte para adicionar ao tópico “${doc.nodes[_fileDragNode]?.text ?? ''}”',
                          style: TextStyle(color: theme.colorScheme.onPrimary),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toolbarOverlay(BuildContext context, Set<String> visibleIds) {
    final n = doc.nodes[editor.selectedId];
    if (n == null || !visibleIds.contains(n.id)) {
      return const SizedBox.shrink();
    }
    final s = editor.sizes[n.id] ?? estimateNodeSize(n);
    final m = _transform.value;
    final top = MatrixUtils.transformPoint(
      m,
      n.pos + kOrigin - Offset(0, s.height / 2),
    );
    final bottom = MatrixUtils.transformPoint(
      m,
      n.pos + kOrigin + Offset(0, s.height / 2),
    );
    return CustomSingleChildLayout(
      delegate: _ToolbarLayout(top, bottom),
      child: widget.selectionToolbar!(context),
    );
  }
}

/// Posiciona a barra flutuante acima do tópico (ou abaixo, se não couber).
class _ToolbarLayout extends SingleChildLayoutDelegate {
  _ToolbarLayout(this.top, this.bottom);
  final Offset top;
  final Offset bottom;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) =>
      BoxConstraints.loose(Size(math.max(0.0, c.maxWidth - 16), c.maxHeight));

  @override
  Offset getPositionForChild(Size size, Size child) {
    var y = top.dy - child.height - 14;
    if (y < 8) y = bottom.dy + 14;
    y = y.clamp(8.0, math.max(8.0, size.height - child.height - 8)).toDouble();
    final x = (top.dx - child.width / 2)
        .clamp(8.0, math.max(8.0, size.width - child.width - 8))
        .toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _ToolbarLayout old) =>
      old.top != top || old.bottom != bottom;
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({
    required this.collapsed,
    required this.count,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final bool collapsed;
  final int count;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: collapsed ? 'Expandir ($count)' : 'Recolher',
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: collapsed ? color : background,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            child: collapsed
                ? Text(
                    count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                      fontSize: 9,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                : Container(width: 8, height: 1.6, color: color),
          ),
        ),
      ),
    );
  }
}

class _EdgesPainter extends CustomPainter {
  _EdgesPainter({
    required this.doc,
    required this.sizes,
    required this.visibleIds,
    required this.fallback,
    required this.textColor,
  });

  final MindMapDoc doc;
  final Map<String, Size> sizes;
  final Set<String> visibleIds;
  final Color fallback;
  final Color textColor;

  Size _size(MindMapNode n) => sizes[n.id] ?? estimateNodeSize(n);

  static bool _low(MindMapNode n) =>
      n.shape == 'underline' || n.shape == 'plain';

  Rect _rect(MindMapNode n) {
    final s = _size(n);
    return Rect.fromCenter(
      center: n.pos + kOrigin,
      width: s.width,
      height: s.height,
    );
  }

  /// Retângulo que envolve o nó e todos os descendentes visíveis.
  Rect _subtreeRect(String id, {bool includeSelf = true}) {
    Rect? r = includeSelf ? _rect(doc.nodes[id]!) : null;
    void walk(String i) {
      for (final c in doc.nodes[i]!.childrenIds) {
        if (!visibleIds.contains(c)) continue;
        final cr = _rect(doc.nodes[c]!);
        r = r == null ? cr : r!.expandToInclude(cr);
        walk(c);
      }
    }

    walk(id);
    return r ?? _rect(doc.nodes[id]!);
  }

  void _label(
    Canvas canvas,
    String text,
    Offset at,
    Color color, {
    Alignment anchor = Alignment.center,
    Color? bg,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 260);
    final box = Rect.fromLTWH(
      at.dx - (anchor.x + 1) / 2 * (tp.width + 14),
      at.dy - (anchor.y + 1) / 2 * (tp.height + 6),
      tp.width + 14,
      tp.height + 6,
    );
    if (bg != null) {
      final rr = RRect.fromRectAndRadius(box, const Radius.circular(8));
      canvas.drawRRect(rr, Paint()..color = bg);
      canvas.drawRRect(
        rr,
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    tp.paint(canvas, box.topLeft + const Offset(7, 3));
  }

  void _dashedRRect(Canvas canvas, RRect rr, Paint p) {
    final path = Path()..addRRect(rr);
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 9, m.length)), p);
        d += 15;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Limites (contornos de ramos) ficam atrás de tudo.
    for (final id in visibleIds) {
      final n = doc.nodes[id]!;
      if (!n.boundary) continue;
      final color = parseHex(n.color) ?? fallback;
      final r = _subtreeRect(id).inflate(14);
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(18));
      canvas.drawRRect(rr, Paint()..color = color.withValues(alpha: 0.07));
      _dashedRRect(
        canvas,
        rr,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );
      if (n.boundaryLabel.trim().isNotEmpty) {
        _label(
          canvas,
          n.boundaryLabel,
          Offset(r.left + 12, r.top),
          color,
          anchor: Alignment.bottomLeft,
        );
      }
    }

    // Eixo da espinha de peixe.
    if (doc.layout == 'fishbone') {
      final root = doc.root;
      final mains = root.childrenIds
          .where(visibleIds.contains)
          .map((c) => doc.nodes[c]!)
          .toList();
      if (mains.isNotEmpty) {
        final minX = mains
            .map((m) => fishboneJoint(doc, m).dx)
            .reduce(math.min);
        final a =
            kOrigin + Offset(root.pos.dx - _size(root).width / 2, root.pos.dy);
        final b = kOrigin + Offset(minX - 30, root.pos.dy);
        canvas.drawLine(
          a,
          b,
          paint
            ..color = parseHex(root.color) ?? fallback
            ..strokeWidth = doc.connectorWidth + 1.5,
        );
      }
    }
    // Eixo da linha do tempo.
    if (doc.layout == 'timeline') {
      final root = doc.root;
      final mains = root.childrenIds
          .where(visibleIds.contains)
          .map((c) => doc.nodes[c]!)
          .toList();
      if (mains.isNotEmpty) {
        final maxX = mains.map((m) => _rect(m).right).reduce(math.max);
        final a =
            kOrigin + Offset(root.pos.dx + _size(root).width / 2, root.pos.dy);
        final b = Offset(maxX + 30, root.pos.dy + kOrigin.dy);
        final color = parseHex(root.color) ?? fallback;
        canvas.drawLine(
          a,
          b,
          paint
            ..color = color
            ..strokeWidth = doc.connectorWidth + 1,
        );
        final head = Path()
          ..moveTo(b.dx + 10, b.dy)
          ..lineTo(b.dx - 2, b.dy - 7)
          ..lineTo(b.dx - 2, b.dy + 7)
          ..close();
        canvas.drawPath(head, Paint()..color = color);
      }
    }

    for (final id in visibleIds) {
      final n = doc.nodes[id]!;
      final parent = n.parentId == null ? null : doc.nodes[n.parentId];
      if (parent == null) continue;

      final kind = edgeKind(doc, parent, n);
      final depth = doc.depthOf(n.id);
      paint
        ..color = parseHex(n.color) ?? fallback
        ..strokeWidth = math.max(1.2, doc.connectorWidth - (depth - 1) * 0.6);
      final pr = _rect(parent), cr = _rect(n);
      final path = Path();

      switch (kind) {
        case 'v':
          final down = n.pos.dy >= parent.pos.dy;
          final a = down ? pr.bottomCenter : pr.topCenter;
          final b = down ? cr.topCenter : cr.bottomCenter;
          final midY = (a.dy + b.dy) / 2;
          path
            ..moveTo(a.dx, a.dy)
            ..lineTo(a.dx, midY);
          if (doc.connectorStyle == 'curved') {
            path.cubicTo(
              a.dx,
              midY + (b.dy - midY) * 0.5,
              b.dx,
              midY,
              b.dx,
              b.dy,
            );
          } else {
            path
              ..lineTo(b.dx, midY)
              ..lineTo(b.dx, b.dy);
          }
        case 'tree':
          final down = n.pos.dy >= parent.pos.dy;
          final x = pr.left + 16;
          final a = Offset(x, down ? pr.bottom : pr.top);
          final b = Offset(cr.left, cr.center.dy);
          final r = math.min(8.0, (b.dy - a.dy).abs() / 2);
          final dy = down ? 1.0 : -1.0;
          path
            ..moveTo(a.dx, a.dy)
            ..lineTo(x, b.dy - dy * r)
            ..quadraticBezierTo(x, b.dy, x + r, b.dy)
            ..lineTo(b.dx, b.dy);
        case 'axis':
          final a = Offset(cr.center.dx, parent.pos.dy + kOrigin.dy);
          final b = n.pos.dy >= parent.pos.dy ? cr.topCenter : cr.bottomCenter;
          canvas.drawCircle(a, 5, Paint()..color = paint.color);
          path
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy);
        case 'bone':
          final joint = fishboneJoint(doc, n) + kOrigin;
          final b = n.pos.dy < parent.pos.dy ? cr.bottomCenter : cr.topCenter;
          path
            ..moveTo(joint.dx, joint.dy)
            ..lineTo(b.dx, b.dy);
        case 'rib':
          // Liga o subtópico à espinha diagonal do tópico principal.
          final joint = fishboneJoint(doc, parent) + kOrigin;
          final top = parent.pos.dy < doc.root.pos.dy
              ? pr.bottomCenter
              : pr.topCenter;
          final y = cr.center.dy;
          final t = ((y - top.dy) / (joint.dy - top.dy)).clamp(0.0, 1.0);
          final bx = top.dx + (joint.dx - top.dx) * t;
          path
            ..moveTo(cr.right, y)
            ..lineTo(bx, y);
        default:
          final side = n.pos.dx >= parent.pos.dx ? 1.0 : -1.0;
          final start = Offset(
            side > 0 ? pr.right : pr.left,
            parent.pos.dy + kOrigin.dy + (_low(parent) ? pr.height / 2 : 0),
          );
          final end = Offset(
            side > 0 ? cr.left : cr.right,
            n.pos.dy + kOrigin.dy + (_low(n) ? cr.height / 2 : 0),
          );
          path.moveTo(start.dx, start.dy);
          final style = kind == 'elbow' ? 'elbow' : doc.connectorStyle;
          switch (style) {
            case 'straight':
              path.lineTo(end.dx, end.dy);
            case 'elbow':
              final midX = start.dx + (end.dx - start.dx) / 2;
              final r = math.min(12.0, (end.dy - start.dy).abs() / 2);
              final dy = end.dy > start.dy ? 1.0 : -1.0;
              path.lineTo(midX - side * r, start.dy);
              path.quadraticBezierTo(midX, start.dy, midX, start.dy + dy * r);
              path.lineTo(midX, end.dy - dy * r);
              path.quadraticBezierTo(midX, end.dy, midX + side * r, end.dy);
              path.lineTo(end.dx, end.dy);
            default:
              final dx = (end.dx - start.dx) * 0.5;
              path.cubicTo(
                start.dx + dx,
                start.dy,
                end.dx - dx,
                end.dy,
                end.dx,
                end.dy,
              );
          }
      }
      canvas.drawPath(path, paint);
    }

    // Resumos: chave ao lado de todos os subtópicos, com o texto.
    for (final id in visibleIds) {
      final n = doc.nodes[id]!;
      final text = n.summary;
      if (text == null) continue;
      final kids = n.childrenIds.where(visibleIds.contains).toList();
      if (kids.isEmpty) continue;
      final color = parseHex(n.color) ?? fallback;
      final r = _subtreeRect(id, includeSelf: false);
      final p = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final vertical = doc.layout == 'org';
      if (vertical) {
        final y = r.bottom + 12;
        final brace = Path()
          ..moveTo(r.left, y)
          ..quadraticBezierTo(r.left, y + 10, r.left + 12, y + 10)
          ..lineTo(r.center.dx - 10, y + 10)
          ..quadraticBezierTo(r.center.dx, y + 10, r.center.dx, y + 20)
          ..quadraticBezierTo(r.center.dx, y + 10, r.center.dx + 10, y + 10)
          ..lineTo(r.right - 12, y + 10)
          ..quadraticBezierTo(r.right, y + 10, r.right, y);
        canvas.drawPath(brace, p);
        _label(
          canvas,
          text.isEmpty ? 'Resumo' : text,
          Offset(r.center.dx, y + 26),
          color,
          anchor: Alignment.topCenter,
          bg: textColor.computeLuminance() > 0.5
              ? const Color(0xFF1B1B24)
              : Colors.white,
        );
      } else {
        final right = n.pos.dx <= (doc.nodes[kids.first]!.pos.dx);
        final x = right ? r.right + 12 : r.left - 12;
        final d = right ? 1.0 : -1.0;
        final brace = Path()
          ..moveTo(x, r.top)
          ..quadraticBezierTo(x + d * 10, r.top, x + d * 10, r.top + 12)
          ..lineTo(x + d * 10, r.center.dy - 10)
          ..quadraticBezierTo(x + d * 10, r.center.dy, x + d * 20, r.center.dy)
          ..quadraticBezierTo(
            x + d * 10,
            r.center.dy,
            x + d * 10,
            r.center.dy + 10,
          )
          ..lineTo(x + d * 10, r.bottom - 12)
          ..quadraticBezierTo(x + d * 10, r.bottom, x, r.bottom);
        canvas.drawPath(brace, p);
        _label(
          canvas,
          text.isEmpty ? 'Resumo' : text,
          Offset(x + d * 26, r.center.dy),
          color,
          anchor: right ? Alignment.centerLeft : Alignment.centerRight,
          bg: textColor.computeLuminance() > 0.5
              ? const Color(0xFF1B1B24)
              : Colors.white,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) => true;
}

/// Miniatura do mapa com a área visível; clique ou arraste para navegar.
class _Minimap extends StatelessWidget {
  const _Minimap({
    required this.doc,
    required this.editor,
    required this.transform,
    required this.viewport,
    required this.onJump,
  });

  final MindMapDoc doc;
  final EditorController editor;
  final TransformationController transform;
  final Size Function() viewport;
  final ValueChanged<Offset> onJump;

  static const size = Size(180, 118);

  (Rect, double, Offset) _frame() {
    Rect? b;
    for (final n in editor.visibleNodes()) {
      final s = editor.sizes[n.id] ?? estimateNodeSize(n);
      final r = Rect.fromCenter(
        center: n.pos,
        width: s.width,
        height: s.height,
      );
      b = b == null ? r : b.expandToInclude(r);
    }
    final bounds = (b ?? Rect.zero).inflate(60);
    final sc = math.min(size.width / bounds.width, size.height / bounds.height);
    final off = size.center(Offset.zero) - bounds.center * sc;
    return (bounds, sc, off);
  }

  void _jump(Offset local) {
    final (_, sc, off) = _frame();
    onJump((local - off) / sc);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      color: cs.surface.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        onTapDown: (d) => _jump(d.localPosition),
        onPanUpdate: (d) => _jump(d.localPosition),
        child: AnimatedBuilder(
          animation: transform,
          builder: (context, _) {
            final (_, sc, off) = _frame();
            final m = transform.value;
            final inv = Matrix4.inverted(m);
            final vp = viewport();
            final tl = MatrixUtils.transformPoint(inv, Offset.zero) - kOrigin;
            final br =
                MatrixUtils.transformPoint(inv, Offset(vp.width, vp.height)) -
                kOrigin;
            return CustomPaint(
              size: size,
              painter: _MinimapPainter(
                doc: doc,
                editor: editor,
                scale: sc,
                offset: off,
                view: Rect.fromPoints(tl, br),
                accent: cs.primary,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.doc,
    required this.editor,
    required this.scale,
    required this.offset,
    required this.view,
    required this.accent,
  });

  final MindMapDoc doc;
  final EditorController editor;
  final double scale;
  final Offset offset;
  final Rect view;
  final Color accent;

  Offset _t(Offset p) => p * scale + offset;

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final nodes = editor.visibleNodes().toList();
    for (final n in nodes) {
      final p = n.parentId == null ? null : doc.nodes[n.parentId];
      if (p == null) continue;
      line.color = (parseHex(n.color) ?? accent).withValues(alpha: 0.7);
      canvas.drawLine(_t(p.pos), _t(n.pos), line);
    }
    for (final n in nodes) {
      final s = editor.sizes[n.id] ?? estimateNodeSize(n);
      final r = Rect.fromCenter(
        center: _t(n.pos),
        width: math.max(3, s.width * scale),
        height: math.max(2, s.height * scale),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        Paint()
          ..color =
              parseHex(n.id == doc.rootId ? n.fillColor : n.color) ?? accent,
      );
    }
    final v = Rect.fromPoints(_t(view.topLeft), _t(view.bottomRight));
    canvas.drawRect(v, Paint()..color = accent.withValues(alpha: 0.12));
    canvas.drawRect(
      v,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) => true;
}

/// Setas tracejadas das relações entre tópicos.
class _RelationsPainter extends CustomPainter {
  _RelationsPainter({
    required this.doc,
    required this.sizes,
    required this.visibleIds,
    required this.labelBg,
    required this.linkingFrom,
    required this.hover,
  }) : super(repaint: hover);

  final MindMapDoc doc;
  final Map<String, Size> sizes;
  final Set<String> visibleIds;
  final Color labelBg;
  final String? linkingFrom;
  final ValueNotifier<Offset?> hover;

  static const _defaultColor = Color(0xFF8E7CC3);

  Rect _rect(String id) {
    final n = doc.nodes[id]!;
    final s = sizes[id] ?? estimateNodeSize(n);
    return Rect.fromCenter(
      center: n.pos + kOrigin,
      width: s.width,
      height: s.height,
    );
  }

  /// Ponto da borda de [r] na direção de [toward].
  static Offset _edge(Rect r, Offset toward) {
    final c = r.center;
    final d = toward - c;
    if (d.distance < 1) return c;
    final sx = d.dx.abs() < 1e-6 ? double.infinity : (r.width / 2) / d.dx.abs();
    final sy = d.dy.abs() < 1e-6
        ? double.infinity
        : (r.height / 2) / d.dy.abs();
    final t = math.min(math.min(sx, sy), 1.0);
    return c + d * t;
  }

  static void _arrow(Canvas canvas, Offset from, Offset tip, Color color) {
    final d = tip - from;
    if (d.distance < 0.1) return;
    final u = d / d.distance;
    final n = Offset(-u.dy, u.dx);
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(tip.dx - u.dx * 11 + n.dx * 5.5, tip.dy - u.dy * 11 + n.dy * 5.5)
      ..lineTo(tip.dx - u.dx * 11 - n.dx * 5.5, tip.dy - u.dy * 11 - n.dy * 5.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  static void _dashed(Canvas canvas, Path path, Paint p) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 8, m.length)), p);
        d += 13;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final r in doc.relations) {
      if (!visibleIds.contains(r.from) || !visibleIds.contains(r.to)) continue;
      final a = _rect(r.from), b = _rect(r.to);
      final mid = (a.center + b.center) / 2;
      final d = b.center - a.center;
      final ctrl = mid + Offset(-d.dy, d.dx) * 0.22 + const Offset(0, -30);
      final start = _edge(a.inflate(4), ctrl);
      final end = _edge(b.inflate(6), ctrl);
      final c1 = start + (ctrl - start) * 0.9;
      final c2 = end + (ctrl - end) * 0.9;
      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
      final color = parseHex(r.color) ?? _defaultColor;
      p.color = color;
      _dashed(canvas, path, p);
      _arrow(canvas, c2, end, color);

      if (r.label.trim().isNotEmpty) {
        final metric = path.computeMetrics().firstOrNull;
        final at =
            metric?.getTangentForOffset(metric.length / 2)?.position ?? ctrl;
        final tp = TextPainter(
          text: TextSpan(
            text: r.label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: 220);
        final box = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: at,
            width: tp.width + 14,
            height: tp.height + 6,
          ),
          const Radius.circular(8),
        );
        canvas.drawRRect(box, Paint()..color = labelBg);
        canvas.drawRRect(
          box,
          Paint()
            ..color = color.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke,
        );
        tp.paint(canvas, box.outerRect.topLeft + const Offset(7, 3));
      }
    }

    // Prévia enquanto o usuário escolhe o destino.
    final from = linkingFrom;
    final h = hover.value;
    if (from != null && h != null && doc.nodes.containsKey(from)) {
      final end = h + kOrigin;
      final start = _edge(_rect(from).inflate(4), end);
      p.color = _defaultColor;
      _dashed(
        canvas,
        Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy),
        p,
      );
      _arrow(canvas, start, end, _defaultColor);
    }
  }

  @override
  bool shouldRepaint(covariant _RelationsPainter old) => true;
}

/// Grade de pontos no fundo (desenhada em coordenadas de tela).
class _GridPainter extends CustomPainter {
  _GridPainter({required this.transform, required this.color})
    : super(repaint: transform);

  final TransformationController transform;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final m = transform.value;
    final s = m.getMaxScaleOnAxis();
    var step = 32.0 * s;
    while (step < 14) {
      step *= 2;
    }
    final t = m.getTranslation();
    final ox = t.x % step, oy = t.y % step;
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final pts = <Offset>[];
    for (var x = ox; x < size.width; x += step) {
      for (var y = oy; y < size.height; y += step) {
        pts.add(Offset(x, y));
      }
    }
    canvas.drawPoints(PointMode.points, pts, p);
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}
