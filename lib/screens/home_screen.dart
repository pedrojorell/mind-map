import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../file_actions.dart';
import '../layout.dart';
import '../library.dart';
import '../models.dart';
import '../templates.dart';
import 'editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.library});

  final Library library;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _filter = '';

  Library get lib => widget.library;

  Future<void> _open(MindMapDoc doc) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(library: lib, doc: doc),
    ));
    if (mounted) setState(() {});
  }

  void _create(MapTemplate t) {
    final name = lib.uniqueName(t.title == 'Em branco' || t.title == 'Clássico'
        ? 'Novo mapa'
        : t.title);
    final doc = docFromOutline(name, t.outline);
    lib.add(doc);
    _open(doc);
  }

  Future<void> _openFile() async {
    final doc = await openFromFile(context, lib);
    if (doc != null) _open(doc);
  }

  Future<void> _rename(MindMapDoc d) async {
    final name = await promptText(context,
        title: 'Renomear mapa', initial: d.name, label: 'Nome');
    if (name != null) lib.rename(d.id, name);
  }

  Future<void> _delete(MindMapDoc d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir mapa?'),
        content: Text(
            '“${d.name}” será removido da biblioteca. Arquivos .pmap salvos no disco não são apagados.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
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
        showSnack(context, r.path == null ? 'Arquivo baixado.' : 'Salvo em ${r.path}');
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Erro ao salvar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) {
        final theme = Theme.of(context);
        final q = _filter.trim().toLowerCase();
        final docs = lib.docsByRecent
            .where((d) => q.isEmpty || d.name.toLowerCase().contains(q))
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: const Row(
              children: [
                PinealLogo(size: 26),
                SizedBox(width: 10),
                Text('PinealMap', style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              TextButton.icon(
                onPressed: _openFile,
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Abrir arquivo'),
              ),
              IconButton(
                tooltip: lib.themeMode == ThemeMode.dark
                    ? 'Tema claro'
                    : 'Tema escuro',
                onPressed: lib.toggleTheme,
                icon: Icon(lib.themeMode == ThemeMode.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                sliver: SliverToBoxAdapter(
                  child: Text('Criar novo mapa', style: theme.textTheme.titleLarge),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 170,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    scrollDirection: Axis.horizontal,
                    itemCount: kTemplates.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 14),
                    itemBuilder: (_, i) => _TemplateCard(
                      template: kTemplates[i],
                      onTap: () => _create(kTemplates[i]),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                sliver: SliverToBoxAdapter(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text('Meus mapas (${lib.docsByRecent.length})',
                          style: theme.textTheme.titleLarge),
                      SizedBox(
                        width: 280,
                        height: 40,
                        child: TextField(
                          onChanged: (v) => setState(() => _filter = v),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Buscar mapas…',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (docs.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_tree_outlined,
                              size: 56, color: theme.colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            q.isEmpty
                                ? 'Nenhum mapa ainda. Escolha um modelo acima ou abra um arquivo .pmap.'
                                : 'Nenhum mapa encontrado.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 300,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      childAspectRatio: 1.15,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      childCount: docs.length,
                      (_, i) {
                        final d = docs[i];
                        return _DocCard(
                          doc: d,
                          onOpen: () => _open(d),
                          onAction: (a) {
                            switch (a) {
                              case 'rename':
                                _rename(d);
                              case 'duplicate':
                                lib.duplicate(d.id);
                              case 'export':
                                _export(d);
                              case 'delete':
                                _delete(d);
                            }
                          },
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});

  final MapTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 200,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  padding: const EdgeInsets.all(10),
                  child: template.title == 'Em branco'
                      ? Icon(Icons.add_circle_outline,
                          size: 42, color: theme.colorScheme.primary)
                      : CustomPaint(
                          painter: _PreviewPainter(
                              docFromOutline('', template.outline),
                              theme.colorScheme.primary)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(template.title, style: theme.textTheme.titleSmall),
                    Text(template.description,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis),
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

class _DocCard extends StatelessWidget {
  const _DocCard(
      {required this.doc, required this.onOpen, required this.onAction});

  final MindMapDoc doc;
  final VoidCallback onOpen;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final updated = DateTime.fromMillisecondsSinceEpoch(doc.updatedAt);
    String two(int v) => v.toString().padLeft(2, '0');
    final when =
        '${two(updated.day)}/${two(updated.month)}/${updated.year} ${two(updated.hour)}:${two(updated.minute)}';
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                padding: const EdgeInsets.all(12),
                child: CustomPaint(
                    painter: _PreviewPainter(doc, theme.colorScheme.primary)),
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
                        Text(doc.name,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis),
                        Text('${doc.nodes.length} tópicos · $when',
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Opções',
                    onSelected: onAction,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('Renomear')),
                      PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
                      PopupMenuItem(
                          value: 'export', child: Text('Salvar como arquivo .pmap')),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
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
      final r = Rect.fromCenter(center: n.pos, width: s.width, height: s.height);
      b = b == null ? r : b.expandToInclude(r);
    }
    final bounds = b!;
    final scale = math.min(size.width / bounds.width, size.height / bounds.height)
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
          line);
    }
    for (final n in nodes) {
      final s = estimateNodeSize(n);
      final r = Rect.fromCenter(
          center: tp(n.pos),
          width: math.max(6, s.width * scale),
          height: math.max(3, s.height * scale * 0.7));
      canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(4)),
          Paint()..color = parseHex(n.color) ?? fallback);
    }
  }

  @override
  bool shouldRepaint(covariant _PreviewPainter old) => true;
}

/// Logo do PinealMap (pinha estilizada).
class PinealLogo extends StatelessWidget {
  const PinealLogo({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _LogoPainter(Theme.of(context).colorScheme.primary),
      );
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final body = Path()
      ..moveTo(c.dx, c.dy - r * 0.95)
      ..cubicTo(c.dx + r * 0.85, c.dy - r * 0.4, c.dx + r * 0.7, c.dy + r * 0.7,
          c.dx, c.dy + r * 0.95)
      ..cubicTo(c.dx - r * 0.7, c.dy + r * 0.7, c.dx - r * 0.85, c.dy - r * 0.4,
          c.dx, c.dy - r * 0.95)
      ..close();
    canvas.drawPath(body, Paint()..color = color);
    final s = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.09;
    for (var i = 0; i < 4; i++) {
      final y = c.dy - r * 0.35 + i * r * 0.3;
      canvas.drawArc(
          Rect.fromCenter(
              center: Offset(c.dx, y), width: r * (1.1 - i * 0.12), height: r * 0.4),
          0.2,
          math.pi - 0.4,
          false,
          s);
    }
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.color != color;
}
