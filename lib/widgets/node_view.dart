import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../media.dart';
import '../models.dart';
import 'markers.dart';
import 'render_helpers.dart';

/// Cores efetivas (com valores automáticos) de um nó.
class NodeColors {
  NodeColors(this.branch, this.fill, this.text);
  final Color branch;
  final Color fill;
  final Color text;

  static NodeColors of(BuildContext context, MindMapNode n) {
    final cs = Theme.of(context).colorScheme;
    // O canvas define scaffoldBackgroundColor como a cor de fundo do mapa.
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final branch = parseHex(n.color) ?? cs.primary;
    final Color fill;
    if (n.shape == 'underline' || n.shape == 'plain') {
      fill = parseHex(n.fillColor) ?? Colors.transparent;
    } else {
      fill =
          parseHex(n.fillColor) ??
          Color.alphaBlend(branch.withValues(alpha: 0.16), bg);
    }
    final bgForContrast = fill.a < 0.3 ? bg : fill;
    final autoText = bgForContrast.computeLuminance() > 0.5
        ? const Color(0xFF15171F)
        : Colors.white;
    return NodeColors(branch, fill, parseHex(n.textColor) ?? autoText);
  }
}

ShapeBorder shapeFor(String shape) {
  switch (shape) {
    case 'rounded':
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    case 'rect':
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(3));
    case 'ellipse':
      return const OvalBorder();
    case 'hexagon':
      return BeveledRectangleBorder(borderRadius: BorderRadius.circular(18));
    case 'underline':
      return const RoundedRectangleBorder();
    case 'plain':
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    default:
      return const StadiumBorder();
  }
}

class NodeView extends StatefulWidget {
  const NodeView({
    super.key,
    required this.node,
    required this.selected,
    required this.editing,
    required this.selectAllOnEdit,
    this.initialText,
    required this.dropTarget,
    required this.isRoot,
    required this.onCommit,
    required this.onCancel,
    this.number = '',
    this.onBadgeTap,
  });

  final MindMapNode node;
  final bool selected;
  final bool editing;
  final bool selectAllOnEdit;
  final String? initialText;
  final bool dropTarget;
  final bool isRoot;
  final ValueChanged<String> onCommit;
  final VoidCallback onCancel;

  /// Numeração exibida antes do texto (vazio = sem número).
  final String number;

  /// Clique num ícone do tópico: 'links', 'files' ou 'note'.
  final void Function(String kind, Offset globalPos)? onBadgeTap;

  @override
  State<NodeView> createState() => _NodeViewState();
}

