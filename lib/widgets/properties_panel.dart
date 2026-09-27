import 'package:flutter/material.dart';

import '../editor_controller.dart';
import '../models.dart';
import 'elements_panel.dart';
import 'markers.dart';
import 'media_panel.dart';
import 'node_view.dart';

/// Abas do painel lateral do editor.
enum PanelTab {
  style('Estilo do tópico', Icons.brush_outlined),
  map('Mapa e tema', Icons.account_tree_outlined),
  markers('Marcadores', Icons.flag_outlined),
  stickers('Adesivos', Icons.emoji_emotions_outlined),
  media('Imagens e documentos', Icons.perm_media_outlined),
  elements('Elementos: balão, limite, resumo, tabela…', Icons.widgets_outlined),
  details('Links, etiquetas e anotações', Icons.link);

  const PanelTab(this.title, this.icon);
  final String title;
  final IconData icon;
}

class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({
    super.key,
    required this.editor,
    required this.tab,
    this.onClose,
  });

  final EditorController editor;
  final PanelTab tab;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final n = editor.selected;
    final List<Widget> body = switch (tab) {
      PanelTab.style =>
        n == null ? _noSelection(context) : _styleTab(context, n),
      PanelTab.map => _mapTab(context),
      PanelTab.markers =>
        n == null ? _noSelection(context) : _markersTab(context, n),
      PanelTab.stickers =>
        n == null ? _noSelection(context) : [_StickerPicker(editor: editor)],
      PanelTab.media =>
        n == null
            ? _noSelection(context)
            : [
                MediaSection(
                  key: ValueKey('media_${n.id}'),
                  editor: editor,
                  node: n,
                ),
              ],
      PanelTab.elements =>
        n == null
            ? _noSelection(context)
            : [
                ElementsSection(
                  key: ValueKey('el_${n.id}'),
                  editor: editor,
                  node: n,
                ),
              ],
      PanelTab.details =>
        n == null ? _noSelection(context) : _detailsTab(context, n),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 2),
          child: Row(
            children: [
              Expanded(child: Text(tab.title, style: t.titleSmall)),
              if (onClose != null)
                IconButton(
                  tooltip: 'Fechar painel',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: onClose,
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: body,
          ),
        ),
      ],
    );
  }

  List<Widget> _noSelection(BuildContext context) => [
    const SizedBox(height: 24),
    Icon(
      Icons.touch_app_outlined,
      size: 40,
      color: Theme.of(context).colorScheme.outline,
    ),
    const SizedBox(height: 8),
    Text(
      'Selecione um tópico no mapa.',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyMedium,
    ),
  ];

  // ------------------------------------------------------------------ estilo

  List<Widget> _styleTab(BuildContext context, MindMapNode n) {
    final id = n.id;
    return [
      CommitTextField(
        key: ValueKey('text_$id'),
        value: n.text,
        label: 'Texto',
        maxLines: 3,
        onCommit: (v) {
          if (v.trim().isNotEmpty) {
            editor.updateNode(id, (n) => n.text = v.trim(), relayout: true);
          }
        },
      ),
      _Section('Fonte'),
      Row(
        children: [
          _Toggle(
            tip: 'Negrito',
            icon: Icons.format_bold,
            on: n.bold,
            onTap: () =>
                editor.updateNode(id, (n) => n.bold = !n.bold, relayout: true),
          ),
          _Toggle(
            tip: 'Itálico',
            icon: Icons.format_italic,
            on: n.italic,
            onTap: () => editor.updateNode(
              id,
              (n) => n.italic = !n.italic,
              relayout: true,
            ),
          ),
          _Toggle(
            tip: 'Sublinhado',
            icon: Icons.format_underline,
            on: n.underline,
            onTap: () =>
                editor.updateNode(id, (n) => n.underline = !n.underline),
          ),
          _Toggle(
            tip: 'Tachado',
            icon: Icons.format_strikethrough,
            on: n.strike,
            onTap: () => editor.updateNode(id, (n) => n.strike = !n.strike),
          ),
        ],
      ),
      Row(
        children: [
          for (final a in const [
            ('left', Icons.format_align_left),
            ('center', Icons.format_align_center),
            ('right', Icons.format_align_right),
          ])
            _Toggle(
              tip: kAligns[a.$1]!,
              icon: a.$2,
              on: n.align == a.$1,
              onTap: () => editor.updateNode(id, (n) => n.align = a.$1),
            ),
          const Spacer(),
          FontSizeStepper(
            value: n.fontSize,
            onChanged: (v) =>
                editor.updateNode(id, (n) => n.fontSize = v, relayout: true),
          ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: _SliderRow(
              label: 'Largura',
              value: n.maxWidth,
              min: 80,
              max: 800,
              divisions: 36,
              onChanged: (v) =>
                  editor.updateNode(id, (n) => n.maxWidth = v, relayout: true),
            ),
          ),
        ],
      ),
      _Section('Cor do texto'),
      ColorRow(
        colors: const ['', '#FFFFFF', '#15171F', ...kPalette],
        selected: n.textColor ?? '',
        onPick: (c) =>
            editor.updateNode(id, (n) => n.textColor = c.isEmpty ? null : c),
      ),
      _Section('Formato'),
      ShapeGrid(
        selected: n.shape,
        onPick: (s) =>
            editor.updateNode(id, (n) => n.shape = s, relayout: true),
      ),
      _Section('Preenchimento'),
      ColorRow(
        colors: kFillPalette,
        selected: n.fillColor ?? '',
        onPick: (c) =>
            editor.updateNode(id, (n) => n.fillColor = c.isEmpty ? null : c),
      ),
      _Section('Borda e ramo'),
      ColorRow(
        colors: {...editor.doc.theme.palette, ...kPalette}.toList(),
        selected: n.color,
        onPick: (c) => editor.updateNode(id, (n) => n.color = c),
      ),
      const SizedBox(height: 6),
      Row(
        children: [
          _Toggle(
            tip: 'Borda tracejada',
            icon: Icons.line_style,
            on: n.dashed,
            onTap: () => editor.updateNode(id, (n) => n.dashed = !n.dashed),
          ),
          Expanded(
            child: _SliderRow(
              label: 'Espessura',
              value: n.borderWidth,
              min: 0,
              max: 6,
              divisions: 12,
              onChanged: (v) => editor.updateNode(id, (n) => n.borderWidth = v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.format_paint_outlined, size: 18),
        label: const Text('Aplicar estilo a todo o ramo'),
        onPressed: n.childrenIds.isEmpty
            ? null
            : () {
                final src = n;
                editor.updateBranch(id, (m) {
                  m.color = src.color;
                  if (m.id != src.id) {
                    m
                      ..fillColor = src.fillColor
                      ..textColor = src.textColor
                      ..shape = src.shape
                      ..dashed = src.dashed
                      ..borderWidth = src.borderWidth;
                  }
                });
              },
      ),
    ];
  }

  // -------------------------------------------------------------------- mapa

  List<Widget> _mapTab(BuildContext context) {
    final doc = editor.doc;
    final cs = Theme.of(context).colorScheme;
    return [
      _Section('Estrutura'),
      GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 1.1,
        children: [
          for (final e in kLayouts.entries)
            _PickTile(
              selected: doc.layout == e.key,
              tooltip: e.value,
              padding: const EdgeInsets.all(4),
              onTap: () => editor.setLayout(e.key),
              child: CustomPaint(
                painter: LayoutGlyph(e.key, cs.primary, cs.outline),
              ),
            ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          kLayouts[doc.layout] ?? '',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Numerar tópicos'),
        subtitle: const Text('Mostra 1, 1.1, 1.2… antes do texto'),
        value: doc.numbering,
        onChanged: editor.setNumbering,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('Organização automática'),
        subtitle: const Text('Reposiciona os tópicos ao editar'),
        value: doc.autoLayout,
        onChanged: editor.setAutoLayout,
      ),
      _Section('Espaçamento entre tópicos'),
      _SliderRow(
        label: 'Horizontal',
        value: doc.hGap,
        min: 24,
        max: 160,
        divisions: 17,
        onChanged: (v) => editor.setSpacing(h: v),
      ),
      _SliderRow(
        label: 'Vertical',
        value: doc.vGap,
        min: 4,
        max: 60,
        divisions: 14,
        onChanged: (v) => editor.setSpacing(v: v),
      ),
      _Section('Tema de cores'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.3,
        children: [
          for (final t in kThemes)
            _PickTile(
              selected: doc.themeId == t.id,
              tooltip: t.name,
              onTap: () => editor.applyTheme(t.id),
              child: ThemeSwatch(theme: t),
            ),
        ],
      ),
      _Section('Fundo'),
      ColorRow(
        colors: const [
          '',
          '#FFFFFF',
          '#F7F5FF',
          '#FFF8F0',
          '#F1FAFD',
          '#F3F8F2',
          '#FFFDE7',
          '#1F2333',
          '#14111F',
          '#0B1F2A',
        ],
        selected: doc.background ?? '',
        onPick: (c) => editor.setBackground(c.isEmpty ? null : c),
      ),
      _Section('Ramificações'),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [
          for (final e in kConnectorStyles.entries)
            ButtonSegment(value: e.key, label: Text(e.value)),
        ],
        selected: {doc.connectorStyle},
        onSelectionChanged: (s) => editor.setConnector(style: s.first),
      ),
      _SliderRow(
        label: 'Espessura',
        value: doc.connectorWidth,
        min: 1,
        max: 8,
        divisions: 14,
        onChanged: (v) => editor.setConnector(width: v),
      ),
    ];
  }

  // -------------------------------------------------------------- marcadores

  List<Widget> _markersTab(BuildContext context, MindMapNode n) {
    return [
      for (final g in kMarkerGroups) ...[
        _Section(g.name),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final v in g.values)
              _PickTile(
                selected: n.marker(g.id) == v,
                tooltip: markerLabel(g.id, v),
                padding: const EdgeInsets.all(5),
                onTap: () => editor.toggleMarker(g.id, v),
                child: MarkerIcon(g.id, v, size: 20),
              ),
          ],
        ),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: n.markers.isEmpty ? null : () => editor.clearMarkers(),
        icon: const Icon(Icons.layers_clear_outlined, size: 18),
        label: const Text('Remover todos os marcadores'),
      ),
    ];
  }

  // ---------------------------------------------------------------- detalhes

  List<Widget> _detailsTab(BuildContext context, MindMapNode n) {
    final t = Theme.of(context).textTheme;
    final id = n.id;
    final rels = editor.relationsOf(id);
    return [
      LinksSection(key: ValueKey('links_$id'), editor: editor, node: n),
      Row(
        children: [
          Expanded(child: _Section('Relações')),
          TextButton.icon(
            icon: const Icon(Icons.moving, size: 18),
            label: const Text('Nova'),
            onPressed: () => editor.startRelation(id),
          ),
        ],
      ),
      if (rels.isEmpty)
        Text(
          'Ligue este tópico a qualquer outro com uma seta.',
          style: t.bodySmall,
        )
      else
        for (final r in rels)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  r.from == id ? Icons.arrow_forward : Icons.arrow_back,
                  size: 16,
                  color: parseHex(r.color),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: CommitTextField(
                    key: ValueKey('rel_${r.id}'),
                    value: r.label,
                    label:
                        editor.doc.nodes[r.from == id ? r.to : r.from]?.text
                            .replaceAll('\n', ' ') ??
                        '',
                    hint: 'Rótulo da relação',
                    onCommit: (v) =>
                        editor.updateRelation(r.id, (r) => r.label = v.trim()),
                  ),
                ),
                IconButton(
                  tooltip: 'Excluir relação',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () => editor.removeRelation(r.id),
                ),
              ],
            ),
          ),
    ];
  }
}

