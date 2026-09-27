import 'dart:math';
import 'dart:ui';

import 'models.dart';

const double kHGap = 64;
const double kVGap = 18;

/// Estimativa do tamanho de um nó quando ainda não foi medido na tela.
Size estimateNodeSize(MindMapNode n) {
  final lines = n.text.split('\n');
  final longest = lines.fold<int>(0, (m, l) => max(m, l.length));
  var w = longest * n.fontSize * 0.58 + 36 + n.markers.length * 22;
  var h = lines.length * n.fontSize * 1.35 + 22;
  if (n.sticker != null) {
    h += 40;
    w = max(w, 70);
  }
  if (n.image != null) {
    // Altura aproximada (proporção 4:3) até a imagem ser medida na tela.
    h += n.image!.width * 0.75 + 8;
    w = max(w, n.image!.width + 32);
  }
  if (n.tags.isNotEmpty) h += 24;
  if (n.callouts.isNotEmpty) h += 34.0 * n.callouts.length;
  if (n.formula != null) h += 40;
  if (n.table != null) {
    h += 26.0 * n.table!.length + 8;
    w = max(w, 90.0 * (n.table!.firstOrNull?.length ?? 1));
  }
  if (n.task != null) h += 22;
  return Size(w.clamp(60.0, 560.0), h);
}

/// Como a linha entre [parent] e [child] é desenhada:
/// - `h`: horizontal (curva/reta/cotovelo conforme o estilo do mapa)
/// - `elbow`: sempre em cotovelo (mapa lógico)
/// - `v`: vertical, de baixo do pai para cima do filho (organograma)
/// - `tree`: árvore recuada (linha vertical saindo da esquerda do pai)
/// - `axis`: eixo horizontal da linha do tempo
/// - `bone` / `rib`: espinha de peixe
String edgeKind(MindMapDoc doc, MindMapNode parent, MindMapNode child) {
  final isRoot = parent.id == doc.rootId;
  switch (doc.layout) {
    case 'org':
      return 'v';
    case 'tree':
      return 'tree';
    case 'timeline':
      return isRoot ? 'axis' : 'tree';
    case 'fishbone':
      if (isRoot) return 'bone';
      if (parent.parentId == doc.rootId) return 'rib';
      return 'h';
    case 'logic':
      return 'elbow';
    default:
      return 'h';
  }
}

/// Posição do botão de recolher em relação ao nó ([size] = tamanho do nó).
/// Retorna o deslocamento a partir do centro.
Offset collapseToggleOffset(MindMapDoc doc, MindMapNode n, Size size) {
  final child = n.childrenIds.isEmpty ? null : doc.nodes[n.childrenIds.first];
  final kind = child == null ? 'h' : edgeKind(doc, n, child);
  final low = n.shape == 'underline' || n.shape == 'plain';
  switch (kind) {
    case 'v':
      return Offset(0, size.height / 2 + 11);
    case 'tree':
      return Offset(-size.width / 2 + 16, size.height / 2 + 11);
    case 'rib':
      return Offset(
        0,
        (child!.pos.dy > n.pos.dy ? 1 : -1) * (size.height / 2 + 11),
      );
    default:
      final side = sideOf(doc, n) * 1.0;
      return Offset(side * (size.width / 2 + 11), low ? size.height / 2 : 0);
  }
}

/// Organiza o mapa de acordo com a estrutura escolhida. A raiz mantém sua
/// posição; tópicos flutuantes organizam apenas os próprios filhos.
void autoLayout(MindMapDoc doc, Map<String, Size> sizes) {
  _Layout(doc, sizes).run();
}

class _Layout {
  _Layout(this.doc, this.sizes);

  final MindMapDoc doc;
  final Map<String, Size> sizes;

  late final double hGap = doc.hGap;
  late final double vGap = doc.vGap;

  Size sizeOf(String id) => sizes[id] ?? estimateNodeSize(doc.nodes[id]!);
  MindMapNode node(String id) => doc.nodes[id]!;

  List<String> kids(String id) {
    final n = doc.nodes[id]!;
    return n.collapsed ? const [] : n.childrenIds;
  }

