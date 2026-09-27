import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../editor_controller.dart';
import '../models.dart';
import 'properties_panel.dart' show CommitTextField;

/// Seção do painel com título, descrição e conteúdo recolhível.
class _Block extends StatelessWidget {
  const _Block({
    required this.icon,
    required this.title,
    required this.children,
    this.active = false,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;
  final bool active;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active ? cs.primary.withValues(alpha: 0.6) : cs.outlineVariant,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: active,
          dense: true,
          shape: const Border(),
          leading: Icon(icon, size: 20, color: active ? cs.primary : null),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          trailing: trailing,
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class ElementsSection extends StatelessWidget {
  const ElementsSection({super.key, required this.editor, required this.node});

  final EditorController editor;
  final MindMapNode node;

  MindMapNode get n => node;

  void _update(void Function(MindMapNode n) fn) =>
      editor.updateNode(n.id, fn, relayout: true);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ------------------------------------------------------------ balões
        _Block(
          icon: Icons.chat_bubble_outline,
          title: 'Balões (${n.callouts.length})',
          active: n.callouts.isNotEmpty,
          children: [
            Text(
              'Pequenas observações que ficam acima do tópico.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < n.callouts.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: CommitTextField(
                        key: ValueKey('callout_${n.id}_$i'),
                        value: n.callouts[i],
                        maxLines: 3,
                        onCommit: (v) {
                          final idx = i;
                          _update((n) => n.callouts[idx] = v);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remover balão',
                      onPressed: () {
                        final idx = i;
                        _update((n) => n.callouts.removeAt(idx));
                      },
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: () => _update((n) => n.callouts.add('Observação')),
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              label: const Text('Adicionar balão'),
            ),
          ],
        ),

        // ------------------------------------------------------------ limite
        _Block(
          icon: Icons.crop_free,
          title: 'Limite do ramo',
          active: n.boundary,
          trailing: Switch(
            value: n.boundary,
            onChanged: (v) => _update((n) => n.boundary = v),
          ),
          children: [
            Text(
              'Contorno tracejado em volta deste tópico e de todos os subtópicos.',
              style: t.bodySmall,
            ),
            const SizedBox(height: 8),
            CommitTextField(
              key: ValueKey('boundary_${n.id}'),
              value: n.boundaryLabel,
              label: 'Título do limite (opcional)',
              onCommit: (v) => _update((n) {
                n.boundaryLabel = v.trim();
                if (v.trim().isNotEmpty) n.boundary = true;
              }),
            ),
          ],
        ),

        // ------------------------------------------------------------ resumo
        _Block(
          icon: Icons.data_array,
          title: 'Resumo dos subtópicos',
          active: n.summary != null,
          trailing: Switch(
            value: n.summary != null,
            onChanged: n.childrenIds.isEmpty
                ? null
                : (v) => _update((n) => n.summary = v ? 'Resumo' : null),
          ),
          children: [
            Text(
              n.childrenIds.isEmpty
                  ? 'Adicione subtópicos para poder resumi-los com uma chave.'
                  : 'Uma chave agrupa todos os subtópicos com um texto de conclusão.',
              style: t.bodySmall,
            ),
            if (n.summary != null) ...[
              const SizedBox(height: 8),
              CommitTextField(
                key: ValueKey('summary_${n.id}'),
                value: n.summary!,
                label: 'Texto do resumo',
                maxLines: 3,
                onCommit: (v) => _update((n) => n.summary = v),
              ),
            ],
          ],
        ),

        // --------------------------------------------------------- comentários
        _CommentsBlock(editor: editor, node: n),

        // ------------------------------------------------------------ tabela
        _TableBlock(editor: editor, node: n),

        // ------------------------------------------------------------ fórmula
        _FormulaBlock(editor: editor, node: n),

        // ------------------------------------------------------------ tarefa
        _TaskBlock(editor: editor, node: n),
      ],
    );
  }
}

class _CommentsBlock extends StatefulWidget {
  const _CommentsBlock({required this.editor, required this.node});
  final EditorController editor;
  final MindMapNode node;

  @override
  State<_CommentsBlock> createState() => _CommentsBlockState();
}

class _CommentsBlockState extends State<_CommentsBlock> {
  final _c = TextEditingController();
  static String _author = '';
  late final _a = TextEditingController(text: _author);

