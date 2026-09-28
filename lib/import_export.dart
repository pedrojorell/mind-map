import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import 'file_actions.dart';
import 'io/file_io.dart';
import 'layout.dart';
import 'library.dart';
import 'models.dart';
import 'templates.dart';

// =====================================================================
// Exportação
// =====================================================================

/// Formatos de exportação: extensão, nome e descrição.
const kExportFormats = <String, (String, String)>{
  'pdf': ('PDF', 'Imagem do mapa + tópicos em texto'),
  'doc': ('Word (.doc)', 'Documento com títulos, anotações e links'),
  'csv': ('Excel / planilha (.csv)', 'Uma linha por tópico, com tarefas'),
  'html': ('Página web (.html)', 'Lista navegável com imagens'),
  'md': ('Markdown (.md)', 'Tópicos em Markdown'),
  'txt': ('Texto (.txt)', 'Tópicos recuados'),
  'opml': ('OPML (.opml)', 'Para outros apps de tópicos'),
  'mm': ('FreeMind (.mm)', 'Compatível com FreeMind/Freeplane/XMind'),
};

List<(MindMapNode, int)> _walk(MindMapDoc doc) {
  final out = <(MindMapNode, int)>[];
  void walk(String id, int depth) {
    final n = doc.nodes[id];
    if (n == null) return;
    out.add((n, depth));
    for (final c in n.childrenIds) {
      walk(c, depth + 1);
    }
  }

  walk(doc.rootId, 0);
  for (final n in doc.nodes.values) {
    if (n.parentId == null && n.id != doc.rootId) walk(n.id, 1);
  }
  return out;
}

String _one(String s) => s.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();

String _esc(String s) => const HtmlEscape().convert(s);