  void run() {
    final root = doc.root;
    final rootKids = kids(root.id);
    switch (doc.layout) {
      case 'right':
      case 'logic':
        _horizontal(root.id, rootKids, 1);
      case 'left':
        _horizontal(root.id, rootKids, -1);
      case 'org':
        _vertical(root.id, 1);
      case 'tree':
        _tree(root.id, 1);
      case 'timeline':
        _timeline();
      case 'fishbone':
        _fishbone();
      default:
        final rightCount = (rootKids.length / 2).ceil();
        _horizontal(root.id, rootKids.sublist(0, rightCount), 1);
        // Lado esquerdo em ordem invertida para seguir o sentido horário.
        _horizontal(
          root.id,
          rootKids.sublist(rightCount).reversed.toList(),
          -1,
        );
    }

    for (final n in doc.nodes.values) {
      if (n.parentId == null && n.id != doc.rootId) {
        switch (doc.layout) {
          case 'org':
            _vertical(n.id, 1);
          case 'tree':
          case 'timeline':
            _tree(n.id, 1);
          default:
            _horizontal(n.id, kids(n.id), doc.layout == 'left' ? -1 : 1);
        }
      }
    }
  }

  // ------------------------------------------------------------ horizontal

  final _heights = <String, double>{};

  double _subtreeHeight(String id) {
    final cached = _heights[id];
    if (cached != null) return cached;
    final own = sizeOf(id).height;
    final c = kids(id);
    var h = own;
    if (c.isNotEmpty) {
      final sum =
          c.fold<double>(0, (s, k) => s + _subtreeHeight(k)) +
          vGap * (c.length - 1);
      h = max(own, sum);
    }
    return _heights[id] = h;
  }

  void _horizontal(String parentId, List<String> children, int dir) {
    if (children.isEmpty) return;
    final parent = node(parentId);
    final pw = sizeOf(parentId).width;
    final total =
        children.fold<double>(0, (s, k) => s + _subtreeHeight(k)) +
        vGap * (children.length - 1);
    var y = parent.pos.dy - total / 2;
    for (final id in children) {
      final h = _subtreeHeight(id);
      final cw = sizeOf(id).width;
      node(id).pos = Offset(
        parent.pos.dx + dir * (pw / 2 + hGap + cw / 2),
        y + h / 2,
      );
      _horizontal(id, kids(id), dir);
      y += h + vGap;
    }
  }

  // ------------------------------------------------------ vertical (organograma)

  final _widths = <String, double>{};
  double get _siblingGap => vGap + 14;
  double get _levelGap => max(36.0, hGap * 0.75);

  double _subtreeWidth(String id) {
    final cached = _widths[id];
    if (cached != null) return cached;
    final own = sizeOf(id).width;
    final c = kids(id);
    var w = own;
    if (c.isNotEmpty) {
      final sum =
          c.fold<double>(0, (s, k) => s + _subtreeWidth(k)) +
          _siblingGap * (c.length - 1);
      w = max(own, sum);
    }
    return _widths[id] = w;
  }

  /// Filhos abaixo ([dir] = 1) ou acima (-1) do pai, lado a lado.
  void _vertical(String parentId, int dir) {
    final children = kids(parentId);
    if (children.isEmpty) return;
    final parent = node(parentId);
    final ph = sizeOf(parentId).height;
    final total =
        children.fold<double>(0, (s, k) => s + _subtreeWidth(k)) +
        _siblingGap * (children.length - 1);
    var x = parent.pos.dx - total / 2;
    for (final id in children) {
      final w = _subtreeWidth(id);
      final ch = sizeOf(id).height;
      node(id).pos = Offset(
        x + w / 2,
        parent.pos.dy + dir * (ph / 2 + _levelGap + ch / 2),
      );
      _vertical(id, dir);
      x += w + _siblingGap;
    }
  }

  // ------------------------------------------------------- árvore recuada

  static const _indent = 34.0;

  /// Filhos empilhados abaixo ([dir] = 1) ou acima (-1) do pai, recuados.
  /// Retorna a coordenada y da borda mais distante usada.
  double _tree(String parentId, int dir) {
    final parent = node(parentId);
    final ps = sizeOf(parentId);
    var edge = parent.pos.dy + dir * ps.height / 2;
    final left = parent.pos.dx - ps.width / 2;
    for (final id in kids(parentId)) {
      final cs = sizeOf(id);
      final y = edge + dir * (vGap + cs.height / 2);
      node(id).pos = Offset(left + _indent + cs.width / 2, y);
      edge = _tree(id, dir);
      edge = dir > 0
          ? max(edge, y + cs.height / 2)
          : min(edge, y - cs.height / 2);
    }
    return edge;
  }

