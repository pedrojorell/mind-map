import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'editor_controller.dart';
import 'file_actions.dart';
import 'io/file_io.dart';
import 'models.dart';

const kImageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

/// Imagens maiores que isto são reduzidas antes de entrar no mapa.
const _maxImageBytes = 350 * 1024;
const _maxImageSide = 900;

/// Documentos até este tamanho são embutidos no mapa (no navegador, sempre
/// que possível, pois lá não existe caminho de arquivo).
const kMaxEmbeddedBytes = 2 * 1024 * 1024;

bool isImageName(String name) {
  final i = name.lastIndexOf('.');
  return i >= 0 &&
      kImageExtensions.contains(name.substring(i + 1).toLowerCase());
}

String formatBytes(int? n) {
  if (n == null) return '';
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
  return '${(n / 1024 / 1024).toStringAsFixed(1)} MB';
}

// --------------------------------------------------------------- imagens

final _decoded = <String, Uint8List>{};

/// Bytes de uma imagem em base64 (com cache para não decodificar a cada quadro).
Uint8List imageBytes(String data) {
  final hit = _decoded[data];
  if (hit != null) return hit;
  if (_decoded.length > 80) _decoded.remove(_decoded.keys.first);
  return _decoded[data] = base64Decode(data);
}

/// Prepara uma imagem para o mapa: reduz fotos grandes e guarda em base64.
Future<NodeImage?> prepareImage(Uint8List bytes, String name) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final w = desc.width, h = desc.height;
    var out = bytes;
    if (bytes.length > _maxImageBytes || math.max(w, h) > _maxImageSide * 2) {
      final scale = math.min(1.0, _maxImageSide / math.max(w, h));
      final codec = await desc.instantiateCodec(
        targetWidth: math.max(1, (w * scale).round()),
        targetHeight: math.max(1, (h * scale).round()),
      );
      final frame = await codec.getNextFrame();
      final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (png != null) out = png.buffer.asUint8List();
    }
    desc.dispose();
    buffer.dispose();
    final display = math.min(240.0, w.toDouble()).clamp(60.0, 240.0);
    return NodeImage(data: base64Encode(out), name: name, width: display);
  } catch (_) {
    return null;
  }
}

/// Abre o seletor e devolve uma imagem pronta (ou null).
Future<NodeImage?> pickImage(BuildContext context) async {
  try {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Escolha uma imagem',
    );
    final f = r?.files.firstOrNull;
    if (f == null) return null;
    final bytes =
        f.bytes ??
        (f.path != null ? Uint8List.fromList(await readBytes(f.path!)) : null);
    if (bytes == null) return null;
    final img = await prepareImage(bytes, f.name);
    if (img == null && context.mounted) {
      showSnack(context, 'Não foi possível ler a imagem “${f.name}”.');
    }
    return img;
  } catch (e) {
    if (context.mounted) showSnack(context, 'Erro ao abrir imagem: $e');
    return null;
  }
}

// ------------------------------------------------------------- documentos

/// Cria um anexo a partir de um arquivo. No desktop guarda o caminho e, se o
/// arquivo for pequeno e [embed] estiver ligado, também o conteúdo.
Future<NodeAttachment?> attachmentFrom({
  required String name,
  String? path,
  Uint8List? bytes,
  int? size,
  bool embed = false,
}) async {
  final hasPath = canUseFilePaths && path != null && path.isNotEmpty;
  final length = size ?? bytes?.length;
  final shouldEmbed =
      bytes != null && bytes.length <= kMaxEmbeddedBytes && (embed || !hasPath);
  if (!hasPath && !shouldEmbed) return null;
  return NodeAttachment(
    name: name,
    path: hasPath ? path : '',
    data: shouldEmbed ? base64Encode(bytes) : null,
    size: length,
  );
}

/// Abre o seletor de documentos e anexa ao tópico [nodeId].
Future<void> pickDocuments(
  BuildContext context,
  EditorController editor,
  String nodeId, {
  bool embed = false,
}) async {
  try {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: !canUseFilePaths || embed,
      dialogTitle: 'Escolha documentos para anexar',
    );
    if (r == null) return;
    final atts = <NodeAttachment>[];
    var skipped = 0;
    for (final f in r.files) {
      final a = await attachmentFrom(
        name: f.name,
        path: f.path,
        bytes: f.bytes,
        size: f.size,
        embed: embed,
      );
      if (a == null) {
        skipped++;
      } else {
        atts.add(a);
      }
    }
    if (atts.isNotEmpty) {
      editor.updateNode(
        nodeId,
        (n) => n.attachments.addAll(atts),
        relayout: true,
      );
    }
    if (skipped > 0 && context.mounted) {
      showSnack(
        context,
        '$skipped arquivo(s) grande(s) demais para guardar no navegador (máx. ${formatBytes(kMaxEmbeddedBytes)}).',
      );
    }
  } catch (e) {
    if (context.mounted) showSnack(context, 'Erro ao anexar: $e');
  }
}

