import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'editor_controller.dart';
import 'io/file_io.dart';
import 'library.dart';
import 'models.dart';

const kFileExtension = 'pmap';

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      width: 420,
      duration: const Duration(seconds: 3),
    ));
}

String safeFileName(String name) {
  final s = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_');
  return s.isEmpty ? 'mapa' : s;
}

String _ensureExt(String path, String ext) =>
    path.toLowerCase().endsWith('.$ext') ? path : '$path.$ext';

/// Mostra o diálogo "Salvar como" e grava os bytes.
/// Retorna o caminho gravado (desktop) ou null (cancelado / navegador).
/// [ok] indica se algo foi salvo/baixado.
Future<({bool ok, String? path})> saveBytesAs({
  required String fileName,
  required String ext,
  required Uint8List bytes,
  String dialogTitle = 'Salvar como',
}) async {
  final result = await FilePicker.platform.saveFile(
    dialogTitle: dialogTitle,
    fileName: '${safeFileName(fileName)}.$ext',
    type: FileType.custom,
    allowedExtensions: [ext],
    bytes: bytes,
  );
  if (!canUseFilePaths) {
    // No navegador o arquivo é baixado pelo próprio file_picker.
    return (ok: true, path: null);
  }
  if (result == null) return (ok: false, path: null);
  final path = _ensureExt(result, ext);
  await writeBytes(path, bytes);
  return (ok: true, path: path);
}

Uint8List encodeDoc(MindMapDoc doc) {
  final j = doc.toJson()..remove('filePath');
  return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(j)));
}

/// Ctrl+S: grava no arquivo já associado ou pergunta onde salvar.
Future<void> saveToFile(BuildContext context, EditorController editor,
    {bool saveAs = false}) async {
  final doc = editor.doc;
  await editor.library.saveNow(doc);
  try {
    final bytes = encodeDoc(doc);
    final path = doc.filePath;
    if (!saveAs && path != null && canUseFilePaths) {
      await writeBytes(path, bytes);
      editor.markSavedToFile(path);
      if (context.mounted) showSnack(context, 'Salvo em $path');
      return;
    }
    final r = await saveBytesAs(
      fileName: doc.name,
      ext: kFileExtension,
      bytes: bytes,
      dialogTitle: 'Salvar mapa mental',
    );
    if (!r.ok) return;
    editor.markSavedToFile(r.path);
    if (context.mounted) {
      showSnack(context,
          r.path == null ? 'Arquivo baixado.' : 'Salvo em ${r.path}');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Erro ao salvar: $e');
  }
}

/// Abre um arquivo .pmap (ou .json) e adiciona à biblioteca.
Future<MindMapDoc?> openFromFile(BuildContext context, Library library) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Abrir mapa mental',
      type: FileType.custom,
      allowedExtensions: const [kFileExtension, 'json'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.single;
    List<int>? bytes = f.bytes;
    String? path;
    if (canUseFilePaths) path = f.path;
    if (bytes == null && path != null) bytes = await readBytes(path);
    if (bytes == null) throw const FormatException('Arquivo vazio.');
    final json = jsonDecode(utf8.decode(bytes));
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Não é um arquivo do PinealMap.');
    }
    final doc = MindMapDoc.fromJson(json)..filePath = path;
    return library.importDoc(doc);
  } catch (e) {
    if (context.mounted) showSnack(context, 'Não foi possível abrir: $e');
    return null;
  }
}

/// Converte o mapa em tópicos Markdown.
String toMarkdown(MindMapDoc doc) {
  final b = StringBuffer('# ${doc.root.text.replaceAll('\n', ' ')}\n\n');
  void walk(String id, int depth) {
    final n = doc.nodes[id]!;
    final text = n.text.replaceAll('\n', ' ');
    final label = n.hasLink ? '[$text](${n.link})' : text;
    b.writeln('${'  ' * depth}- $label');
    if (n.note.trim().isNotEmpty) {
      for (final line in n.note.trim().split('\n')) {
        b.writeln('${'  ' * (depth + 1)}> $line');
      }
    }
    for (final c in n.childrenIds) {
      walk(c, depth + 1);
    }
  }

  for (final c in doc.root.childrenIds) {
    walk(c, 0);
  }
  final floating = doc.nodes.values
      .where((n) => n.parentId == null && n.id != doc.rootId)
      .toList();
  if (floating.isNotEmpty) {
    b.writeln('\n## Tópicos flutuantes\n');
    for (final f in floating) {
      walk(f.id, 0);
    }
  }
  return b.toString();
}

Future<void> exportMarkdown(BuildContext context, MindMapDoc doc) async {
  try {
    final r = await saveBytesAs(
      fileName: doc.name,
      ext: 'md',
      bytes: Uint8List.fromList(utf8.encode(toMarkdown(doc))),
      dialogTitle: 'Exportar como Markdown',
    );
    if (r.ok && context.mounted) {
      showSnack(context, r.path == null ? 'Markdown baixado.' : 'Exportado: ${r.path}');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Erro ao exportar: $e');
  }
}

Future<void> exportPng(
    BuildContext context, MindMapDoc doc, Future<Uint8List?> Function() capture) async {
  try {
    final bytes = await capture();
    if (bytes == null) throw StateError('falha ao gerar imagem');
    final r = await saveBytesAs(
      fileName: doc.name,
      ext: 'png',
      bytes: bytes,
      dialogTitle: 'Exportar imagem PNG',
    );
    if (r.ok && context.mounted) {
      showSnack(context, r.path == null ? 'Imagem baixada.' : 'Exportado: ${r.path}');
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Erro ao exportar: $e');
  }
}
