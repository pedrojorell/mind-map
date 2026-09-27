import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor_controller.dart';
import '../file_actions.dart';
import '../library.dart';
import '../models.dart';
import '../widgets/mind_map_canvas.dart';
import '../widgets/properties_panel.dart';

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key, required this.library, required this.doc});

  final Library library;
  final MindMapDoc doc;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController editor =
      EditorController(library: widget.library, doc: widget.doc);
  final _canvasKey = GlobalKey<MindMapCanvasState>();
  final _canvasFocus = FocusNode(debugLabel: 'canvas');
  final _searchFocus = FocusNode(debugLabel: 'search');
  final _searchCtrl = TextEditingController();
  final _scale = ValueNotifier<double>(1);
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  bool _showPanel = true;
  String? _lastSelected;
  int _searchIndex = -1;

  MindMapCanvasState? get canvas => _canvasKey.currentState;

  @override
  void initState() {
    super.initState();
    editor.addListener(_onEditorChanged);
    _lastSelected = editor.selectedId;
  }

  void _onEditorChanged() {
    if (editor.selectedId != _lastSelected) {
      _lastSelected = editor.selectedId;
      final id = _lastSelected;
      if (id != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => canvas?.ensureVisible(id));
      }
    }
  }

  @override
  void dispose() {
    editor.removeListener(_onEditorChanged);
    editor.dispose();
    _canvasFocus.dispose();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    _scale.dispose();
    super.dispose();
  }

  void _snack(String msg) => showSnack(context, msg);

  // ------------------------------------------------------------- ações

  Future<void> _save({bool saveAs = false}) =>
      saveToFile(context, editor, saveAs: saveAs);

  Future<void> _rename() async {
    final name = await promptText(context,
        title: 'Renomear mapa', initial: editor.doc.name, label: 'Nome');
    if (name != null) editor.rename(name);
  }

  Future<void> _copy({bool cut = false}) async {
    final id = editor.selectedId;
    if (id == null) return;
    final text = editor.outlineText(id);
    widget.library.clipboardText = text;
    await Clipboard.setData(ClipboardData(text: text));
    if (cut) {
      editor.cut();
    } else {
      editor.copy();
    }
  }

  Future<void> _paste() async {
    String text = '';
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {}
    final lib = widget.library;
    // Se o texto do sistema é o mesmo que copiamos, cola preservando estilos.
    if (lib.clipboard != null &&
        (text.isEmpty || text == lib.clipboardText)) {
      editor.paste();
    } else if (text.trim().isNotEmpty) {
      editor.pasteOutline(text);
    } else {
      _snack('Nada para colar.');
    }
  }

  void _addFloating() {
    final c = canvas?.viewportCenterScene ?? Offset.zero;
    editor.addFloating(c + const Offset(0, 120));
  }

  void _search({bool backwards = false}) {
    final results = editor.search(_searchCtrl.text);
    if (results.isEmpty) {
      _snack('Nada encontrado.');
      return;
    }
    _searchIndex = (_searchIndex + (backwards ? -1 : 1)) % results.length;
    if (_searchIndex < 0) _searchIndex += results.length;
    final id = results[_searchIndex].id;
    editor.reveal(id);
    WidgetsBinding.instance.addPostFrameCallback((_) => canvas?.centerOn(id));
  }

  // ------------------------------------------------------------ teclado

  bool get _ctrl =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  /// Atalhos que funcionam em qualquer lugar da tela.
  KeyEventResult _onGlobalKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (!_ctrl) return KeyEventResult.ignored;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyS) {
      _save(saveAs: shift);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      _searchFocus.requestFocus();
      _searchCtrl.selection =
          TextSelection(baseOffset: 0, extentOffset: _searchCtrl.text.length);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyE) {
      exportPng(context, editor.doc, () async => canvas?.capturePng());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Atalhos do canvas (apenas quando nenhum campo de texto está em uso).
  KeyEventResult _onCanvasKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (editor.editingId != null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final alt = HardwareKeyboard.instance.isAltPressed;
    final ctrl = _ctrl;

    bool run(VoidCallback f) {
      f();
      return true;
    }

    var handled = false;
    if (ctrl) {
      if (k == LogicalKeyboardKey.keyZ) {
        handled = run(shift ? editor.redo : editor.undo);
      } else if (k == LogicalKeyboardKey.keyY) {
        handled = run(editor.redo);
      } else if (k == LogicalKeyboardKey.keyC) {
        handled = run(_copy);
      } else if (k == LogicalKeyboardKey.keyX) {
        handled = run(() => _copy(cut: true));
      } else if (k == LogicalKeyboardKey.keyV) {
        handled = run(_paste);
      } else if (k == LogicalKeyboardKey.keyL) {
        handled = run(editor.arrangeNow);
      } else if (k == LogicalKeyboardKey.digit0 ||
          k == LogicalKeyboardKey.numpad0) {
        handled = run(() => canvas?.fitToScreen());
      } else if (k == LogicalKeyboardKey.equal ||
          k == LogicalKeyboardKey.add ||
          k == LogicalKeyboardKey.numpadAdd) {
        handled = run(() => canvas?.zoomBy(1.2));
      } else if (k == LogicalKeyboardKey.minus ||
          k == LogicalKeyboardKey.numpadSubtract) {
        handled = run(() => canvas?.zoomBy(1 / 1.2));
      }
    } else if (alt && k == LogicalKeyboardKey.arrowUp) {
      handled = run(() => editor.moveSibling(-1));
    } else if (alt && k == LogicalKeyboardKey.arrowDown) {
      handled = run(() => editor.moveSibling(1));
    } else if (k == LogicalKeyboardKey.tab || k == LogicalKeyboardKey.insert) {
      handled = run(() => editor.addChild());
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      handled = run(() => editor.addSibling());
    } else if (k == LogicalKeyboardKey.f2 || k == LogicalKeyboardKey.space) {
      handled = run(() => editor.startEditing());
    } else if (k == LogicalKeyboardKey.delete ||
        k == LogicalKeyboardKey.backspace) {
      handled = run(() => editor.deleteNode());
    } else if (k == LogicalKeyboardKey.slash) {
      handled = run(() => editor.toggleCollapse());
    } else if (k == LogicalKeyboardKey.escape) {
      handled = run(() => editor.select(null));
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      handled = run(() => editor.navigate(AxisDirection.left));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      handled = run(() => editor.navigate(AxisDirection.right));
    } else if (k == LogicalKeyboardKey.arrowUp) {
      handled = run(() => editor.navigate(AxisDirection.up));
    } else if (k == LogicalKeyboardKey.arrowDown) {
      handled = run(() => editor.navigate(AxisDirection.down));
    } else if (!alt &&
        editor.selectedId != null &&
        e is KeyDownEvent &&
        e.character != null &&
        e.character!.runes.length == 1 &&
        e.character!.runes.first >= 32 &&
        e.character!.runes.first != 127) {
      // Começa a digitar: substitui o texto do tópico selecionado.
      handled = run(() => editor.startEditing(null, false, e.character));
    }
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  // ------------------------------------------------------ menu de contexto

  Future<void> _contextMenu(
      Offset global, String? nodeId, Offset scenePos) async {
    final isRoot = nodeId == editor.doc.rootId;
    final n = nodeId == null ? null : editor.doc.nodes[nodeId];
    PopupMenuItem<String> item(String v, IconData i, String t,
            {bool enabled = true, String? shortcut}) =>
        PopupMenuItem(
          value: v,
          enabled: enabled,
          height: 38,
          child: Row(children: [
            Icon(i, size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(t)),
            if (shortcut != null)
              Text(shortcut, style: Theme.of(context).textTheme.bodySmall),
          ]),
        );

    final items = <PopupMenuEntry<String>>[
      if (n != null) ...[
        item('child', Icons.subdirectory_arrow_right, 'Adicionar subtópico',
            shortcut: 'Tab'),
        item('sibling', Icons.add, 'Adicionar tópico irmão',
            enabled: !isRoot, shortcut: 'Enter'),
        item('edit', Icons.edit_outlined, 'Editar texto', shortcut: 'F2'),
        const PopupMenuDivider(),
        item('copy', Icons.copy, 'Copiar', shortcut: 'Ctrl+C'),
        item('cut', Icons.cut, 'Recortar', enabled: !isRoot, shortcut: 'Ctrl+X'),
        item('paste', Icons.paste, 'Colar como subtópico', shortcut: 'Ctrl+V'),
        const PopupMenuDivider(),
        if (n.childrenIds.isNotEmpty)
          item('collapse', n.collapsed ? Icons.unfold_more : Icons.unfold_less,
              n.collapsed ? 'Expandir ramo' : 'Recolher ramo',
              shortcut: '/'),
        if (n.parentId != null)
          item('detach', Icons.call_split, 'Soltar do pai (flutuante)'),
        item('link', Icons.link, n.hasLink ? 'Abrir link' : 'Adicionar link'),
        const PopupMenuDivider(),
        item('delete', Icons.delete_outline, 'Excluir',
            enabled: !isRoot, shortcut: 'Del'),
      ] else ...[
        item('float', Icons.bubble_chart_outlined, 'Tópico flutuante aqui'),
        item('paste', Icons.paste, 'Colar', shortcut: 'Ctrl+V'),
        const PopupMenuDivider(),
        item('arrange', Icons.auto_fix_high, 'Organizar mapa',
            shortcut: 'Ctrl+L'),
        item('fit', Icons.fit_screen_outlined, 'Ajustar à tela',
            shortcut: 'Ctrl+0'),
        item('expand', Icons.unfold_more, 'Expandir tudo'),
        item('collapseAll', Icons.unfold_less, 'Recolher tudo'),
      ],
    ];

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(global.dx, global.dy, global.dx, global.dy),
      items: items,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'child':
        editor.addChild(nodeId);
      case 'sibling':
        editor.addSibling();
      case 'edit':
        editor.startEditing(nodeId);
      case 'copy':
        _copy();
      case 'cut':
        _copy(cut: true);
      case 'paste':
        _paste();
      case 'collapse':
        editor.toggleCollapse(nodeId);
      case 'detach':
        editor.detach(nodeId);
      case 'link':
        if (n!.hasLink) {
          openLink(context, n.link!);
        } else {
          final url = await promptText(context,
              title: 'Adicionar link', initial: '', label: 'https://…');
          if (url != null && url.trim().isNotEmpty) {
            editor.updateNode(n.id, (n) => n.link = url.trim());
          }
        }
      case 'delete':
        editor.deleteNode(nodeId);
      case 'float':
        editor.addFloating(scenePos);
      case 'arrange':
        editor.arrangeNow();
      case 'fit':
        canvas?.fitToScreen();
      case 'expand':
        editor.setAllCollapsed(false);
      case 'collapseAll':
        editor.setAllCollapsed(true);
    }
    _canvasFocus.requestFocus();
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final panel = PropertiesPanel(editor: editor);
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onGlobalKey,
          child: Scaffold(
            key: _scaffoldKey,
            appBar: _appBar(context, wide),
            endDrawer: wide ? null : Drawer(width: 340, child: SafeArea(child: panel)),
            body: Column(
              children: [
                _toolbar(context),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Focus(
                          focusNode: _canvasFocus,
                          autofocus: true,
                          onKeyEvent: _onCanvasKey,
                          child: Stack(
                            children: [
                              MindMapCanvas(
                                key: _canvasKey,
                                editor: editor,
                                focusNode: _canvasFocus,
                                scale: _scale,
                                onContextMenu: _contextMenu,
                                onMessage: _snack,
                              ),
                              Positioned(
                                right: 14,
                                bottom: 14,
                                child: _zoomControls(context),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (wide && _showPanel) ...[
                        const VerticalDivider(width: 1),
                        SizedBox(width: 330, child: panel),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _appBar(BuildContext context, bool wide) {
    final doc = editor.doc;
    final dirty = editor.hasUnsavedFileChanges;
    return AppBar(
      titleSpacing: 0,
      title: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _rename,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${doc.name}${dirty ? ' •' : ''}',
                  overflow: TextOverflow.ellipsis),
              Text(
                doc.filePath ?? 'Salvo automaticamente na biblioteca',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Desfazer (Ctrl+Z)',
          onPressed: editor.canUndo ? editor.undo : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          tooltip: 'Refazer (Ctrl+Y)',
          onPressed: editor.canRedo ? editor.redo : null,
          icon: const Icon(Icons.redo),
        ),
        const SizedBox(width: 4),
        FilledButton.tonalIcon(
          onPressed: () => _save(),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Salvar'),
        ),
        PopupMenuButton<String>(
          tooltip: 'Arquivo',
          icon: const Icon(Icons.more_vert),
          onSelected: (v) {
            switch (v) {
              case 'saveAs':
                _save(saveAs: true);
              case 'png':
                exportPng(context, doc, () async => canvas?.capturePng());
              case 'md':
                exportMarkdown(context, doc);
              case 'copyText':
                Clipboard.setData(
                    ClipboardData(text: editor.outlineText(doc.rootId)));
                _snack('Tópicos copiados como texto.');
              case 'rename':
                _rename();
              case 'theme':
                widget.library.toggleTheme();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
                value: 'saveAs', child: Text('Salvar como… (Ctrl+Shift+S)')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'png', child: Text('Exportar imagem PNG (Ctrl+E)')),
            PopupMenuItem(value: 'md', child: Text('Exportar Markdown')),
            PopupMenuItem(value: 'copyText', child: Text('Copiar tópicos como texto')),
            PopupMenuDivider(),
            PopupMenuItem(value: 'rename', child: Text('Renomear')),
            PopupMenuItem(value: 'theme', child: Text('Alternar tema claro/escuro')),
          ],
        ),
        IconButton(
          tooltip: 'Propriedades',
          isSelected: wide ? _showPanel : false,
          icon: const Icon(Icons.tune),
          onPressed: () {
            if (wide) {
              setState(() => _showPanel = !_showPanel);
            } else {
              _scaffoldKey.currentState?.openEndDrawer();
            }
          },
        ),
        const SizedBox(width: 6),
      ],
    );
  }

  Widget _toolbar(BuildContext context) {
    final sel = editor.selected;
    final isRoot = sel?.id == editor.doc.rootId;
    Widget btn(IconData i, String label, String tip, VoidCallback? onTap) =>
        Tooltip(
          message: tip,
          waitDuration: const Duration(milliseconds: 400),
          child: TextButton.icon(
            onPressed: onTap == null
                ? null
                : () {
                    onTap();
                    _canvasFocus.requestFocus();
                  },
            icon: Icon(i, size: 18),
            label: Text(label),
          ),
        );
    const gap = SizedBox(
        height: 24, child: VerticalDivider(width: 16, indent: 2, endIndent: 2));

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  btn(Icons.subdirectory_arrow_right, 'Subtópico',
                      'Adicionar subtópico (Tab)', () => editor.addChild()),
                  btn(Icons.add, 'Tópico', 'Adicionar tópico irmão (Enter)',
                      sel == null || isRoot ? null : editor.addSibling),
                  btn(Icons.bubble_chart_outlined, 'Flutuante',
                      'Tópico flutuante (duplo clique no fundo)', _addFloating),
                  gap,
                  btn(Icons.delete_outline, 'Excluir', 'Excluir (Del)',
                      sel == null || isRoot ? null : () => editor.deleteNode()),
                  btn(
                      sel?.collapsed ?? false
                          ? Icons.unfold_more
                          : Icons.unfold_less,
                      sel?.collapsed ?? false ? 'Expandir' : 'Recolher',
                      'Recolher/expandir ramo (/)',
                      sel == null || sel.childrenIds.isEmpty
                          ? null
                          : () => editor.toggleCollapse()),
                  gap,
                  btn(Icons.auto_fix_high, 'Organizar',
                      'Organizar mapa automaticamente (Ctrl+L)',
                      editor.arrangeNow),
                  btn(Icons.fit_screen_outlined, 'Ajustar',
                      'Ajustar à tela (Ctrl+0)', () => canvas?.fitToScreen()),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 230,
            height: 36,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              onChanged: (_) => _searchIndex = -1,
              onSubmitted: (_) {
                _search(backwards: HardwareKeyboard.instance.isShiftPressed);
                _searchFocus.requestFocus();
              },
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar (Ctrl+F)',
                prefixIcon: const Icon(Icons.search, size: 18),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _zoomControls(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 3,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Diminuir zoom (Ctrl -)',
            icon: const Icon(Icons.remove),
            onPressed: () => canvas?.zoomBy(1 / 1.2),
          ),
          ValueListenableBuilder<double>(
            valueListenable: _scale,
            builder: (_, s, _) => TextButton(
              onPressed: () => canvas?.resetZoom(),
              child: Text('${(s * 100).round()}%'),
            ),
          ),
          IconButton(
            tooltip: 'Aumentar zoom (Ctrl +)',
            icon: const Icon(Icons.add),
            onPressed: () => canvas?.zoomBy(1.2),
          ),
          IconButton(
            tooltip: 'Centralizar na ideia principal',
            icon: const Icon(Icons.center_focus_strong_outlined),
            onPressed: () => canvas?.centerOn(editor.doc.rootId),
          ),
        ],
      ),
    );
  }
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String initial,
  String? label,
}) async {
  final c = TextEditingController(text: initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: initial.length);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(labelText: label),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('OK')),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  return result;
}