// ======================================================================
// Componentes reutilizáveis (painel, faixa de ferramentas e barra flutuante)
// ======================================================================

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.tip,
    required this.icon,
    required this.on,
    required this.onTap,
  });
  final String tip;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    isSelected: on,
    style: IconButton.styleFrom(
      backgroundColor: on
          ? Theme.of(context).colorScheme.primaryContainer
          : null,
    ),
    icon: Icon(icon),
    onPressed: onTap,
  );
}

/// Quadradinho selecionável (tema, estrutura, marcador…).
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.selected,
    required this.onTap,
    required this.child,
    this.tooltip,
    this.padding = const EdgeInsets.all(6),
  });

  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tile = Material(
      color: selected
          ? cs.primaryContainer
          : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? cs.primary : Colors.transparent,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    return tooltip == null
        ? tile
        : Tooltip(
            message: tooltip!,
            waitDuration: const Duration(milliseconds: 400),
            child: tile,
          );
  }
}

/// Grade com as formas disponíveis para um tópico.
class ShapeGrid extends StatelessWidget {
  const ShapeGrid({super.key, required this.selected, required this.onPick});
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final e in kShapes.entries)
          _PickTile(
            selected: selected == e.key,
            tooltip: e.value,
            onTap: () => onPick(e.key),
            child: SizedBox(
              width: 38,
              height: 22,
              child: _ShapePreview(e.key, cs.onSurface),
            ),
          ),
      ],
    );
  }
}