String _date(int? ms) {
  if (ms == null) return '';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

String toPlainText(MindMapDoc doc) {
  final b = StringBuffer();
  for (final (n, d) in _walk(doc)) {
    b.writeln('${'\t' * d}${_one(n.text)}');
  }
  return b.toString();
}

String toCsv(MindMapDoc doc) {
  String cell(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer('﻿'); // BOM para o Excel reconhecer acentos
  b.writeln(
    [
      'Nível',
      'Número',
      'Tópico',
      'Tópico pai',
      'Anotação',
      'Links',
      'Etiquetas',
      'Início',
      'Fim',
      'Progresso (%)',
      'Responsável',
      'Documentos',
    ].map(cell).join(';'),
  );
  for (final (n, d) in _walk(doc)) {
    final parent = n.parentId == null
        ? ''
        : _one(doc.nodes[n.parentId]?.text ?? '');
    b.writeln(
      [
        '$d',
        doc.numberOf(n.id),
        _one(n.text),
        parent,
        n.note.trim(),
        n.links.map((l) => l.resolved).join(' | '),
        n.tags.join(', '),
        _date(n.task?.start),
        _date(n.task?.end),
        n.task == null ? '' : '${n.task!.progress}',
        n.task?.assignee ?? '',
        n.attachments.map((a) => a.name).join(', '),
      ].map(cell).join(';'),
    );
  }
  return b.toString();
}

String toHtml(MindMapDoc doc, {bool forWord = false}) {
  final b = StringBuffer()
    ..writeln('<!DOCTYPE html><html lang="pt-BR"><head><meta charset="utf-8">')
    ..writeln('<title>${_esc(doc.name)}</title>')
    ..writeln(
      '<style>body{font-family:Segoe UI,Arial,sans-serif;max-width:900px;margin:32px auto;padding:0 16px;color:#222;line-height:1.5}'
      'h1{color:#5B3FD9}li{margin:4px 0}.note{color:#555;font-size:.92em;white-space:pre-wrap;border-left:3px solid #ddd;padding-left:8px;margin:4px 0}'
      '.tag{display:inline-block;background:#EEE8FF;color:#4A32B0;border-radius:10px;padding:0 8px;font-size:.8em;margin-left:6px}'
      '.task{color:#2E7D32;font-size:.85em;margin-left:6px}img{max-width:320px;border-radius:8px;display:block;margin:6px 0}'
      'table{border-collapse:collapse;margin:6px 0}td{border:1px solid #bbb;padding:3px 8px}</style></head><body>',
    );
  void node(String id, int depth) {
    final n = doc.nodes[id]!;
    final num = doc.numbering ? '${doc.numberOf(id)} ' : '';
    b.write('<li><strong>${_esc(num + n.text)}</strong>');
    for (final t in n.tags) {
      b.write('<span class="tag">${_esc(t)}</span>');
    }
    if (n.task != null) {
      b.write(
        '<span class="task">☐ ${n.task!.progress}% ${_date(n.task!.start)} – ${_date(n.task!.end)} ${_esc(n.task!.assignee)}</span>',
      );
    }
    if (n.image != null && !forWord) {
      b.write(
        '<img alt="${_esc(n.image!.name)}" src="data:image/png;base64,${n.image!.data}">',
      );
    }
    for (final l in n.links) {
      b.write(
        '<div>🔗 <a href="${_esc(l.resolved)}">${_esc(l.label)}</a></div>',
      );
    }
    for (final a in n.attachments) {
      b.write('<div>📎 ${_esc(a.name)}</div>');
    }
    if (n.note.trim().isNotEmpty) {
      b.write('<div class="note">${_esc(n.note.trim())}</div>');
    }
    if (n.table != null) {
      b.write('<table>');
      for (final r in n.table!) {
        b.write('<tr>${r.map((c) => '<td>${_esc(c)}</td>').join()}</tr>');
      }
      b.write('</table>');
    }
    if (n.childrenIds.isNotEmpty) {
      b.write('<ul>');
      for (final c in n.childrenIds) {
        node(c, depth + 1);
      }
      b.write('</ul>');
    }
    b.writeln('</li>');
  }

  b.writeln('<h1>${_esc(doc.root.text)}</h1>');
  if (doc.root.note.trim().isNotEmpty) {
    b.writeln('<div class="note">${_esc(doc.root.note.trim())}</div>');
  }
  b.writeln('<ul>');
  for (final c in doc.root.childrenIds) {
    node(c, 1);
  }
  for (final n in doc.nodes.values) {
    if (n.parentId == null && n.id != doc.rootId) node(n.id, 1);
  }
  b.writeln('</ul></body></html>');
  return b.toString();
}

String toOpml(MindMapDoc doc) {
  final x = XmlBuilder();
  x.processing('xml', 'version="1.0" encoding="UTF-8"');
  x.element(
    'opml',
    attributes: {'version': '2.0'},
    nest: () {
      x.element('head', nest: () => x.element('title', nest: doc.name));
      x.element(
        'body',
        nest: () {
          void node(String id) {
            final n = doc.nodes[id]!;
            x.element(
              'outline',
              attributes: {
                'text': _one(n.text),
                if (n.note.trim().isNotEmpty) '_note': n.note.trim(),
                if (n.hasLink) 'url': n.links.first.resolved,
              },
              nest: () {
                for (final c in n.childrenIds) {
                  node(c);
                }
              },
            );
          }

          node(doc.rootId);
        },
      );
    },
  );
  return x.buildDocument().toXmlString(pretty: true);
}

String toFreeMind(MindMapDoc doc) {
  final x = XmlBuilder();
  x.element(
    'map',
    attributes: {'version': '1.0.1'},
    nest: () {
      void node(String id, bool top) {
        final n = doc.nodes[id]!;
        x.element(
          'node',
          attributes: {
            'ID': 'ID_${id.hashCode.abs()}',
            'TEXT': n.text,
            if (n.hasLink) 'LINK': n.links.first.resolved,
            if (top && n.parentId == doc.rootId)
              'POSITION': n.pos.dx >= doc.root.pos.dx ? 'right' : 'left',
            'COLOR': n.color.toLowerCase(),
          },
          nest: () {
            if (n.note.trim().isNotEmpty) {
              x.element(
                'richcontent',
                attributes: {'TYPE': 'NOTE'},
                nest: () {
                  x.element(
                    'html',
                    nest: () {
                      x.element(
                        'body',
                        nest: () => x.element('p', nest: n.note.trim()),
                      );
                    },
                  );
                },
              );
            }
            for (final c in n.childrenIds) {
              node(c, true);
            }
          },
        );
      }

      node(doc.rootId, true);
    },
  );
  return x.buildDocument().toXmlString(pretty: true);
}

/// Remove caracteres que as fontes padrão do PDF não conseguem desenhar.
String _pdfSafe(String s) =>
    String.fromCharCodes(s.runes.where((r) => r < 0x100 || r == 0x2022));

Future<Uint8List> toPdf(MindMapDoc doc, Uint8List? png) async {
  final pdf = pw.Document(title: doc.name, creator: 'MapLong');
  if (png != null) {
    final img = pw.MemoryImage(png);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          children: [
            pw.Text(
              _pdfSafe(doc.name),
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 10),
            pw.Expanded(
              child: pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
            ),
          ],
        ),
      ),
    );
  }
  final items = _walk(doc);
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Header(level: 0, text: _pdfSafe(_one(doc.root.text))),
        for (final (n, d) in items.skip(1)) ...[
          pw.Padding(
            padding: pw.EdgeInsets.only(
              left: (d - 1) * 16.0,
              top: d == 1 ? 8 : 2,
            ),
            child: pw.Text(
              _pdfSafe(
                '${d == 1 ? '' : '• '}${doc.numbering ? '${doc.numberOf(n.id)} ' : ''}${_one(n.text)}'
                '${n.tags.isEmpty ? '' : '  [${n.tags.join(', ')}]'}',
              ),
              style: pw.TextStyle(
                fontSize: d == 1 ? 13 : 11,
                fontWeight: d == 1 ? pw.FontWeight.bold : pw.FontWeight.normal,
              ),
            ),
          ),
          if (n.note.trim().isNotEmpty)
            pw.Padding(
              padding: pw.EdgeInsets.only(left: d * 16.0, top: 1),
              child: pw.Text(
                _pdfSafe(n.note.trim()),
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          for (final l in n.links)
            pw.Padding(
              padding: pw.EdgeInsets.only(left: d * 16.0),
              child: pw.UrlLink(
                destination: l.resolved,
                child: pw.Text(
                  _pdfSafe(l.label),
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.blue700,
                  ),
                ),
              ),
            ),
        ],
      ],
    ),
  );
  return pdf.save();
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

