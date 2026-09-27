import 'package:flutter/material.dart';

/// Botão grande da faixa de ferramentas: ícone em cima, rótulo embaixo.
/// Com [menu], mostra uma seta; se [onTap] for nulo o botão inteiro abre o menu.
class RibbonButton extends StatelessWidget {
  const RibbonButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.tip,
    this.menu,
    this.enabled,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? tip;
  final List<Widget>? menu;
  final bool? enabled;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEnabled = enabled ?? (onTap != null || menu != null);
    final fg = isEnabled
        ? (active ? cs.primary : cs.onSurface)
        : cs.onSurface.withValues(alpha: 0.35);

    Widget face({required bool arrow}) => Container(
      constraints: const BoxConstraints(minWidth: 58),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: active
          ? BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(10),
            )
          : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 23, color: fg),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11.5, color: fg, height: 1.1),
              ),
              if (arrow) Icon(Icons.arrow_drop_down, size: 14, color: fg),
            ],
          ),
        ],
      ),
    );

    Widget button;
    if (menu == null) {
      button = InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: isEnabled ? onTap : null,
        child: face(arrow: false),
      );
    } else {
      button = MenuAnchor(
        menuChildren: menu!,
        builder: (context, c, _) => InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: !isEnabled
              ? null
              : onTap ?? () => c.isOpen ? c.close() : c.open(),
          onSecondaryTap: isEnabled ? () => c.open() : null,
          child: onTap == null
              ? face(arrow: true)
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    face(arrow: false),
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: isEnabled
                          ? () => c.isOpen ? c.close() : c.open()
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: Icon(Icons.arrow_drop_down, size: 16, color: fg),
                      ),
                    ),
                  ],
                ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Tooltip(
        message: tip ?? label,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      ),
    );
  }
}

/// Botões pequenos empilhados (ex.: recortar/copiar).
class RibbonStack extends StatelessWidget {
  const RibbonStack({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisAlignment: MainAxisAlignment.center, children: children);
}

class RibbonSmallButton extends StatelessWidget {
  const RibbonSmallButton({
    super.key,
    required this.icon,
    required this.tip,
    required this.onTap,
  });
  final IconData icon;
  final String tip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tip,
    style: IconButton.styleFrom(
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: const Size(34, 30),
      fixedSize: const Size(34, 30),
      padding: EdgeInsets.zero,
    ),
    iconSize: 18,
    onPressed: onTap,
    icon: Icon(icon),
  );
}

class RibbonDivider extends StatelessWidget {
  const RibbonDivider({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: SizedBox(
      height: 46,
      child: VerticalDivider(
        width: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
  );
}