class _ShapePreview extends StatelessWidget {
  const _ShapePreview(this.shape, this.color);
  final String shape;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (shape == 'underline') {
      return Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: color, width: 2)),
        ),
        alignment: Alignment.center,
        child: Text('Abc', style: TextStyle(fontSize: 10, color: color)),
      );
    }
    if (shape == 'plain') {
      return Center(
        child: Text(
          'Abc',
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    // Na miniatura, o chanfro padrão do hexágono viraria um losango.
    final s = shape == 'hexagon'
        ? BeveledRectangleBorder(borderRadius: BorderRadius.circular(8))
        : shapeFor(shape);
    return Container(
      decoration: ShapeDecoration(
        shape: s is OutlinedBorder
            ? s.copyWith(side: BorderSide(color: color, width: 1.5))
            : s,
      ),
    );
  }
}

/// Miniatura da paleta de um tema.
class ThemeSwatch extends StatelessWidget {
  const ThemeSwatch({super.key, required this.theme});
  final MapTheme theme;

  @override
  Widget build(BuildContext context) {
    final bg =
        parseHex(theme.background) ?? Theme.of(context).colorScheme.surface;
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 10,
            decoration: BoxDecoration(
              color: parseHex(theme.rootFill),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final c in theme.palette.take(6))
                      Expanded(
                        child: Container(
                          height: 6,
                          margin: const EdgeInsets.all(0.8),
                          decoration: BoxDecoration(
                            color: parseHex(c),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  theme.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: bg.computeLuminance() > 0.5
                        ? const Color(0xFF3A3A48)
                        : Colors.white,
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

/// Ícone desenhado de uma estrutura de mapa.
class LayoutGlyph extends CustomPainter {
  LayoutGlyph(this.layout, this.accent, this.line);
  final String layout;
  final Color accent;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final p = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final fill = Paint()..color = line.withValues(alpha: 0.6);
    void branch(int dir, double dy) {
      final a = c + Offset(dir * 8.0, 0);
      final b = c + Offset(dir * 22.0, dy);
      canvas.drawPath(
        Path()
          ..moveTo(a.dx, a.dy)
          ..cubicTo(a.dx + dir * 7, a.dy, b.dx - dir * 7, b.dy, b.dx, b.dy),
        p,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: b + Offset(dir * 6.0, 0),
            width: 12,
            height: 5,
          ),
          const Radius.circular(2),
        ),
        fill,
      );
    }

    var center = c;
    final fill2 = Paint()..color = line.withValues(alpha: 0.6);
    void box(Offset o) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: o, width: 11, height: 5),
        const Radius.circular(2),
      ),
      fill2,
    );
    switch (layout) {
      case 'org':
        center = c + const Offset(0, -12);
        for (final dx in [-16.0, 0.0, 16.0]) {
          canvas.drawLine(center + Offset(dx, 6), center + Offset(dx, 12), p);
          box(center + Offset(dx, 16));
        }
        canvas.drawLine(
          center + const Offset(-16, 6),
          center + const Offset(16, 6),
          p,
        );
        canvas.drawLine(
          center + const Offset(0, 3),
          center + const Offset(0, 6),
          p,
        );
      case 'tree':
        center = c + const Offset(-8, -14);
        final x = center.dx - 5;
        canvas.drawLine(Offset(x, center.dy + 4), Offset(x, center.dy + 26), p);
        for (final dy in [9.0, 18.0, 26.0]) {
          canvas.drawLine(
            Offset(x, center.dy + dy),
            Offset(x + 8, center.dy + dy),
            p,
          );
          box(Offset(x + 14, center.dy + dy));
        }
      case 'timeline':
        center = c + const Offset(-20, 0);
        canvas.drawLine(center, c + const Offset(24, 0), p);
        for (final (dx, dy) in [(0.0, -9.0), (12.0, 9.0), (24.0, -9.0)]) {
          final o = c + Offset(dx - 8, 0);
          canvas.drawCircle(o, 1.8, fill2);
          box(o + Offset(0, dy));
        }
      case 'fishbone':
        center = c + const Offset(18, 0);
        canvas.drawLine(c + const Offset(-24, 0), center, p);
        for (final dx in [-16.0, 0.0]) {
          for (final dy in [-1.0, 1.0]) {
            canvas.drawLine(
              c + Offset(dx + 6, 0),
              c + Offset(dx - 2, dy * 12),
              p,
            );
            box(c + Offset(dx - 4, dy * 15));
          }
        }
      case 'logic':
        center = c + const Offset(-14, 0);
        final x = center.dx + 12;
        canvas.drawLine(Offset(center.dx + 9, c.dy), Offset(x, c.dy), p);
        canvas.drawLine(Offset(x, c.dy - 12), Offset(x, c.dy + 12), p);
        for (final dy in [-12.0, 0.0, 12.0]) {
          canvas.drawLine(Offset(x, c.dy + dy), Offset(x + 8, c.dy + dy), p);
          box(Offset(x + 14, c.dy + dy));
        }
      case 'right':
        center = c + const Offset(-12, 0);
        canvas.save();
        canvas.translate(-12, 0);
        for (final dy in [-14.0, -5.0, 5.0, 14.0]) {
          branch(1, dy);
        }
        canvas.restore();
      case 'left':
        center = c + const Offset(12, 0);
        canvas.save();
        canvas.translate(12, 0);
        for (final dy in [-14.0, -5.0, 5.0, 14.0]) {
          branch(-1, dy);
        }
        canvas.restore();
      default:
        for (final dy in [-11.0, 11.0]) {
          branch(1, dy);
          branch(-1, dy);
        }
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: 18, height: 9),
        const Radius.circular(3),
      ),
      Paint()..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant LayoutGlyph old) =>
      old.layout != layout || old.accent != accent || old.line != line;
}

