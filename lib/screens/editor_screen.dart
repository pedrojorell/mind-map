import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor_controller.dart';
import '../file_actions.dart';
import '../import_export.dart';
import '../library.dart';
import '../media.dart';
import '../models.dart';
import '../widgets/gantt_view.dart';
import '../widgets/media_panel.dart';
import '../widgets/mind_map_canvas.dart';
import '../widgets/outline_view.dart';
import '../widgets/properties_panel.dart';
import '../widgets/ribbon.dart';
import '../widgets/brand.dart';

enum _RibbonTab { home, insert, design, view }

enum _View { map, outline, gantt }

const _ribbonTabNames = {
  _RibbonTab.home: 'Início',
  _RibbonTab.insert: 'Inserir',
  _RibbonTab.design: 'Design',
  _RibbonTab.view: 'Exibir',
};

class EditorScreen extends StatefulWidget {
  const EditorScreen({
    super.key,
    required this.library,
    required this.doc,
    this.active = true,
    this.onHome,
  });

  final Library library;
  final MindMapDoc doc;

  /// Aba visível no momento (recebe o foco do teclado ao ficar ativa).
  final bool active;

  /// Volta para a aba Início (sem ela, fecha a tela).
  final VoidCallback? onHome;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late final EditorController editor = EditorController(
    library: widget.library,
    doc: widget.doc,
  );
  final _canvasKey = GlobalKey<MindMapCanvasState>();
  final _canvasFocus = FocusNode(debugLabel: 'canvas');
  final _searchFocus = FocusNode(debugLabel: 'search');
  final _searchCtrl = TextEditingController();
  final _scale = ValueNotifier<double>(1);
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  _RibbonTab _ribbonTab = _RibbonTab.home;
  PanelTab _panelTab = PanelTab.style;
  bool _showPanel = true;
  bool _showGrid = true;
  bool _showMinimap = true;
  _View _view = _View.map;
  bool get _outline => _view != _View.map;

  /// Tela limpa: só o mapa (F11).
  bool _zen = false;

  /// Modo apresentação (F5): percorre os ramos um a um.
  bool _presenting = false;
  List<String> _steps = const [];
  int _step = 0;
  String? _lastSelected;
  int _searchIndex = -1;

  MindMapCanvasState? get canvas => _canvasKey.currentState;

  @override
  void initState() {
    super.initState();
    editor.addListener(_onEditorChanged);
    _lastSelected = editor.selectedId;
  }

