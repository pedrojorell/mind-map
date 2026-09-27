import 'dart:math';
import 'dart:ui';

import 'models.dart';

const double kHGap = 64;
const double kVGap = 18;

/// Estimativa do tamanho de um nó quando ainda não foi medido na tela.
Size estimateNodeSize(MindMapNode n) {
  final lines = n.text.split('\n');
  final longest = lines.fold<int>(0, (m, l) => max(m, l.length));
  final w = (longest * n.fontSize * 0.58 + 36).clamp(60.0, 320.0);
  final h = lines.length * n.fontSize * 1.35 + 22;
  return Size(w, h);
}

/// Organiza o mapa em árvore balanceada (metade dos ramos à direita e metade
/// à esquerda da ideia principal). A raiz mantém sua posição.
void autoLayout(MindMapDoc doc, Map<String, Size> sizes) {
  Size sizeOf(String id) => sizes[id] ?? estimateNodeSize(doc.nodes[id]!);

  List<String> kids(String id) {
    final n = doc.nodes[id]!;
    return n.collapsed ? const [] : n.childrenIds;
  }

  final heights = <String, double>{};
  double subtreeHeight(String id) {
    final cached = heights[id];
    if (cached != null) return cached;
    final own = sizeOf(id).height;
    final c = kids(id);
    var h = own;
    if (c.isNotEmpty) {
      final sum = c.fold<double>(0, (s, k) => s + subtreeHeight(k)) +
          kVGap * (c.length - 1);
      h = max(own, sum);
    }
    heights[id] = h;
    return h;
  }

  void place(String parentId, List<String> children, int dir) {
    if (children.isEmpty) return;
    final parent = doc.nodes[parentId]!;
    final pw = sizeOf(parentId).width;
    final total = children.fold<double>(0, (s, k) => s + subtreeHeight(k)) +
        kVGap * (children.length - 1);
    var y = parent.pos.dy - total / 2;
    for (final id in children) {
      final h = subtreeHeight(id);
      final cw = sizeOf(id).width;
      final n = doc.nodes[id]!;
      n.pos = Offset(parent.pos.dx + dir * (pw / 2 + kHGap + cw / 2), y + h / 2);
      place(id, kids(id), dir);
      y += h + kVGap;
    }
  }

  final root = doc.root;
  final rootKids = kids(root.id);
  final rightCount = (rootKids.length / 2).ceil();
  place(root.id, rootKids.sublist(0, rightCount), 1);
  // Lado esquerdo em ordem invertida para seguir o sentido horário.
  place(root.id, rootKids.sublist(rightCount).reversed.toList(), -1);

  // Tópicos flutuantes organizam apenas seus próprios filhos.
  for (final n in doc.nodes.values) {
    if (n.parentId == null && n.id != doc.rootId) {
      place(n.id, kids(n.id), 1);
    }
  }
}

/// Lado (1 direita, -1 esquerda) em que um nó fica em relação ao pai.
int sideOf(MindMapDoc doc, MindMapNode n) {
  final p = n.parentId == null ? null : doc.nodes[n.parentId];
  if (p == null) return 1;
  return n.pos.dx >= p.pos.dx ? 1 : -1;
}
