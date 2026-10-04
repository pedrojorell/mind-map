import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_info.dart';
import '../import_export.dart';
import '../services/updates.dart';
import '../widgets/app_dialogs.dart';

import '../library.dart';
import '../models.dart';
import '../templates.dart';
import 'editor_screen.dart';
import '../widgets/brand.dart';
import 'home_screen.dart';

/// Janela principal com abas, como num navegador: a aba "Início" e uma aba
/// para cada mapa aberto. Os mapas continuam abertos (com zoom, seleção e
/// histórico) ao trocar de aba.
class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.library,
    this.initialFiles = const [],
  });

  final Library library;

  /// Arquivos para abrir em abas logo ao iniciar.
  final List<String> initialFiles;

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  final List<String> _open = [];

  /// Aba ativa: -1 = Início; demais = índice em [_open].
  int _active = -1;

  Library get lib => widget.library;

  @override
  void initState() {
    super.initState();
    lib.addListener(_onLibrary);
    _openFiles(widget.initialFiles);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStart());
    // Arquivos enviados por uma segunda janela do MapLong (Windows).
    _openFilesChannel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is List) {
        await _openFiles((call.arguments as List).whereType<String>().toList());
      }
    });
  }

  static const _openFilesChannel = MethodChannel('maplong/open_files');

  /// Versão nova encontrada no GitHub (mostrada numa faixa no topo).
  UpdateInfo? _update;

  /// Boas-vindas na primeira abertura e verificação de atualização.
  Future<void> _onStart() async {
    if (!mounted) return;
    if (!lib.welcomeSeen && widget.initialFiles.isEmpty) {
      await showWelcomeDialog(context, lib);
    }
    if (!lib.checkUpdates) return;
    final info = await checkForUpdate();
    if (info != null && mounted) setState(() => _update = info);
  }

  Future<void> _openFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        final doc = await importFromPath(lib, path);
        if (doc != null && mounted) openDoc(doc);
      } catch (e) {
        debugPrint('MapLong: não foi possível abrir $path: $e');
      }
    }
  }

  @override
  void dispose() {
    _openFilesChannel.setMethodCallHandler(null);
    lib.removeListener(_onLibrary);
    super.dispose();
  }

  /// Fecha abas de mapas que foram excluídos da biblioteca.
  void _onLibrary() {
    final gone = _open.where((id) => lib.doc(id) == null).toList();
    if (gone.isEmpty) {
      setState(() {}); // nomes das abas podem ter mudado
      return;
    }
    setState(() {
      final activeId = _active >= 0 ? _open[_active] : null;
      _open.removeWhere(gone.contains);
      _active = activeId == null ? -1 : _open.indexOf(activeId);
    });
  }

  void openDoc(MindMapDoc doc) {
    setState(() {
      var i = _open.indexOf(doc.id);
      if (i < 0) {
        _open.add(doc.id);
        i = _open.length - 1;
      }
      _active = i;
    });
  }

  void _newMap() {
    final t = kTemplates.firstWhere((t) => t.title == 'Clássico');
    final doc = docFromTemplate(lib.uniqueName('Novo mapa'), t);
    lib.add(doc);
    openDoc(doc);
  }

  void _close(int i) {
    setState(() {
      final activeId = _active >= 0 ? _open[_active] : null;
      _open.removeAt(i);
      if (activeId == null) return;
      final j = _open.indexOf(activeId);
      // Fechou a aba ativa: vai para a vizinha (ou para o Início).
      _active = j >= 0 ? j : (i - 1).clamp(-1, _open.length - 1);
    });
  }

  void _select(int i) => setState(() => _active = i);

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final hk = HardwareKeyboard.instance;
    if (!hk.isControlPressed && !hk.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.keyT) {
      _newMap();
    } else if (k == LogicalKeyboardKey.keyW) {
      if (_active >= 0) _close(_active);
    } else if (k == LogicalKeyboardKey.tab) {
      final n = _open.length + 1;
      final dir = hk.isShiftPressed ? -1 : 1;
      _select(((_active + 1 + dir) % n + n) % n - 1);
    } else if (k.keyId >= LogicalKeyboardKey.digit1.keyId &&
        k.keyId <= LogicalKeyboardKey.digit9.keyId) {
      final i = k.keyId - LogicalKeyboardKey.digit1.keyId;
      _select(i == 0 ? -1 : (i - 1).clamp(-1, _open.length - 1));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        body: Column(
          children: [
            _TabStrip(
              library: lib,
              open: _open,
              active: _active,
              onSelect: _select,
              onClose: _close,
              onNew: _newMap,
            ),
            if (_update case final info?)
              _UpdateBar(
                info: info,
                onOpen: () => showUpdateDialog(context, info),
                onDismiss: () => setState(() => _update = null),
              ),
            Expanded(
              child: IndexedStack(
                index: _active + 1,
                children: [
                  HomeScreen(library: lib, onOpen: openDoc),
                  for (var i = 0; i < _open.length; i++)
                    if (lib.doc(_open[i]) case final doc?)
                      TickerMode(
                        key: ValueKey(doc.id),
                        enabled: i == _active,
                        child: EditorScreen(
                          library: lib,
                          doc: doc,
                          active: i == _active,
                          onHome: () => _select(-1),
                        ),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabStrip extends StatelessWidget {
  const _TabStrip({
    required this.library,
    required this.open,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onNew,
  });

  final Library library;
  final List<String> open;
  final int active;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onClose;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 6),
              _Tab(
                selected: active == -1,
                icon: const MapLongMark(height: 14),
                label: 'Início',
                onTap: () => onSelect(-1),
                width: 110,
              ),
              Expanded(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(scrollbars: false),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < open.length; i++)
                        if (library.doc(open[i]) case final doc?)
                          _Tab(
                            selected: active == i,
                            icon: Icon(
                              Icons.hub,
                              size: 15,
                              color: parseHex(doc.root.fillColor) ?? cs.primary,
                            ),
                            label: doc.name,
                            tooltip: doc.filePath ?? doc.name,
                            onTap: () => onSelect(i),
                            onClose: () => onClose(i),
                          ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: IconButton(
                          tooltip: 'Novo mapa em nova aba (Ctrl+T)',
                          visualDensity: VisualDensity.compact,
                          iconSize: 20,
                          onPressed: onNew,
                          icon: const Icon(Icons.add),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatefulWidget {
  const _Tab({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClose,
    this.tooltip,
    this.width = 200,
  });

  final bool selected;
  final Widget icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClose;
  final String? tooltip;
  final double width;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sel = widget.selected;
    return Padding(
      padding: const EdgeInsets.only(top: 5, right: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Listener(
          // Clique com o botão do meio fecha a aba, como no navegador.
          onPointerDown: (e) {
            if (e.buttons == kMiddleMouseButton) widget.onClose?.call();
          },
          child: Tooltip(
            message: widget.tooltip ?? widget.label,
            waitDuration: const Duration(milliseconds: 700),
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10),
              ),
              child: Container(
                width: widget.width,
                padding: const EdgeInsets.only(left: 12, right: 4),
                decoration: BoxDecoration(
                  color: sel
                      ? cs.surface
                      : _hover
                      ? cs.surface.withValues(alpha: 0.5)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                  border: sel
                      ? Border(top: BorderSide(color: cs.primary, width: 2.5))
                      : null,
                ),
                child: Row(
                  children: [
                    widget.icon,
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                          color: sel ? cs.onSurface : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                    if (widget.onClose != null)
                      Opacity(
                        opacity: sel || _hover ? 1 : 0.55,
                        child: IconButton(
                          tooltip: 'Fechar aba (Ctrl+W)',
                          visualDensity: VisualDensity.compact,
                          iconSize: 15,
                          style: IconButton.styleFrom(
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            minimumSize: const Size(26, 26),
                            fixedSize: const Size(26, 26),
                            padding: EdgeInsets.zero,
                          ),
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Faixa discreta avisando que há uma versão nova.
class _UpdateBar extends StatelessWidget {
  const _UpdateBar({
    required this.info,
    required this.onOpen,
    required this.onDismiss,
  });

  final UpdateInfo info;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.system_update_alt,
              size: 18,
              color: cs.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'MapLong ${info.version} está disponível '
                '(você usa a $kAppVersion).',
                style: TextStyle(color: cs.onPrimaryContainer),
              ),
            ),
            TextButton(onPressed: onOpen, child: const Text('Ver novidades')),
            IconButton(
              tooltip: 'Dispensar',
              visualDensity: VisualDensity.compact,
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