  @override
  void didUpdateWidget(covariant EditorScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _canvasFocus.requestFocus(),
      );
    }
  }

  void _onEditorChanged() {
    if (editor.selectedId != _lastSelected) {
      _lastSelected = editor.selectedId;
      final id = _lastSelected;
      if (id != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => canvas?.ensureVisible(id),
        );
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

  /// Executa uma ação e devolve o foco ao mapa (para os atalhos funcionarem).
  void _run(VoidCallback f) {
    f();
    _canvasFocus.requestFocus();
  }

  // ------------------------------------------------------------- ações

  Future<void> _save({bool saveAs = false}) =>
      saveToFile(context, editor, saveAs: saveAs);

  Future<void> _exportPng() =>
      exportPng(context, editor.doc, () async => canvas?.capturePng());

  Future<void> _rename() async {
    final name = await promptText(
      context,
      title: 'Renomear mapa',
      initial: editor.doc.name,
      label: 'Nome',
    );
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

  Future<void> _paste({bool asText = false}) async {
    String text = '';
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {}
    final lib = widget.library;
    // Se o texto do sistema é o mesmo que copiamos, cola preservando estilos.
    if (!asText &&
        lib.clipboard != null &&
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

  void _startRelation() {
    if (editor.selectedId == null) {
      _snack('Selecione o tópico de origem da relação.');
      return;
    }
    if (_outline) setState(() => _view = _View.map);
    editor.startRelation();
  }

  Future<void> _addMultiple() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar vários tópicos'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Um tópico por linha. Use espaços no início da linha para criar subtópicos.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: c,
                autofocus: true,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Marketing\n  Redes sociais\n  E-mail\nVendas',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (text != null && text.trim().isNotEmpty) {
      editor.addMultiple(text, editor.selectedId ?? editor.doc.rootId);
    }
    _canvasFocus.requestFocus();
  }

  /// Tópico alvo para inserir mídia: o selecionado ou um novo flutuante.
  String _mediaTarget(String text) {
    final id = editor.selectedId;
    if (id != null) return id;
    final c = canvas?.viewportCenterScene ?? Offset.zero;
    return editor.addFloating(c, text: text, edit: false);
  }

  Future<void> _addLink([String kind = 'web']) async {
    final id = _mediaTarget('Link');
    await addLinkTo(context, editor, id, kind: kind);
    _canvasFocus.requestFocus();
  }

  Future<void> _insertImage({bool asNewTopic = false}) async {
    final img = await pickImage(context);
    if (img == null) return;
    String id;
    final sel = editor.selectedId;
    if (asNewTopic && sel != null) {
      id = editor.addChildWith(
        sel,
        text: img.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
        edit: false,
      )!;
    } else {
      id = _mediaTarget(img.name.replaceFirst(RegExp(r'\.[^.]+$'), ''));
    }
    editor.updateNode(id, (n) => n.image = img, relayout: true);
    _canvasFocus.requestFocus();
  }

  Future<void> _attachDocuments() async {
    final id = _mediaTarget('Documentos');
    await pickDocuments(context, editor, id);
    _canvasFocus.requestFocus();
  }

  void _onBadgeTap(String nodeId, String kind, Offset pos) {
    editor.select(nodeId);
    if (kind == 'note') {
      _openPanel(PanelTab.details);
    } else {
      showNodeItemsMenu(context, editor, nodeId, kind, pos);
    }
  }

  void _openPanel(PanelTab tab) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    setState(() {
      _panelTab = tab;
      _showPanel = true;
    });
    if (!wide) _scaffoldKey.currentState?.openEndDrawer();
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

  // ------------------------------------------------- apresentação e janelas

  void _startPresentation() {
    final order = editor.readingOrder();
    final steps = [
      for (final id in order)
        if (id == editor.doc.rootId ||
            (editor.doc.depthOf(id) <= 2 &&
                editor.doc.nodes[id]!.parentId != null))
          id,
    ];
    setState(() {
      _view = _View.map;
      _presenting = true;
      _steps = steps;
      _step = 0;
    });
    editor.cancelRelation();
    editor.cancelEditing();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _canvasFocus.requestFocus();
      _goStep(0);
    });
  }

  void _stopPresentation() {
    setState(() => _presenting = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => canvas?.fitToScreen());
  }

  void _goStep(int i) {
    if (_steps.isEmpty) return;
    final step = i.clamp(0, _steps.length - 1);
    setState(() => _step = step);
    final id = _steps[step];
    final visible = editor.visibleNodes().map((n) => n.id).toSet();
    final ids = id == editor.doc.rootId
        ? visible
        : editor.doc.subtreeIds(id).where(visible.contains);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => canvas?.fitToIds(ids, maxScale: 2.2, margin: 90),
    );
  }

  Future<void> _findReplace() async {
    final find = TextEditingController(text: _searchCtrl.text);
    final repl = TextEditingController();
    var notes = false;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Localizar e substituir'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: find,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Localizar',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: repl,
                  decoration: const InputDecoration(
                    labelText: 'Substituir por',
                    prefixIcon: Icon(Icons.find_replace),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: notes,
                  onChanged: (v) => setD(() => notes = v ?? false),
                  title: const Text('Incluir anotações'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                _searchCtrl.text = find.text;
                _searchIndex = -1;
                _search();
              },
              child: const Text('Localizar próximo'),
            ),
            FilledButton(
              onPressed: () {
                final n = editor.replaceAll(find.text, repl.text, notes: notes);
                Navigator.pop(ctx);
                _snack(
                  n == 0 ? 'Nada encontrado.' : '$n tópico(s) alterado(s).',
                );
              },
              child: const Text('Substituir tudo'),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      find.dispose();
      repl.dispose();
    });
  }

  Future<void> _showVersions() async {
    final lib = widget.library;
    await lib.saveNow(editor.doc);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          final list = lib.versions(editor.doc.id);
          String when(int ms) {
            final d = DateTime.fromMillisecondsSinceEpoch(ms);
            String two(int v) => v.toString().padLeft(2, '0');
            return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
          }

          return AlertDialog(
            title: const Text('Histórico de versões'),
            content: SizedBox(
              width: 460,
              height: 380,
              child: list.isEmpty
                  ? const Center(child: Text('Nenhuma versão salva ainda.'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final (at, json) = list[i];
                        var count = 0;
                        var root = '';
                        try {
                          final d = MindMapDoc.fromJson(
                            jsonDecode(json) as Map<String, dynamic>,
                          );
                          count = d.nodes.length;
                          root = d.root.text.replaceAll('\n', ' ');
                        } catch (_) {}
                        return ListTile(
                          leading: Icon(
                            i == 0 ? Icons.bookmark : Icons.history,
                          ),
                          title: Text(when(at)),
                          subtitle: Text(
                            '$count tópicos · $root',
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: TextButton(
                            onPressed: () {
                              editor.restoreVersion(json);
                              Navigator.pop(ctx);
                              _snack('Versão restaurada (Ctrl+Z desfaz).');
                            },
                            child: const Text('Restaurar'),
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  await lib.saveVersion(editor.doc, force: true);
                  setD(() {});
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Salvar versão agora'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showStats() {
    final doc = editor.doc;
    final nodes = doc.nodes.values.toList();
    final words = nodes.fold<int>(
      0,
      (s, n) =>
          s +
          '${n.text} ${n.note}'
              .split(RegExp(r'\s+'))
              .where((w) => w.isNotEmpty)
              .length,
    );
    final depth = nodes.fold<int>(0, (m, n) => math.max(m, doc.depthOf(n.id)));
    final tasks = nodes.where((n) => n.task != null).toList();
    final rows = <(IconData, String, String)>[
      (Icons.hub_outlined, 'Tópicos', '${nodes.length}'),
      (
        Icons.account_tree_outlined,
        'Ramos principais',
        '${doc.root.childrenIds.length}',
      ),
      (Icons.layers_outlined, 'Níveis', '${depth + 1}'),
      (Icons.text_fields, 'Palavras', '$words'),
      (Icons.moving, 'Relações', '${doc.relations.length}'),
      (
        Icons.image_outlined,
        'Imagens',
        '${nodes.where((n) => n.image != null).length}',
      ),
      (
        Icons.attach_file,
        'Documentos',
        '${nodes.fold<int>(0, (s, n) => s + n.attachments.length)}',
      ),
      (
        Icons.link,
        'Links',
        '${nodes.fold<int>(0, (s, n) => s + n.links.length)}',
      ),
      (
        Icons.forum_outlined,
        'Comentários',
        '${nodes.fold<int>(0, (s, n) => s + n.comments.length)}',
      ),
      (
        Icons.task_alt,
        'Tarefas concluídas',
        '${tasks.where((n) => n.task!.done).length} de ${tasks.length}',
      ),
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estatísticas do mapa'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in rows)
                ListTile(
                  dense: true,
                  leading: Icon(r.$1),
                  title: Text(r.$2),
                  trailing: Text(
                    r.$3,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  /// Liga/desliga um elemento no tópico selecionado e abre o painel.
  void _element(void Function(MindMapNode n) fn) {
    final id = editor.selectedId;
    if (id == null) {
      _snack('Selecione um tópico primeiro.');
      return;
    }
    editor.updateNode(id, fn, relayout: true);
    _openPanel(PanelTab.elements);
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
      _searchCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchCtrl.text.length,
      );
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyE) {
      _exportPng();
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
    if (_presenting) {
      if (k == LogicalKeyboardKey.escape) {
        _stopPresentation();
      } else if (k == LogicalKeyboardKey.arrowLeft ||
          k == LogicalKeyboardKey.arrowUp ||
          k == LogicalKeyboardKey.pageUp) {
        _goStep(_step - 1);
      } else if (k == LogicalKeyboardKey.arrowRight ||
          k == LogicalKeyboardKey.arrowDown ||
          k == LogicalKeyboardKey.pageDown ||
          k == LogicalKeyboardKey.space ||
          k == LogicalKeyboardKey.enter) {
        _goStep(_step + 1);
      } else if (k == LogicalKeyboardKey.home) {
        _goStep(0);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f5) {
      _startPresentation();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.f11) {
      setState(() => _zen = !_zen);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape &&
        (_zen || editor.focusId != null) &&
        editor.linkingFrom == null) {
      if (_zen) {
        setState(() => _zen = false);
      } else {
        editor.setFocus(null);
      }
      return KeyEventResult.handled;
    }
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
        handled = run(() => _paste(asText: shift));
      } else if (k == LogicalKeyboardKey.keyL) {
        handled = run(editor.arrangeNow);
      } else if (k == LogicalKeyboardKey.keyA) {
        handled = run(editor.selectAll);
      } else if (k == LogicalKeyboardKey.keyH) {
        handled = run(_findReplace);
      } else if (alt && k == LogicalKeyboardKey.keyC) {
        handled = run(() {
          editor.copyStyle();
          _snack('Estilo copiado. Selecione tópicos e use Ctrl+Alt+V.');
        });
      } else if (alt && k == LogicalKeyboardKey.keyV) {
        handled = run(editor.pasteStyle);
      } else if (k == LogicalKeyboardKey.keyR) {
        handled = run(_startRelation);
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
    } else if (alt && k == LogicalKeyboardKey.keyF) {
      handled = run(_addFloating);
    } else if (alt && k == LogicalKeyboardKey.arrowUp) {
      handled = run(() => editor.moveSibling(-1));
    } else if (alt && k == LogicalKeyboardKey.arrowDown) {
      handled = run(() => editor.moveSibling(1));
    } else if (shift && k == LogicalKeyboardKey.insert) {
      handled = run(() => editor.addMainTopic());
    } else if (k == LogicalKeyboardKey.tab || k == LogicalKeyboardKey.insert) {
      handled = run(() => editor.addChild());
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      handled = run(
        () => shift ? editor.addSiblingBefore() : editor.addSibling(),
      );
    } else if (k == LogicalKeyboardKey.f2 || k == LogicalKeyboardKey.space) {
      handled = run(() => editor.startEditing());
    } else if (k == LogicalKeyboardKey.delete ||
        k == LogicalKeyboardKey.backspace) {
      handled = run(editor.deleteSelection);
    } else if (k == LogicalKeyboardKey.slash) {
      handled = run(() => editor.toggleCollapse());
    } else if (k == LogicalKeyboardKey.escape) {
      handled = run(
        () => editor.linkingFrom != null
            ? editor.cancelRelation()
            : editor.select(null),
      );
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
    Offset global,
    String? nodeId,
    Offset scenePos,
  ) async {
    final isRoot = nodeId == editor.doc.rootId;
    final n = nodeId == null ? null : editor.doc.nodes[nodeId];
    PopupMenuItem<String> item(
      String v,
      IconData i,
      String t, {
      bool enabled = true,
      String? shortcut,
    }) => PopupMenuItem(
      value: v,
      enabled: enabled,
      height: 36,
      child: Row(
        children: [
          Icon(i, size: 18),
          const SizedBox(width: 12),
          Expanded(child: Text(t)),
          if (shortcut != null) ...[
            const SizedBox(width: 16),
            Text(shortcut, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );

    final items = <PopupMenuEntry<String>>[
      if (n != null) ...[
        item(
          'child',
          Icons.subdirectory_arrow_right,
          'Adicionar subtópico',
          shortcut: 'Tab',
        ),
        item(
          'sibling',
          Icons.add,
          'Tópico depois',
          enabled: !isRoot,
          shortcut: 'Enter',
        ),
        item(
          'before',
          Icons.vertical_align_top,
          'Tópico antes',
          enabled: !isRoot,
          shortcut: 'Shift+Enter',
        ),
        item('edit', Icons.edit_outlined, 'Editar texto', shortcut: 'F2'),
        const PopupMenuDivider(),
        item('copy', Icons.copy, 'Copiar', shortcut: 'Ctrl+C'),
        item(
          'cut',
          Icons.cut,
          'Recortar',
          enabled: !isRoot,
          shortcut: 'Ctrl+X',
        ),
        item('paste', Icons.paste, 'Colar como subtópico', shortcut: 'Ctrl+V'),
        const PopupMenuDivider(),
        item('relation', Icons.moving, 'Criar relação', shortcut: 'Ctrl+R'),
        item('focus', Icons.center_focus_weak, 'Focar neste ramo'),
        item(
          'copyStyle',
          Icons.format_paint_outlined,
          'Copiar estilo',
          shortcut: 'Ctrl+Alt+C',
        ),
        if (editor.copiedStyle != null)
          item(
            'pasteStyle',
            Icons.format_color_fill,
            'Colar estilo',
            shortcut: 'Ctrl+Alt+V',
          ),
        item(
          'elements',
          Icons.widgets_outlined,
          'Balão, limite, resumo, tabela…',
        ),
        item('marker', Icons.flag_outlined, 'Marcadores…'),
        item('sticker', Icons.emoji_emotions_outlined, 'Adesivo…'),
        const PopupMenuDivider(),
        item(
          'image',
          Icons.add_photo_alternate_outlined,
          n.image == null ? 'Inserir imagem' : 'Trocar imagem',
        ),
        item('files', Icons.attach_file, 'Anexar documento'),
        item('link', Icons.add_link, 'Adicionar link'),
        if (n.hasLink) item('openLinks', Icons.open_in_new, 'Abrir link'),
        if (n.childrenIds.isNotEmpty)
          item(
            'collapse',
            n.collapsed ? Icons.unfold_more : Icons.unfold_less,
            n.collapsed ? 'Expandir ramo' : 'Recolher ramo',
            shortcut: '/',
          ),
        if (n.parentId != null)
          item('detach', Icons.call_split, 'Soltar do pai (flutuante)'),
        const PopupMenuDivider(),
        item(
          'delete',
          Icons.delete_outline,
          'Excluir',
          enabled: !isRoot,
          shortcut: 'Del',
        ),
      ] else ...[
        item('float', Icons.bubble_chart_outlined, 'Tópico flutuante aqui'),
        item('paste', Icons.paste, 'Colar', shortcut: 'Ctrl+V'),
        const PopupMenuDivider(),
        item(
          'arrange',
          Icons.auto_fix_high,
          'Organizar mapa',
          shortcut: 'Ctrl+L',
        ),
        item(
          'fit',
          Icons.fit_screen_outlined,
          'Ajustar à tela',
          shortcut: 'Ctrl+0',
        ),
        item('expand', Icons.unfold_more, 'Expandir tudo'),
        item('collapseAll', Icons.unfold_less, 'Recolher tudo'),
        item('theme', Icons.palette_outlined, 'Tema e fundo…'),
        item(
          'selectAll',
          Icons.select_all,
          'Selecionar tudo',
          shortcut: 'Ctrl+A',
        ),
      ],
    ];

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        global.dx,
        global.dy,
        global.dx,
        global.dy,
      ),
      items: items,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'child':
        editor.addChild(nodeId);
      case 'sibling':
        editor.addSibling();
      case 'before':
        editor.addSiblingBefore();
      case 'edit':
        editor.startEditing(nodeId);
      case 'copy':
        _copy();
      case 'cut':
        _copy(cut: true);
      case 'paste':
        _paste();
      case 'relation':
        _startRelation();
      case 'focus':
        editor.setFocus(nodeId);
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => canvas?.fitToScreen(),
        );
      case 'copyStyle':
        editor.copyStyle(nodeId);
      case 'pasteStyle':
        editor.pasteStyle(nodeId);
      case 'elements':
        _openPanel(PanelTab.elements);
      case 'marker':
        _openPanel(PanelTab.markers);
      case 'sticker':
        _openPanel(PanelTab.stickers);
      case 'collapse':
        editor.toggleCollapse(nodeId);
      case 'detach':
        editor.detach(nodeId);
      case 'link':
        await _addLink();
      case 'openLinks':
        await showNodeItemsMenu(context, editor, n!.id, 'links', global);
      case 'image':
        await _insertImage();
      case 'files':
        await _attachDocuments();
      case 'delete':
        if (editor.multi.isNotEmpty) {
          editor.deleteSelection();
        } else {
          editor.deleteNode(nodeId);
        }
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
      case 'theme':
        _openPanel(PanelTab.map);
      case 'selectAll':
        editor.selectAll();
    }
    _canvasFocus.requestFocus();
  }

  // ------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 760;
        final cs = Theme.of(context).colorScheme;
        Widget panel({VoidCallback? onClose}) =>
            PropertiesPanel(editor: editor, tab: _panelTab, onClose: onClose);
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: _onGlobalKey,
          child: Scaffold(
            key: _scaffoldKey,
            endDrawer: wide
                ? null
                : Drawer(width: 320, child: SafeArea(child: panel())),
            body: _zen || _presenting
                ? _workArea(context)
                : Column(
                    children: [
                      _titleBar(context),
                      Container(
                        color: cs.surfaceContainerLow,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ribbonTabs(context),
                            SizedBox(height: 74, child: _ribbon(context)),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: cs.outlineVariant),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _workArea(context)),
                            if (wide && _showPanel) ...[
                              VerticalDivider(
                                width: 1,
                                color: cs.outlineVariant,
                              ),
                              SizedBox(
                                width: 300,
                                child: ColoredBox(
                                  color: cs.surfaceContainerLowest,
                                  child: panel(
                                    onClose: () =>
                                        setState(() => _showPanel = false),
                                  ),
                                ),
                              ),
                            ],
                            VerticalDivider(width: 1, color: cs.outlineVariant),
                            _panelRail(context, wide),
                          ],
                        ),
                      ),
                      _statusBar(context),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _workArea(BuildContext context) {
    if (_view == _View.outline) {
      return OutlineView(editor: editor);
    }
    if (_view == _View.gantt) {
      return GanttView(
        editor: editor,
        onOpenTask: (_) => _openPanel(PanelTab.elements),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final focusNode = editor.focusId == null
        ? null
        : editor.doc.nodes[editor.focusId];
    return Focus(
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
            showGrid: _showGrid && !_presenting,
            showMinimap: _showMinimap && !_presenting,
            highlightId: _presenting && _steps.isNotEmpty
                ? _steps[_step]
                : null,
            onContextMenu: _contextMenu,
            onMessage: _snack,
            onNodeDoubleClick: (_) {
              if (MediaQuery.sizeOf(context).width >= 760 && !_zen) {
                setState(() {
                  _panelTab = PanelTab.details;
                  _showPanel = true;
                });
              }
            },
            selectionToolbar: _presenting
                ? null
                : (_) => _selectionToolbar(context),
            onBadgeTap: _onBadgeTap,
            onFilesDropped: (files, nodeId, scene) => handleDroppedFiles(
              context,
              editor,
              files,
              nodeId: nodeId,
              scenePos: scene,
            ),
          ),
          if (focusNode != null && !_presenting)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.center_focus_weak,
                          size: 18,
                          color: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Foco: ${focusNode.text.replaceAll('\n', ' ')}',
                          style: TextStyle(color: cs.onPrimaryContainer),
                        ),
                        TextButton(
                          onPressed: () {
                            editor.setFocus(null);
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => canvas?.fitToScreen(),
                            );
                          },
                          child: const Text('Mostrar tudo (Esc)'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_presenting) _presentationBar(context),
          if (_zen && !_presenting)
            Positioned(
              top: 12,
              right: 12,
              child: FilledButton.tonalIcon(
                onPressed: () => setState(() => _zen = false),
                icon: const Icon(Icons.fullscreen_exit),
                label: const Text('Sair do modo Zen (Esc)'),
              ),
            ),
          if (editor.linkingFrom != null)
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Material(
                  color: cs.inverseSurface,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.moving,
                          size: 18,
                          color: cs.onInverseSurface,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Clique no tópico de destino da relação',
                          style: TextStyle(color: cs.onInverseSurface),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: editor.cancelRelation,
                          child: Text(
                            'Cancelar (Esc)',
                            style: TextStyle(color: cs.inversePrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _presentationBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = _steps.isEmpty ? null : _steps[_step];
    final title = id == null
        ? ''
        : editor.doc.nodes[id]?.text.replaceAll('\n', ' ') ?? '';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 20,
      child: Center(
        child: Material(
          color: cs.inverseSurface.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(28),
          elevation: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Anterior (←)',
                  color: cs.onInverseSurface,
                  onPressed: _step > 0 ? () => _goStep(_step - 1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Text(
                    '${_step + 1}/${_steps.length}  ·  $title',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: cs.onInverseSurface),
                  ),
                ),
                IconButton(
                  tooltip: 'Próximo (→ ou Espaço)',
                  color: cs.onInverseSurface,
                  onPressed: _step < _steps.length - 1
                      ? () => _goStep(_step + 1)
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: 4),
                TextButton.icon(
                  onPressed: _stopPresentation,
                  icon: Icon(Icons.close, color: cs.inversePrimary),
                  label: Text(
                    'Sair (Esc)',
                    style: TextStyle(color: cs.inversePrimary),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- barra de título

  Widget _titleBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final doc = editor.doc;
    final dirty = editor.hasUnsavedFileChanges;
    final narrow = MediaQuery.sizeOf(context).width < 980;
    return Material(
      color: cs.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Voltar à tela inicial',
                icon: const Icon(Icons.arrow_back),
                onPressed:
                    widget.onHome ?? () => Navigator.of(context).maybePop(),
              ),
              const MapLongMark(height: 20),
              const SizedBox(width: 8),
              Flexible(
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: _rename,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${doc.name}${dirty ? ' •' : ''}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          doc.filePath ?? 'Salvo automaticamente na biblioteca',
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _quick(
                Icons.undo,
                'Desfazer (Ctrl+Z)',
                editor.canUndo ? editor.undo : null,
              ),
              _quick(
                Icons.redo,
                'Refazer (Ctrl+Y)',
                editor.canRedo ? editor.redo : null,
              ),
              _quick(Icons.save_outlined, 'Salvar (Ctrl+S)', () => _save()),
              const Spacer(),
              SegmentedButton<_View>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: [
                  ButtonSegment(
                    value: _View.map,
                    icon: const Icon(Icons.hub_outlined, size: 18),
                    label: narrow ? null : const Text('Mapa'),
                  ),
                  ButtonSegment(
                    value: _View.outline,
                    icon: const Icon(Icons.format_list_bulleted, size: 18),
                    label: narrow ? null : const Text('Esboço'),
                  ),
                  ButtonSegment(
                    value: _View.gantt,
                    icon: const Icon(Icons.view_timeline_outlined, size: 18),
                    label: narrow ? null : const Text('Gantt'),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (s) {
                  editor.cancelRelation();
                  setState(() => _view = s.first);
                },
              ),
              const SizedBox(width: 6),
              IconButton(
                tooltip: 'Apresentar (F5)',
                onPressed: _startPresentation,
                icon: const Icon(Icons.slideshow_outlined),
              ),
              const SizedBox(width: 12),
              if (!narrow)
                SizedBox(
                  width: 210,
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _searchFocus,
                    onChanged: (_) => _searchIndex = -1,
                    onSubmitted: (_) {
                      if (_outline) setState(() => _view = _View.map);
                      _search(
                        backwards: HardwareKeyboard.instance.isShiftPressed,
                      );
                      _searchFocus.requestFocus();
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                      hintText: 'Localizar (Ctrl+F)',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
              const SizedBox(width: 8),
              MenuAnchor(
                builder: (context, c, _) => FilledButton.icon(
                  onPressed: () => c.isOpen ? c.close() : c.open(),
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('Exportar'),
                ),
                menuChildren: [
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.image_outlined),
                    shortcut: const SingleActivator(
                      LogicalKeyboardKey.keyE,
                      control: true,
                    ),
                    onPressed: _exportPng,
                    child: const Text('Imagem PNG'),
                  ),
                  for (final e in kExportFormats.entries)
                    MenuItemButton(
                      leadingIcon: Icon(switch (e.key) {
                        'pdf' => Icons.picture_as_pdf_outlined,
                        'doc' => Icons.description_outlined,
                        'csv' => Icons.table_chart_outlined,
                        'html' => Icons.language,
                        'opml' || 'mm' => Icons.account_tree_outlined,
                        _ => Icons.notes,
                      }),
                      onPressed: () => exportAs(
                        context,
                        doc,
                        e.key,
                        () async => canvas?.capturePng(),
                      ),
                      child: Text(e.value.$1),
                    ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.save_as_outlined),
                    shortcut: const SingleActivator(
                      LogicalKeyboardKey.keyS,
                      control: true,
                      shift: true,
                    ),
                    onPressed: () => _save(saveAs: true),
                    child: const Text('Arquivo MapLong (.maplong)'),
                  ),
                  MenuItemButton(
                    leadingIcon: const Icon(Icons.content_copy),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: editor.outlineText(doc.rootId)),
                      );
                      _snack('Tópicos copiados como texto.');
                    },
                    child: const Text('Copiar como texto'),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: widget.library.themeMode == ThemeMode.dark
                    ? 'Tema claro'
                    : 'Tema escuro',
                onPressed: widget.library.toggleTheme,
                icon: Icon(
                  widget.library.themeMode == ThemeMode.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quick(IconData i, String tip, VoidCallback? onTap) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    onPressed: onTap == null ? null : () => _run(onTap),
    icon: Icon(i),
  );

  // ----------------------------------------------------------- faixa (ribbon)

  Widget _ribbonTabs(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          const SizedBox(width: 12),
          for (final t in _RibbonTab.values)
            InkWell(
              onTap: () => setState(() => _ribbonTab = t),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _ribbonTabNames[t]!,
                      style: TextStyle(
                        fontWeight: _ribbonTab == t
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: _ribbonTab == t
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 3,
                      width: _ribbonTab == t ? 22 : 0,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ribbon(BuildContext context) {
    final sel = editor.selected;
    final isRoot = sel?.id == editor.doc.rootId;
    final hasSel = sel != null;
    final doc = editor.doc;
    final cs = Theme.of(context).colorScheme;

    final List<Widget> items = switch (_ribbonTab) {
      _RibbonTab.home => [
        RibbonButton(
          icon: Icons.content_paste,
          label: 'Colar',
          onTap: () => _run(_paste),
          menu: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.content_paste, size: 18),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                control: true,
              ),
              onPressed: () => _run(_paste),
              child: const Text('Colar'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.text_snippet_outlined, size: 18),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyV,
                control: true,
                shift: true,
              ),
              onPressed: () => _run(() => _paste(asText: true)),
              child: const Text('Colar texto como tópicos'),
            ),
          ],
        ),
        RibbonStack(
          children: [
            RibbonSmallButton(
              icon: Icons.content_cut,
              tip: 'Recortar (Ctrl+X)',
              onTap: hasSel && !isRoot
                  ? () => _run(() => _copy(cut: true))
                  : null,
            ),
            RibbonSmallButton(
              icon: Icons.copy,
              tip: 'Copiar (Ctrl+C)',
              onTap: hasSel ? () => _run(_copy) : null,
            ),
          ],
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.add_box_outlined,
          label: 'Tópico',
          onTap: () => _run(() => editor.addSibling()),
          menu: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.south, size: 18),
              shortcut: const SingleActivator(LogicalKeyboardKey.enter),
              onPressed: () => _run(() => editor.addSibling()),
              child: const Text('Tópico depois'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.north, size: 18),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.enter,
                shift: true,
              ),
              onPressed: () => _run(() => editor.addSiblingBefore()),
              child: const Text('Tópico antes'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.account_tree_outlined, size: 18),
              shortcut: const SingleActivator(
                LogicalKeyboardKey.insert,
                shift: true,
              ),
              onPressed: () => _run(() => editor.addMainTopic()),
              child: const Text('Ramo principal'),
            ),
          ],
        ),
        RibbonButton(
          icon: Icons.subdirectory_arrow_right,
          label: 'Subtópico',
          tip: 'Adicionar subtópico (Tab)',
          onTap: () => _run(() => editor.addChild()),
        ),
        RibbonButton(
          icon: Icons.bubble_chart_outlined,
          label: 'Flutuante',
          tip: 'Tópico flutuante (Alt+F ou duplo clique no fundo)',
          onTap: () => _run(_addFloating),
        ),
        RibbonButton(
          icon: Icons.playlist_add,
          label: 'Vários tópicos',
          onTap: _addMultiple,
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.moving,
          label: 'Relação',
          tip: 'Ligar dois tópicos com uma seta (Ctrl+R)',
          onTap: hasSel ? _startRelation : null,
        ),
        RibbonButton(
          icon: Icons.category_outlined,
          label: 'Formato',
          onTap: null,
          enabled: hasSel,
          menu: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: 250,
                child: ShapeGrid(
                  selected: sel?.shape ?? '',
                  onPick: (s) {
                    if (sel != null) {
                      editor.updateNode(
                        sel.id,
                        (n) => n.shape = s,
                        relayout: true,
                      );
                    }
                  },
                ),
              ),
            ),
          ],
        ),
        RibbonButton(
          icon: Icons.format_paint_outlined,
          label: 'Estilo',
          onTap: () => _openPanel(PanelTab.style),
        ),
        RibbonButton(
          icon: Icons.brush,
          label: editor.copiedStyle == null ? 'Pincel' : 'Colar estilo',
          tip: 'Pincel de formato: copia o estilo do tópico e aplica em outros',
          active: editor.copiedStyle != null,
          onTap: hasSel
              ? () => _run(() {
                  if (editor.copiedStyle == null) {
                    editor.copyStyle();
                    _snack(
                      'Estilo copiado. Selecione outro tópico e clique em "Colar estilo".',
                    );
                  } else {
                    editor.pasteStyle();
                  }
                })
              : null,
          menu: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.copy, size: 18),
              onPressed: hasSel ? () => _run(editor.copyStyle) : null,
              child: const Text('Copiar estilo (Ctrl+Alt+C)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.format_color_fill, size: 18),
              onPressed: editor.copiedStyle == null
                  ? null
                  : () => _run(editor.pasteStyle),
              child: const Text('Colar estilo (Ctrl+Alt+V)'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.clear, size: 18),
              onPressed: editor.copiedStyle == null
                  ? null
                  : () => setState(() => editor.copiedStyle = null),
              child: const Text('Limpar pincel'),
            ),
          ],
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: (sel?.collapsed ?? false)
              ? Icons.unfold_more
              : Icons.unfold_less,
          label: (sel?.collapsed ?? false) ? 'Expandir' : 'Recolher',
          tip: 'Recolher/expandir ramo (/)',
          onTap: sel == null || sel.childrenIds.isEmpty
              ? null
              : () => _run(() => editor.toggleCollapse()),
        ),
        RibbonButton(
          icon: Icons.delete_outline,
          label: 'Excluir',
          tip: 'Excluir tópico (Del)',
          onTap: hasSel && !isRoot
              ? () => _run(() => editor.deleteNode())
              : null,
        ),
        RibbonButton(
          icon: Icons.auto_fix_high,
          label: 'Organizar',
          tip: 'Organizar mapa automaticamente (Ctrl+L)',
          onTap: () => _run(editor.arrangeNow),
        ),
      ],
      _RibbonTab.insert => [
        RibbonButton(
          icon: Icons.subdirectory_arrow_right,
          label: 'Subtópico',
          onTap: () => _run(() => editor.addChild()),
        ),
        RibbonButton(
          icon: Icons.account_tree_outlined,
          label: 'Ramo principal',
          onTap: () => _run(() => editor.addMainTopic()),
        ),
        RibbonButton(
          icon: Icons.playlist_add,
          label: 'Vários tópicos',
          onTap: _addMultiple,
        ),
        RibbonButton(
          icon: Icons.bubble_chart_outlined,
          label: 'Flutuante',
          onTap: () => _run(_addFloating),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.moving,
          label: 'Relação',
          onTap: hasSel ? _startRelation : null,
        ),
        RibbonButton(
          icon: Icons.flag_outlined,
          label: 'Marcador',
          onTap: () => _openPanel(PanelTab.markers),
        ),
        RibbonButton(
          icon: Icons.emoji_emotions_outlined,
          label: 'Adesivo',
          onTap: () => _openPanel(PanelTab.stickers),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.add_photo_alternate_outlined,
          label: 'Imagem',
          tip: 'Inserir imagem no tópico selecionado',
          onTap: _insertImage,
          menu: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.image_outlined, size: 18),
              onPressed: _insertImage,
              child: const Text('No tópico selecionado'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.subdirectory_arrow_right, size: 18),
              onPressed: hasSel ? () => _insertImage(asNewTopic: true) : null,
              child: const Text('Como novo subtópico'),
            ),
          ],
        ),
        RibbonButton(
          icon: Icons.attach_file,
          label: 'Documento',
          tip: 'Anexar PDF, Word, Excel ou qualquer arquivo',
          onTap: _attachDocuments,
        ),
        RibbonButton(
          icon: Icons.add_link,
          label: 'Link',
          onTap: () => _addLink(),
          menu: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.public, size: 18),
              onPressed: () => _addLink('web'),
              child: const Text('Site'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.alternate_email, size: 18),
              onPressed: () => _addLink('email'),
              child: const Text('E-mail'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.call_outlined, size: 18),
              onPressed: () => _addLink('phone'),
              child: const Text('Telefone'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.folder_open_outlined, size: 18),
              onPressed: () => _addLink('file'),
              child: const Text('Pasta ou arquivo do computador'),
            ),
          ],
        ),
        RibbonButton(
          icon: Icons.perm_media_outlined,
          label: 'Mídia',
          tip: 'Área de imagens e documentos',
          onTap: () => _openPanel(PanelTab.media),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.chat_bubble_outline,
          label: 'Balão',
          tip: 'Balão de observação acima do tópico',
          onTap: () => _element((n) => n.callouts.add('Observação')),
        ),
        RibbonButton(
          icon: Icons.crop_free,
          label: 'Limite',
          tip: 'Contorno em volta do ramo',
          active: sel?.boundary ?? false,
          onTap: () => _element((n) => n.boundary = !n.boundary),
        ),
        RibbonButton(
          icon: Icons.data_array,
          label: 'Resumo',
          tip: 'Chave resumindo os subtópicos',
          active: sel?.summary != null,
          onTap: sel == null || sel.childrenIds.isEmpty
              ? null
              : () => _element(
                  (n) => n.summary = n.summary == null ? 'Resumo' : null,
                ),
        ),
        RibbonButton(
          icon: Icons.table_chart_outlined,
          label: 'Tabela',
          onTap: () => _element(
            (n) => n.table ??= [
              ['Item', 'Valor'],
              ['', ''],
              ['', ''],
            ],
          ),
        ),
        RibbonButton(
          icon: Icons.functions,
          label: 'Fórmula',
          onTap: () => _element((n) => n.formula ??= r'E = mc^2'),
        ),
        RibbonButton(
          icon: Icons.forum_outlined,
          label: 'Comentário',
          onTap: () => _openPanel(PanelTab.elements),
        ),
        RibbonButton(
          icon: Icons.task_alt,
          label: 'Tarefa',
          onTap: () => _element((n) {
            if (n.task != null) return;
            final now = DateTime.now();
            final day = DateTime(now.year, now.month, now.day);
            n.task = NodeTask(
              start: day.millisecondsSinceEpoch,
              end: day.add(const Duration(days: 3)).millisecondsSinceEpoch,
            );
          }),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.sell_outlined,
          label: 'Etiqueta',
          onTap: () => _openPanel(PanelTab.details),
        ),
        RibbonButton(
          icon: Icons.sticky_note_2_outlined,
          label: 'Anotação',
          onTap: () => _openPanel(PanelTab.details),
        ),
        RibbonButton(
          icon: Icons.format_list_numbered,
          label: 'Numeração',
          active: doc.numbering,
          onTap: () => _run(() => editor.setNumbering(!doc.numbering)),
        ),
      ],
      _RibbonTab.design => [
        RibbonButton(
          icon: Icons.schema_outlined,
          label: 'Estrutura',
          onTap: null,
          menu: [
            for (final e in kLayouts.entries)
              MenuItemButton(
                leadingIcon: SizedBox(
                  width: 56,
                  height: 30,
                  child: CustomPaint(
                    painter: LayoutGlyph(e.key, cs.primary, cs.outline),
                  ),
                ),
                trailingIcon: doc.layout == e.key
                    ? Icon(Icons.check, size: 18, color: cs.primary)
                    : null,
                onPressed: () => _run(() => editor.setLayout(e.key)),
                child: Text(e.value),
              ),
          ],
        ),
        RibbonButton(
          icon: Icons.palette_outlined,
          label: 'Tema',
          onTap: null,
          menu: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: SizedBox(
                width: 300,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final t in kThemes)
                      SizedBox(
                        width: 142,
                        height: 44,
                        child: InkWell(
                          onTap: () => _run(() => editor.applyTheme(t.id)),
                          borderRadius: BorderRadius.circular(8),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: doc.themeId == t.id
                                    ? cs.primary
                                    : cs.outlineVariant,
                                width: doc.themeId == t.id ? 2 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: ThemeSwatch(theme: t),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        RibbonButton(
          icon: Icons.timeline,
          label: 'Ramificação',
          onTap: null,
          menu: [
            for (final e in kConnectorStyles.entries)
              MenuItemButton(
                trailingIcon: doc.connectorStyle == e.key
                    ? Icon(Icons.check, size: 18, color: cs.primary)
                    : null,
                onPressed: () => _run(() => editor.setConnector(style: e.key)),
                child: Text(e.value),
              ),
          ],
        ),
        RibbonButton(
          icon: Icons.format_color_fill,
          label: 'Fundo',
          onTap: () => _openPanel(PanelTab.map),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: doc.autoLayout ? Icons.toggle_on : Icons.toggle_off_outlined,
          label: 'Auto-organizar',
          active: doc.autoLayout,
          onTap: () => _run(() => editor.setAutoLayout(!doc.autoLayout)),
        ),
        RibbonButton(
          icon: Icons.auto_fix_high,
          label: 'Organizar agora',
          onTap: () => _run(editor.arrangeNow),
        ),
        RibbonButton(
          icon: Icons.tune,
          label: 'Mais opções',
          onTap: () => _openPanel(PanelTab.map),
        ),
      ],
      _RibbonTab.view => [
        RibbonButton(
          icon: Icons.fit_screen_outlined,
          label: 'Ajustar',
          tip: 'Ajustar à tela (Ctrl+0)',
          onTap: () => _run(() => canvas?.fitToScreen()),
        ),
        RibbonButton(
          icon: Icons.center_focus_strong_outlined,
          label: 'Centralizar',
          onTap: () => _run(() => canvas?.centerOn(doc.rootId)),
        ),
        RibbonButton(
          icon: Icons.zoom_in,
          label: 'Aproximar',
          onTap: () => _run(() => canvas?.zoomBy(1.2)),
        ),
        RibbonButton(
          icon: Icons.zoom_out,
          label: 'Afastar',
          onTap: () => _run(() => canvas?.zoomBy(1 / 1.2)),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.unfold_more,
          label: 'Expandir tudo',
          onTap: () => _run(() => editor.setAllCollapsed(false)),
        ),
        RibbonButton(
          icon: Icons.unfold_less,
          label: 'Recolher tudo',
          onTap: () => _run(() => editor.setAllCollapsed(true)),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.grid_4x4,
          label: 'Grade',
          active: _showGrid,
          onTap: () => setState(() => _showGrid = !_showGrid),
        ),
        RibbonButton(
          icon: Icons.view_sidebar_outlined,
          label: 'Painel',
          active: _showPanel,
          onTap: () => setState(() => _showPanel = !_showPanel),
        ),
        RibbonButton(
          icon: Icons.format_list_bulleted,
          label: 'Esboço',
          active: _view == _View.outline,
          onTap: () => setState(
            () => _view = _view == _View.outline ? _View.map : _View.outline,
          ),
        ),
        RibbonButton(
          icon: Icons.view_timeline_outlined,
          label: 'Gantt',
          active: _view == _View.gantt,
          onTap: () => setState(
            () => _view = _view == _View.gantt ? _View.map : _View.gantt,
          ),
        ),
        RibbonButton(
          icon: Icons.map_outlined,
          label: 'Minimapa',
          active: _showMinimap,
          onTap: () => setState(() => _showMinimap = !_showMinimap),
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.slideshow_outlined,
          label: 'Apresentar',
          tip: 'Apresentação ramo a ramo (F5)',
          onTap: _startPresentation,
        ),
        RibbonButton(
          icon: Icons.fullscreen,
          label: 'Zen',
          tip: 'Só o mapa, sem distrações (F11)',
          onTap: () => setState(() => _zen = true),
        ),
        RibbonButton(
          icon: Icons.center_focus_weak,
          label: editor.focusId == null ? 'Focar ramo' : 'Mostrar tudo',
          active: editor.focusId != null,
          onTap: () {
            editor.setFocus(editor.focusId == null ? editor.selectedId : null);
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => canvas?.fitToScreen(),
            );
          },
        ),
        const RibbonDivider(),
        RibbonButton(
          icon: Icons.find_replace,
          label: 'Substituir',
          tip: 'Localizar e substituir (Ctrl+H)',
          onTap: _findReplace,
        ),
        RibbonButton(
          icon: Icons.history,
          label: 'Versões',
          tip: 'Histórico de versões do mapa',
          onTap: _showVersions,
        ),
        RibbonButton(
          icon: Icons.insights_outlined,
          label: 'Estatísticas',
          onTap: _showStats,
        ),
        RibbonButton(
          icon: widget.library.themeMode == ThemeMode.dark
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
          label: widget.library.themeMode == ThemeMode.dark
              ? 'Modo claro'
              : 'Modo escuro',
          onTap: widget.library.toggleTheme,
        ),
      ],
    };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Row(children: items),
    );
  }

  // --------------------------------------------------------- barra flutuante

  Widget _selectionToolbar(BuildContext context) {
    final n = editor.selected;
    if (n == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final id = n.id;

    Widget colorMenu(
      IconData icon,
      String tip,
      Color? swatch,
      List<String> colors,
      String selected,
      ValueChanged<String> pick,
    ) => MenuAnchor(
      menuChildren: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            width: 200,
            child: ColorRow(
              colors: colors,
              selected: selected,
              onPick: (c) => _run(() => pick(c)),
            ),
          ),
        ),
      ],
      builder: (context, c, _) => IconButton(
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: () => c.isOpen ? c.close() : c.open(),
        icon: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            Container(
              width: 16,
              height: 3,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: swatch ?? cs.outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );

    Widget tool(
      IconData i,
      String tip,
      VoidCallback onTap, {
      bool on = false,
    }) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      isSelected: on,
      style: IconButton.styleFrom(
        backgroundColor: on ? cs.primaryContainer : null,
      ),
      iconSize: 19,
      onPressed: () => _run(onTap),
      icon: Icon(i),
    );

    const gap = SizedBox(
      height: 26,
      child: VerticalDivider(width: 10, indent: 3, endIndent: 3),
    );

    return Material(
      elevation: 6,
      shadowColor: Colors.black38,
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FontSizeStepper(
              value: n.fontSize,
              onChanged: (v) => _run(
                () => editor.updateNode(
                  id,
                  (n) => n.fontSize = v,
                  relayout: true,
                ),
              ),
            ),
            const SizedBox(width: 4),
            tool(
              Icons.format_bold,
              'Negrito',
              on: n.bold,
              () => editor.updateNode(
                id,
                (n) => n.bold = !n.bold,
                relayout: true,
              ),
            ),
            tool(
              Icons.format_italic,
              'Itálico',
              on: n.italic,
              () => editor.updateNode(
                id,
                (n) => n.italic = !n.italic,
                relayout: true,
              ),
            ),
            colorMenu(
              Icons.format_color_text,
              'Cor do texto',
              parseHex(n.textColor),
              const ['', '#FFFFFF', '#15171F', ...kPalette],
              n.textColor ?? '',
              (c) => editor.updateNode(
                id,
                (n) => n.textColor = c.isEmpty ? null : c,
              ),
            ),
            gap,
            MenuAnchor(
              menuChildren: [
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: SizedBox(
                    width: 250,
                    child: ShapeGrid(
                      selected: n.shape,
                      onPick: (s) => _run(
                        () => editor.updateNode(
                          id,
                          (n) => n.shape = s,
                          relayout: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              builder: (context, c, _) => IconButton(
                tooltip: 'Formato',
                visualDensity: VisualDensity.compact,
                iconSize: 19,
                onPressed: () => c.isOpen ? c.close() : c.open(),
                icon: const Icon(Icons.crop_square),
              ),
            ),
            colorMenu(
              Icons.format_color_fill,
              'Preenchimento',
              parseHex(n.fillColor),
              kFillPalette,
              n.fillColor ?? '',
              (c) => editor.updateNode(
                id,
                (n) => n.fillColor = c.isEmpty ? null : c,
              ),
            ),
            colorMenu(
              Icons.border_color_outlined,
              'Cor da borda e do ramo',
              parseHex(n.color),
              {...editor.doc.theme.palette, ...kPalette}.toList(),
              n.color,
              (c) => editor.updateNode(id, (n) => n.color = c),
            ),
            gap,
            tool(
              Icons.subdirectory_arrow_right,
              'Subtópico (Tab)',
              () => editor.addChild(),
            ),
            tool(Icons.moving, 'Relação (Ctrl+R)', _startRelation),
            tool(
              Icons.add_photo_alternate_outlined,
              'Imagem',
              _insertImage,
              on: n.image != null,
            ),
            tool(Icons.add_link, 'Link', () => _addLink(), on: n.hasLink),
            tool(
              Icons.attach_file,
              'Documentos',
              () => _openPanel(PanelTab.media),
              on: n.attachments.isNotEmpty,
            ),
            tool(
              Icons.flag_outlined,
              'Marcadores',
              () => _openPanel(PanelTab.markers),
              on: n.markers.isNotEmpty,
            ),
            tool(
              Icons.emoji_emotions_outlined,
              'Adesivo',
              () => _openPanel(PanelTab.stickers),
              on: n.sticker != null,
            ),
            tool(
              Icons.sticky_note_2_outlined,
              'Anotação',
              () => _openPanel(PanelTab.details),
              on: n.note.trim().isNotEmpty,
            ),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------- painel lateral

  Widget _panelRail(BuildContext context, bool wide) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 52,
      color: cs.surfaceContainerLow,
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final t in PanelTab.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: IconButton(
                tooltip: t.title,
                isSelected: _showPanel && _panelTab == t,
                style: IconButton.styleFrom(
                  backgroundColor: _showPanel && _panelTab == t
                      ? cs.primaryContainer
                      : null,
                  foregroundColor: _showPanel && _panelTab == t
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(t.icon),
                onPressed: () {
                  if (!wide) {
                    _openPanel(t);
                    return;
                  }
                  setState(() {
                    if (_showPanel && _panelTab == t) {
                      _showPanel = false;
                    } else {
                      _panelTab = t;
                      _showPanel = true;
                    }
                  });
                },
              ),
            ),
          const Spacer(),
          IconButton(
            tooltip: 'Atalhos de teclado',
            icon: const Icon(Icons.keyboard_outlined),
            color: cs.onSurfaceVariant,
            onPressed: () => showShortcutsDialog(context),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ barra de status

  Widget _statusBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme.bodySmall;
    final doc = editor.doc;
    final sel = editor.selected;
    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.hub_outlined, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text('Tópicos: ${doc.nodes.length}', style: t),
          if (doc.relations.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text('Relações: ${doc.relations.length}', style: t),
          ],
          if (editor.multi.isNotEmpty) ...[
            const SizedBox(width: 12),
            Text('${editor.selection.length} selecionados', style: t),
          ] else if (sel != null) ...[
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                '[${sel.text.replaceAll('\n', ' ')}]',
                overflow: TextOverflow.ellipsis,
                style: t,
              ),
            ),
          ],
          const Spacer(),
          Icon(Icons.cloud_done_outlined, size: 14, color: cs.primary),
          const SizedBox(width: 4),
          Text('Salvo', style: t),
          const SizedBox(width: 12),
          if (!_outline) ...[
            IconButton(
              tooltip: 'Afastar',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () => canvas?.zoomBy(1 / 1.2),
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 110,
              child: ValueListenableBuilder<double>(
                valueListenable: _scale,
                builder: (_, s, _) => SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    overlayShape: SliderComponentShape.noOverlay,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    value: s.clamp(0.1, 3.0),
                    min: 0.1,
                    max: 3,
                    onChanged: (v) => canvas?.setZoom(v),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Aproximar',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () => canvas?.zoomBy(1.2),
              icon: const Icon(Icons.add),
            ),
            ValueListenableBuilder<double>(
              valueListenable: _scale,
              builder: (_, s, _) => InkWell(
                onTap: () => canvas?.resetZoom(),
                child: SizedBox(
                  width: 44,
                  child: Text(
                    '${(s * 100).round()}%',
                    textAlign: TextAlign.center,
                    style: t,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Ajustar à tela (Ctrl+0)',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: () => canvas?.fitToScreen(),
              icon: const Icon(Icons.fit_screen_outlined),
            ),
          ],
        ],
      ),
    );
  }
}

void showShortcutsDialog(BuildContext context) {
  const rows = [
    ('Tab', 'Novo subtópico'),
    ('Enter', 'Tópico depois'),
    ('Shift+Enter', 'Tópico antes'),
    ('Shift+Ins', 'Novo ramo principal'),
    ('Alt+F', 'Tópico flutuante'),
    ('Ctrl+R', 'Criar relação'),
    ('F2 / Espaço', 'Editar texto'),
    ('Del', 'Excluir tópico'),
    ('Setas', 'Navegar entre tópicos'),
    ('Alt+↑ / Alt+↓', 'Reordenar entre irmãos'),
    ('/', 'Recolher/expandir ramo'),
    ('Ctrl+C / X / V', 'Copiar / recortar / colar'),
    ('Ctrl+Shift+V', 'Colar texto como tópicos'),
    ('Ctrl+Z / Ctrl+Y', 'Desfazer / refazer'),
    ('Ctrl+L', 'Organizar mapa'),
    ('Ctrl+0', 'Ajustar à tela'),
    ('Ctrl+F', 'Localizar'),
    ('Ctrl+S', 'Salvar arquivo .maplong'),
    ('Ctrl+E', 'Exportar PNG'),
    ('2 cliques', 'Editar nome e informações do tópico'),
    ('3 cliques', 'Criar tópico conectado'),
    ('Ctrl/Shift + clique', 'Selecionar vários tópicos'),
    ('Ctrl+A', 'Selecionar tudo'),
    ('Ctrl+H', 'Localizar e substituir'),
    ('Ctrl+Alt+C / V', 'Copiar / colar estilo'),
    ('F5', 'Apresentação'),
    ('F11', 'Modo Zen'),
    ('Ctrl+T', 'Novo mapa em nova aba'),
    ('Ctrl+W', 'Fechar aba'),
    ('Ctrl+Tab', 'Próxima aba'),
    ('Ctrl+1…9', 'Ir para a aba'),
  ];
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Atalhos de teclado'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 130,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          r.$1,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(child: Text(r.$2)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
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
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, c.text),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
  return result;
}
