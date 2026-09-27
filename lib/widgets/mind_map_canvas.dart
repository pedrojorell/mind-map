import 'dart:ui' show PointMode;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
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
  });

  final EditorController editor;
  final FocusNode focusNode;

  /// Menu de contexto (clique direito) em [globalPos]; [nodeId] nulo = fundo.
  final void Function(Offset globalPos, String? nodeId, Offset scenePos)
      onContextMenu;
  final ValueChanged<String> onMessage;

  /// Nível de zoom atual (atualizado pelo canvas).
  final ValueNotifier<double> scale;

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

  EditorController get editor => widget.editor;
  MindMapDoc get doc => editor.doc;

  @override
  void initState() {
    super.initState();
    _transform.addListener(() => scale.value = _transform.value.getMaxScaleOnAxis());
    WidgetsBinding.instance.addPostFrameCallback((_) => fitToScreen(maxScale: 1));
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Size get _viewport =>
      (context.findRenderObject() as RenderBox?)?.size ?? const Size(800, 600);

  Offset toScene(Offset local) {
    final inv = Matrix4.inverted(_transform.value);
    final v = inv.transform3(vm.Vector3(local.dx, local.dy, 0));
    return Offset(v.x, v.y) - kOrigin;
  }

  Offset get viewportCenterScene =>
      toScene(_viewport.center(Offset.zero));

  void _setView(Offset sceneCenter, double s) {
    final vp = _viewport;
    final p = sceneCenter + kOrigin;
    _transform.value = Matrix4.identity()
      ..translateByDouble(vp.width / 2 - p.dx * s, vp.height / 2 - p.dy * s, 0, 1)
      ..scaleByDouble(s, s, 1, 1);
  }

  Rect contentBounds({double margin = 0}) {
    Rect? r;
    for (final n in doc.visibleNodes()) {
      final s = editor.sizes[n.id] ?? estimateNodeSize(n);
      final nr = Rect.fromCenter(center: n.pos, width: s.width, height: s.height);
      r = r == null ? nr : r.expandToInclude(nr);
    }
    return (r ?? Rect.fromCenter(center: Offset.zero, width: 200, height: 80))
        .inflate(margin);
  }

  void fitToScreen({double maxScale = 1.5}) {
    if (!mounted) return;
    final b = contentBounds(margin: 60);
    final vp = _viewport;
    final s = math.min(vp.width / b.width, vp.height / b.height)
        .clamp(0.1, maxScale)
        .toDouble();
    _setView(b.center, s);
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
    if (vp.deflate(20).contains(p - half) && vp.deflate(20).contains(p + half)) {
      return;
    }
    centerOn(id);
  }

  void zoomBy(double factor) {
    final c = viewportCenterScene;
    final s = (scale.value * factor).clamp(0.1, 3.0).toDouble();
    _setView(c, s);
  }

  void resetZoom() => _setView(viewportCenterScene, 1);

  Future<Uint8List?> capturePng() async {
    final ro = _boundaryKey.currentContext?.findRenderObject();
    if (ro is! RenderCaptureBoundary) return null;
    final b = contentBounds(margin: 40).shift(kOrigin);
    final pixels = b.width * b.height;
    // Limita a resolução em mapas enormes.
    final ratio = math.min(2.0, math.sqrt(40e6 / pixels));
    return ro.capturePng(b, pixelRatio: ratio);
  }

  // ------------------------------------------------------------- arrastar

  void _onDragStart(String id, Offset global) {
    if (editor.editingId == id) return;
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
      widget.onMessage('Tópico movido para “${doc.nodes[target]?.text ?? ''}”.');
    } else if (turnedOff) {
      widget.onMessage(
          'Posição livre: organização automática desativada (reative em Exibir).');
    }
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;
    final visible = doc.visibleNodes().toList();

    final nodeWidgets = <Widget>[];
    final toggles = <Widget>[];
    for (final n in visible) {
      final isRoot = n.id == doc.rootId;
      final p = n.pos + kOrigin;
      nodeWidgets.add(Positioned(
        key: ValueKey(n.id),
        left: p.dx,
        top: p.dy,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: MeasureSize(
            onChange: (s) => editor.reportSize(n.id, s),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) {
                widget.focusNode.requestFocus();
                editor.select(n.id);
              },
              onDoubleTap: () => editor.startEditing(n.id),
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
                selected: editor.selectedId == n.id,
                editing: editor.editingId == n.id,
                selectAllOnEdit: editor.editingSelectAll,
                initialText: editor.editingId == n.id
                    ? editor.editingInitialText
                    : null,
                dropTarget: _dropTarget == n.id,
                onCommit: (text) {
                  editor.commitEditing(text);
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
      ));

      // Botão de recolher/expandir ramos.
      final size = editor.sizes[n.id];
      if (n.childrenIds.isNotEmpty && size != null && !isRoot) {
        final side = sideOf(doc, n);
        final c = p + Offset(side * (size.width / 2 + 11), n.shape == 'underline' ? size.height / 2 : 0);
        toggles.add(Positioned(
          key: ValueKey('t_${n.id}'),
          left: c.dx - 9,
          top: c.dy - 9,
          child: _CollapseToggle(
            collapsed: n.collapsed,
            count: doc.subtreeIds(n.id).length - 1,
            color: parseHex(n.color) ?? theme.colorScheme.primary,
            onTap: () => editor.toggleCollapse(n.id),
          ),
        ));
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _GridPainter(
              transform: _transform,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            onTapDown: (_) {
              widget.focusNode.requestFocus();
              if (editor.editingId != null) {
                FocusManager.instance.primaryFocus?.unfocus();
              }
            },
            onTap: () => editor.select(null),
            onDoubleTapDown: (d) {
              final scene = toScene(d.localPosition);
              editor.addFloating(scene);
            },
            onDoubleTap: () {},
            onSecondaryTapDown: (d) => widget.onContextMenu(
                d.globalPosition, null, toScene(d.localPosition)),
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
                      Positioned.fill(child: ColoredBox(color: bg)),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _EdgesPainter(
                            doc: doc,
                            sizes: editor.sizes,
                            visibleIds: visible.map((n) => n.id).toSet(),
                            fallback: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      ...nodeWidgets,
                      ...toggles,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CollapseToggle extends StatelessWidget {
  const _CollapseToggle({
    required this.collapsed,
    required this.count,
    required this.color,
    required this.onTap,
  });

  final bool collapsed;
  final int count;
  final Color color;
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
              color: collapsed ? color : Theme.of(context).scaffoldBackgroundColor,
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            child: collapsed
                ? Text(count > 99 ? '99+' : '$count',
                    style: const TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w700))
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
  });

  final MindMapDoc doc;
  final Map<String, Size> sizes;
  final Set<String> visibleIds;
  final Color fallback;

  Size _size(MindMapNode n) => sizes[n.id] ?? estimateNodeSize(n);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final id in visibleIds) {
      final n = doc.nodes[id]!;
      final parent = n.parentId == null ? null : doc.nodes[n.parentId];
      if (parent == null) continue;

      final side = n.pos.dx >= parent.pos.dx ? 1.0 : -1.0;
      final ps = _size(parent), cs = _size(n);
      final pUnder = parent.shape == 'underline';
      final cUnder = n.shape == 'underline';

      final start = kOrigin +
          Offset(parent.pos.dx + side * ps.width / 2,
              parent.pos.dy + (pUnder ? ps.height / 2 : 0));
      final end = kOrigin +
          Offset(n.pos.dx - side * cs.width / 2,
              n.pos.dy + (cUnder ? cs.height / 2 : 0));

      final depth = doc.depthOf(n.id);
      paint
        ..color = parseHex(n.color) ?? fallback
        ..strokeWidth = math.max(1.2, doc.connectorWidth - (depth - 1) * 0.6);

      final path = Path()..moveTo(start.dx, start.dy);
      switch (doc.connectorStyle) {
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
          path.cubicTo(start.dx + dx, start.dy, end.dx - dx, end.dy, end.dx, end.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgesPainter oldDelegate) => true;
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
