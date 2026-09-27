import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor_controller.dart';
import '../models.dart';
import 'markers.dart';

/// Visão em tópicos (esboço): o mapa como uma lista recuada e editável.
/// Enter cria o próximo tópico, Tab cria um subtópico.
class OutlineView extends StatelessWidget {
  const OutlineView({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final doc = editor.doc;
    final rows = <(MindMapNode, int)>[];
    void walk(String id, int depth) {
      final n = doc.nodes[id];
      if (n == null) return;
      rows.add((n, depth));
      if (n.collapsed) return;
      for (final c in n.childrenIds) {
        walk(c, depth + 1);
      }
    }

    walk(doc.rootId, 0);
    for (final n in doc.nodes.values) {
      if (n.parentId == null && n.id != doc.rootId) walk(n.id, 0);
    }

    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 80),
            itemCount: rows.length,
            itemBuilder: (context, i) {
              final (n, depth) = rows[i];
              return _OutlineRow(
                key: ValueKey(n.id),
                editor: editor,
                node: n,
                depth: depth,
                isRoot: n.id == doc.rootId,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _OutlineRow extends StatefulWidget {
  const _OutlineRow({
    super.key,
    required this.editor,
    required this.node,
    required this.depth,
    required this.isRoot,
  });

  final EditorController editor;
  final MindMapNode node;
  final int depth;
  final bool isRoot;

  @override
  State<_OutlineRow> createState() => _OutlineRowState();
}

class _OutlineRowState extends State<_OutlineRow> {
  late final _c = TextEditingController(text: widget.node.text);
  late final _focus = FocusNode(onKeyEvent: _onKey);
  bool _hover = false;

  EditorController get editor => widget.editor;
  String get id => widget.node.id;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        editor.select(id);
      } else {
        _commit();
      }
      if (mounted) setState(() {});
    });
    _maybeFocus();
  }

  @override
  void didUpdateWidget(covariant _OutlineRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != widget.node.text) {
      _c.text = widget.node.text;
    }
    _maybeFocus();
  }

  /// Tópicos recém-criados entram direto em edição.
  void _maybeFocus() {
    if (editor.editingId == id && !_focus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focus.requestFocus();
        _c.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _c.text.length,
        );
      });
    }
  }

  /// Grava o texto. Retorna depois que o controlador aplicou a mudança.
  void _commit() {
    final v = _c.text.trim();
    if (editor.editingId == id) {
      editor.commitEditing(v.isEmpty ? widget.node.text : v);
    } else if (v.isNotEmpty && v != widget.node.text) {
      editor.updateNode(id, (n) => n.text = v, relayout: true);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      _commit();
      editor.select(id);
      if (widget.isRoot) {
        editor.addChild(id);
      } else if (shift) {
        editor.addSiblingBefore();
      } else {
        editor.addSibling();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.tab && !shift) {
      _commit();
      editor.addChild(id);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      _c.text = widget.node.text;
      editor.cancelEditing();
      _focus.unfocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.node;
    final cs = Theme.of(context).colorScheme;
    final color = parseHex(n.color) ?? cs.primary;
    final selected = editor.selectedId == id;
    final isRoot = widget.isRoot;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: EdgeInsets.only(left: 8 + widget.depth * 26.0, right: 4),
        decoration: BoxDecoration(
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.45)
              : _hover
              ? cs.surfaceContainerHighest.withValues(alpha: 0.4)
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: n.childrenIds.isEmpty
                  ? null
                  : InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => editor.toggleCollapse(id),
                      child: Icon(
                        n.collapsed ? Icons.chevron_right : Icons.expand_more,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
            ),
            Container(
              width: isRoot ? 12 : 8,
              height: isRoot ? 12 : 8,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isRoot ? (parseHex(n.fillColor) ?? color) : color,
                shape: isRoot ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: isRoot ? BorderRadius.circular(3) : null,
              ),
            ),
            if (n.sticker != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(n.sticker!, style: const TextStyle(fontSize: 18)),
              ),
            for (final m in n.markers)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: MarkerIcon.fromString(m, size: 16),
              ),
            Expanded(
              child: TextField(
                controller: _c,
                focusNode: _focus,
                maxLines: null,
                style: TextStyle(
                  fontSize: isRoot ? 22 : (widget.depth == 1 ? 16 : 14.5),
                  fontWeight: isRoot || n.bold
                      ? FontWeight.w700
                      : (widget.depth == 1 ? FontWeight.w600 : FontWeight.w400),
                  fontStyle: n.italic ? FontStyle.italic : FontStyle.normal,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
            if (n.note.trim().isNotEmpty)
              Tooltip(
                message: n.note,
                child: Icon(
                  Icons.sticky_note_2_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ),
            if (_hover || selected) ...[
              IconButton(
                tooltip: 'Subtópico (Tab)',
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                onPressed: () => editor.addChild(id),
                icon: const Icon(Icons.subdirectory_arrow_right),
              ),
              if (!isRoot)
                IconButton(
                  tooltip: 'Excluir',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => editor.deleteNode(id),
                  icon: const Icon(Icons.delete_outline),
                ),
            ] else
              const SizedBox(width: 80),
          ],
        ),
      ),
    );
  }
}
