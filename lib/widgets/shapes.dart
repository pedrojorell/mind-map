import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Contorno de um tópico conforme a forma escolhida (ver `kShapes`).
/// [corner] ajusta o raio dos cantos nas formas retangulares.
ShapeBorder shapeFor(String shape, {double? corner}) {
  switch (shape) {
    case 'rounded':
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(corner ?? 12),
      );
    case 'rect':
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(corner ?? 3),
      );
    case 'ellipse':
    case 'circle':
      return const OvalBorder();
    case 'hexagon':
      return BeveledRectangleBorder(borderRadius: BorderRadius.circular(18));
    case 'underline':
      return const RoundedRectangleBorder();
    case 'plain':
      return RoundedRectangleBorder(borderRadius: BorderRadius.circular(6));
    case 'pill':
      return const StadiumBorder();
    default:
      return MapShapeBorder(shape, corner: corner);
  }
}

/// Formas desenhadas por caminho (losango, documento, setas, nuvem…).
class MapShapeBorder extends OutlinedBorder {
  const MapShapeBorder(this.kind, {this.corner, super.side});

  final String kind;
  final double? corner;

  @override
  EdgeInsetsGeometry get dimensions =>
      EdgeInsets.all(math.max(side.strokeInset, 0));

  @override
  OutlinedBorder copyWith({BorderSide? side}) =>
      MapShapeBorder(kind, corner: corner, side: side ?? this.side);