/// Exporta [doc] no formato [ext] (ver [kExportFormats]).
Future<void> exportAs(
  BuildContext context,
  MindMapDoc doc,
  String ext,
  Future<Uint8List?> Function() capturePng,
) async {
  try {
    final Uint8List bytes = switch (ext) {
      'pdf' => await toPdf(doc, await capturePng()),
      // O Word abre páginas HTML salvas com a extensão .doc.
      'doc' => _utf8(toHtml(doc, forWord: true)),
      'csv' => _utf8(toCsv(doc)),
      'html' => _utf8(toHtml(doc)),
      'md' => _utf8(toMarkdown(doc)),
      'txt' => _utf8(toPlainText(doc)),
      'opml' => _utf8(toOpml(doc)),
      'mm' => _utf8(toFreeMind(doc)),
      _ => throw ArgumentError('Formato desconhecido: $ext'),
    };
    final r = await saveBytesAs(
      fileName: doc.name,
      ext: ext,
      bytes: bytes,
      dialogTitle: 'Exportar ${kExportFormats[ext]?.$1 ?? ext}',
    );
    if (r.ok && context.mounted) {
      showSnack(
        context,
        r.path == null ? 'Arquivo baixado.' : 'Exportado: ${r.path}',
      );
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Erro ao exportar: $e');
  }
}

// =====================================================================
// Importação
// =====================================================================

/// Converte Markdown (títulos e listas) em texto recuado.
String markdownToOutline(String md) {
  final out = StringBuffer();
  var heading = 0;
  for (final raw in md.split(RegExp(r'\r?\n'))) {
    final line = raw.replaceAll('\t', '    ');
    final h = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line.trim());
    if (h != null) {
      heading = h.group(1)!.length;
      out.writeln('${'  ' * (heading - 1)}${h.group(2)}');
      continue;
    }
    final b = RegExp(r'^(\s*)([-*+]|\d+[.)])\s+(.*)$').firstMatch(line);
    if (b != null) {
      final indent = b.group(1)!.length ~/ 2;
      out.writeln('${'  ' * (heading + indent)}${b.group(3)}');
    } else if (line.trim().isNotEmpty && heading > 0) {
      out.writeln('${'  ' * heading}${line.trim()}');
    }
  }
  return out.toString();
}