/// Seletor de tamanho de fonte com botões − / +.
class FontSizeStepper extends StatelessWidget {
  const FontSizeStepper({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final double value;
  final ValueChanged<double> onChanged;

  static const sizes = [
    10.0,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    20,
    22,
    24,
    28,
    32,
    36,
    40,
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _step(Icons.text_decrease, 'Diminuir fonte', () {
            final smaller = sizes.where((s) => s < value - 0.1);
            if (smaller.isNotEmpty) onChanged(smaller.last.toDouble());
          }),
          PopupMenuButton<double>(
            tooltip: 'Tamanho da fonte',
            initialValue: value,
            onSelected: onChanged,
            itemBuilder: (_) => [
              for (final s in sizes)
                PopupMenuItem(
                  value: s.toDouble(),
                  height: 32,
                  child: Text('${s.round()}'),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '${value.round()}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          _step(Icons.text_increase, 'Aumentar fonte', () {
            final bigger = sizes.where((s) => s > value + 0.1);
            if (bigger.isNotEmpty) onChanged(bigger.first.toDouble());
          }),
        ],
      ),
    );
  }

  Widget _step(IconData i, String tip, VoidCallback onTap) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    iconSize: 17,
    onPressed: onTap,
    icon: Icon(i),
  );
}

class _StickerPicker extends StatefulWidget {
  const _StickerPicker({required this.editor});
  final EditorController editor;