  @override
  ShapeBorder scale(double t) =>
      MapShapeBorder(kind, corner: corner, side: side.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      shapePath(kind, rect.deflate(side.strokeInset), corner: corner);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      shapePath(kind, rect, corner: corner);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final r = rect.inflate(side.width * side.strokeAlign / 2);
    canvas.drawPath(
      shapePath(kind, r, corner: corner, details: true),
      side.toPaint()..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MapShapeBorder &&
      other.kind == kind &&
      other.corner == corner &&
      other.side == side;

  @override
  int get hashCode => Object.hash(kind, corner, side);
}

/// Caminho da forma [kind] dentro de [r]. Com [details], inclui as linhas
/// internas (dobra da nota, divisórias do processo, tampa do cilindro).
Path shapePath(String kind, Rect r, {double? corner, bool details = false}) {
  final l = r.left, t = r.top, w = r.width, h = r.height;
  final rr = r.right, b = r.bottom, cx = r.center.dx, cy = r.center.dy;
  Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  switch (kind) {
    case 'diamond':
      return poly([
        Offset(cx, t),
        Offset(rr, cy),
        Offset(cx, b),
        Offset(l, cy),
      ]);
    case 'document':
      final yb = b - h * 0.14;
      return Path()
        ..moveTo(l, t)
        ..lineTo(rr, t)
        ..lineTo(rr, yb)
        ..cubicTo(
          rr - w * 0.3,
          yb - h * 0.14,
          l + w * 0.45,
          b + h * 0.08,
          l,
          yb,
        )
        ..close();
    case 'parallelogram':
      final s = math.min(h * 0.35, w * 0.2);
      return poly([
        Offset(l + s, t),
        Offset(rr, t),
        Offset(rr - s, b),
        Offset(l, b),
      ]);
    case 'process':
      final p = Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(corner ?? 2)));
      if (details) {
        final i = math.min(10.0, w * 0.08);
        p
          ..moveTo(l + i, t)
          ..lineTo(l + i, b)
          ..moveTo(rr - i, t)
          ..lineTo(rr - i, b);
      }
      return p;
    case 'internal':
      final p = Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(corner ?? 2)));
      if (details) {
        final i = math.min(9.0, math.min(w, h) * 0.2);
        p
          ..moveTo(l + i, t)
          ..lineTo(l + i, b)
          ..moveTo(l, t + i)
          ..lineTo(rr, t + i);
      }
      return p;
    case 'cylinder':
      final e = math.min(h * 0.18, 10.0);
      final top = Rect.fromLTWH(l, t, w, 2 * e);
      final p = Path()
        ..moveTo(l, t + e)
        ..lineTo(l, b - e)
        ..arcTo(Rect.fromLTWH(l, b - 2 * e, w, 2 * e), math.pi, -math.pi, false)
        ..lineTo(rr, t + e)
        ..arcTo(top, 0, -math.pi, false)
        ..close();
      if (details) p.addOval(top);
      return p;
    case 'card':
      final c = corner ?? math.min(14.0, h * 0.32);
      return poly([
        Offset(l + c, t),
        Offset(rr, t),
        Offset(rr, b),
        Offset(l, b),
        Offset(l, t + c),
      ]);
    case 'dshape':
      final rad = math.min(h / 2, w / 2);
      return Path()
        ..moveTo(l, t)
        ..lineTo(rr - rad, t)
        ..arcToPoint(Offset(rr - rad, b), radius: Radius.elliptical(rad, h / 2))
        ..lineTo(l, b)
        ..close();
    case 'tab':
      final th = math.min(8.0, h * 0.22);
      return poly([
        Offset(l, t),
        Offset(l + w * 0.36, t),
        Offset(l + w * 0.42, t + th),
        Offset(rr, t + th),
        Offset(rr, b),
        Offset(l, b),
      ]);
    case 'octagon':
      final c = math.min(w, h) * 0.29;
      return poly([
        Offset(l + c, t),
        Offset(rr - c, t),
        Offset(rr, t + c),
        Offset(rr, b - c),
        Offset(rr - c, b),
        Offset(l + c, b),
        Offset(l, b - c),
        Offset(l, t + c),
      ]);
    case 'tag':
      final p = math.min(h / 2, w * 0.3);
      return poly([
        Offset(l, t),
        Offset(rr - p, t),
        Offset(rr, cy),
        Offset(rr - p, b),
        Offset(l, b),
      ]);
    case 'arrowRight':
    case 'arrowLeft':
      final a = math.min(h * 0.6, w * 0.35);
      final s = h * 0.18;
      final pts = [
        Offset(l, t + s),
        Offset(rr - a, t + s),
        Offset(rr - a, t),
        Offset(rr, cy),
        Offset(rr - a, b),
        Offset(rr - a, b - s),
        Offset(l, b - s),
      ];
      return poly(
        kind == 'arrowRight'
            ? pts
            : [for (final p in pts) Offset(l + rr - p.dx, p.dy)],
      );
    case 'arrowBoth':
      final a = math.min(h * 0.55, w * 0.25);
      final s = h * 0.18;
      return poly([
        Offset(l, cy),
        Offset(l + a, t),
        Offset(l + a, t + s),
        Offset(rr - a, t + s),
        Offset(rr - a, t),
        Offset(rr, cy),
        Offset(rr - a, b),
        Offset(rr - a, b - s),
        Offset(l + a, b - s),
        Offset(l + a, b),
      ]);
    case 'speech':
      final th = math.min(10.0, h * 0.25);
      final body = Path()
        ..addRRect(
          RRect.fromLTRBR(l, t, rr, b - th, const Radius.circular(10)),
        );
      final tail = poly([
        Offset(l + w * 0.18, b - th - 1),
        Offset(l + w * 0.12, b),
        Offset(l + w * 0.34, b - th - 1),
      ]);
      return Path.combine(PathOperation.union, body, tail);
    case 'star':
      final pts = <Offset>[];
      for (var i = 0; i < 10; i++) {
        final ang = -math.pi / 2 + i * math.pi / 5;
        final k = i.isEven ? 1.0 : 0.45;
        pts.add(
          Offset(
            cx + math.cos(ang) * w / 2 * k,
            cy + math.sin(ang) * h / 2 * k,
          ),
        );
      }
      // A ponta de baixo fica um pouco acima da borda: centraliza a estrela.
      final shift = (b - pts.map((p) => p.dy).reduce(math.max)) / 2;
      return poly([for (final p in pts) p.translate(0, shift)]);
    case 'gem':
      return poly([
        Offset(l + w * 0.2, t),
        Offset(rr - w * 0.2, t),
        Offset(rr, t + h * 0.35),
        Offset(cx, b),
        Offset(l, t + h * 0.35),
      ]);
    case 'cloud':
      Path oval(double x, double y, double ow, double oh) => Path()
        ..addOval(
          Rect.fromCenter(
            center: Offset(l + w * x, t + h * y),
            width: w * ow,
            height: h * oh,
          ),
        );
      var p = oval(0.5, 0.55, 0.8, 0.75);
      for (final o in const [
        (0.22, 0.58, 0.42, 0.62),
        (0.38, 0.3, 0.42, 0.55),
        (0.62, 0.28, 0.46, 0.56),
        (0.8, 0.55, 0.4, 0.62),
        (0.5, 0.75, 0.5, 0.5),
      ]) {
        p = Path.combine(PathOperation.union, p, oval(o.$1, o.$2, o.$3, o.$4));
      }
      return p;
    case 'sticky':
      final f = math.min(14.0, h * 0.25);
      final p = poly([
        Offset(l, t),
        Offset(rr, t),
        Offset(rr, b - f),
        Offset(rr - f, b),
        Offset(l, b),
      ]);
      if (details) {
        p
          ..moveTo(rr, b - f)
          ..lineTo(rr - f, b - f)
          ..lineTo(rr - f, b);
      }
      return p;
    case 'ellipse':
    case 'circle':
      return Path()..addOval(r);
    default:
      return Path()
        ..addRRect(RRect.fromRectAndRadius(r, Radius.circular(corner ?? 3)));
  }
}

