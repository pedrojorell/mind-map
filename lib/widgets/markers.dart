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

/// Rostos desenhados como emoji (além dos ícones de [_faces]).
const _emojiFaces = <String, (String, String)>{
  'laugh': ('😂', 'Rindo'),
  'wink': ('😉', 'Piscando'),
  'cool': ('😎', 'Tranquilão'),
  'think': ('🤔', 'Pensando'),
  'surprise': ('😮', 'Surpreso'),
  'cry': ('😭', 'Chorando'),
  'sleep': ('😴', 'Com sono'),
  'party': ('🥳', 'Comemorando'),
  'starstruck': ('🤩', 'Encantado'),
  'sick': ('🤒', 'Doente'),
  'angel': ('😇', 'Anjo'),
  'scream': ('😱', 'Assustado'),
};

const _arrows = <String, (IconData, String)>{
  'up': (Icons.arrow_upward, 'Para cima'),
  'down': (Icons.arrow_downward, 'Para baixo'),
  'left': (Icons.arrow_back, 'Para a esquerda'),
  'right': (Icons.arrow_forward, 'Para a direita'),
  'up_right': (Icons.north_east, 'Subindo'),
  'down_right': (Icons.south_east, 'Descendo'),
  'down_left': (Icons.south_west, 'Voltando'),
  'up_left': (Icons.north_west, 'Retornando'),
  'repeat': (Icons.sync, 'Repetir'),
  'swap': (Icons.swap_horiz, 'Trocar'),
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
  'heart': (Icons.favorite, Color(0xFFE91E63), 'Favorito'),
  'pin': (Icons.push_pin, Color(0xFFD32F2F), 'Fixado'),
  'lock': (Icons.lock, Color(0xFF616161), 'Bloqueado'),
  'link': (Icons.link, Color(0xFF1976D2), 'Ligação'),
  'phone': (Icons.call, Color(0xFF388E3C), 'Ligar'),
  'mail': (Icons.mail, Color(0xFF0288D1), 'E-mail'),
  'home': (Icons.home, Color(0xFF6D4C41), 'Casa'),
  'calendar': (Icons.event, Color(0xFFE64A19), 'Data'),
  'bug': (Icons.bug_report, Color(0xFF7B1FA2), 'Problema'),
  'rocket': (Icons.rocket_launch, Color(0xFF3949AB), 'Lançamento'),
  'trophy': (Icons.emoji_events, Color(0xFFFFA000), 'Conquista'),
  'target': (Icons.track_changes, Color(0xFFC62828), 'Meta'),
};

/// Descrição curta de um marcador (para dicas).
String markerLabel(String group, String value) {
  switch (group) {
    case 'priority':
      return 'Prioridade $value';
    case 'progress':
      return 'Progresso $value%';
    case 'face':
      return _faces[value]?.$3 ?? _emojiFaces[value]?.$2 ?? value;
    case 'arrow':
      return 'Seta: ${_arrows[value]?.$2 ?? value}';
    case 'person':
      return 'Pessoa';
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
        final i = (n - 1) % colors.length;
        return _circle(colors[i < 0 ? 0 : i], value, dark: i == 2);
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
        if (_emojiFaces[value] case final e?) {
          return SizedBox.square(
            dimension: size + 1,
            child: FittedBox(
              child: Text(e.$1, style: const TextStyle(height: 1)),
            ),
          );
        }
        final f = _faces[value] ?? _faces['neutral']!;
        return Icon(f.$1, size: size + 1, color: f.$2);
      case 'person':
        return _iconCircle(
          Icons.person,
          parseHex(value) ?? const Color(0xFF1E88E5),
        );
      case 'arrow':
        return _iconCircle(
          _arrows[value]?.$1 ?? Icons.arrow_forward,
          const Color(0xFFEC407A),
        );
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

  Widget _iconCircle(IconData icon, Color color) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Icon(icon, size: size * 0.72, color: Colors.white),
  );

  Widget _circle(Color color, String text, {bool dark = false}) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: Text(
      text,
      style: TextStyle(
        fontSize: size * (text.length > 1 ? 0.5 : 0.6),
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