  @override
  void dispose() {
    _c.dispose();
    _a.dispose();
    super.dispose();
  }

  void _add() {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _author = _a.text.trim();
    _c.clear();
    widget.editor.updateNode(
      widget.node.id,
      (n) => n.comments.add(
        NodeComment(
          id: newId(),
          text: text,
          author: _author,
          at: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      relayout: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.node;
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    String when(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      String two(int v) => v.toString().padLeft(2, '0');
      return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
    }

    return _Block(
      icon: Icons.forum_outlined,
      title: 'Comentários (${n.comments.length})',
      active: n.comments.isNotEmpty,
      children: [
        for (final c in n.comments)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 13,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    (c.author.isEmpty ? '?' : c.author[0]).toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${c.author.isEmpty ? 'Anônimo' : c.author} · ${when(c.at)}',
                        style: t.labelSmall,
                      ),
                      Text(c.text),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Excluir comentário',
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  onPressed: () => widget.editor.updateNode(
                    n.id,
                    (n) => n.comments.removeWhere((x) => x.id == c.id),
                    relayout: true,
                  ),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        TextField(
          controller: _a,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Seu nome',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _c,
          minLines: 1,
          maxLines: 4,
          onSubmitted: (_) => _add(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Escreva um comentário…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: 'Enviar',
              onPressed: _add,
              icon: const Icon(Icons.send),
            ),
          ),
        ),
      ],
    );
  }
}

class _TableBlock extends StatelessWidget {
  const _TableBlock({required this.editor, required this.node});
  final EditorController editor;
  final MindMapNode node;

  void _update(void Function(List<List<String>> t) fn) {
    editor.updateNode(node.id, (n) {
      final t = n.table ?? [];
      fn(t);
      n.table = t.isEmpty ? null : t;
    }, relayout: true);
  }