/// Espaço extra em volta do texto para que ele caiba dentro da forma.
/// [content] é o tamanho do texto/conteúdo; [root] indica a ideia principal.
EdgeInsets shapeInsets(String shape, Size content, {bool root = false}) {
  final w = content.width, h = content.height;
  final bh = root ? 24.0 : 16.0, bv = root ? 14.0 : 9.0;
  EdgeInsets sym(double x, double y) =>
      EdgeInsets.symmetric(horizontal: x, vertical: y);
  switch (shape) {
    case 'underline':
    case 'plain':
      return const EdgeInsets.fromLTRB(6, 4, 6, 6);
    case 'hexagon':
      return sym(root ? 32 : 24, bv);
    case 'ellipse':
      return sym(26, root ? 20 : 14);
    case 'circle':
      final d = math.sqrt(w * w + h * h) + 10;
      return sym((d - w) / 2, (d - h) / 2);
    case 'diamond':
      return sym(w / 2 + 10, h / 2 + 8);
    case 'parallelogram':
      return sym(bh + h * 0.45, bv);
    case 'document':
      return EdgeInsets.fromLTRB(bh, bv, bh, bv + h * 0.3);
    case 'process':
      return sym(bh + 10, bv);
    case 'internal':
      return EdgeInsets.fromLTRB(bh + 8, bv + 8, bh, bv);
    case 'cylinder':
      return EdgeInsets.fromLTRB(bh, bv + 14, bh, bv + 6);
    case 'card':
      return EdgeInsets.fromLTRB(bh + 4, bv, bh, bv);
    case 'dshape':
      return EdgeInsets.fromLTRB(bh, bv, bh + h * 0.5, bv);
    case 'tab':
      return EdgeInsets.fromLTRB(bh, bv + 8, bh, bv);
    case 'octagon':
      return sym(bh + h * 0.35, bv + 2);
    case 'tag':
      return EdgeInsets.fromLTRB(bh, bv, bh + h * 0.55, bv);
    case 'arrowRight':
      return EdgeInsets.fromLTRB(
        bh,
        bv + h * 0.25,
        bh + h * 0.8,
        bv + h * 0.25,
      );
    case 'arrowLeft':
      return EdgeInsets.fromLTRB(
        bh + h * 0.8,
        bv + h * 0.25,
        bh,
        bv + h * 0.25,
      );
    case 'arrowBoth':
      return sym(bh + h * 0.7, bv + h * 0.25);
    case 'speech':
      return EdgeInsets.fromLTRB(bh, bv, bh, bv + 10);
    case 'star':
      return sym(w * 0.75 + 14, h * 0.85 + 14);
    case 'gem':
      return EdgeInsets.fromLTRB(bh + w * 0.2, bv, bh + w * 0.2, bv + h * 0.7);
    case 'cloud':
      return sym(bh + w * 0.2, bv + h * 0.35);
    case 'sticky':
      return EdgeInsets.fromLTRB(14, 14, 18, 18);
    default:
      return sym(bh, bv);
  }
}

/// Envolve o conteúdo com o espaço calculado por [insets] a partir do
/// tamanho dele (as formas precisam de mais espaço quanto maior o texto).
class ShapePadding extends SingleChildRenderObjectWidget {
  const ShapePadding({super.key, required this.insets, super.child});

  final EdgeInsets Function(Size content) insets;

  @override
  RenderShapePadding createRenderObject(BuildContext context) =>
      RenderShapePadding(insets);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderShapePadding renderObject,
  ) {
    renderObject.insets = insets;
  }
}

class RenderShapePadding extends RenderShiftedBox {
  RenderShapePadding(this._insets) : super(null);

