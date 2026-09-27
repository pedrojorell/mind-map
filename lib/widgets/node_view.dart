import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'render_helpers.dart';

/// Cores efetivas (com valores automáticos) de um nó.
class NodeColors {
  NodeColors(this.branch, this.fill, this.text);
  final Color branch;
  final Color fill;
  final Color text;

  static NodeColors of(BuildContext context, MindMapNode n) {
    final cs = Theme.of(context).colorScheme;
    final branch = parseHex(n.color) ?? cs.primary;
    final Color fill;
    if (n.shape == 'underline') {
      fill = parseHex(n.fillColor) ?? Colors.transparent;
    } else {
      fill = parseHex(n.fillColor) ??
          Color.alphaBlend(branch.withValues(alpha: 0.16), cs.surface);
    }
    final bgForContrast =
        fill.a < 0.3 ? Theme.of(context).scaffoldBackgroundColor : fill;
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
    case 'underline':
      return const RoundedRectangleBorder();
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
    );

    final Widget label = widget.editing && _text != null
        ? IntrinsicWidth(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 40, maxWidth: 300),
              child: TextField(
                controller: _text,
                focusNode: _focus,
                style: style,
                maxLines: null,
                cursorColor: colors.text,
                textAlign: TextAlign.center,
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(n.text.isEmpty ? ' ' : n.text,
                style: style, textAlign: TextAlign.center),
          );

    final badges = <Widget>[
      if (n.note.trim().isNotEmpty)
        Icon(Icons.sticky_note_2_outlined, size: 14, color: colors.text),
      if (n.hasLink) Icon(Icons.link, size: 15, color: colors.text),
      if (n.attachments.isNotEmpty)
        Icon(Icons.attach_file, size: 14, color: colors.text),
    ];

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        label,
        for (final b in badges) ...[const SizedBox(width: 6), b],
      ],
    );

    final isUnderline = n.shape == 'underline';
    final shape = shapeFor(n.shape);
    final highlight = widget.dropTarget
        ? cs.tertiary
        : widget.selected
            ? cs.primary
            : null;

    final padding = isUnderline
        ? const EdgeInsets.fromLTRB(6, 4, 6, 6)
        : n.shape == 'ellipse'
            ? EdgeInsets.symmetric(
                horizontal: 26, vertical: widget.isRoot ? 20 : 14)
            : EdgeInsets.symmetric(
                horizontal: widget.isRoot ? 24 : 16,
                vertical: widget.isRoot ? 14 : 9);

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
      final side = n.dashed
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
                  )
                ]
              : null,
        ),
        child: content,
      );
      if (n.dashed) {
        box = CustomPaint(
          foregroundPainter: DashedBorderPainter(
              shape: shape, color: colors.branch, width: n.borderWidth),
          child: box,
        );
      }
    }

    if (highlight != null) {
      box = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: (isUnderline
                  ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))
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

    return MouseRegion(
      cursor: widget.editing ? SystemMouseCursors.text : SystemMouseCursors.click,
      child: box,
    );
  }
}
