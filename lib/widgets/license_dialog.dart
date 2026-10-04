import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../file_actions.dart';
import '../library.dart';
import '../licensing/license.dart';

/// Tela da licença: estado atual, compra e ativação do código.
Future<void> showLicenseDialog(BuildContext context, Library library) {
  return showDialog<void>(
    context: context,
    builder: (_) => LicenseDialog(library: library),
  );
}

/// No modo leitura, explica e oferece a ativação. Devolve true quando a
/// ação pode continuar.
bool ensureCanEdit(BuildContext context, Library library) {
  if (!library.readOnly) return true;
  showLicenseDialog(context, library);
  return false;
}

/// Resumo curto do estado da licença.
String licenseStatusText(Library lib) {
  final l = lib.license;
  if (l != null) return '${l.plan.label} — ${l.email}';
  final d = lib.trialDaysLeft;
  if (d > 0) {
    return 'Teste grátis: ${d == 1 ? 'falta 1 dia' : 'faltam $d dias'}';
  }
  return 'Teste encerrado — modo leitura';
}

Future<void> openStore(BuildContext context) async {
  if (kStoreUrl.isEmpty) return;
  final ok = await launchUrl(
    Uri.parse(kStoreUrl),
    mode: LaunchMode.externalApplication,
  ).catchError((_) => false);
  if (!ok && context.mounted) {
    showSnack(context, 'Não foi possível abrir $kStoreUrl');
  }
}

class LicenseDialog extends StatefulWidget {
  const LicenseDialog({super.key, required this.library});
  final Library library;

  @override
  State<LicenseDialog> createState() => _LicenseDialogState();
}

class _LicenseDialogState extends State<LicenseDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Library get lib => widget.library;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final lic = await lib.activateLicense(_code.text);
      _code.clear();
      if (mounted) {
        showSnack(
          context,
          lic.isOwner
              ? 'Licença de proprietário ativada.'
              : 'Licença ativada. Obrigado por apoiar o MapLong!',
        );
      }
    } on LicenseException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _paste() async {
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text != null && text.trim().isNotEmpty) {
        setState(() {
          _code.text = text.trim();
          _error = null;
        });
      }
    } catch (_) {}
  }

  Future<void> _remove() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover a licença deste computador?'),
        content: const Text(
          'Seus mapas não são apagados. Guarde o código para ativar de novo '
          'aqui ou em outro computador.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true) await lib.removeLicense();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: lib,
      builder: (context, _) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.workspace_premium_outlined),
            SizedBox(width: 10),
            Flexible(child: Text('Licença do MapLong')),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _status(context),
                const SizedBox(height: 16),
                if (lib.license case final l?)
                  ..._details(context, l)
                else ...[
                  _offer(context),
                  const SizedBox(height: 20),
                  _activation(context),
                ],
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _status(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final l = lib.license;
    final days = lib.trialDaysLeft;
    final (icon, title, text, bg, fg) = l != null
        ? (
            Icons.verified_outlined,
            l.isOwner ? 'Acesso de proprietário' : 'Licença ativada',
            'Todos os recursos liberados neste computador.',
            cs.primaryContainer,
            cs.onPrimaryContainer,
          )
        : days > 0
        ? (
            Icons.hourglass_top_outlined,
            'Teste grátis: ${days == 1 ? 'falta 1 dia' : 'faltam $days dias'}',
            'Tudo liberado durante o teste. Depois, os mapas ficam somente '
                'para leitura até a ativação.',
            cs.secondaryContainer,
            cs.onSecondaryContainer,
          )
        : (
            Icons.lock_outline,
            'O teste grátis terminou',
            'Seus mapas continuam salvos: você pode abrir, apresentar e '
                'exportar. Para criar e editar, ative uma licença.',
            cs.errorContainer,
            cs.onErrorContainer,
          );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(color: fg)),
                const SizedBox(height: 2),
                Text(text, style: t.bodySmall?.copyWith(color: fg)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _details(BuildContext context, License l) {
    final t = Theme.of(context).textTheme;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: t.bodySmall)),
          Expanded(child: SelectableText(value, style: t.bodyMedium)),
        ],
      ),
    );
    return [
      row('Plano', l.plan.label),
      row('Licenciado para', l.email),
      row('Identificação', l.id),
      row('Emitida em', l.issuedLabel),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _remove,
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Remover deste computador'),
        ),
      ),
    ];
  }

  Widget _offer(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Licença vitalícia', style: t.titleMedium),
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: kLicensePrice,
                  style: t.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.primary,
                  ),
                ),
                TextSpan(text: '  pagamento único', style: t.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final item in const [
            'Todos os recursos liberados, para sempre',
            'Sem mensalidade',
            'Pix ou cartão pelo Mercado Pago; o código chega na hora',
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item, style: t.bodyMedium)),
                ],
              ),
            ),
          if (kStoreUrl.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('license-buy'),
              onPressed: () => openStore(context),
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('Comprar agora'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _activation(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Já tem um código?', style: t.titleSmall),
        const SizedBox(height: 8),
        TextField(
          key: const Key('license-code'),
          controller: _code,
          minLines: 2,
          maxLines: 4,
          enabled: !_busy,
          style: const TextStyle(fontFamily: 'Consolas', fontSize: 12.5),
          decoration: InputDecoration(
            hintText: 'MAPLONG-…',
            border: const OutlineInputBorder(),
            errorText: _error,
            errorMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: 'Colar',
              onPressed: _busy ? null : _paste,
              icon: const Icon(Icons.content_paste),
            ),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            key: const Key('license-activate'),
            onPressed: _busy ? null : _activate,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.key),
            label: const Text('Ativar'),
          ),
        ),
      ],
    );
  }
}