  @override
  State<_StickerPicker> createState() => _StickerPickerState();
}

class _StickerPickerState extends State<_StickerPicker> {
  String _category = kStickers.keys.first;

  @override
  Widget build(BuildContext context) {
    final n = widget.editor.selected!;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final c in kStickers.keys)
              ChoiceChip(
                label: Text(c),
                visualDensity: VisualDensity.compact,
                labelStyle: const TextStyle(fontSize: 12),
                selected: _category == c,
                onSelected: (_) => setState(() => _category = c),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          children: [
            for (final e in kStickers[_category]!)
              Material(
                color: n.sticker == e
                    ? cs.primaryContainer
                    : cs.surfaceContainerHighest.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () =>
                      widget.editor.setSticker(n.sticker == e ? null : e),
                  child: Center(
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: n.sticker == null
              ? null
              : () => widget.editor.setSticker(null),
          icon: const Icon(Icons.hide_image_outlined, size: 18),
          label: const Text('Remover adesivo'),
        ),
      ],
    );
  }
}

/// Campo de texto que só grava ao perder o foco ou pressionar Enter,
/// evitando uma entrada no histórico a cada tecla.
class CommitTextField extends StatefulWidget {
  const CommitTextField({
    super.key,
    required this.value,
    required this.onCommit,
    this.label,
    this.hint,
    this.maxLines = 1,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final String? label;
  final String? hint;
  final int maxLines;

  @override
  State<CommitTextField> createState() => _CommitTextFieldState();
}

class _CommitTextFieldState extends State<CommitTextField> {
  late final TextEditingController _c = TextEditingController(
    text: widget.value,
  );
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant CommitTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _c.text) _c.text = widget.value;
  }