  EdgeInsets Function(Size) _insets;
  set insets(EdgeInsets Function(Size) v) {
    _insets = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      return;
    }
    c.layout(constraints.loosen(), parentUsesSize: true);
    final pad = _insets(c.size);
    (c.parentData! as BoxParentData).offset = Offset(pad.left, pad.top);
    size = constraints.constrain(
      Size(c.size.width + pad.horizontal, c.size.height + pad.vertical),
    );
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    final w = child?.getMinIntrinsicWidth(height) ?? 0;
    return w + _insets(Size(w, height)).horizontal;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    final w = child?.getMaxIntrinsicWidth(height) ?? 0;
    return w + _insets(Size(w, height)).horizontal;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    final h = child?.getMinIntrinsicHeight(width) ?? 0;
    return h + _insets(Size(width, h)).vertical;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final h = child?.getMaxIntrinsicHeight(width) ?? 0;
    return h + _insets(Size(width, h)).vertical;
  }
}

/// Desenha a borda tracejada ou pontilhada seguindo o contorno de [shape].
class PatternBorderPainter extends CustomPainter {
  PatternBorderPainter({
    required this.shape,
    required this.color,
    required this.width,
    this.dotted = false,
  });

  final ShapeBorder shape;
  final Color color;
  final double width;
  final bool dotted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final path = shape is MapShapeBorder
        ? shapePath(
            (shape as MapShapeBorder).kind,
            rect,
            corner: (shape as MapShapeBorder).corner,
            details: true,
          )
        : shape.getOuterPath(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = dotted ? StrokeCap.round : StrokeCap.butt;
    final dash = dotted ? 0.1 : 7.0;
    final gap = dotted ? width * 2 + 2 : 5.0;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant PatternBorderPainter old) =>
      old.color != color ||
      old.width != width ||
      old.shape != shape ||
      old.dotted != dotted;
}

/// Dá ao caminho a aparência de um traço feito à mão: um leve tremido suave
/// e sempre igual para o mesmo [seed] (não muda a cada quadro).
Path roughen(Path path, int seed, {double amplitude = 1.4}) {
  final rnd = math.Random(seed);
  final out = Path();
  const wave = 26.0, step = 4.0;
  for (final m in path.computeMetrics()) {
    final k = (m.length / wave).ceil() + 2;
    final ctrl = [for (var i = 0; i < k; i++) rnd.nextDouble() * 2 - 1];
    double noise(double d) {
      final x = d / wave;
      final i = x.floor().clamp(0, k - 2);
      final f = x - i;
      final s = f * f * (3 - 2 * f);
      return ctrl[i] * (1 - s) + ctrl[i + 1] * s;
    }

    // Traços fechados passam um pouco do ponto inicial, como à mão.
    final total = m.isClosed ? m.length + 5 : m.length;
    final n = math.max(2, (total / step).ceil());
    for (var i = 0; i <= n; i++) {
      final d = total * i / n;
      final tan = m.getTangentForOffset(d % (m.length + 0.0001));
      if (tan == null) continue;
      final normal = Offset(-tan.vector.dy, tan.vector.dx);
      final p = tan.position + normal * (noise(d) * amplitude);
      if (i == 0) {
        out.moveTo(p.dx, p.dy);
      } else {
        out.lineTo(p.dx, p.dy);
      }
    }
  }
  return out;
}

/// Borda com aparência de desenho à mão (dois traços levemente diferentes).
class SketchBorderPainter extends CustomPainter {
  SketchBorderPainter({
    required this.shape,
    required this.color,
    required this.width,
    required this.seed,
    this.dashed = false,
  });

  final ShapeBorder shape;
  final Color color;
  final double width;
  final int seed;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final base = shape is MapShapeBorder
        ? shapePath(
            (shape as MapShapeBorder).kind,
            rect,
            corner: (shape as MapShapeBorder).corner,
            details: true,
          )
        : shape.getOuterPath(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, width)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final (s, alpha) in [(seed, 1.0), (seed + 7, 0.55)]) {
      final path = roughen(base, s);
      paint.color = color.withValues(alpha: color.a * alpha);
      if (!dashed) {
        canvas.drawPath(path, paint);
        continue;
      }
      for (final m in path.computeMetrics()) {
        var d = 0.0;
        while (d < m.length) {
          canvas.drawPath(m.extractPath(d, d + 7), paint);
          d += 12;
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant SketchBorderPainter old) =>
      old.color != color ||
      old.width != width ||
      old.shape != shape ||
      old.seed != seed ||
      old.dashed != dashed;
}
