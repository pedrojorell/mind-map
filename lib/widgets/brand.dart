import 'package:flutter/material.dart';

/// Nome do aplicativo.
const kAppName = 'MapLong';

/// Cores da marca (degradê da logo: ciano → azul → roxo).
const kBrandCyan = Color(0xFF00AEEF);
const kBrandBlue = Color(0xFF2F5BFF);
const kBrandViolet = Color(0xFF8A2BFF);

/// Cor base do tema do aplicativo.
const kBrandSeed = Color(0xFF3B4CF5);

const kBrandGradient = LinearGradient(
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
  colors: [kBrandCyan, kBrandBlue, kBrandViolet],
);

/// Símbolo completo da logo (o "M" ligado aos quatro tópicos).
class MapLongSymbol extends StatelessWidget {
  const MapLongSymbol({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/maplong_symbol.png',
    height: height,
    filterQuality: FilterQuality.medium,
    semanticLabel: kAppName,
  );
}

/// Só o "M" da logo, para espaços pequenos (abas, barra de título).
class MapLongMark extends StatelessWidget {
  const MapLongMark({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/brand/maplong_m.png',
    height: height,
    filterQuality: FilterQuality.medium,
    semanticLabel: kAppName,
  );
}

/// Nome "MapLong": "Map" na cor do texto e "Long" com o degradê da marca,
/// legível tanto no tema claro quanto no escuro.
class MapLongWordmark extends StatelessWidget {
  const MapLongWordmark({super.key, this.fontSize = 22});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w900,
      letterSpacing: fontSize * 0.04,
      height: 1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'MAP',
          style: style.copyWith(color: Theme.of(context).colorScheme.onSurface),
        ),
        ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => kBrandGradient.createShader(r),
          child: Text('LONG', style: style.copyWith(color: Colors.white)),
        ),
      ],
    );
  }
}