  @override
  Widget build(BuildContext context) {
    final table = node.table;
    final cols = table == null
        ? 0
        : table.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    return _Block(
      icon: Icons.table_chart_outlined,
      title: 'Tabela',
      active: table != null,
      children: [
        if (table == null)
          OutlinedButton.icon(
            onPressed: () => _update(
              (t) => t.addAll([
                ['Item', 'Valor'],
                ['', ''],
                ['', ''],
              ]),
            ),
            icon: const Icon(Icons.grid_on, size: 18),
            label: const Text('Criar tabela 3 × 2'),
          )
        else ...[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              children: [
                for (var r = 0; r < table.length; r++)
                  Row(
                    children: [
                      for (var c = 0; c < cols; c++)
                        SizedBox(
                          width: 92,
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: CommitTextField(
                              key: ValueKey('cell_${node.id}_${r}_$c'),
                              value: c < table[r].length ? table[r][c] : '',
                              onCommit: (v) => _update((t) {
                                while (t[r].length <= c) {
                                  t[r].add('');
                                }
                                t[r][c] = v;
                              }),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              ActionChip(
                label: const Text('+ Linha'),
                onPressed: () => _update(
                  (t) => t.add(List.filled(cols, '', growable: true)),
                ),
              ),
              ActionChip(
                label: const Text('+ Coluna'),
                onPressed: () => _update((t) {
                  for (final row in t) {
                    row.add('');
                  }
                }),
              ),
              ActionChip(
                label: const Text('− Linha'),
                onPressed: table.length <= 1
                    ? null
                    : () => _update((t) => t.removeLast()),
              ),
              ActionChip(
                label: const Text('− Coluna'),
                onPressed: cols <= 1
                    ? null
                    : () => _update((t) {
                        for (final row in t) {
                          if (row.length >= cols) row.removeLast();
                        }
                      }),
              ),
              ActionChip(
                avatar: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remover'),
                onPressed: () => _update((t) => t.clear()),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _FormulaBlock extends StatelessWidget {
  const _FormulaBlock({required this.editor, required this.node});
  final EditorController editor;
  final MindMapNode node;

  static const _examples = {
    'Bhaskara': r'x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}',
    'Pitágoras': r'a^2 + b^2 = c^2',
    'Somatório': r'\sum_{i=1}^{n} i = \frac{n(n+1)}{2}',
    'Integral': r'\int_a^b f(x)\,dx',
    'Einstein': r'E = mc^2',
  };

  @override
  Widget build(BuildContext context) {
    final f = node.formula;
    final cs = Theme.of(context).colorScheme;
    return _Block(
      icon: Icons.functions,
      title: 'Fórmula (LaTeX)',
      active: f != null,
      children: [
        CommitTextField(
          key: ValueKey('formula_${node.id}'),
          value: f ?? '',
          hint: r'ex.: E = mc^2',
          maxLines: 3,
          onCommit: (v) => editor.updateNode(
            node.id,
            (n) => n.formula = v.trim().isEmpty ? null : v.trim(),
            relayout: true,
          ),
        ),
        if (f != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Math.tex(
                f,
                textStyle: const TextStyle(fontSize: 18),
                onErrorFallback: (e) => Text(
                  'Erro: ${e.message}',
                  style: TextStyle(color: cs.error, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final e in _examples.entries)
              ActionChip(
                label: Text(e.key),
                visualDensity: VisualDensity.compact,
                onPressed: () => editor.updateNode(
                  node.id,
                  (n) => n.formula = e.value,
                  relayout: true,
                ),
              ),
            if (f != null)
              ActionChip(
                avatar: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remover'),
                visualDensity: VisualDensity.compact,
                onPressed: () => editor.updateNode(
                  node.id,
                  (n) => n.formula = null,
                  relayout: true,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _TaskBlock extends StatelessWidget {
  const _TaskBlock({required this.editor, required this.node});
  final EditorController editor;
  final MindMapNode node;

  void _update(void Function(NodeTask t) fn) {
    editor.updateNode(node.id, (n) {
      final t = n.task ?? NodeTask();
      fn(t);
      n.task = t;
    }, relayout: true);
  }

  Future<void> _pick(BuildContext context, bool start) async {
    final t = node.task;
    final current = start ? t?.start : t?.end;
    final d = await showDatePicker(
      context: context,
      initialDate: current == null
          ? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(current),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: start ? 'Data de início' : 'Data de término',
    );
    if (d == null) return;
    _update((t) {
      if (start) {
        t.start = d.millisecondsSinceEpoch;
        if (t.end != null && t.end! < t.start!) t.end = t.start;
      } else {
        t.end = d.millisecondsSinceEpoch;
        if (t.start != null && t.start! > t.end!) t.start = t.end;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = node.task;
    String fmt(int? ms) {
      if (ms == null) return 'Escolher';
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    }

    return _Block(
      icon: Icons.task_alt,
      title: 'Tarefa (Gantt)',
      active: t != null,
      trailing: Switch(
        value: t != null,
        onChanged: (v) => editor.updateNode(node.id, (n) {
          if (v) {
            final now = DateTime.now();
            final day = DateTime(now.year, now.month, now.day);
            n.task = NodeTask(
              start: day.millisecondsSinceEpoch,
              end: day.add(const Duration(days: 3)).millisecondsSinceEpoch,
            );
          } else {
            n.task = null;
          }
        }, relayout: true),
      ),
      children: [
        if (t == null)
          Text(
            'Transforme o tópico numa tarefa com datas, responsável e progresso. Veja tudo na visão Gantt.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(context, true),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: Text(fmt(t.start)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(context, false),
                  icon: const Icon(Icons.flag_outlined, size: 16),
                  label: Text(fmt(t.end)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Progresso'),
              Expanded(
                child: Slider(
                  value: t.progress.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  label: '${t.progress}%',
                  onChanged: (v) {
                    if (v.round() != t.progress) {
                      _update((t) => t.progress = v.round());
                    }
                  },
                ),
              ),
              Text('${t.progress}%'),
            ],
          ),
          CommitTextField(
            key: ValueKey('assignee_${node.id}'),
            value: t.assignee,
            label: 'Responsável',
            onCommit: (v) => _update((t) => t.assignee = v.trim()),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: t.done,
            title: const Text('Concluída'),
            onChanged: (v) => _update((t) => t.progress = v == true ? 100 : 0),
          ),
        ],
      ],
    );
  }
}