/// Abre um anexo: pelo caminho no desktop ou baixando a cópia embutida.
Future<void> openAttachment(BuildContext context, NodeAttachment a) async {
  if (a.path.isNotEmpty && canUseFilePaths && await fileExists(a.path)) {
    final ok = await launchUrl(Uri.file(a.path)).catchError((_) => false);
    if (ok) return;
  }
  if (a.embedded) {
    final dot = a.name.lastIndexOf('.');
    final base = dot > 0 ? a.name.substring(0, dot) : a.name;
    final r = await saveBytesAs(
      fileName: base,
      ext: a.extension.isEmpty ? 'bin' : a.extension,
      bytes: base64Decode(a.data!),
      dialogTitle: 'Salvar anexo',
    );
    if (r.ok && r.path != null && canUseFilePaths) {
      await launchUrl(Uri.file(r.path!)).catchError((_) => false);
    }
    return;
  }
  if (context.mounted) {
    showSnack(context, 'Arquivo não encontrado: ${a.path}');
  }
}

Future<void> openNodeLink(BuildContext context, NodeLink l) async {
  final u = l.resolved;
  final ok = await launchUrl(
    Uri.parse(u),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!ok && context.mounted) showSnack(context, 'Não foi possível abrir $u');
}

IconData linkIcon(String kind) => switch (kind) {
  'email' => Icons.alternate_email,
  'phone' => Icons.call_outlined,
  'file' => Icons.folder_open_outlined,
  _ => Icons.public,
};

(IconData, Color) fileIcon(String ext) {
  switch (ext) {
    case 'pdf':
      return (Icons.picture_as_pdf_outlined, const Color(0xFFE53935));
    case 'doc':
    case 'docx':
    case 'odt':
    case 'rtf':
      return (Icons.description_outlined, const Color(0xFF1E6FD9));
    case 'xls':
    case 'xlsx':
    case 'csv':
    case 'ods':
      return (Icons.table_chart_outlined, const Color(0xFF1E8E3E));
    case 'ppt':
    case 'pptx':
    case 'odp':
      return (Icons.slideshow_outlined, const Color(0xFFE8710A));
    case 'zip':
    case 'rar':
    case '7z':
      return (Icons.folder_zip_outlined, const Color(0xFF8D6E63));
    case 'mp3':
    case 'wav':
    case 'ogg':
      return (Icons.audiotrack_outlined, const Color(0xFF8E24AA));
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
      return (Icons.movie_outlined, const Color(0xFFD81B60));
    case 'txt':
    case 'md':
      return (Icons.article_outlined, const Color(0xFF607D8B));
    default:
      if (kImageExtensions.contains(ext)) {
        return (Icons.image_outlined, const Color(0xFF00897B));
      }
      return (Icons.insert_drive_file_outlined, const Color(0xFF757575));
  }
}

// ------------------------------------------------------- arrastar e soltar

/// Recebe arquivos soltos no mapa. Imagens viram a imagem do tópico (a
/// primeira) ou novos subtópicos; os demais arquivos viram anexos. Sem um
/// tópico alvo, cria um tópico flutuante em [scenePos].
Future<void> handleDroppedFiles(
  BuildContext context,
  EditorController editor,
  List<XFile> files, {
  String? nodeId,
  Offset? scenePos,
}) async {
  if (files.isEmpty) return;
  var target = nodeId;
  if (target == null) {
    final first = files.first.name;
    target = editor.addFloating(
      scenePos ?? Offset.zero,
      text: first,
      edit: false,
    );
  }
  final atts = <NodeAttachment>[];
  var images = 0;
  for (final f in files) {
    Uint8List? bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (_) {
      continue; // pastas e itens sem conteúdo
    }
    if (isImageName(f.name)) {
      final img = await prepareImage(bytes, f.name);
      if (img == null) continue;
      final node = editor.doc.nodes[target];
      if (node == null) return;
      if (node.image == null && images == 0) {
        editor.updateNode(target, (n) => n.image = img, relayout: true);
      } else {
        final child = editor.addChildWith(
          target,
          text: _stripExt(f.name),
          edit: false,
        );
        if (child != null) {
          editor.updateNode(child, (n) => n.image = img, relayout: true);
        }
      }
      images++;
    } else {
      final a = await attachmentFrom(
        name: f.name,
        path: f.path,
        bytes: bytes,
        size: bytes.length,
      );
      if (a != null) atts.add(a);
    }
  }
  if (atts.isNotEmpty) {
    editor.updateNode(
      target,
      (n) => n.attachments.addAll(atts),
      relayout: true,
    );
  }
  editor.select(target);
  if (context.mounted) {
    final parts = [
      if (images > 0) '$images imagem(ns)',
      if (atts.isNotEmpty) '${atts.length} documento(s)',
    ];
    if (parts.isNotEmpty) {
      showSnack(context, 'Adicionado: ${parts.join(' e ')}.');
    }
  }
}

String _stripExt(String name) {
  final i = name.lastIndexOf('.');
  return i > 0 ? name.substring(0, i) : name;
}