class _NodeViewState extends State<NodeView> {
  TextEditingController? _text;
  FocusNode? _focus;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing) _beginEdit();
  }

  @override
  void didUpdateWidget(covariant NodeView old) {
    super.didUpdateWidget(old);
    if (widget.editing && !old.editing) _beginEdit();
    if (!widget.editing && old.editing) _endEdit();
  }

  void _beginEdit() {
    _finished = false;
    final initial = widget.initialText ?? widget.node.text;
    _text = TextEditingController(text: initial);
    _text!.selection = widget.selectAllOnEdit && widget.initialText == null
        ? TextSelection(baseOffset: 0, extentOffset: initial.length)
        : TextSelection.collapsed(offset: initial.length);
    _focus = FocusNode(onKeyEvent: _onKey);
    _focus!.addListener(() {
      if (!(_focus?.hasFocus ?? true)) _commit();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus?.requestFocus());
  }

  void _endEdit() {
    final t = _text, f = _focus;
    _text = null;
    _focus = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      t?.dispose();
      f?.dispose();
    });
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final shift = HardwareKeyboard.instance.isShiftPressed;
    if ((e.logicalKey == LogicalKeyboardKey.enter ||
            e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
        !shift) {
      _commit();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      _finished = true;
      widget.onCancel();
      return KeyEventResult.handled;
    }
    if (e.logicalKey == LogicalKeyboardKey.tab) {
      _commit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _commit() {
    if (_finished || _text == null) return;
    _finished = true;
    final v = _text!.text.trim();
    widget.onCommit(v.isEmpty ? widget.node.text : v);
  }

  @override
  void dispose() {
    _text?.dispose();
    _focus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.node;
    final cs = Theme.of(context).colorScheme;
    final colors = NodeColors.of(context, n);
    final style = TextStyle(
      fontSize: n.fontSize,
      height: 1.25,
      fontWeight: n.bold ? FontWeight.w700 : FontWeight.w500,
      fontStyle: n.italic ? FontStyle.italic : FontStyle.normal,
      color: colors.text,
      decoration: TextDecoration.combine([
        if (n.underline) TextDecoration.underline,
        if (n.strike) TextDecoration.lineThrough,
      ]),
      decorationColor: colors.text,
    );
    final textAlign = switch (n.align) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final maxW = n.maxWidth.clamp(80.0, 800.0);

    final Widget label = widget.editing && _text != null
        ? IntrinsicWidth(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: 40, maxWidth: maxW),
              child: TextField(
                controller: _text,
                focusNode: _focus,
                style: style,
                maxLines: null,
                cursorColor: colors.text,
                textAlign: textAlign,
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          )
        : ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW),
            child: Text(
              n.text.isEmpty ? ' ' : n.text,
              style: style,
              textAlign: textAlign,
            ),
          );

    Widget badge(String kind, IconData icon, int count, String tip) {
      final child = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: colors.text),
          if (count > 1)
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                color: colors.text,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      );
      if (widget.onBadgeTap == null) return child;
      return Tooltip(
        message: tip,
        waitDuration: const Duration(milliseconds: 400),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => widget.onBadgeTap!(kind, d.globalPosition),
            child: Padding(padding: const EdgeInsets.all(2), child: child),
          ),
        ),
      );
    }

    final links = n.links.where((l) => l.url.trim().isNotEmpty).toList();
    final badges = <Widget>[
      if (n.note.trim().isNotEmpty)
        badge('note', Icons.sticky_note_2_outlined, 1, 'Anotação'),
      if (links.isNotEmpty)
        badge(
          'links',
          links.length == 1 ? linkIcon(links.first.kind) : Icons.link,
          links.length,
          links.length == 1 ? 'Abrir ${links.first.label}' : 'Links',
        ),
      if (n.attachments.isNotEmpty)
        badge('files', Icons.attach_file, n.attachments.length, 'Documentos'),
      if (n.comments.isNotEmpty)
        badge(
          'comments',
          Icons.chat_bubble_outline,
          n.comments.length,
          'Comentários',
        ),
    ];

    final markerSize = (n.fontSize * 1.05).clamp(14.0, 30.0);
    Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final m in n.markers) ...[
          MarkerIcon.fromString(m, size: markerSize),
          const SizedBox(width: 5),
        ],
        if (n.markers.isNotEmpty) const SizedBox(width: 2),
        if (widget.number.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              widget.number,
              style: style.copyWith(
                fontWeight: FontWeight.w800,
                color: colors.text.withValues(alpha: 0.75),
              ),
            ),
          ),
        label,
        for (final b in badges) ...[const SizedBox(width: 6), b],
      ],
    );
    final extras = <Widget>[
      if (n.formula != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Math.tex(
            n.formula!,
            textStyle: TextStyle(fontSize: n.fontSize + 2, color: colors.text),
            onErrorFallback: (e) => Text(
              'Fórmula inválida',
              style: TextStyle(
                fontSize: 12,
                color: colors.text.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      if (n.table != null && n.table!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _NodeTable(
            rows: n.table!,
            color: colors.branch,
            text: colors.text,
          ),
        ),
      if (n.task != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: _TaskStrip(
            task: n.task!,
            color: colors.branch,
            text: colors.text,
          ),
        ),
    ];
    if (extras.isNotEmpty) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [content, ...extras],
      );
    }
    if (n.tags.isNotEmpty) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                for (final t in n.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.branch.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colors.branch.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      t,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        color: colors.text,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }
    final img = n.image;
    if (n.sticker != null || img != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (img != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  imageBytes(img.data),
                  width: img.width,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => Icon(
                    Icons.broken_image_outlined,
                    size: 40,
                    color: colors.text,
                  ),
                ),
              ),
            ),
          if (n.sticker != null) ...[
            Text(
              n.sticker!,
              style: TextStyle(fontSize: (n.fontSize * 2).clamp(28.0, 64.0)),
            ),
            const SizedBox(height: 2),
          ],
          content,
        ],
      );
    }

    final isUnderline = n.shape == 'underline';
    final isPlain = n.shape == 'plain';
    // Pílula com adesivo ficaria oval: usa cantos arredondados.
    final shape =
        (n.sticker != null || img != null || n.tags.isNotEmpty) &&
            n.shape == 'pill'
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))
        : shapeFor(n.shape);
    final highlight = widget.dropTarget
        ? cs.tertiary
        : widget.selected
        ? cs.primary
        : null;

    final padding = isUnderline || isPlain
        ? const EdgeInsets.fromLTRB(6, 4, 6, 6)
        : n.shape == 'hexagon'
        ? EdgeInsets.symmetric(
            horizontal: widget.isRoot ? 32 : 24,
            vertical: widget.isRoot ? 14 : 9,
          )
        : n.shape == 'ellipse'
        ? EdgeInsets.symmetric(
            horizontal: 26,
            vertical: widget.isRoot ? 20 : 14,
          )
        : EdgeInsets.symmetric(
            horizontal: widget.isRoot ? 24 : 16,
            vertical: widget.isRoot ? 14 : 9,
          );

    Widget box;
    if (isUnderline) {
      box = Container(
        padding: padding,
        decoration: BoxDecoration(
          color: colors.fill,
          border: Border(
            bottom: BorderSide(color: colors.branch, width: n.borderWidth + 1),
          ),
        ),
        child: content,
      );
    } else {
      final side = n.dashed || isPlain
          ? BorderSide.none
          : BorderSide(color: colors.branch, width: n.borderWidth);
      box = Container(
        padding: padding,
        decoration: ShapeDecoration(
          color: colors.fill,
          shape: shape is OutlinedBorder ? shape.copyWith(side: side) : shape,
          shadows: widget.isRoot
              ? [
                  BoxShadow(
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                    color: Colors.black.withValues(alpha: 0.18),
                  ),
                ]
              : null,
        ),
        child: content,
      );
      if (n.dashed && !isPlain) {
        box = CustomPaint(
          foregroundPainter: DashedBorderPainter(
            shape: shape,
            color: colors.branch,
            width: n.borderWidth,
          ),
          child: box,
        );
      }
    }

    if (highlight != null) {
      box = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape:
              (isUnderline
                      ? RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        )
                      : shape is OutlinedBorder
                      ? shape
                      : const StadiumBorder())
                  .copyWith(
                    side: BorderSide(
                      color: highlight,
                      width: 2.5,
                      strokeAlign: BorderSide.strokeAlignOutside,
                    ),
                  ),
        ),
        child: box,
      );
    }

    if (n.callouts.isNotEmpty) {
      box = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in n.callouts) _Callout(text: c, color: colors.branch),
          box,
        ],
      );
    }

    return MouseRegion(
      cursor: widget.editing
          ? SystemMouseCursors.text
          : SystemMouseCursors.click,
      child: box,
    );
  }
}

