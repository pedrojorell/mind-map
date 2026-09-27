import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../editor_controller.dart';
import '../file_actions.dart';
import '../io/file_io.dart';
import '../models.dart';

Future<void> openLink(BuildContext context, String link) async {
  var u = link.trim();
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(u)) u = 'https://$u';
  final ok = await launchUrl(Uri.parse(u), mode: LaunchMode.externalApplication)
      .catchError((_) => false);
  if (!ok && context.mounted) showSnack(context, 'Não foi possível abrir $u');
}

Future<void> openAttachment(BuildContext context, String path) async {
  final ok = await launchUrl(Uri.file(path)).catchError((_) => false);
  if (!ok && context.mounted) showSnack(context, 'Não foi possível abrir $path');
}

class PropertiesPanel extends StatelessWidget {
  const PropertiesPanel({super.key, required this.editor});

  final EditorController editor;

  @override
  Widget build(BuildContext context) {
    final n = editor.selected;
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (n == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Selecione um tópico para editar suas propriedades.',
                style: t.bodyMedium),
          )
        else
          ..._nodeSection(context, n),
        const Divider(height: 32),
        ..._docSection(context),
      ],
    );
  }

  List<Widget> _nodeSection(BuildContext context, MindMapNode n) {
    final t = Theme.of(context).textTheme;
    final id = n.id;
    return [
      Text('Tópico', style: t.titleMedium),
      const SizedBox(height: 10),
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
      const SizedBox(height: 10),
      CommitTextField(
        key: ValueKey('note_$id'),
        value: n.note,
        label: 'Anotações',
        hint: 'Detalhes, ideias, lembretes…',
        maxLines: 5,
        onCommit: (v) => editor.updateNode(id, (n) => n.note = v),
      ),
      const SizedBox(height: 16),
      _label(context, 'Cor do ramo'),
      _ColorRow(
        colors: kPalette,
        selected: n.color,
        onPick: (c) => editor.updateNode(id, (n) => n.color = c),
      ),
      const SizedBox(height: 12),
      _label(context, 'Preenchimento'),
      _ColorRow(
        colors: kFillPalette,
        selected: n.fillColor ?? '',
        onPick: (c) =>
            editor.updateNode(id, (n) => n.fillColor = c.isEmpty ? null : c),
      ),
      const SizedBox(height: 12),
      _label(context, 'Cor do texto'),
      _ColorRow(
        colors: const ['', '#FFFFFF', '#15171F', ...kPalette],
        selected: n.textColor ?? '',
        onPick: (c) =>
            editor.updateNode(id, (n) => n.textColor = c.isEmpty ? null : c),
      ),
      const SizedBox(height: 14),
      _label(context, 'Forma'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in kShapes.entries)
            ChoiceChip(
              label: Text(e.value),
              selected: n.shape == e.key,
              onSelected: (_) =>
                  editor.updateNode(id, (n) => n.shape = e.key, relayout: true),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          _label(context, 'Texto'),
          const Spacer(),
          IconButton(
            tooltip: 'Negrito',
            isSelected: n.bold,
            icon: const Icon(Icons.format_bold),
            onPressed: () =>
                editor.updateNode(id, (n) => n.bold = !n.bold, relayout: true),
          ),
          IconButton(
            tooltip: 'Itálico',
            isSelected: n.italic,
            icon: const Icon(Icons.format_italic),
            onPressed: () => editor.updateNode(id, (n) => n.italic = !n.italic,
                relayout: true),
          ),
          IconButton(
            tooltip: 'Borda tracejada',
            isSelected: n.dashed,
            icon: const Icon(Icons.line_style),
            onPressed: () =>
                editor.updateNode(id, (n) => n.dashed = !n.dashed),
          ),
        ],
      ),
      _SliderRow(
        label: 'Tamanho da fonte',
        value: n.fontSize,
        min: 10,
        max: 40,
        divisions: 30,
        onChanged: (v) =>
            editor.updateNode(id, (n) => n.fontSize = v, relayout: true),
      ),
      _SliderRow(
        label: 'Espessura da borda',
        value: n.borderWidth,
        min: 0,
        max: 6,
        divisions: 12,
        onChanged: (v) => editor.updateNode(id, (n) => n.borderWidth = v),
      ),
      const SizedBox(height: 4),
      OutlinedButton.icon(
        icon: const Icon(Icons.format_paint_outlined, size: 18),
        label: const Text('Aplicar cor e forma a todo o ramo'),
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
      const SizedBox(height: 16),
      _label(context, 'Link'),
      Row(
        children: [
          Expanded(
            child: CommitTextField(
              key: ValueKey('link_$id'),
              value: n.link ?? '',
              hint: 'https://…',
              onCommit: (v) => editor.updateNode(
                  id, (n) => n.link = v.trim().isEmpty ? null : v.trim()),
            ),
          ),
          IconButton(
            tooltip: 'Abrir link',
            onPressed: n.hasLink ? () => openLink(context, n.link!) : null,
            icon: const Icon(Icons.open_in_new),
          ),
        ],
      ),
      const SizedBox(height: 14),
      Row(
        children: [
          _label(context, 'Anexos'),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('Anexar'),
            onPressed: () => attachFiles(context, editor, id),
          ),
        ],
      ),
      if (n.attachments.isEmpty)
        Text(
            canUseFilePaths
                ? 'Nenhum arquivo anexado.'
                : 'Anexos por caminho de arquivo funcionam na versão desktop.',
            style: t.bodySmall)
      else
        for (var i = 0; i < n.attachments.length; i++)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(n.attachments[i].name, overflow: TextOverflow.ellipsis),
            subtitle:
                Text(n.attachments[i].path, overflow: TextOverflow.ellipsis),
            onTap: () => openAttachment(context, n.attachments[i].path),
            trailing: IconButton(
              tooltip: 'Remover anexo',
              icon: const Icon(Icons.close, size: 18),
              onPressed: () {
                final idx = i;
                editor.updateNode(id, (n) => n.attachments.removeAt(idx));
              },
            ),
          ),
    ];
  }

  List<Widget> _docSection(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final doc = editor.doc;
    return [
      Text('Mapa', style: t.titleMedium),
      const SizedBox(height: 6),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Organização automática'),
        subtitle: const Text('Reposiciona os tópicos ao editar'),
        value: doc.autoLayout,
        onChanged: editor.setAutoLayout,
      ),
      const SizedBox(height: 6),
      _label(context, 'Conectores'),
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
        label: 'Espessura dos conectores',
        value: doc.connectorWidth,
        min: 1,
        max: 8,
        divisions: 14,
        onChanged: (v) => editor.setConnector(width: v),
      ),
    ];
  }

  Widget _label(BuildContext context, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s, style: Theme.of(context).textTheme.labelLarge),
      );
}

