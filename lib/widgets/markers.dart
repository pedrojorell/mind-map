import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models.dart';

const _faces = <String, (IconData, Color, String)>{
  'happy': (Icons.sentiment_very_satisfied, Color(0xFFFFB300), 'Feliz'),
  'calm': (Icons.sentiment_satisfied, Color(0xFF8BC34A), 'Tranquilo'),
  'neutral': (Icons.sentiment_neutral, Color(0xFF90A4AE), 'Neutro'),
  'sad': (Icons.sentiment_dissatisfied, Color(0xFF42A5F5), 'Triste'),
  'angry': (Icons.sentiment_very_dissatisfied, Color(0xFFE53935), 'Bravo'),
  'love': (Icons.favorite, Color(0xFFEC407A), 'Amei'),
};

const _symbols = <String, (IconData, Color, String)>{
  'check': (Icons.check_circle, Color(0xFF43A047), 'Concluído'),
  'cross': (Icons.cancel, Color(0xFFE53935), 'Cancelado'),
  'question': (Icons.help, Color(0xFF5C6BC0), 'Dúvida'),
  'warning': (Icons.warning_rounded, Color(0xFFFFA000), 'Atenção'),
  'idea': (Icons.lightbulb, Color(0xFFFBC02D), 'Ideia'),
  'info': (Icons.info, Color(0xFF1E88E5), 'Informação'),
  'time': (Icons.schedule, Color(0xFF8E24AA), 'Prazo'),
  'money': (Icons.monetization_on, Color(0xFF2E7D32), 'Custo'),
};

/// Descrição curta de um marcador (para dicas).
String markerLabel(String group, String value) {
  switch (group) {
    case 'priority':
      return 'Prioridade $value';
    case 'progress':
      return 'Progresso $value%';
    case 'face':
      return _faces[value]?.$3 ?? value;
    case 'symbol':
      return _symbols[value]?.$3 ?? value;
    case 'day':
      return value[0].toUpperCase() + value.substring(1);
    default:
      final g = kMarkerGroups.where((g) => g.id == group).firstOrNull;
      return g?.name ?? group;
  }
}

/// Desenha um marcador (`grupo:valor`) com o tamanho [size].
class MarkerIcon extends StatelessWidget {
  const MarkerIcon(this.group, this.value, {super.key, this.size = 18});

  factory MarkerIcon.fromString(String marker, {double size = 18}) {
    final i = marker.indexOf(':');
    return MarkerIcon(
      marker.substring(0, math.max(0, i)),
      marker.substring(i + 1),
      size: size,
    );
  }

  final String group;
  final String value;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (group) {
      case 'priority':
        final n = int.tryParse(value) ?? 1;
        const colors = [
          Color(0xFFE53935),
          Color(0xFFFB8C00),
          Color(0xFFFDD835),
          Color(0xFF43A047),
          Color(0xFF1E88E5),
          Color(0xFF3949AB),
          Color(0xFF8E24AA),
          Color(0xFF6D4C41),
          Color(0xFF757575),
        ];
        return _circle(colors[(n - 1).clamp(0, 8)], value, dark: n == 3);
      case 'progress':
        return SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _ProgressPainter((int.tryParse(value) ?? 0) / 100),
          ),
        );
      case 'flag':
        return Icon(
          Icons.flag_rounded,
          size: size,
          color: parseHex(value) ?? Colors.red,
        );
      case 'star':
        return Icon(
          Icons.star_rounded,
          size: size + 2,
          color: parseHex(value) ?? Colors.amber,
        );
      case 'face':
        final f = _faces[value] ?? _faces['neutral']!;
        return Icon(f.$1, size: size + 1, color: f.$2);
      case 'symbol':
        final f = _symbols[value] ?? _symbols['info']!;
        return Icon(f.$1, size: size + 1, color: f.$2);
      case 'day':
        return Container(
          height: size,
          padding: EdgeInsets.symmetric(horizontal: size * 0.22),
          decoration: BoxDecoration(
            color: const Color(0xFFFF7043),
            borderRadius: BorderRadius.circular(size * 0.25),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              value.toUpperCase(),
              style: TextStyle(
                fontSize: size * 0.48,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                height: 1,
              ),
            ),
          ),
        );
      default:
        return SizedBox.square(dimension: size);
    }
  }

  Widget _circle(Color color, String text, {bool dark = false}) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      text,
      style: TextStyle(
        fontSize: size * 0.6,
        height: 1,
        fontWeight: FontWeight.w800,
        color: dark ? const Color(0xFF3E2723) : Colors.white,
      ),
    ),
  );
}

class _ProgressPainter extends CustomPainter {
  _ProgressPainter(this.fraction);
  final double fraction;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    const color = Color(0xFF1E88E5);
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      r - 0.8,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    if (fraction >= 1) {
      canvas.drawCircle(c, r, Paint()..color = color);
      final tick = Path()
        ..moveTo(c.dx - r * 0.45, c.dy)
        ..lineTo(c.dx - r * 0.1, c.dy + r * 0.35)
        ..lineTo(c.dx + r * 0.5, c.dy - r * 0.35);
      canvas.drawPath(
        tick,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.25
          ..strokeCap = StrokeCap.round,
      );
    } else if (fraction > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 2.5),
        -math.pi / 2,
        2 * math.pi * fraction,
        true,
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter old) =>
      old.fraction != fraction;
}