  double _treeWidth(String id) {
    var w = sizeOf(id).width;
    for (final c in kids(id)) {
      w = max(w, _indent + _treeWidth(c));
    }
    return w;
  }

  // ------------------------------------------------------- linha do tempo

  void _timeline() {
    final root = doc.root;
    final rs = sizeOf(root.id);
    var x = root.pos.dx + rs.width / 2 + hGap;
    final children = kids(root.id);
    for (var i = 0; i < children.length; i++) {
      final id = children[i];
      final cs = sizeOf(id);
      final w = max(cs.width, _treeWidth(id));
      // Marcos alternam acima e abaixo do eixo.
      final dir = i.isEven ? 1 : -1;
      final y = root.pos.dy + dir * (cs.height / 2 + 28);
      node(id).pos = Offset(x + cs.width / 2, y);
      _tree(id, dir);
      x += w + max(24.0, hGap * 0.5);
    }
  }

  // ---------------------------------------------------- espinha de peixe

  void _fishbone() {
    final root = doc.root;
    final rs = sizeOf(root.id);
    final spineY = root.pos.dy;
    final children = kids(root.id);
    var x = root.pos.dx - rs.width / 2 - hGap;
    for (var i = 0; i < children.length; i += 2) {
      var colWidth = 0.0;
      for (final j in [i, i + 1]) {
        if (j >= children.length) continue;
        final id = children[j];
        final dir = j.isEven ? -1 : 1; // pares acima, ímpares abaixo
        final cs = sizeOf(id);
        final ribs = kids(id);
        final ribsHeight = ribs.fold<double>(
          0,
          (s, r) => s + _subtreeHeight(r) + vGap,
        );
        final dist = max(90.0, ribsHeight + cs.height / 2 + 30);
        // Tópico principal no fim da "espinha" diagonal.
        final topX = x - dist * 0.5;
        node(id).pos = Offset(topX, spineY + dir * dist);
        // Subtópicos ao longo da espinha diagonal, à esquerda dela.
        var y = spineY + dir * (dist - cs.height / 2 - 14);
        var ribsWidth = 0.0;
        for (final r in ribs) {
          final h = _subtreeHeight(r);
          final rw = sizeOf(r).width;
          final cy = y - dir * h / 2;
          final boneX = _boneX(topX, spineY + dir * dist, x, spineY, cy);
          node(r).pos = Offset(boneX - 12 - rw / 2, cy);
          _horizontal(r, kids(r), -1);
          ribsWidth = max(ribsWidth, rw + 12 + _subtreeReach(r));
          y -= dir * (h + vGap);
        }
        colWidth = max(colWidth, max(cs.width, ribsWidth) + dist * 0.5);
      }
      x -= colWidth + hGap * 0.6;
    }
  }

  /// x da espinha diagonal (de [ax],[ay] até [bx],[by]) na altura [y].
  static double _boneX(double ax, double ay, double bx, double by, double y) {
    if ((by - ay).abs() < 1) return bx;
    final t = ((y - ay) / (by - ay)).clamp(0.0, 1.0);
    return ax + (bx - ax) * t;
  }

  /// Largura ocupada pelos descendentes horizontais de [id].
  double _subtreeReach(String id) {
    var w = 0.0;
    for (final c in kids(id)) {
      w = max(w, hGap + sizeOf(c).width + _subtreeReach(c));
    }
    return w;
  }
}

/// Lado (1 direita, -1 esquerda) em que um nó fica em relação ao pai.
int sideOf(MindMapDoc doc, MindMapNode n) {
  final p = n.parentId == null ? null : doc.nodes[n.parentId];
  if (p == null) return doc.layout == 'left' ? -1 : 1;
  return n.pos.dx >= p.pos.dx ? 1 : -1;
}

/// Ponto da espinha de peixe onde o tópico principal [main] se liga ao eixo.
Offset fishboneJoint(MindMapDoc doc, MindMapNode main) {
  final root = doc.root;
  final dist = main.pos.dy - root.pos.dy;
  return Offset(main.pos.dx + dist.abs() * 0.5, root.pos.dy);
}

