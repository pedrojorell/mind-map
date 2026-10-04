import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../file_actions.dart';
import '../import_export.dart';
import '../layout.dart';
import '../library.dart';
import '../models.dart';
import '../templates.dart';
import '../widgets/app_dialogs.dart';
import '../widgets/brand.dart';
import 'editor_screen.dart';

enum _Section { home, maps, favorites, templates, trash }

enum _Sort { recent, name, size }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.library, this.onOpen});

  final Library library;

  /// Abre o mapa (numa aba). Sem ele, abre o editor numa nova tela.
  final ValueChanged<MindMapDoc>? onOpen;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = '';
  _Section _section = _Section.home;
  String _category = kTemplateCategories.first;
  _Sort _sort = _Sort.recent;
  bool _grid = false;

  Library get lib => widget.library;

  Future<void> _open(MindMapDoc doc) async {
    if (widget.onOpen != null) {
      widget.onOpen!(doc);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EditorScreen(library: lib, doc: doc),
      ),
    );
    if (mounted) setState(() {});
  }

  void _create(MapTemplate t) {
    final name = lib.uniqueName(
      t.title == 'Em branco' || t.title == 'Clássico' ? 'Novo mapa' : t.title,
    );
    final doc = docFromTemplate(name, t);
    lib.add(doc);
    _open(doc);
  }

  void _createFromText(String text) {
    final first = text
        .split(RegExp(r'\r?\n'))
        .map(cleanOutlineLine)
        .firstWhere((l) => l.isNotEmpty, orElse: () => 'Novo mapa');
    final name = lib.uniqueName(
      first.length > 40 ? '${first.substring(0, 40)}…' : first,
    );
    final doc = docFromOutline(name, text);
    lib.add(doc);
    _open(doc);
  }

  Future<void> _textToMapDialog() async {
    final c = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Texto para mapa mental'),
        content: SizedBox(
          width: 480,
          child: _TextToMapField(controller: c, minLines: 8),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Gerar mapa'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => c.dispose());
    if (text != null && text.trim().isNotEmpty) _createFromText(text);
  }

  Future<void> _fromClipboard() async {
    String text = '';
    try {
      text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {}
    if (!mounted) return;
    if (text.trim().isEmpty) {
      showSnack(context, 'A área de transferência está vazia.');
      return;
    }
    _createFromText(text);
  }

  Future<void> _openFile() async {
    final doc = await importFromFile(context, lib);
    if (doc != null) _open(doc);
  }

  Future<void> _rename(MindMapDoc d) async {
    final name = await promptText(
      context,
      title: 'Renomear mapa',
      initial: d.name,
      label: 'Nome',
    );
    if (name != null) lib.rename(d.id, name);
  }

  /// Envia para a lixeira, com opção de desfazer.
  Future<void> _delete(MindMapDoc d) async {
    await lib.moveToTrash(d.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 420,
          content: Text('“${d.name}” foi para a lixeira.'),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () => lib.restore(d.id),
          ),
        ),
      );
  }

  /// Apaga de vez (na lixeira).
  Future<void> _deleteForever(MindMapDoc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir definitivamente?'),
        content: Text(
          '“${d.name}” será apagado para sempre. Arquivos .maplong salvos no disco não são apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (ok == true) await lib.delete(d.id);
  }

  Future<void> _export(MindMapDoc d) async {
    try {
      final r = await saveBytesAs(
        fileName: d.name,
        ext: kFileExtension,
        bytes: encodeDoc(d),
        dialogTitle: 'Salvar mapa mental',
      );
      if (!r.ok) return;
      if (r.path != null) {
        d.filePath = r.path;
        await lib.saveNow(d);
      }
      if (mounted) {
        showSnack(
          context,
          r.path == null ? 'Arquivo baixado.' : 'Salvo em ${r.path}',
        );
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Erro ao salvar: $e');
    }
  }

  void _docAction(MindMapDoc d, String a) {
    switch (a) {
      case 'open':
        _open(d);
      case 'rename':
        _rename(d);
      case 'duplicate':
        lib.duplicate(d.id);
      case 'export':
        _export(d);
      case 'delete':
        _delete(d);
      case 'star':
        lib.toggleStar(d.id);
      case 'restore':
        lib.restore(d.id);
      case 'forever':
        _deleteForever(d);
    }
  }

  List<MindMapDoc> _docs() {
    final q = _filter.trim().toLowerCase();
    final source = switch (_section) {
      _Section.trash => lib.trash,
      _Section.favorites => lib.docsByRecent.where((d) => d.starred).toList(),
      _ => lib.docsByRecent,
    };
    final docs = source
        .where(
          (d) =>
              q.isEmpty ||
              d.name.toLowerCase().contains(q) ||
              d.root.text.toLowerCase().contains(q),
        )
        .toList();
    switch (_sort) {
      case _Sort.name:
        docs.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case _Sort.size:
        docs.sort((a, b) => b.nodes.length.compareTo(a.nodes.length));
      case _Sort.recent:
        break;
    }
    return docs;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final width = MediaQuery.sizeOf(context).width;
        final compactNav = width < 900;
        final showSide = width >= 1200;
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: cs.surfaceContainerLow,
          body: SafeArea(
            child: Row(
              children: [
                _sidebar(context, compactNav),
                Expanded(
                  child: Column(
                    children: [
                      _topBar(context, showSide),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _mainCard(context)),
                              if (showSide) ...[
                                const SizedBox(width: 16),
                                SizedBox(
                                  width: 320,
                                  child: _sidePanel(context),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
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

  // --------------------------------------------------------- barra lateral

  Widget _sidebar(BuildContext context, bool compact) {
    final cs = Theme.of(context).colorScheme;
    Widget nav(_Section s, IconData icon, String label) {
      final sel = _section == s;
      final item = Material(
        color: sel ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _section = s),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 0 : 14,
              vertical: 11,
            ),
            child: Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(
                  icon,
                  size: 21,
                  color: sel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
                if (!compact) ...[
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? cs.onPrimaryContainer : cs.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: compact ? Tooltip(message: label, child: item) : item,
      );
    }

    return SizedBox(
      width: compact ? 76 : 236,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 10 : 16,
          14,
          compact ? 10 : 16,
          14,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: compact
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (compact)
                  const MapLongMark(height: 26)
                else ...[
                  const MapLongSymbol(height: 32),
                  const SizedBox(width: 8),
                  const Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MapLongWordmark(fontSize: 21),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 22),
            _NewMapButton(
              compact: compact,
              onTap: () => _create(kTemplates[1]),
              onBlank: () => _create(kTemplates[0]),
              onText: _textToMapDialog,
            ),
            const SizedBox(height: 10),
            compact
                ? IconButton.outlined(
                    tooltip: 'Abrir ou importar arquivo',
                    onPressed: _openFile,
                    icon: const Icon(Icons.folder_open_outlined),
                  )
                : OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _openFile,
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Abrir arquivo'),
                  ),
            const SizedBox(height: 22),
            nav(_Section.home, Icons.space_dashboard_outlined, 'Painel'),
            nav(_Section.maps, Icons.folder_copy_outlined, 'Meus mapas'),
            nav(_Section.favorites, Icons.star_outline, 'Favoritos'),
            nav(
              _Section.templates,
              Icons.auto_awesome_mosaic_outlined,
              'Modelos',
            ),
            nav(
              _Section.trash,
              Icons.delete_outline,
              'Lixeira${lib.trash.isEmpty ? '' : ' (${lib.trash.length})'}',
            ),
            const Spacer(),
            Divider(color: cs.outlineVariant),
            _sideAction(
              compact,
              lib.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              lib.isDark ? 'Modo claro' : 'Modo escuro',
              lib.toggleTheme,
            ),
            _sideAction(
              compact,
              Icons.settings_outlined,
              'Configurações',
              () => showSettingsDialog(context, lib),
            ),
            _sideAction(
              compact,
              Icons.info_outline,
              'Sobre o MapLong',
              () => showAboutMapLong(context),
            ),
            _sideAction(
              compact,
              Icons.keyboard_outlined,
              'Atalhos',
              () => showShortcutsDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideAction(
    bool compact,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: compact ? label : '',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 0 : 14,
            vertical: 10,
          ),
          child: Row(
            mainAxisAlignment: compact
                ? MainAxisAlignment.center
                : MainAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: cs.onSurfaceVariant),
              if (!compact) ...[
                const SizedBox(width: 12),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- barra superior

  Widget _topBar(BuildContext context, bool showSide) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    onChanged: (v) => setState(() => _filter = v),
                    decoration: InputDecoration(
                      hintText: 'Pesquisar mapas e modelos…',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: cs.surface,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(22),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (!showSide)
            FilledButton.tonalIcon(
              onPressed: _textToMapDialog,
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Texto → mapa'),
            ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Importar da área de transferência',
            onPressed: _fromClipboard,
            icon: const Icon(Icons.content_paste_go),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- área principal

  Widget _mainCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final docs = _docs();
    final q = _filter.trim().toLowerCase();
    final templates = kTemplates
        .where(
          (t) =>
              q.isEmpty ||
              t.title.toLowerCase().contains(q) ||
              t.description.toLowerCase().contains(q),
        )
        .toList();

    final slivers = <Widget>[];
    if (_section == _Section.home) {
      slivers.addAll([
        _pad(_categoryTabs(context)),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 184,
            child: _templateStrip(
              context,
              q.isEmpty
                  ? kTemplates.where((t) => t.category == _category).toList()
                  : templates,
            ),
          ),
        ),
        _pad(_docsHeader(context, 'Mapas recentes', docs.length), top: 26),
        ..._docsSlivers(context, docs.take(_grid ? 12 : 10).toList()),
      ]);
    } else if (_section == _Section.maps || _section == _Section.favorites) {
      slivers.addAll([
        _pad(
          _docsHeader(
            context,
            _section == _Section.maps ? 'Meus mapas' : 'Favoritos',
            docs.length,
          ),
          top: 20,
        ),
        ..._docsSlivers(context, docs),
      ]);
    } else if (_section == _Section.trash) {
      slivers.addAll([
        _pad(
          Row(
            children: [
              Expanded(
                child: Text(
                  'Lixeira (${docs.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(
                'Itens são apagados após ${Library.trashDays} dias.  ',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton.icon(
                onPressed: docs.isEmpty
                    ? null
                    : () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Esvaziar a lixeira?'),
                            content: const Text(
                              'Todos os mapas da lixeira serão apagados para sempre.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Esvaziar'),
                              ),
                            ],
                          ),
                        );
                        if (ok == true) await lib.emptyTrash();
                      },
                icon: const Icon(Icons.delete_forever_outlined),
                label: const Text('Esvaziar'),
              ),
            ],
          ),
          top: 20,
        ),
        if (docs.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: Text('A lixeira está vazia.')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            sliver: SliverList.builder(
              itemCount: docs.length,
              itemBuilder: (_, i) => _DocRow(
                doc: docs[i],
                trashed: true,
                onOpen: () => _docAction(docs[i], 'restore'),
                onAction: (a) => _docAction(docs[i], a),
              ),
            ),
          ),
      ]);
    } else {
      for (final c in kTemplateCategories) {
        final list = templates.where((t) => t.category == c).toList();
        if (list.isEmpty) continue;
        slivers.add(
          _pad(
            Text(c, style: Theme.of(context).textTheme.titleMedium),
            top: 20,
          ),
        );
        slivers.add(
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 1.2,
              ),
              delegate: SliverChildBuilderDelegate(
                childCount: list.length,
                (_, i) => _TemplateCard(
                  template: list[i],
                  onTap: () => _create(list[i]),
                ),
              ),
            ),
          ),
        );
      }
      slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomScrollView(slivers: slivers),
    );
  }

  Widget _pad(Widget child, {double top = 16}) => SliverPadding(
    padding: EdgeInsets.fromLTRB(22, top, 22, 8),
    sliver: SliverToBoxAdapter(child: child),
  );

  Widget _categoryTabs(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            'Começar com um modelo',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 18),
          for (final c in kTemplateCategories)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(c),
                selected: _category == c,
                showCheckmark: false,
                side: BorderSide(color: cs.outlineVariant),
                shape: const StadiumBorder(),
                onSelected: (_) => setState(() => _category = c),
              ),
            ),
          TextButton(
            onPressed: () => setState(() => _section = _Section.templates),
            child: const Text('Ver todos'),
          ),
        ],
      ),
    );
  }

  Widget _templateStrip(BuildContext context, List<MapTemplate> list) {
    final items = [if (!list.contains(kTemplates[0])) kTemplates[0], ...list];
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      scrollDirection: Axis.horizontal,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (_, i) => SizedBox(
        width: 200,
        child: _TemplateCard(
          template: items[i],
          onTap: () => _create(items[i]),
        ),
      ),
    );
  }

  Widget _docsHeader(BuildContext context, String title, int count) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text('$title ($count)', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        PopupMenuButton<_Sort>(
          tooltip: 'Ordenar',
          initialValue: _sort,
          onSelected: (s) => setState(() => _sort = s),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _Sort.recent,
              child: Text('Modificados recentemente'),
            ),
            PopupMenuItem(value: _Sort.name, child: Text('Nome')),
            PopupMenuItem(value: _Sort.size, child: Text('Número de tópicos')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.sort, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(switch (_sort) {
                  _Sort.recent => 'Recentes',
                  _Sort.name => 'Nome',
                  _Sort.size => 'Tópicos',
                }),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(
              value: false,
              icon: Icon(Icons.view_list_outlined, size: 18),
              tooltip: 'Lista',
            ),
            ButtonSegment(
              value: true,
              icon: Icon(Icons.grid_view_outlined, size: 18),
              tooltip: 'Grade',
            ),
          ],
          selected: {_grid},
          onSelectionChanged: (s) => setState(() => _grid = s.first),
        ),
      ],
    );
  }

  List<Widget> _docsSlivers(BuildContext context, List<MindMapDoc> docs) {
    final theme = Theme.of(context);
    if (docs.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(
                  Icons.account_tree_outlined,
                  size: 52,
                  color: theme.colorScheme.outline,
                ),
                const SizedBox(height: 12),
                Text(
                  _filter.trim().isEmpty
                      ? 'Nenhum mapa ainda. Escolha um modelo, gere um mapa a partir de texto ou abra um arquivo .maplong.'
                      : 'Nenhum mapa encontrado.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ];
    }
    if (_grid) {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.15,
            ),
            delegate: SliverChildBuilderDelegate(
              childCount: docs.length,
              (_, i) => _DocCard(
                doc: docs[i],
                onOpen: () => _open(docs[i]),
                onAction: (a) => _docAction(docs[i], a),
              ),
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
        sliver: SliverToBoxAdapter(child: _listHeader(context)),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
        sliver: SliverList.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) => _DocRow(
            doc: docs[i],
            onOpen: () => _open(docs[i]),
            onAction: (a) => _docAction(docs[i], a),
          ),
        ),
      ),
    ];
  }

  Widget _listHeader(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(
      builder: (context, c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            const SizedBox(width: 50),
            Expanded(flex: 5, child: Text('Nome', style: style)),
            if (c.maxWidth > 620)
              Expanded(flex: 3, child: Text('Local', style: style)),
            if (c.maxWidth > 480)
              Expanded(flex: 3, child: Text('Modificado', style: style)),
            SizedBox(
              width: 70,
              child: Text('Tópicos', style: style, textAlign: TextAlign.end),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------- painel direito

  Widget _sidePanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  colors: [kBrandCyan, kBrandBlue, kBrandViolet],
                ).createShader(r),
                child: const Icon(Icons.auto_fix_high, color: Colors.white),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Texto para mapa mental',
                  overflow: TextOverflow.ellipsis,
                  style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Cole uma lista ou tópicos com recuo — a primeira linha vira a ideia principal.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 12),
          _InlineTextToMap(onGenerate: _createFromText),
          const SizedBox(height: 22),
          Text('Outras formas de começar', style: t.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _QuickTile(
                icon: Icons.content_paste_go,
                label: 'Da área de transferência',
                onTap: _fromClipboard,
              ),
              _QuickTile(
                icon: Icons.upload_file_outlined,
                label: 'Abrir arquivo',
                onTap: _openFile,
              ),
              _QuickTile(
                icon: Icons.crop_free,
                label: 'Mapa em branco',
                onTap: () => _create(kTemplates[0]),
              ),
              _QuickTile(
                icon: Icons.format_list_bulleted,
                label: 'Lista à direita',
                onTap: () => _create(kTemplates[2]),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.tips_and_updates_outlined,
                      size: 18,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('Dicas rápidas', style: t.titleSmall),
                  ],
                ),
                const SizedBox(height: 8),
                for (final tip in const [
                  'Tab cria um subtópico; Enter, um tópico irmão.',
                  'Ctrl+R liga dois tópicos com uma relação.',
                  'Use marcadores e adesivos no painel à direita do editor.',
                  'O modo Esboço mostra o mapa como uma lista editável.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  '),
                        Expanded(child: Text(tip, style: t.bodySmall)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ======================================================================

class _NewMapButton extends StatelessWidget {
  const _NewMapButton({
    required this.compact,
    required this.onTap,
    required this.onBlank,
    required this.onText,
  });

  final bool compact;
  final VoidCallback onTap;
  final VoidCallback onBlank;
  final VoidCallback onText;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          leadingIcon: const Icon(Icons.hub_outlined),
          onPressed: onTap,
          child: const Text('Mapa clássico'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.crop_free),
          onPressed: onBlank,
          child: const Text('Mapa em branco'),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Icons.auto_fix_high),
          onPressed: onText,
          child: const Text('A partir de texto…'),
        ),
      ],
      builder: (context, c, _) => Tooltip(
        message: compact ? 'Novo mapa' : '',
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [kBrandCyan, kBrandBlue, kBrandViolet],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: kBrandBlue.withValues(alpha: 0.35),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => c.isOpen ? c.close() : c.open(),
              child: SizedBox(
                height: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.add_circle, color: Colors.white),
                    if (!compact) ...[
                      const SizedBox(width: 8),
                      const Text(
                        'Novo mapa',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.expand_more,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ],
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

class _TextToMapField extends StatelessWidget {
  const _TextToMapField({required this.controller, this.minLines = 6});
  final TextEditingController controller;
  final int minLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: minLines,
    maxLines: minLines + 6,
    autofocus: minLines > 6,
    decoration: InputDecoration(
      hintText:
          'Viagem de férias\n  Destino\n    Praia\n  Orçamento\n  Roteiro',
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

class _InlineTextToMap extends StatefulWidget {
  const _InlineTextToMap({required this.onGenerate});
  final ValueChanged<String> onGenerate;

  @override
  State<_InlineTextToMap> createState() => _InlineTextToMapState();
}

class _InlineTextToMapState extends State<_InlineTextToMap> {
  final _c = TextEditingController();

  @override
  void initState() {
    super.initState();
    _c.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TextToMapField(controller: _c),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _c.text.trim().isEmpty
              ? null
              : () {
                  widget.onGenerate(_c.text);
                  _c.clear();
                },
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: const Text('Gerar mapa'),
        ),
      ],
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 134,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          alignment: Alignment.centerLeft,
          side: BorderSide(color: cs.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onTap,
        child: Row(
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatefulWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final MapTemplate template;
  final VoidCallback onTap;

  @override
  State<_TemplateCard> createState() => _TemplateCardState();
}

class _TemplateCardState extends State<_TemplateCard> {
  bool _hover = false;
  late final MindMapDoc _preview = docFromTemplate('', widget.template);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final t = widget.template;
    final blank = t.title == 'Em branco';
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _hover ? cs.primary : cs.outlineVariant,
            width: _hover ? 1.5 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    color:
                        parseHex(themeById(t.theme).background) ??
                        cs.surfaceContainerHighest.withValues(alpha: 0.45),
                    padding: const EdgeInsets.all(10),
                    child: blank
                        ? Icon(Icons.add, size: 44, color: cs.primary)
                        : CustomPaint(
                            painter: _PreviewPainter(_preview, cs.primary),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        blank ? 'Em branco' : t.title,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        t.description,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  final now = DateTime.now();
  if (d.year == now.year && d.month == now.month && d.day == now.day) {
    return 'Hoje, ${two(d.hour)}:${two(d.minute)}';
  }
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

PopupMenuButton<String> _docMenu(
  ValueChanged<String> onAction, {
  bool trashed = false,
  bool starred = false,
}) => PopupMenuButton<String>(
  tooltip: 'Opções',
  onSelected: onAction,
  itemBuilder: (_) => trashed
      ? const [
          PopupMenuItem(value: 'restore', child: Text('Restaurar')),
          PopupMenuItem(
            value: 'forever',
            child: Text('Excluir definitivamente'),
          ),
        ]
      : [
          const PopupMenuItem(value: 'open', child: Text('Abrir')),
          PopupMenuItem(
            value: 'star',
            child: Text(
              starred ? 'Remover dos favoritos' : 'Adicionar aos favoritos',
            ),
          ),
          const PopupMenuItem(value: 'rename', child: Text('Renomear')),
          const PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
          const PopupMenuItem(
            value: 'export',
            child: Text('Salvar como arquivo .maplong'),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: 'delete',
            child: Text('Mover para a lixeira'),
          ),
        ],
);

class _DocRow extends StatefulWidget {
  const _DocRow({
    required this.doc,
    required this.onOpen,
    required this.onAction,
    this.trashed = false,
  });

  final bool trashed;
  final MindMapDoc doc;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  State<_DocRow> createState() => _DocRowState();
}

class _DocRowState extends State<_DocRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final d = widget.doc;
    final color = parseHex(d.root.fillColor) ?? cs.primary;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover
            ? cs.surfaceContainerHighest.withValues(alpha: 0.45)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: widget.onOpen,
          onSecondaryTapDown: (e) async {
            final v = await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                e.globalPosition.dx,
                e.globalPosition.dy,
                e.globalPosition.dx,
                e.globalPosition.dy,
              ),
              items: widget.trashed
                  ? const [
                      PopupMenuItem(value: 'restore', child: Text('Restaurar')),
                      PopupMenuItem(
                        value: 'forever',
                        child: Text('Excluir definitivamente'),
                      ),
                    ]
                  : const [
                      PopupMenuItem(value: 'open', child: Text('Abrir')),
                      PopupMenuItem(value: 'star', child: Text('Favorito')),
                      PopupMenuItem(value: 'rename', child: Text('Renomear')),
                      PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicar'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Mover para a lixeira'),
                      ),
                    ],
            );
            if (v != null) widget.onAction(v);
          },
          child: LayoutBuilder(
            builder: (context, c) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.hub, size: 20, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.name,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          d.root.text.replaceAll('\n', ' '),
                          style: theme.textTheme.bodySmall,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (c.maxWidth > 620)
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Icon(
                            d.filePath == null
                                ? Icons.inventory_2_outlined
                                : Icons.description_outlined,
                            size: 16,
                            color: cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              d.filePath == null
                                  ? 'Biblioteca local'
                                  : d.filePath!.split(RegExp(r'[\\/]')).last,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (c.maxWidth > 480)
                    Expanded(
                      flex: 3,
                      child: Text(
                        _formatDate(d.updatedAt),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${d.nodes.length}',
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (!widget.trashed)
                    IconButton(
                      tooltip: d.starred
                          ? 'Remover dos favoritos'
                          : 'Favoritar',
                      onPressed: () => widget.onAction('star'),
                      icon: Icon(
                        d.starred ? Icons.star : Icons.star_outline,
                        color: d.starred ? const Color(0xFFFFB300) : cs.outline,
                      ),
                    )
                  else
                    TextButton(
                      onPressed: () => widget.onAction('restore'),
                      child: const Text('Restaurar'),
                    ),
                  SizedBox(
                    width: 48,
                    child: _docMenu(
                      widget.onAction,
                      trashed: widget.trashed,
                      starred: d.starred,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  const _DocCard({
    required this.doc,
    required this.onOpen,
    required this.onAction,
  });

  final MindMapDoc doc;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color:
                      parseHex(doc.background) ??
                      cs.surfaceContainerHighest.withValues(alpha: 0.45),
                  padding: const EdgeInsets.all(12),
                  child: CustomPaint(painter: _PreviewPainter(doc, cs.primary)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 2, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.name,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${doc.nodes.length} tópicos · ${_formatDate(doc.updatedAt)}',
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    if (doc.starred)
                      const Icon(
                        Icons.star,
                        size: 18,
                        color: Color(0xFFFFB300),
                      ),
                    _docMenu(onAction, starred: doc.starred),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Miniatura do mapa.
class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.doc, this.fallback);

  final MindMapDoc doc;
  final Color fallback;

  @override
  void paint(Canvas canvas, Size size) {
    final nodes = doc.visibleNodes().toList();
    if (nodes.isEmpty) return;
    Rect? b;
    for (final n in nodes) {
      final s = estimateNodeSize(n);
      final r = Rect.fromCenter(
        center: n.pos,
        width: s.width,
        height: s.height,
      );
      b = b == null ? r : b.expandToInclude(r);
    }
    final bounds = b!;
    final scale = math
        .min(size.width / bounds.width, size.height / bounds.height)
        .clamp(0.02, 0.6);
    final offset = size.center(Offset.zero) - bounds.center * scale;
    Offset tp(Offset p) => p * scale + offset;

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final n in nodes) {
      final p = n.parentId == null ? null : doc.nodes[n.parentId];
      if (p == null) continue;
      line.color = parseHex(n.color) ?? fallback;
      final a = tp(p.pos), c = tp(n.pos);
      final dx = (c.dx - a.dx) / 2;
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(a.dx + dx, a.dy, c.dx - dx, c.dy, c.dx, c.dy),
        line,
      );
    }
    for (final n in nodes) {
      final s = estimateNodeSize(n);
      final isRoot = n.id == doc.rootId;
      final r = Rect.fromCenter(
        center: tp(n.pos),
        width: math.max(6, s.width * scale),
        height: math.max(3, s.height * scale * 0.7),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(4)),
        Paint()
          ..color = isRoot
              ? (parseHex(n.fillColor) ?? fallback)
              : parseHex(n.color) ?? fallback,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => true;
}
