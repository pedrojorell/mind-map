import 'package:flutter/material.dart';

import '../editor_controller.dart';
import '../file_actions.dart';
import '../media.dart';
import '../models.dart';
import '../services/web_apis.dart';

/// Tópico que recebe o conteúdo: o selecionado ou um novo tópico flutuante.
String _targetNode(EditorController editor, String text, Offset scenePos) {
  final id = editor.selectedId;
  if (id != null && editor.doc.nodes.containsKey(id)) return id;
  return editor.addFloating(scenePos, text: text, edit: false);
}

Widget _errorBox(BuildContext context, Object error, VoidCallback retry) {
  final cs = Theme.of(context).colorScheme;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off, size: 40, color: cs.error),
          const SizedBox(height: 8),
          Text('$error', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: retry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    ),
  );
}

// =====================================================================
// Wikipédia
// =====================================================================

/// Pesquisa um assunto na Wikipédia e traz resumo, link, imagem e seções
/// (como subtópicos) para o tópico selecionado.
Future<void> showWikipediaDialog(
  BuildContext context,
  EditorController editor, {
  Offset scenePos = Offset.zero,
}) async {
  final initial = editor.selected?.text.replaceAll('\n', ' ').trim() ?? '';
  final applied = await showDialog<_WikiChoice>(
    context: context,
    builder: (_) => _WikipediaDialog(initialQuery: initial),
  );
  if (applied == null || !context.mounted) return;
  final s = applied.summary;
  final id = _targetNode(editor, s.title, scenePos);

  editor.updateNode(id, (n) {
    if (applied.note && s.extract.isNotEmpty) {
      n.note = n.note.trim().isEmpty
          ? s.extract
          : '${n.note.trim()}\n\n${s.extract}';
    }
    if (applied.link &&
        s.url.isNotEmpty &&
        !n.links.any((l) => l.url == s.url)) {
      n.links.add(NodeLink(url: s.url, title: 'Wikipédia: ${s.title}'));
    }
  }, relayout: true);

  for (final section in applied.sections) {
    editor.addChildWith(id, text: section, edit: false);
  }

  if (applied.image && s.image != null) {
    try {
      final bytes = await webApis.getBytes(s.image!);
      final img = await prepareImage(bytes, '${s.title}.jpg');
      if (img != null) {
        editor.updateNode(id, (n) => n.image = img, relayout: true);
      }
    } catch (e) {
      if (context.mounted) showSnack(context, '$e');
    }
  }
  editor.select(id);
  if (context.mounted) {
    showSnack(context, 'Conteúdo da Wikipédia adicionado: ${s.title}.');
  }
}

class _WikiChoice {
  _WikiChoice(this.summary, this.note, this.link, this.image, this.sections);
  final WikiSummary summary;
  final bool note;
  final bool link;
  final bool image;
  final List<String> sections;
}

class _WikipediaDialog extends StatefulWidget {
  const _WikipediaDialog({required this.initialQuery});
  final String initialQuery;

  @override
  State<_WikipediaDialog> createState() => _WikipediaDialogState();
}

class _WikipediaDialogState extends State<_WikipediaDialog> {
  late final _query = TextEditingController(text: widget.initialQuery);
  Future<List<WikiSearchResult>>? _results;

  // Artigo escolhido.
  WikiSummary? _summary;
  List<String> _sections = const [];
  final Set<String> _pickedSections = {};
  bool _loadingArticle = false;
  Object? _articleError;