/// Balão de texto preso ao tópico (callout).
class _Callout extends StatelessWidget {
  const _Callout({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final bg = Color.alphaBlend(
      color.withValues(alpha: 0.18),
      Theme.of(context).scaffoldBackgroundColor,
    );
    final fg = bg.computeLuminance() > 0.5
        ? const Color(0xFF15171F)
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: CustomPaint(
        painter: _CalloutPainter(bg, color),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240),
          padding: const EdgeInsets.fromLTRB(10, 5, 10, 13),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: fg, height: 1.2),
          ),
        ),
      ),
    );
  }
}

class _CalloutPainter extends CustomPainter {
  _CalloutPainter(this.fill, this.stroke);
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height - 8),
      const Radius.circular(10),
    );
    final path = Path()
      ..addRRect(body)
      ..moveTo(size.width / 2 - 7, size.height - 8)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width / 2 + 7, size.height - 8)
      ..close();
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawRRect(
      body,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3,
    );
  }

  @override
  bool shouldRepaint(covariant _CalloutPainter old) =>
      old.fill != fill || old.stroke != stroke;
}

class _NodeTable extends StatelessWidget {
  const _NodeTable({
    required this.rows,
    required this.color,
    required this.text,
  });
  final List<List<String>> rows;
  final Color color;
  final Color text;

  @override
  Widget build(BuildContext context) {
    final cols = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final border = BorderSide(color: color.withValues(alpha: 0.6));
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        border: TableBorder(
          top: border,
          bottom: border,
          left: border,
          right: border,
          horizontalInside: border,
          verticalInside: border,
        ),
        children: [
          for (var i = 0; i < rows.length; i++)
            TableRow(
              decoration: i == 0
                  ? BoxDecoration(color: color.withValues(alpha: 0.18))
                  : null,
              children: [
                for (var c = 0; c < cols; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Text(
                      c < rows[i].length ? rows[i][c] : '',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: text,
                        fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

String _shortDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

class _TaskStrip extends StatelessWidget {
  const _TaskStrip({
    required this.task,
    required this.color,
    required this.text,
  });
  final NodeTask task;
  final Color color;
  final Color text;

  @override
  Widget build(BuildContext context) {
    final dates = [
      if (task.start != null) _shortDate(task.start!),
      if (task.end != null) _shortDate(task.end!),
    ].join(' → ');
    final style = TextStyle(fontSize: 11, color: text.withValues(alpha: 0.85));
    return SizedBox(
      width: 150,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.progress / 100,
              minHeight: 6,
              color: task.done ? const Color(0xFF43A047) : color,
              backgroundColor: color.withValues(alpha: 0.2),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text('${task.progress}%', style: style),
              const Spacer(),
              if (dates.isNotEmpty) Text(dates, style: style),
            ],
          ),
          if (task.assignee.isNotEmpty)
            Text(
              '👤 ${task.assignee}',
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