  void _commit() {
    if (_c.text != widget.value) widget.onCommit(_c.text);
  }

  @override
  void dispose() {
    // O campo some quando outro tópico é selecionado: grava depois do quadro
    // atual para não alterar o estado durante a construção da tela.
    final text = _c.text, commit = widget.onCommit;
    if (text != widget.value) {
      WidgetsBinding.instance.addPostFrameCallback((_) => commit(text));
    }
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      focusNode: _focus,
      minLines: 1,
      maxLines: widget.maxLines,
      textInputAction: widget.maxLines == 1
          ? TextInputAction.done
          : TextInputAction.newline,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        hintText: widget.hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

/// Fileira de amostras de cor ('' = automático).
class ColorRow extends StatelessWidget {
  const ColorRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onPick,
    this.size = 24,
  });

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onPick;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        for (final hex in colors)
          Tooltip(
            message: hex.isEmpty ? 'Automático' : hex,
            waitDuration: const Duration(milliseconds: 500),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onPick(hex),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: parseHex(hex) ?? Colors.transparent,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected.toUpperCase() == hex.toUpperCase()
                        ? cs.primary
                        : Theme.of(context).dividerColor,
                    width: selected.toUpperCase() == hex.toUpperCase() ? 3 : 1,
                  ),
                ),
                child: hex.isEmpty
                    ? Icon(
                        Icons.auto_awesome,
                        size: size * 0.55,
                        color: cs.onSurface,
                      )
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value, min, max;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final v = (_drag ?? widget.value).clamp(widget.min, widget.max).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(
            widget.label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: v.toStringAsFixed(v < 10 ? 1 : 0),
            onChanged: (x) => setState(() => _drag = x),
            // Só grava no histórico ao soltar o controle.
            onChangeEnd: (x) {
              setState(() => _drag = null);
              widget.onChanged(x);
            },
          ),
        ),
        SizedBox(
          width: 30,
          child: Text(
            v.toStringAsFixed(v < 10 ? 1 : 0),
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
