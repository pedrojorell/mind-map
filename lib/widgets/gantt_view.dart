import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../editor_controller.dart';
import '../models.dart';

/// Visão Gantt: os tópicos do mapa como linhas de tarefas numa linha do
/// tempo. Arraste uma barra para mudar as datas; arraste a borda direita
/// para mudar a duração.
class GanttView extends StatefulWidget {
  const GanttView({super.key, required this.editor, this.onOpenTask});

  final EditorController editor;

  /// Pede para abrir o painel de edição da tarefa.
  final ValueChanged<String>? onOpenTask;

  @override
  State<GanttView> createState() => _GanttViewState();
}

class _GanttViewState extends State<GanttView> {
  bool _onlyTasks = false;
  double _dayWidth = 34;
  final _hScroll = ScrollController();

  static const _rowH = 38.0;
  static const _nameW = 280.0;
  static const _day = Duration(days: 1);

  EditorController get editor => widget.editor;

  // Arraste em andamento: id, modo ('move' ou 'end') e dias deslocados.
  String? _dragId;
  String _dragMode = 'move';
  double _dragDx = 0;

  @override
  void dispose() {
    _hScroll.dispose();
    super.dispose();
  }

  DateTime _dayOf(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day);
  }

  @override
  Widget build(BuildContext context) {
    final doc = editor.doc;
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    final rows = <(MindMapNode, int)>[];
    void walk(String id, int depth) {
      final n = doc.nodes[id];
      if (n == null) return;
      if (!_onlyTasks || n.task != null) rows.add((n, depth));
      for (final c in n.childrenIds) {
        walk(c, depth + 1);
      }
    }

    walk(doc.rootId, 0);

    // Intervalo exibido.
    final today = DateTime.now();
    var first = DateTime(today.year, today.month, today.day);
    var last = first.add(const Duration(days: 21));
    for (final (n, _) in rows) {
      final task = n.task;
      if (task == null) continue;
      if (task.start != null && _dayOf(task.start!).isBefore(first)) {
        first = _dayOf(task.start!);
      }
      if (task.end != null && _dayOf(task.end!).isAfter(last)) {
        last = _dayOf(task.end!);
      }
    }
    first = first.subtract(const Duration(days: 3));
    last = last.add(const Duration(days: 7));
    final days = last.difference(first).inDays + 1;

    final tasks = rows.where((r) => r.$1.task != null).toList();
    final done = tasks.where((r) => r.$1.task!.done).length;

    return ColoredBox(
      color: cs.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                Text('Cronograma', style: t.titleMedium),
                Text(
                  '${tasks.length} tarefas · $done concluídas',
                  style: t.bodySmall,
                ),
                FilterChip(
                  label: const Text('Só tarefas'),
                  selected: _onlyTasks,
                  onSelected: (v) => setState(() => _onlyTasks = v),
                ),
                SegmentedButton<double>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: 18, label: Text('Mês')),
                    ButtonSegment(value: 34, label: Text('Semana')),
                    ButtonSegment(value: 60, label: Text('Dia')),
                  ],
                  selected: {_dayWidth},
                  onSelectionChanged: (s) =>
                      setState(() => _dayWidth = s.first),
                ),
                Text(
                  'Clique no nome para criar/editar a tarefa. Arraste a barra para mudar as datas.',
                  style: t.bodySmall,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Coluna de nomes.
                  SizedBox(
                    width: _nameW,
                    child: Column(
                      children: [
                        Container(
                          height: 44,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          color: cs.surfaceContainerLow,
                          child: Text('Tópico', style: t.labelLarge),
                        ),
                        for (final (n, depth) in rows)
                          _nameCell(context, n, depth),
                      ],
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  // Linha do tempo.
                  Expanded(
                    child: Scrollbar(
                      controller: _hScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _hScroll,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: days * _dayWidth,
                          child: Column(
                            children: [
                              _header(context, first, days),
                              Stack(
                                children: [
                                  CustomPaint(
                                    size: Size(
                                      days * _dayWidth,
                                      rows.length * _rowH,
                                    ),
                                    painter: _GridPainter(
                                      first: first,
                                      days: days,
                                      dayWidth: _dayWidth,
                                      rows: rows.length,
                                      rowH: _rowH,
                                      line: cs.outlineVariant.withValues(
                                        alpha: 0.5,
                                      ),
                                      weekend: cs.surfaceContainerHighest
                                          .withValues(alpha: 0.35),
                                      today: cs.error,
                                    ),
                                  ),
                                  for (var i = 0; i < rows.length; i++)
                                    if (rows[i].$1.task != null)
                                      _bar(context, rows[i].$1, i, first),
                                ],
                              ),
                            ],
                          ),
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
    );
  }

  Widget _nameCell(BuildContext context, MindMapNode n, int depth) {
    final cs = Theme.of(context).colorScheme;
    final selected = editor.selectedId == n.id;
    final color = parseHex(n.color) ?? cs.primary;
    return InkWell(
      onTap: () {
        editor.select(n.id);
        widget.onOpenTask?.call(n.id);
      },
      child: Container(
        height: _rowH,
        padding: EdgeInsets.only(left: 12 + depth * 14.0, right: 8),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withValues(alpha: 0.5) : null,
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                n.text.replaceAll('\n', ' '),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: depth <= 1 ? FontWeight.w600 : FontWeight.w400,
                  decoration: n.task?.done ?? false
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
            ),
            if (n.task != null)
              Text(
                '${n.task!.progress}%',
                style: Theme.of(context).textTheme.bodySmall,
              )
            else
              Icon(Icons.add_task, size: 16, color: cs.outline),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, DateTime first, int days) {
    final cs = Theme.of(context).colorScheme;
    const months = [
      'jan',
      'fev',
      'mar',
      'abr',
      'mai',
      'jun',
      'jul',
      'ago',
      'set',
      'out',
      'nov',
      'dez',
    ];
    const week = ['S', 'T', 'Q', 'Q', 'S', 'S', 'D'];
    return Container(
      height: 44,
      color: cs.surfaceContainerLow,
      child: Stack(
        children: [
          for (var i = 0; i < days; i++)
            Positioned(
              left: i * _dayWidth,
              top: 0,
              width: _dayWidth,
              height: 44,
              child: Builder(
                builder: (_) {
                  final d = first.add(_day * i);
                  final showMonth = d.day == 1 || i == 0;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        showMonth
                            ? '${months[d.month - 1]}/${d.year % 100}'
                            : '',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                        overflow: TextOverflow.visible,
                        softWrap: false,
                      ),
                      Text(
                        _dayWidth >= 30
                            ? '${week[d.weekday - 1]} ${d.day}'
                            : '${d.day}',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: cs.onSurfaceVariant,
                        ),
                        softWrap: false,
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, MindMapNode n, int row, DateTime first) {
    final cs = Theme.of(context).colorScheme;
    final task = n.task!;
    final start = task.start == null ? DateTime.now() : _dayOf(task.start!);
    final end = task.end == null ? start : _dayOf(task.end!);
    var left = start.difference(first).inDays * _dayWidth;
    var width = (end.difference(start).inDays + 1) * _dayWidth;
    if (_dragId == n.id) {
      if (_dragMode == 'move') {
        left += _dragDx;
      } else {
        width = math.max(_dayWidth, width + _dragDx);
      }
    }
    final color = task.done
        ? const Color(0xFF43A047)
        : (parseHex(n.color) ?? cs.primary);
    final label = n.text.replaceAll('\n', ' ');

    void commit() {
      final days = (_dragDx / _dayWidth).round();
      final mode = _dragMode;
      setState(() {
        _dragId = null;
        _dragDx = 0;
      });
      if (days == 0) return;
      editor.updateNode(n.id, (n) {
        final t = n.task!;
        final s = DateTime.fromMillisecondsSinceEpoch(
          t.start ?? start.millisecondsSinceEpoch,
        );
        final e = DateTime.fromMillisecondsSinceEpoch(
          t.end ?? end.millisecondsSinceEpoch,
        );
        if (mode == 'move') {
          t.start = s.add(_day * days).millisecondsSinceEpoch;
          t.end = e.add(_day * days).millisecondsSinceEpoch;
        } else {
          final ne = e.add(_day * days);
          t.end = (ne.isBefore(s) ? s : ne).millisecondsSinceEpoch;
        }
      });
    }

    return Positioned(
      left: left,
      top: row * _rowH + 7,
      width: width,
      height: _rowH - 14,
      child: Tooltip(
        message:
            '$label\n${task.progress}%${task.assignee.isEmpty ? '' : ' · ${task.assignee}'}',
        waitDuration: const Duration(milliseconds: 500),
        child: GestureDetector(
          onTap: () {
            editor.select(n.id);
            widget.onOpenTask?.call(n.id);
          },
          onHorizontalDragStart: (_) => setState(() {
            _dragId = n.id;
            _dragMode = 'move';
            _dragDx = 0;
          }),
          onHorizontalDragUpdate: (d) => setState(() => _dragDx += d.delta.dx),
          onHorizontalDragEnd: (_) => commit(),
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.28),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color, width: 1.2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: task.progress / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
                // Alça para mudar a data de término.
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 10,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: GestureDetector(
                      onHorizontalDragStart: (_) => setState(() {
                        _dragId = n.id;
                        _dragMode = 'end';
                        _dragDx = 0;
                      }),
                      onHorizontalDragUpdate: (d) =>
                          setState(() => _dragDx += d.delta.dx),
                      onHorizontalDragEnd: (_) => commit(),
                      child: Container(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(6),
                          ),
                        ),
                      ),
                    ),
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

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.first,
    required this.days,
    required this.dayWidth,
    required this.rows,
    required this.rowH,
    required this.line,
    required this.weekend,
    required this.today,
  });

  final DateTime first;
  final int days;
  final double dayWidth;
  final int rows;
  final double rowH;
  final Color line;
  final Color weekend;
  final Color today;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = line;
    for (var i = 0; i < days; i++) {
      final d = first.add(Duration(days: i));
      if (d.weekday >= 6) {
        canvas.drawRect(
          Rect.fromLTWH(i * dayWidth, 0, dayWidth, size.height),
          Paint()..color = weekend,
        );
      }
      canvas.drawLine(
        Offset(i * dayWidth, 0),
        Offset(i * dayWidth, size.height),
        p,
      );
    }
    for (var r = 1; r <= rows; r++) {
      canvas.drawLine(Offset(0, r * rowH), Offset(size.width, r * rowH), p);
    }
    final now = DateTime.now();
    final t =
        DateTime(now.year, now.month, now.day).difference(first).inHours / 24;
    final x = (t + 0.5) * dayWidth;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = today
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => true;
}