/// Espaço mínimo entre dois tópicos que não podem se sobrepor.
const double kOverlapGap = 10;

/// Afasta tópicos que estão um em cima do outro, movendo cada um junto com
/// seus subtópicos. Retorna true se algo mudou de lugar.
///
/// - [anchorId]: tópico que não deve sair do lugar (o que está sendo
///   editado ou arrastado); os outros é que se afastam dele.
/// - [onlyFloating]: só move tópicos flutuantes (usado quando a organização
///   automática já cuida da árvore principal).
bool resolveOverlaps(
  MindMapDoc doc,
  Map<String, Size> sizes, {
  String? anchorId,
  bool onlyFloating = false,
  int maxPasses = 24,
}) {
  final visible = doc.visibleNodes().toList();
  if (visible.length < 2) return false;

  Rect rectOf(MindMapNode n) {
    final s = sizes[n.id] ?? estimateNodeSize(n);
    return Rect.fromCenter(center: n.pos, width: s.width, height: s.height);
  }

  // Raiz do "grupo" de cada nó: a ideia principal ou um tópico flutuante.
  String groupOf(MindMapNode n) {
    var cur = n;
    while (cur.parentId != null) {
      final p = doc.nodes[cur.parentId];
      if (p == null) break;
      cur = p;
    }
    return cur.id;
  }

  final group = {for (final n in visible) n.id: groupOf(n)};

  void shift(String id, Offset delta) {
    for (final c in doc.subtreeIds(id)) {
      final n = doc.nodes[c];
      if (n != null) n.pos += delta;
    }
  }

  final locked = <String, Offset>{};
  var changed = false;
  for (var pass = 0; pass < maxPasses; pass++) {
    var moved = false;
    for (var i = 0; i < visible.length; i++) {
      for (var j = i + 1; j < visible.length; j++) {
        final a = visible[i], b = visible[j];
        final ra = rectOf(a), rb = rectOf(b);
        if (!ra
            .inflate(kOverlapGap / 2)
            .overlaps(rb.inflate(kOverlapGap / 2))) {
          continue;
        }

        // Quem se move (levando os subtópicos junto).
        String? mover;
        if (onlyFloating) {
          final ga = group[a.id]!, gb = group[b.id]!;
          if (ga == gb) continue; // dentro da mesma árvore: a organização cuida
          if (ga == doc.rootId) {
            mover = gb;
          } else if (gb == doc.rootId) {
            mover = ga;
          } else {
            mover = gb == anchorId ? ga : gb;
          }
        } else if (doc.isInSubtree(b.id, a.id)) {
          mover = b.id; // b é descendente de a
        } else if (doc.isInSubtree(a.id, b.id)) {
          mover = a.id;
        } else if (anchorId != null && doc.isInSubtree(anchorId, b.id)) {
          mover = a.id; // b é (ou contém) o tópico fixo
        } else if (anchorId != null && doc.isInSubtree(anchorId, a.id)) {
          mover = b.id;
        } else {
          mover = rb.center.dy >= ra.center.dy ? b.id : a.id;
        }
        if (mover == doc.rootId) mover = mover == a.id ? b.id : a.id;
        if (mover == doc.rootId) continue;

        final moverIsA = doc.isInSubtree(a.id, mover);
        final mine = moverIsA ? ra : rb;
        final other = moverIsA ? rb : ra;

        // Direção de fuga: escolhida no primeiro empurrão (eixo com menor
        // sobreposição) e mantida depois, para não ficar indo e voltando.
        final dir = locked[mover] ??= () {
          final ox = min(mine.right - other.left, other.right - mine.left);
          final oy = min(mine.bottom - other.top, other.bottom - mine.top);
          return ox < oy
              ? Offset(mine.center.dx >= other.center.dx ? 1 : -1, 0)
              : Offset(0, mine.center.dy >= other.center.dy ? 1 : -1);
        }();
        final double dist;
        if (dir.dx > 0) {
          dist = other.right - mine.left;
        } else if (dir.dx < 0) {
          dist = mine.right - other.left;
        } else if (dir.dy > 0) {
          dist = other.bottom - mine.top;
        } else {
          dist = mine.bottom - other.top;
        }
        final delta = dir * (dist + kOverlapGap);
        shift(mover, delta);
        moved = changed = true;
      }
    }
    if (!moved) break;
  }
  return changed;
}