MindMapDoc _fromXmlTree(
  String name,
  XmlElement root,
  String tag,
  String Function(XmlElement) text,
  String? Function(XmlElement) note,
) {
  final doc = MindMapDoc.blank(name: name, withTopics: false);
  doc.root.text = text(root).isEmpty ? name : text(root);
  doc.root.note = note(root) ?? '';
  void walk(XmlElement el, MindMapNode parent) {
    for (final c in el.childElements.where((e) => e.name.local == tag)) {
      final isRootChild = parent.id == doc.rootId;
      final n = MindMapNode(
        id: newId(),
        text: text(c).isEmpty ? '(sem título)' : text(c),
        note: note(c) ?? '',
        parentId: parent.id,
        color: isRootChild
            ? doc.branchColor(parent.childrenIds.length)
            : parent.color,
        fontSize: isRootChild ? 17 : 15,
        shape: isRootChild ? 'pill' : 'underline',
      );
      final link = c.getAttribute('url') ?? c.getAttribute('LINK');
      if (link != null && link.isNotEmpty) n.links.add(NodeLink(url: link));
      doc.nodes[n.id] = n;
      parent.childrenIds.add(n.id);
      walk(c, n);
    }
  }

  walk(root, doc.root);
  return doc;
}

MindMapDoc opmlToDoc(String name, String xml) {
  final d = XmlDocument.parse(xml);
  final body = d.findAllElements('body').first;
  final tops = body.childElements
      .where((e) => e.name.local == 'outline')
      .toList();
  // Um único item no topo vira a ideia principal; vários viram ramos.
  if (tops.length == 1) {
    return _fromXmlTree(
      name,
      tops.single,
      'outline',
      (e) => e.getAttribute('text') ?? e.getAttribute('title') ?? '',
      (e) => e.getAttribute('_note'),
    );
  }
  final wrapper = XmlElement(XmlName('outline'), [
    XmlAttribute(XmlName('text'), name),
  ], tops.map((e) => e.copy()));
  return _fromXmlTree(
    name,
    wrapper,
    'outline',
    (e) => e.getAttribute('text') ?? e.getAttribute('title') ?? '',
    (e) => e.getAttribute('_note'),
  );
}

MindMapDoc freeMindToDoc(String name, String xml) {
  final d = XmlDocument.parse(xml);
  final root = d.rootElement.childElements.firstWhere(
    (e) => e.name.local == 'node',
  );
  String text(XmlElement e) {
    final t = e.getAttribute('TEXT');
    if (t != null) return t;
    final rich = e.childElements.where(
      (c) => c.name.local == 'richcontent' && c.getAttribute('TYPE') != 'NOTE',
    );
    return rich.isEmpty ? '' : rich.first.innerText.trim();
  }

  String? note(XmlElement e) {
    final rich = e.childElements.where(
      (c) => c.name.local == 'richcontent' && c.getAttribute('TYPE') == 'NOTE',
    );
    return rich.isEmpty ? null : rich.first.innerText.trim();
  }

  return _fromXmlTree(name, root, 'node', text, note);
}

/// Formatos aceitos em "Abrir / importar".
const kImportExtensions = [
  kFileExtension,
  kLegacyFileExtension,
  'json',
  'md',
  'markdown',
  'txt',
  'opml',
  'mm',
];

/// Abre um arquivo do MapLong ou importa de outro formato.
Future<MindMapDoc?> importFromFile(
  BuildContext context,
  Library library,
) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Abrir ou importar mapa',
      type: FileType.custom,
      allowedExtensions: kImportExtensions,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    List<int>? bytes = f.bytes;
    final path = canUseFilePaths ? f.path : null;
    if (bytes == null && path != null) bytes = await readBytes(path);
    if (bytes == null) throw const FormatException('Arquivo vazio.');
    final text = utf8.decode(bytes, allowMalformed: true);
    final dot = f.name.lastIndexOf('.');
    final ext = dot < 0 ? '' : f.name.substring(dot + 1).toLowerCase();
    final base = dot < 0 ? f.name : f.name.substring(0, dot);
    final name = library.uniqueName(base);

    MindMapDoc doc;
    switch (ext) {
      case kFileExtension:
      case kLegacyFileExtension:
      case 'json':
        final json = jsonDecode(text);
        if (json is! Map<String, dynamic>) {
          throw const FormatException('Não é um arquivo do MapLong.');
        }
        doc = MindMapDoc.fromJson(json)..filePath = path;
        return library.importDoc(doc);
      case 'md':
      case 'markdown':
        doc = docFromOutline(name, markdownToOutline(text));
      case 'opml':
        doc = opmlToDoc(name, text);
      case 'mm':
        doc = freeMindToDoc(name, text);
      default:
        doc = docFromOutline(name, text);
    }
    doc.name = name;
    doc.autoLayout = true;
    autoLayout(doc, const {});
    library.add(doc);
    if (context.mounted) showSnack(context, 'Importado de ${f.name}.');
    return doc;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Não foi possível abrir: $e');
    return null;
  }
}
