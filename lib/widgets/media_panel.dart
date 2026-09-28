import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../editor_controller.dart';
import '../io/file_io.dart';
import '../media.dart';
import '../models.dart';
import 'properties_panel.dart' show CommitTextField;
import 'web_dialogs.dart';

Widget _section(BuildContext context, String text, {Widget? trailing}) =>
    Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );

// =====================================================================
// Imagens e documentos
// =====================================================================

class MediaSection extends StatefulWidget {
  const MediaSection({super.key, required this.editor, required this.node});

  final EditorController editor;
  final MindMapNode node;

  @override
  State<MediaSection> createState() => _MediaSectionState();
}

class _MediaSectionState extends State<MediaSection> {
  bool _over = false;
  double? _dragWidth;

  EditorController get editor => widget.editor;
  MindMapNode get n => widget.node;

  Future<void> _insertImage() async {
    final img = await pickImage(context);
    if (img != null) {
      editor.updateNode(n.id, (n) => n.image = img, relayout: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final img = n.image;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Área para soltar arquivos.
        DropTarget(
          onDragEntered: (_) => setState(() => _over = true),
          onDragExited: (_) => setState(() => _over = false),
          onDragDone: (d) {
            setState(() => _over = false);
            handleDroppedFiles(context, editor, d.files, nodeId: n.id);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
            decoration: BoxDecoration(
              color: _over
                  ? cs.primaryContainer
                  : cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _over ? cs.primary : cs.outlineVariant,
                width: _over ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_upload_outlined,
                  size: 34,
                  color: _over ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                Text(
                  'Arraste imagens e documentos aqui',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium,
                ),
                Text(
                  'ou use os botões abaixo',
                  textAlign: TextAlign.center,
                  style: t.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _insertImage,
                      icon: const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 18,
                      ),
                      label: const Text('Imagem'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => showFreeImagesDialog(context, editor),
                      icon: const Icon(Icons.image_search, size: 18),
                      label: const Text('Imagens livres'),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => pickDocuments(context, editor, n.id),
                      icon: const Icon(Icons.note_add_outlined, size: 18),
                      label: const Text('Documento'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        _section(context, 'Imagem do tópico'),
        if (img == null)
          Text(
            'Nenhuma imagem. Ela aparece acima do texto do tópico.',
            style: t.bodySmall,
          )
        else ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
              constraints: const BoxConstraints(maxHeight: 180),
              child: Image.memory(
                imageBytes(img.data),
                fit: BoxFit.contain,
                gaplessPlayback: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Tamanho', style: t.bodySmall),
              Expanded(
                child: Slider(
                  value: (_dragWidth ?? img.width).clamp(40, 520),
                  min: 40,
                  max: 520,
                  onChanged: (v) => setState(() => _dragWidth = v),
                  onChangeEnd: (v) {
                    setState(() => _dragWidth = null);
                    editor.updateNode(
                      n.id,
                      (n) => n.image!.width = v,
                      relayout: true,
                    );
                  },
                ),
              ),
              Text('${(_dragWidth ?? img.width).round()}', style: t.bodySmall),
            ],
          ),
          Row(
            children: [
              TextButton.icon(
                onPressed: _insertImage,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Trocar'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => editor.updateNode(
                  n.id,
                  (n) => n.image = null,
                  relayout: true,
                ),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Remover'),
              ),
            ],
          ),
        ],

        _section(
          context,
          'Documentos (${n.attachments.length})',
          trailing: IconButton(
            tooltip: 'Anexar documentos',
            visualDensity: VisualDensity.compact,
            onPressed: () => pickDocuments(context, editor, n.id),
            icon: const Icon(Icons.add),
          ),
        ),
        if (n.attachments.isEmpty)
          Text(
            canUseFilePaths
                ? 'PDF, Word, Excel, apresentações, planilhas… qualquer arquivo.'
                : 'No navegador os arquivos ficam guardados dentro do mapa (até ${formatBytes(kMaxEmbeddedBytes)} cada).',
            style: t.bodySmall,
          )
        else
          for (var i = 0; i < n.attachments.length; i++)
            _AttachmentTile(
              attachment: n.attachments[i],
              onOpen: () => openAttachment(context, n.attachments[i]),
              onRemove: () {
                final idx = i;
                editor.updateNode(
                  n.id,
                  (n) => n.attachments.removeAt(idx),
                  relayout: true,
                );
              },
            ),
        if (canUseFilePaths && n.attachments.isNotEmpty) ...[
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => pickDocuments(context, editor, n.id, embed: true),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('Anexar guardando cópia dentro do mapa'),
          ),
        ],
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.onOpen,
    required this.onRemove,
  });

  final NodeAttachment attachment;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    final (icon, color) = fileIcon(a.extension);
    final cs = Theme.of(context).colorScheme;
    final detail = [
      if (a.extension.isNotEmpty) a.extension.toUpperCase(),
      if (a.size != null) formatBytes(a.size),
      if (a.embedded) 'guardado no mapa' else if (a.path.isNotEmpty) a.path,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        detail,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Abrir',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new),
                ),
                IconButton(
                  tooltip: 'Remover',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// Links, etiquetas e anotações
// =====================================================================

/// Pede um link ao usuário. [kind] sugere o tipo: web, email ou phone.
Future<NodeLink?> promptLink(
  BuildContext context, {
  NodeLink? initial,
  String kind = 'web',
}) async {
  final url = TextEditingController(text: initial?.url ?? '');
  final title = TextEditingController(text: initial?.title ?? '');
  final (label, hint, icon) = switch (kind) {
    'email' => ('E-mail', 'nome@exemplo.com', Icons.alternate_email),
    'phone' => (
      'Telefone / WhatsApp',
      '+55 11 91234-5678',
      Icons.call_outlined,
    ),
    'file' => (
      'Caminho do arquivo ou pasta',
      r'C:\Documentos\relatorio.pdf',
      Icons.folder_open_outlined,
    ),
    _ => ('Endereço do site', 'www.exemplo.com.br', Icons.public),
  };
  final r = await showDialog<NodeLink>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(initial == null ? 'Adicionar link' : 'Editar link'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: url,
              autofocus: true,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                prefixIcon: Icon(icon),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: title,
              decoration: const InputDecoration(
                labelText: 'Nome (opcional)',
                prefixIcon: Icon(Icons.label_outline),
              ),
              onSubmitted: (_) => Navigator.pop(
                ctx,
                NodeLink(url: url.text.trim(), title: title.text.trim()),
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
          onPressed: () => Navigator.pop(
            ctx,
            NodeLink(url: url.text.trim(), title: title.text.trim()),
          ),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  WidgetsBinding.instance.addPostFrameCallback((_) {
    url.dispose();
    title.dispose();
  });
  if (r == null || r.url.isEmpty) return null;
  return r;
}

/// Adiciona um link ao tópico [nodeId] pedindo os dados ao usuário.
Future<void> addLinkTo(
  BuildContext context,
  EditorController editor,
  String nodeId, {
  String kind = 'web',
}) async {
  final l = await promptLink(context, kind: kind);
  if (l != null) {
    editor.updateNode(nodeId, (n) => n.links.add(l), relayout: true);
  }
}

/// Menu com os links e documentos de um tópico (clique nos ícones do mapa).
Future<void> showNodeItemsMenu(
  BuildContext context,
  EditorController editor,
  String nodeId,
  String kind,
  Offset pos,
) async {
  final n = editor.doc.nodes[nodeId];
  if (n == null) return;
  final links = n.links.where((l) => l.url.trim().isNotEmpty).toList();
  if (kind == 'links' && links.length == 1) {
    await openNodeLink(context, links.first);
    return;
  }
  if (kind == 'files' && n.attachments.length == 1) {
    await openAttachment(context, n.attachments.first);
    return;
  }
  final items = <PopupMenuEntry<int>>[
    if (kind == 'links')
      for (var i = 0; i < links.length; i++)
        PopupMenuItem(
          value: i,
          height: 38,
          child: Row(
            children: [
              Icon(linkIcon(links[i].kind), size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Text(links[i].label, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        )
    else if (kind == 'files')
      for (var i = 0; i < n.attachments.length; i++)
        PopupMenuItem(
          value: i,
          height: 38,
          child: Row(
            children: [
              Icon(
                fileIcon(n.attachments[i].extension).$1,
                size: 18,
                color: fileIcon(n.attachments[i].extension).$2,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  n.attachments[i].name,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
  ];
  if (items.isEmpty) return;
  final v = await showMenu<int>(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
    items: items,
  );
  if (v == null || !context.mounted) return;
  if (kind == 'links') {
    await openNodeLink(context, links[v]);
  } else {
    await openAttachment(context, n.attachments[v]);
  }
}

class LinksSection extends StatefulWidget {
  const LinksSection({super.key, required this.editor, required this.node});

  final EditorController editor;
  final MindMapNode node;

  @override
  State<LinksSection> createState() => _LinksSectionState();
}

class _LinksSectionState extends State<LinksSection> {
  final _tag = TextEditingController();

  EditorController get editor => widget.editor;
  MindMapNode get n => widget.node;

  @override
  void dispose() {
    _tag.dispose();
    super.dispose();
  }

  void _addTag() {
    final v = _tag.text.trim();
    _tag.clear();
    if (v.isEmpty || n.tags.contains(v)) return;
    editor.updateNode(n.id, (n) => n.tags.add(v), relayout: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    Widget quick(String kind, IconData icon, String label) => ActionChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      onPressed: () => addLinkTo(context, editor, n.id, kind: kind),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _section(context, 'Links (${n.links.length})'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            quick('web', Icons.public, 'Site'),
            quick('email', Icons.alternate_email, 'E-mail'),
            quick('phone', Icons.call_outlined, 'Telefone'),
            if (canUseFilePaths)
              quick('file', Icons.folder_open_outlined, 'Pasta/arquivo'),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < n.links.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => openNodeLink(context, n.links[i]),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 4, 2, 4),
                  child: Row(
                    children: [
                      Icon(
                        linkIcon(n.links[i].kind),
                        size: 20,
                        color: cs.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              n.links[i].label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              n.links[i].url,
                              overflow: TextOverflow.ellipsis,
                              style: t.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Editar',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: () async {
                          final idx = i;
                          final l = await promptLink(
                            context,
                            initial: n.links[idx],
                            kind: n.links[idx].kind,
                          );
                          if (l != null) {
                            editor.updateNode(
                              n.id,
                              (n) => n.links[idx] = l,
                              relayout: true,
                            );
                          }
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Remover',
                        visualDensity: VisualDensity.compact,
                        iconSize: 18,
                        onPressed: () {
                          final idx = i;
                          editor.updateNode(
                            n.id,
                            (n) => n.links.removeAt(idx),
                            relayout: true,
                          );
                        },
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        _section(context, 'Etiquetas'),
        if (n.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in n.tags)
                  InputChip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                    onDeleted: () => editor.updateNode(
                      n.id,
                      (n) => n.tags.remove(tag),
                      relayout: true,
                    ),
                  ),
              ],
            ),
          ),
        TextField(
          controller: _tag,
          onSubmitted: (_) => _addTag(),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Nova etiqueta (ex.: urgente, R\$ 250, 15/10)',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            suffixIcon: IconButton(
              tooltip: 'Adicionar',
              onPressed: _addTag,
              icon: const Icon(Icons.add),
            ),
          ),
        ),

        _section(context, 'Anotações'),
        CommitTextField(
          key: ValueKey('note_${n.id}'),
          value: n.note,
          hint: 'Detalhes, números, ideias, lembretes…',
          maxLines: 10,
          onCommit: (v) => editor.updateNode(n.id, (n) => n.note = v),
        ),
      ],
    );
  }
}