  bool _note = true, _link = true, _image = true;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    setState(() {
      _summary = null;
      _results = webApis.wikiSearch(_query.text);
    });
  }

  Future<void> _open(String title) async {
    setState(() {
      _loadingArticle = true;
      _articleError = null;
    });
    try {
      final results = await Future.wait([
        webApis.wikiSummary(title),
        webApis.wikiSections(title),
      ]);
      if (!mounted) return;
      final summary = results[0] as WikiSummary?;
      if (summary == null) throw WebApiException('Artigo não encontrado.');
      setState(() {
        _summary = summary;
        _sections = results[1] as List<String>;
        _pickedSections
          ..clear()
          ..addAll(_sections.take(6));
        _image = summary.image != null;
      });
    } catch (e) {
      if (mounted) setState(() => _articleError = e);
    } finally {
      if (mounted) setState(() => _loadingArticle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = _summary;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.travel_explore),
          const SizedBox(width: 10),
          Text(s == null ? 'Pesquisar na Wikipédia' : s.title),
        ],
      ),
      content: SizedBox(
        width: 560,
        height: 460,
        child: s == null ? _searchView(context) : _articleView(context, s),
      ),
      actions: [
        if (s != null)
          TextButton(
            onPressed: () => setState(() => _summary = null),
            child: const Text('Voltar'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (s != null)
          FilledButton.icon(
            onPressed: () => Navigator.pop(
              context,
              _WikiChoice(
                s,
                _note,
                _link,
                _image,
                _sections.where(_pickedSections.contains).toList(),
              ),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar ao mapa'),
          ),
      ],
      actionsOverflowButtonSpacing: 8,
      insetPadding: const EdgeInsets.all(24),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      titleTextStyle: t.titleLarge,
    );
  }

  Widget _searchView(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: _query,
          autofocus: true,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'Assunto (ex.: Fotossíntese, Revolução Francesa…)',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: IconButton(
              onPressed: _search,
              icon: const Icon(Icons.arrow_forward),
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingArticle) const LinearProgressIndicator(),
        if (_articleError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '$_articleError',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: _results == null
              ? const Center(
                  child: Text('Digite um assunto e pressione Enter.'),
                )
              : FutureBuilder<List<WikiSearchResult>>(
                  future: _results,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _errorBox(context, snap.error!, _search);
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final items = snap.data!;
                    if (items.isEmpty) {
                      return const Center(
                        child: Text('Nenhum artigo encontrado.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final r = items[i];
                        return ListTile(
                          leading: SizedBox(
                            width: 44,
                            height: 44,
                            child: r.thumbnail == null
                                ? const Icon(Icons.article_outlined)
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      r.thumbnail!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.article_outlined),
                                    ),
                                  ),
                          ),
                          title: Text(r.title),
                          subtitle: r.description.isEmpty
                              ? null
                              : Text(
                                  r.description,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: _loadingArticle ? null : () => _open(r.title),
                        );
                      },
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            'Fonte: Wikipédia (conteúdo sob licença CC BY-SA).',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  Widget _articleView(BuildContext context, WikiSummary s) {
    final t = Theme.of(context).textTheme;
    return ListView(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (s.image != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    s.image!,
                    width: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            Expanded(child: Text(s.extract, style: t.bodyMedium)),
          ],
        ),
        const SizedBox(height: 12),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _note,
          onChanged: (v) => setState(() => _note = v ?? false),
          title: const Text('Resumo como anotação do tópico'),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _link,
          onChanged: (v) => setState(() => _link = v ?? false),
          title: const Text('Link para o artigo'),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          value: _image,
          onChanged: s.image == null
              ? null
              : (v) => setState(() => _image = v ?? false),
          title: const Text('Imagem do artigo'),
        ),
        if (_sections.isNotEmpty) ...[
          const Divider(),
          Text(
            'Criar subtópicos com as seções do artigo:',
            style: t.labelLarge,
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final sec in _sections)
                FilterChip(
                  label: Text(sec),
                  selected: _pickedSections.contains(sec),
                  onSelected: (v) => setState(() {
                    if (v) {
                      _pickedSections.add(sec);
                    } else {
                      _pickedSections.remove(sec);
                    }
                  }),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

// =====================================================================
// Imagens livres (Openverse)
// =====================================================================

/// Busca imagens de uso livre e coloca a escolhida no tópico, com crédito.
Future<void> showFreeImagesDialog(
  BuildContext context,
  EditorController editor, {
  Offset scenePos = Offset.zero,
}) async {
  final initial = editor.selected?.text.replaceAll('\n', ' ').trim() ?? '';
  final picked = await showDialog<OpenImage>(
    context: context,
    builder: (_) => _FreeImagesDialog(initialQuery: initial),
  );
  if (picked == null || !context.mounted) return;
  try {
    final bytes = await webApis.getBytes(picked.thumbnail);
    final img = await prepareImage(
      bytes,
      picked.title.isEmpty ? 'imagem.jpg' : '${picked.title}.jpg',
    );
    if (img == null) throw WebApiException('Formato de imagem não suportado.');
    final id = _targetNode(
      editor,
      picked.title.isEmpty ? 'Imagem' : picked.title,
      scenePos,
    );
    editor.updateNode(id, (n) {
      n.image = img;
      if (picked.landingUrl.isNotEmpty &&
          !n.links.any((l) => l.url == picked.landingUrl)) {
        n.links.add(
          NodeLink(url: picked.landingUrl, title: 'Crédito: ${picked.credit}'),
        );
      }
    }, relayout: true);
    editor.select(id);
    if (context.mounted) {
      showSnack(context, 'Imagem adicionada (${picked.license}).');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, '$e');
  }
}

class _FreeImagesDialog extends StatefulWidget {
  const _FreeImagesDialog({required this.initialQuery});
  final String initialQuery;

  @override
  State<_FreeImagesDialog> createState() => _FreeImagesDialogState();
}

class _FreeImagesDialogState extends State<_FreeImagesDialog> {
  late final _query = TextEditingController(text: widget.initialQuery);
  Future<List<OpenImage>>? _results;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery.isNotEmpty) _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() =>
      setState(() => _results = webApis.searchImages(_query.text));

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.image_search),
          SizedBox(width: 10),
          Text('Imagens livres'),
        ],
      ),
      content: SizedBox(
        width: 640,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText:
                    'O que procurar (funciona melhor em inglês: forest, city…)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: _search,
                  icon: const Icon(Icons.arrow_forward),
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _results == null
                  ? const Center(
                      child: Text('Digite o que procura e pressione Enter.'),
                    )
                  : FutureBuilder<List<OpenImage>>(
                      future: _results,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return _errorBox(context, snap.error!, _search);
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final items = snap.data!;
                        if (items.isEmpty) {
                          return const Center(
                            child: Text('Nenhuma imagem encontrada.'),
                          );
                        }
                        return GridView.builder(
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 150,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                              ),
                          itemCount: items.length,
                          itemBuilder: (_, i) {
                            final img = items[i];
                            return Tooltip(
                              message: img.credit,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => Navigator.pop(context, img),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.network(
                                    img.thumbnail,
                                    fit: BoxFit.cover,
                                    loadingBuilder: (_, child, p) => p == null
                                        ? child
                                        : const Center(
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                    errorBuilder: (_, _, _) =>
                                        const Icon(Icons.broken_image_outlined),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Fonte: Openverse (Creative Commons Catalog). O crédito da imagem é salvo como link no tópico.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

// =====================================================================
// Tema gerado a partir de uma cor (The Color API)
// =====================================================================

Future<void> showColorThemeDialog(
  BuildContext context,
  EditorController editor,
) async {
  final colors = await showDialog<List<String>>(
    context: context,
    builder: (_) =>
        _ColorThemeDialog(start: editor.doc.root.fillColor ?? '#3B4CF5'),
  );
  if (colors == null || colors.isEmpty) return;
  editor.applyCustomPalette(colors);
  if (context.mounted) showSnack(context, 'Tema personalizado aplicado.');
}

class _ColorThemeDialog extends StatefulWidget {
  const _ColorThemeDialog({required this.start});
  final String start;

  @override
  State<_ColorThemeDialog> createState() => _ColorThemeDialogState();
}

class _ColorThemeDialogState extends State<_ColorThemeDialog> {
  late String _base = widget.start.toUpperCase();
  late final _hex = TextEditingController(text: _base);
  String _mode = 'analogic';
  Future<List<String>>? _result;

  static const _suggestions = [
    '#3B4CF5',
    '#00AEEF',
    '#8A2BFF',
    '#E53935',
    '#FB8C00',
    '#FDD835',
    '#43A047',
    '#00897B',
    '#D81B60',
    '#6D4C41',
    '#455A64',
    '#212121',
  ];

  @override
  void initState() {
    super.initState();
    _generate();
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _generate() {
    final hex = _hex.text.trim().toUpperCase();
    if (!RegExp(r'^#?[0-9A-F]{6}$').hasMatch(hex)) return;
    _base = hex.startsWith('#') ? hex : '#$hex';
    setState(() => _result = webApis.colorScheme(_base, mode: _mode, count: 6));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.palette_outlined),
          SizedBox(width: 10),
          Text('Gerar tema a partir de uma cor'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in _suggestions)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      _hex.text = c;
                      _generate();
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: parseHex(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _base == c ? cs.onSurface : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _hex,
                    onSubmitted: (_) => _generate(),
                    decoration: InputDecoration(
                      labelText: 'Cor base (hexadecimal)',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircleAvatar(
                          radius: 8,
                          backgroundColor: parseHex(_base),
                        ),
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _mode,
                  onChanged: (v) {
                    if (v == null) return;
                    _mode = v;
                    _generate();
                  },
                  items: [
                    for (final e in WebApis.colorModes.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 64,
              child: FutureBuilder<List<String>>(
                future: _result,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      '${snap.error}',
                      style: TextStyle(color: cs.error),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return Row(
                    children: [
                      for (final c in snap.data!)
                        Expanded(
                          child: Tooltip(
                            message: c,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                color: parseHex(c),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Fonte: The Color API. A primeira cor vai para a ideia principal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () async {
            final colors = await _result;
            if (context.mounted) Navigator.pop(context, colors);
          },
          child: const Text('Aplicar tema'),
        ),
      ],
    );
  }
}