Future<void> attachFiles(
    BuildContext context, EditorController editor, String nodeId) async {
  if (!canUseFilePaths) {
    showSnack(context,
        'No navegador não é possível guardar o caminho do arquivo. Use a versão desktop ou adicione um link.');
    return;
  }
  try {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      dialogTitle: 'Escolha arquivos para anexar',
    );
    if (r == null) return;
    final atts = [
      for (final f in r.files)
        if (f.path != null) NodeAttachment(name: f.name, path: f.path!),
    ];
    if (atts.isEmpty) return;
    editor.updateNode(nodeId, (n) => n.attachments.addAll(atts));
  } catch (e) {
    if (context.mounted) showSnack(context, 'Erro ao anexar: $e');
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
  late final TextEditingController _c =
      TextEditingController(text: widget.value);
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
      textInputAction:
          widget.maxLines == 1 ? TextInputAction.done : TextInputAction.newline,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        isDense: true,
        labelText: widget.label,
        hintText: widget.hint,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow(
      {required this.colors, required this.selected, required this.onPick});

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final hex in colors)
          Tooltip(
            message: hex.isEmpty ? 'Automático' : hex,
            waitDuration: const Duration(milliseconds: 500),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => onPick(hex),
              child: Container(
                width: 26,
                height: 26,
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
                    ? Icon(Icons.auto_awesome, size: 14, color: cs.onSurface)
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
          width: 118,
          child: Text(widget.label,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Slider(
            value: v,
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions,
            label: v.toStringAsFixed(1),
            onChanged: (x) => setState(() => _drag = x),
            // Só grava no histórico ao soltar o controle.
            onChangeEnd: (x) {
              setState(() => _drag = null);
              widget.onChanged(x);
            },
          ),
        ),
      ],
    );
  }
}
